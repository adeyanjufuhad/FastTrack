// The fasttrack HTTP API. One Neon Function replaces Supabase's PostgREST +
// RLS, Storage policies and the kyc-check / process-application Edge
// Functions. Access rules (formerly supabase/migrations/*_rls.sql):
//
//   * An applicant reads and writes only their own applicant row,
//     applications, documents and eligibility results.
//   * KYC fields, holdings, eligibility rows and "scored"/decision statuses
//     are written only by this server, never taken from a request body.
//   * Officers (rows in public.staff) read every file, add notes and decide.
//
// Errors follow docs/api-contracts.md:
//   401 no/expired JWT · 403 not owner/officer · 409 KYC mismatch ·
//   422 unreadable · 503 Gemini down and no cache

import { createHash } from "node:crypto";

import { type Claims, AuthError, type NeonAuth } from "./auth.ts";
import type { Query } from "./db.ts";
import { ALLOWED_MIME, MAX_BYTES, objectKey, type Storage, StorageError } from "./storage.ts";
import { extractWithGemini, GeminiUnavailable, modelName, narrativeWithGemini, validateExtract } from "../_shared/gemini.ts";
import { type Extract, type KycResult, score, templateNarrative } from "../_shared/score.ts";

export interface Deps {
  query: Query;
  storage: Storage;
  auth: NeonAuth;
  verify: (token: string) => Promise<Claims>;
  env?: Record<string, string | undefined>;
}

export class HttpError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

type Row = Record<string, unknown>;
interface Caller {
  id: string;
  email: string;
  isOfficer: boolean;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DOC_KINDS = ["id", "statement", "cac", "signature", "other"];
const ROLES = ["individual", "corporate"];
const OFFICER_STATUSES = ["in_review", "more_info", "approved", "declined"];

/** A4 form keys that are real `applicants` columns (see SupabaseRepository._columns). */
const DETAIL_COLUMNS = [
  "email", "phone", "dob", "address", "occupation", "next_of_kin_name",
  "next_of_kin_phone", "rc_number", "nature_of_business",
  "registered_address", "signatory_1_name", "signatory_2_name",
] as const;

const sha256 = (input: string | Uint8Array) => createHash("sha256").update(input).digest("hex");
const last4 = (v?: string | null) => (v && v.length >= 4 ? v.slice(-4) : null);
const mask = (v?: string | null) => (v && v.length > 4 ? "*".repeat(v.length - 4) + v.slice(-4) : null);
const clean = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : null);

/** Optional whole number in [min, max]; null/undefined → null. */
function int(v: unknown, min: number, max: number): number | null {
  if (v === null || v === undefined) return null;
  if (typeof v === "number" && Number.isInteger(v) && v >= min && v <= max) return v;
  throw new HttpError(400, "Amounts and tenor must be whole numbers in range.");
}

function cors(req: Request, env: Deps["env"]): Record<string, string> {
  const allow = (env?.ALLOWED_ORIGINS ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  const origin = req.headers.get("origin");
  // Bearer tokens, not cookies, so "*" is safe when no allowlist is set.
  const value = allow.length === 0 ? "*" : origin && allow.includes(origin) ? origin : allow[0];
  return {
    "Access-Control-Allow-Origin": value,
    "Access-Control-Allow-Headers": "authorization, content-type",
    "Access-Control-Allow-Methods": "GET, POST, PUT, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

async function readJson(req: Request): Promise<Row> {
  try {
    const body = await req.json();
    if (body && typeof body === "object" && !Array.isArray(body)) return body as Row;
  } catch { /* fall through */ }
  throw new HttpError(400, "Invalid JSON body.");
}

export function createHandler(deps: Deps) {
  const { query, storage, auth } = deps;
  const env = deps.env ?? process.env;

  const one = async <T = Row>(sql: string, params: unknown[] = []) => (await query<T>(sql, params))[0] ?? null;

  async function caller(req: Request): Promise<Caller> {
    const h = req.headers.get("authorization") ?? "";
    if (!/^bearer /i.test(h)) throw new HttpError(401, "Sign in required.");
    const claims = await deps.verify(h.slice(7).trim());
    const staff = await one("select 1 from public.staff where user_id = $1", [claims.sub]);
    return { id: claims.sub, email: String(claims.email ?? ""), isOfficer: staff !== null };
  }

  const requireOfficer = (c: Caller) => {
    if (!c.isOfficer) throw new HttpError(403, "Officer access only.");
  };

  /** Applicant rows are keyed by the Neon Auth user id; create on first touch. */
  const ensureApplicant = (c: Caller) =>
    query(
      `insert into public.applicants (id, email) values ($1, nullif($2, ''))
       on conflict (id) do nothing`,
      [c.id, c.email],
    );

  /** The application if the caller owns it or is an officer, else 403. */
  async function applicationFor(c: Caller, id: string): Promise<Row> {
    if (!UUID.test(id)) throw new HttpError(403, "Application not found for this user.");
    const app = await one("select * from public.applications where id = $1", [id]);
    if (!app || (app.applicant_id !== c.id && !c.isOfficer)) {
      throw new HttpError(403, "Application not found for this user.");
    }
    return app;
  }

  const latestEligibility = (applicationId: string) =>
    one(
      `select * from public.eligibility_results where application_id = $1
       order by created_at desc limit 1`,
      [applicationId],
    );

  const fileSql = `
    select to_jsonb(a) as application,
           to_jsonb(p) as applicant,
           (select to_jsonb(e) from public.eligibility_results e
             where e.application_id = a.id order by e.created_at desc limit 1) as eligibility,
           coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at)
             from public.officer_notes n where n.application_id = a.id), '[]'::jsonb) as notes
    from public.applications a
    join public.applicants p on p.id = a.applicant_id`;

  // ── Auth ─────────────────────────────────────────────────────────────

  async function signIn(req: Request, create: boolean) {
    const b = await readJson(req);
    const email = clean(b.email)?.toLowerCase();
    const password = typeof b.password === "string" ? b.password : "";
    if (!email || !password) throw new HttpError(400, "Email and password are required.");
    const s = create
      ? await auth.signUp(email, password, clean(b.name) ?? undefined)
      : await auth.signIn(email, password);
    const staff = await one("select 1 from public.staff where user_id = $1", [s.user.id]);
    return { ...s, user: { ...s.user, is_officer: staff !== null } };
  }

  // ── KYC sandbox (docs/kyc-sandbox.md) ────────────────────────────────
  // Demo rule: a BVN *or* NIN hit on the dummy table passes; names are
  // ignored so a pitch-room typist cannot fail KYC. 00000000000 always fails.

  async function kycCheck(c: Caller, req: Request) {
    // LIVE_KYC must stay false in v1 — no provider integration exists.
    if (env.LIVE_KYC === "true") throw new HttpError(501, "Live KYC is not part of this build.");
    const b = await readJson(req);
    const eleven = /^\d{11}$/;
    const bvn = typeof b.bvn === "string" && eleven.test(b.bvn) ? b.bvn : null;
    const nin = typeof b.nin === "string" && eleven.test(b.nin) ? b.nin : null;
    if (!bvn && !nin) throw new HttpError(400, "Provide an 11-digit BVN or NIN.");

    const hit = await one<{ matched_name: string; result: KycResult }>(
      `select matched_name, result from public.kyc_sandbox
       where bvn = $1 or nin = $2 limit 1`,
      [bvn, nin],
    );
    const result: KycResult = hit ? hit.result : "mismatch";

    // Only masked values are stored on the applicant; logs keep last four digits.
    await query(
      `insert into public.applicants (id, email, kyc_result, bvn_masked, nin_masked)
       values ($1, nullif($2, ''), $3, $4, $5)
       on conflict (id) do update
         set kyc_result = excluded.kyc_result, bvn_masked = excluded.bvn_masked,
             nin_masked = excluded.nin_masked, updated_at = now()`,
      [c.id, c.email, result, mask(bvn), mask(nin)],
    );
    await query(
      `insert into public.kyc_logs (applicant_id, bvn_last4, nin_last4, result, mode)
       values ($1, $2, $3, $4, 'sandbox')`,
      [c.id, last4(bvn), last4(nin), result],
    );
    return { result, matched_name: hit?.matched_name, mode: "sandbox" };
  }

  // ── Documents ────────────────────────────────────────────────────────

  async function upload(c: Caller, req: Request, url: URL) {
    const kind = url.searchParams.get("kind") ?? "";
    if (!DOC_KINDS.includes(kind)) throw new HttpError(400, `kind must be one of ${DOC_KINDS.join(", ")}.`);
    const name = url.searchParams.get("name") || kind;
    const mime = (req.headers.get("content-type") ?? "").split(";")[0].trim().toLowerCase();
    if (!(ALLOWED_MIME as readonly string[]).includes(mime)) {
      throw new HttpError(415, "Upload a JPEG, PNG or PDF.");
    }
    if (Number(req.headers.get("content-length") ?? 0) > MAX_BYTES) {
      throw new HttpError(413, "Files must be 8 MB or smaller.");
    }
    const data = new Uint8Array(await req.arrayBuffer());
    if (data.length === 0) throw new HttpError(400, "Empty file.");
    if (data.length > MAX_BYTES) throw new HttpError(413, "Files must be 8 MB or smaller.");

    await ensureApplicant(c);
    const key = objectKey(c.id, kind, name);
    await storage.put(key, data, mime);
    return one(
      `insert into public.documents (applicant_id, kind, storage_key, file_name, mime, bytes)
       values ($1, $2, $3, $4, $5, $6) returning *`,
      [c.id, kind, key, name.slice(0, 200), mime, data.length],
    );
  }

  async function documentUrl(c: Caller, id: string) {
    if (!UUID.test(id)) throw new HttpError(404, "Document not found.");
    const doc = await one<{ applicant_id: string; storage_key: string }>(
      "select applicant_id, storage_key from public.documents where id = $1",
      [id],
    );
    if (!doc || (doc.applicant_id !== c.id && !c.isOfficer)) throw new HttpError(404, "Document not found.");
    return { url: await storage.signedUrl(doc.storage_key), expires_in: 600 };
  }

  // ── process-application: cache → extract → rules → narrative ────────

  async function processApplication(c: Caller, req: Request) {
    const b = await readJson(req);
    if (typeof b.application_id !== "string") throw new HttpError(400, "application_id is required.");
    const app = await applicationFor(c, b.application_id);
    const applicant = await one<{ role: "individual" | "corporate"; kyc_result: KycResult | null; holdings_ngn: number | null }>(
      "select role, kyc_result, holdings_ngn from public.applicants where id = $1",
      [app.applicant_id],
    );
    if (!applicant) throw new HttpError(422, "Applicant profile missing.");

    const setStatus = (status: string) =>
      query("update public.applications set status = $2, updated_at = now() where id = $1", [app.id, status]);
    const unreadable = async (message = "We could not read this file. Try SMS paste or a clearer PDF.") => {
      await setStatus("more_info");
      return new HttpError(422, message);
    };
    const readCache = async (key: string) => {
      const row = await one<{ payload: unknown }>("select payload from public.extract_cache where input_hash = $1", [key]);
      return row ? validateExtract(row.payload) : null;
    };

    // 1. Extract (cache first)
    let extract: Extract | null = null;
    let modelVersion = "fixture-cache";
    let rawOutput: string | null = null;
    let cacheKey: string | null = null;
    const tenor = Number(app.tenor_months ?? 12);
    const sms = typeof app.sms_text === "string" ? app.sms_text : "";

    if (typeof b.fixture_key === "string" && b.fixture_key.startsWith("fixture:")) {
      extract = await readCache(b.fixture_key);
    }
    try {
      if (!extract && sms.trim().length > 0) {
        cacheKey = sha256(`${applicant.role}${tenor}sms${sms}`);
        extract = await readCache(cacheKey);
        if (!extract) {
          const r = await extractWithGemini({ role: applicant.role, tenor, source: "sms", text: sms });
          extract = r.extract;
          rawOutput = r.raw;
          modelVersion = modelName();
        }
      } else if (!extract) {
        const doc = await one<{ storage_key: string; mime: string | null; bytes: number | null }>(
          `select storage_key, mime, bytes from public.documents
           where applicant_id = $1 and kind = 'statement'
           order by uploaded_at desc limit 1`,
          [app.applicant_id],
        );
        if (!doc) throw await unreadable();
        if ((doc.bytes ?? 0) > MAX_BYTES) throw await unreadable("Statement is larger than 8 MB.");
        let bytes: Uint8Array;
        try {
          bytes = await storage.get(doc.storage_key);
        } catch {
          throw new HttpError(422, "We could not read this file. Try SMS paste or a clearer PDF.");
        }
        cacheKey = sha256(`${applicant.role}${tenor}statement${sha256(bytes)}`);
        extract = await readCache(cacheKey);
        if (!extract) {
          // v1: send the PDF / image to Gemini multimodal directly.
          const r = await extractWithGemini({
            role: applicant.role,
            tenor,
            source: "statement",
            file: { mime: doc.mime ?? "application/pdf", base64: Buffer.from(bytes).toString("base64") },
          });
          extract = r.extract;
          rawOutput = r.raw;
          modelVersion = modelName();
        }
      }
    } catch (e) {
      if (e instanceof GeminiUnavailable) {
        console.warn("gemini unavailable:", e.message);
        throw new HttpError(503, "Statement reader unavailable and no cached extract.");
      }
      throw e;
    }

    if (!extract) throw await unreadable();
    if (cacheKey && rawOutput) {
      await query(
        `insert into public.extract_cache (input_hash, payload) values ($1, $2)
         on conflict (input_hash) do update set payload = excluded.payload`,
        [cacheKey, JSON.stringify(extract)],
      );
    }

    // 2. Rules (Stage A)
    const result = score(extract, { kyc: applicant.kyc_result, tenorMonths: tenor, holdingsNgn: applicant.holdings_ngn });

    // 3. Narrative (Stage B) — never allowed to change the number
    let narrative: string | null = null;
    if (!result.blocked && result.amount !== null) {
      try {
        narrative = await narrativeWithGemini(result.amount, result.tier, result.warnings, extract);
      } catch {
        narrative = null; // fall back to the template below
      }
    }
    narrative ??= templateNarrative(extract, result, applicant.role);

    // 4. Persist
    await query(
      `insert into public.eligibility_results
         (application_id, monthly_income_est, income_regularity, spend_categories, existing_debts,
          extract, tier, amount_prequalified, warnings, narrative, model_version, raw_model_output)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
      [
        app.id,
        extract.monthly_income_est,
        extract.income_regularity,
        JSON.stringify(extract.top_spend_categories),
        JSON.stringify(extract.existing_loan_debits),
        JSON.stringify(extract),
        result.blocked ? null : result.tier,
        result.amount,
        result.warnings,
        narrative,
        modelVersion,
        rawOutput,
      ],
    );

    if (result.blocked) {
      await setStatus("more_info");
      throw new HttpError(409, "We need to confirm your identity before we can show an amount.");
    }
    await setStatus("scored");
    return {
      application_id: app.id,
      status: "scored",
      amount_prequalified: result.amount,
      tier: result.tier,
      warnings: result.warnings,
      narrative,
      applicant_summary: narrative.split(/(?<=\.)\s+/).slice(0, 4).join(" "),
    };
  }

  // ── Router ───────────────────────────────────────────────────────────

  async function route(req: Request, url: URL): Promise<unknown> {
    const m = req.method;
    const seg = url.pathname.replace(/\/+$/, "").split("/").filter(Boolean);
    const path = "/" + seg.join("/");

    if (m === "GET" && (path === "/" || path === "/health")) return { ok: true, service: "fasttrack" };

    // Auth (no bearer needed)
    if (m === "POST" && path === "/auth/sign-up") return signIn(req, true);
    if (m === "POST" && path === "/auth/sign-in") return signIn(req, false);
    if (m === "POST" && path === "/auth/refresh") {
      const b = await readJson(req);
      if (typeof b.refresh_token !== "string") throw new HttpError(400, "refresh_token is required.");
      return auth.refresh(b.refresh_token);
    }
    if (m === "POST" && path === "/auth/sign-out") {
      const b = await readJson(req);
      if (typeof b.refresh_token === "string") await auth.signOut(b.refresh_token).catch(() => {});
      return { ok: true };
    }

    const c = await caller(req);

    if (m === "GET" && path === "/me") return { id: c.id, email: c.email, is_officer: c.isOfficer };

    // Applicant profile
    if (path === "/applicant") {
      if (m === "GET") {
        await ensureApplicant(c);
        return one("select * from public.applicants where id = $1", [c.id]);
      }
      if (m === "PUT") {
        const b = await readJson(req);
        const role = typeof b.role === "string" && ROLES.includes(b.role) ? b.role : "individual";
        const values = DETAIL_COLUMNS.map((k) => clean(b[k]));
        const cols = DETAIL_COLUMNS.join(", ");
        const params = DETAIL_COLUMNS.map((_, i) => `$${i + 4}`).join(", ");
        const sets = DETAIL_COLUMNS.map((k) => `${k} = excluded.${k}`).join(", ");
        return one(
          `insert into public.applicants (id, role, legal_name, ${cols})
           values ($1, $2, $3, ${params})
           on conflict (id) do update
             set role = excluded.role, legal_name = excluded.legal_name, ${sets}, updated_at = now()
           returning *`,
          [c.id, role, clean(b.legal_name), ...values],
        );
      }
    }

    // Applicant's application (first one; created on demand)
    if (m === "GET" && path === "/application") {
      const existing = await one(
        "select * from public.applications where applicant_id = $1 order by created_at limit 1",
        [c.id],
      );
      if (existing) return existing;
      await ensureApplicant(c);
      return one("insert into public.applications (applicant_id) values ($1) returning *", [c.id]);
    }

    if (seg[0] === "applications" && seg[1]) {
      const app = await applicationFor(c, seg[1]);
      if (m === "PUT" && seg.length === 2) {
        // Applicants edit while drafting, submitting or answering a more-info
        // request, and may only move the file back to draft/submitted.
        if (app.applicant_id !== c.id) throw new HttpError(403, "Only the applicant can edit this application.");
        if (!["draft", "submitted", "more_info"].includes(String(app.status))) {
          throw new HttpError(409, "This application can no longer be edited.");
        }
        const b = await readJson(req);
        const status = b.status === undefined ? String(app.status) : String(b.status);
        if (!["draft", "submitted"].includes(status) && status !== app.status) {
          throw new HttpError(403, "Status can only be draft or submitted.");
        }
        return one(
          `update public.applications
             set requested_amount = $2, tenor_months = coalesce($3, tenor_months), purpose = $4,
                 sms_text = $5, status = $6, updated_at = now()
           where id = $1 returning *`,
          [
            app.id,
            int(b.requested_amount, 0, 2_000_000_000),
            int(b.tenor_months, 1, 120),
            clean(b.purpose),
            typeof b.sms_text === "string" && b.sms_text.trim() ? b.sms_text : null,
            status,
          ],
        );
      }
      if (m === "GET" && seg[2] === "eligibility" && seg.length === 3) return latestEligibility(String(app.id));
    }

    if (m === "POST" && path === "/kyc-check") return kycCheck(c, req);
    if (m === "POST" && path === "/process-application") return processApplication(c, req);

    // Documents
    if (path === "/documents") {
      if (m === "POST") return upload(c, req, url);
      if (m === "GET") {
        return query(
          "select * from public.documents where applicant_id = $1 order by uploaded_at desc",
          [c.id],
        );
      }
    }
    if (m === "GET" && seg[0] === "documents" && seg[2] === "url" && seg.length === 3) return documentUrl(c, seg[1]);

    // Officer
    if (seg[0] === "officer") {
      requireOfficer(c);
      if (m === "GET" && path === "/officer/queue") {
        return query(`${fileSql} where a.status <> 'draft' order by a.created_at desc`);
      }
      if (seg[1] === "applications" && seg[2] && UUID.test(seg[2])) {
        const id = seg[2];
        if (m === "GET" && seg.length === 3) {
          const file = await one(`${fileSql} where a.id = $1`, [id]);
          if (!file) throw new HttpError(404, "Application not found.");
          const docs = await query(
            `select d.* from public.documents d join public.applications a on a.applicant_id = d.applicant_id
             where a.id = $1 order by d.uploaded_at desc`,
            [id],
          );
          return { ...file, documents: docs };
        }
        if (m === "POST" && seg[3] === "notes") {
          const b = await readJson(req);
          const body = clean(b.body);
          if (!body || body.length > 4000) throw new HttpError(400, "Notes must be 1–4000 characters.");
          const note = await one(
            `insert into public.officer_notes (application_id, officer_id, officer_email, body)
             select id, $2, nullif($3, ''), $4 from public.applications where id = $1
             returning *`,
            [id, c.id, c.email, body],
          );
          if (!note) throw new HttpError(404, "Application not found.");
          return note;
        }
        if (m === "POST" && seg[3] === "decision") {
          const b = await readJson(req);
          const status = String(b.status ?? "");
          if (!OFFICER_STATUSES.includes(status)) {
            throw new HttpError(400, `status must be one of ${OFFICER_STATUSES.join(", ")}.`);
          }
          const row = await one(
            `update public.applications
               set status = $2::public.application_status, officer_id = $3,
                   decided_at = case when $2::public.application_status = 'in_review' then null else now() end,
                   updated_at = now()
             where id = $1 returning *`,
            [id, status, c.id],
          );
          if (!row) throw new HttpError(404, "Application not found.");
          return row;
        }
      }
    }

    throw new HttpError(404, "Not found.");
  }

  return async function fetch(req: Request): Promise<Response> {
    const headers = cors(req, env);
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
    const url = new URL(req.url);
    try {
      const body = await route(req, url);
      return Response.json(body ?? null, { headers });
    } catch (e) {
      let status = 500;
      let message = "Something went wrong.";
      if (e instanceof HttpError || e instanceof AuthError) {
        status = e.status;
        message = e.message;
      } else if (e instanceof StorageError) {
        status = 503;
        message = e.message;
      } else if (typeof (e as { code?: unknown })?.code === "string" && /^22/.test((e as { code: string }).code)) {
        status = 400; // Postgres data exception: bad date, enum value, etc.
        message = "One of the fields is not in the right format.";
      } else {
        console.error(req.method, url.pathname, e);
      }
      return Response.json({ error: message }, { status, headers });
    }
  };
}

import { createClient, type SupabaseClient, type User } from "jsr:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

export const fail = (status: number, error: string) => json({ error }, status);

/** Client acting as the caller — RLS applies. */
export function userClient(req: Request): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );
}

/** Service-role client. Lives only inside Edge Functions, never in the app. */
export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
}

export async function requireUser(req: Request): Promise<{ user: User; client: SupabaseClient } | Response> {
  const client = userClient(req);
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return fail(401, "Sign in required.");
  return { user: data.user, client };
}

export const isOfficer = (u: User) => u.app_metadata?.role === "officer";

export async function sha256(input: string | Uint8Array<ArrayBuffer>): Promise<string> {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export const last4 = (v?: string | null) => (v && v.length >= 4 ? v.slice(-4) : null);
export const mask = (v?: string | null) => (v && v.length > 4 ? "*".repeat(v.length - 4) + v.slice(-4) : null);

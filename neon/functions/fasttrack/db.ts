// Postgres access. One long-lived pool per function instance, on the pooled
// DATABASE_URL Neon injects. The function connects as the table owner, so
// RLS (enabled, no policies) never blocks it — every access rule lives in
// api.ts instead.

import pg from "pg";

// `date` columns (dob) stay "YYYY-MM-DD" strings instead of local-midnight Dates.
pg.types.setTypeParser(1082, (v: string) => v);

export type Query = <T = Record<string, unknown>>(sql: string, params?: unknown[]) => Promise<T[]>;

export function createQuery(connectionString = process.env.DATABASE_URL): Query {
  if (!connectionString) throw new Error("DATABASE_URL is not set.");
  const pool = new pg.Pool({ connectionString, max: 5, idleTimeoutMillis: 30_000 });
  // An idle client dropped by scale-to-zero or the pooler must not crash the
  // isolate; the pool has already discarded it.
  pool.on("error", (e) => console.warn("pg idle client error:", e.message));
  return async (sql, params = []) => (await pool.query(sql, params)).rows;
}

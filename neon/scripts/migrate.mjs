// Apply neon/migrations/*.sql then neon/seeds/*.sql, in name order, each file
// in one transaction. Every file is idempotent, so re-running is safe.
//
//   DATABASE_URL=$(neon connection-string --database-name fasttrack) npm run migrate
//   npm run migrate -- --schema-only     (skip seeds)
//
// The connection string is read from the environment and never printed.

import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const url = process.env.DATABASE_URL_UNPOOLED || process.env.DATABASE_URL;
if (!url) {
  console.error("Set DATABASE_URL (e.g. DATABASE_URL=$(neon connection-string --database-name fasttrack)).");
  process.exit(1);
}

const dirs = process.argv.includes("--schema-only") ? ["migrations"] : ["migrations", "seeds"];
const client = new pg.Client({ connectionString: url });
await client.connect();
try {
  for (const dir of dirs) {
    for (const file of readdirSync(join(root, dir)).filter((f) => f.endsWith(".sql")).sort()) {
      const sql = readFileSync(join(root, dir, file), "utf8");
      await client.query("begin");
      try {
        await client.query(sql);
        await client.query("commit");
        console.log(`applied ${dir}/${file}`);
      } catch (e) {
        await client.query("rollback");
        throw new Error(`${dir}/${file}: ${e.message}`);
      }
    }
  }
} finally {
  await client.end();
}

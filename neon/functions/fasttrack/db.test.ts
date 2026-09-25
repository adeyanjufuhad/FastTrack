import { strictEqual } from "node:assert/strict";
import { test } from "node:test";

import { explicitSsl } from "./db.ts";

test("sslmode=require becomes an explicit verify-full; other params untouched", () => {
  strictEqual(
    explicitSsl("postgresql://u:p@ep-x-pooler.neon.tech/fasttrack?sslmode=require&channel_binding=require"),
    "postgresql://u:p@ep-x-pooler.neon.tech/fasttrack?sslmode=verify-full&channel_binding=require",
  );
  strictEqual(explicitSsl("postgres://h/db?channel_binding=require&sslmode=require"), "postgres://h/db?channel_binding=require&sslmode=verify-full");
  strictEqual(explicitSsl("postgres://h/db?sslmode=disable"), "postgres://h/db?sslmode=disable");
  strictEqual(explicitSsl("postgres://h/db"), "postgres://h/db");
});

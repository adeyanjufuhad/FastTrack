// Bundle the fasttrack function into dist/fasttrack.zip (a single index.mjs),
// the archive Neon's deploy endpoint expects. Deploy it with any of:
//
//   neon functions deploy fasttrack --src functions/fasttrack/index.ts   (bundles itself)
//   the Neon API / MCP deploy_function with this zip
//
// Usage: node scripts/bundle.mjs [--base64]   (--base64 also writes dist/fasttrack.zip.b64)

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { crc32, deflateRawSync } from "node:zlib";
import { build } from "esbuild";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dist = join(root, "dist");
mkdirSync(dist, { recursive: true });

const result = await build({
  entryPoints: [join(root, "functions/fasttrack/index.ts")],
  bundle: true,
  platform: "node",
  target: "node24",
  format: "esm",
  minify: true,
  legalComments: "none",
  // pg-native is an optional peer of pg; the pure-JS client is used.
  external: ["pg-native"],
  // Restore require/__filename/__dirname for bundled CommonJS (pg uses them).
  banner: {
    js: "import{createRequire as ___cr}from'module';import{fileURLToPath as ___f}from'url';import{dirname as ___d}from'path';const require=___cr(import.meta.url);const __filename=___f(import.meta.url);const __dirname=___d(__filename);",
  },
  write: false,
});
const code = result.outputFiles[0].contents;
writeFileSync(join(dist, "index.mjs"), code);

// Minimal single-entry ZIP (deflate), so no zip binary is needed.
function zip(name, data) {
  const nameBuf = Buffer.from(name);
  const body = deflateRawSync(data, { level: 9 });
  const crc = crc32(data);
  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50, 0);
  local.writeUInt16LE(20, 4); // version needed
  local.writeUInt16LE(0x0800, 6); // UTF-8 names
  local.writeUInt16LE(8, 8); // deflate
  local.writeUInt32LE(0, 10); // time/date
  local.writeUInt32LE(crc, 14);
  local.writeUInt32LE(body.length, 18);
  local.writeUInt32LE(data.length, 22);
  local.writeUInt16LE(nameBuf.length, 26);
  local.writeUInt16LE(0, 28);
  const central = Buffer.alloc(46);
  central.writeUInt32LE(0x02014b50, 0);
  central.writeUInt16LE(20, 4);
  central.writeUInt16LE(20, 6);
  central.writeUInt16LE(0x0800, 8);
  central.writeUInt16LE(8, 10);
  central.writeUInt32LE(0, 12);
  central.writeUInt32LE(crc, 16);
  central.writeUInt32LE(body.length, 20);
  central.writeUInt32LE(data.length, 24);
  central.writeUInt16LE(nameBuf.length, 28);
  central.writeUInt32LE((0o100644 << 16) >>> 0, 38); // external attrs: -rw-r--r--
  central.writeUInt32LE(0, 42); // local header offset
  const cdOffset = local.length + nameBuf.length + body.length;
  const cdSize = central.length + nameBuf.length;
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(1, 8);
  end.writeUInt16LE(1, 10);
  end.writeUInt32LE(cdSize, 12);
  end.writeUInt32LE(cdOffset, 16);
  return Buffer.concat([local, nameBuf, body, central, nameBuf, end]);
}

const archive = zip("index.mjs", Buffer.from(code));
writeFileSync(join(dist, "fasttrack.zip"), archive);
if (process.argv.includes("--base64")) writeFileSync(join(dist, "fasttrack.zip.b64"), archive.toString("base64"));
console.log(`index.mjs ${(code.length / 1024).toFixed(1)} KiB → fasttrack.zip ${(archive.length / 1024).toFixed(1)} KiB`);

// Private "documents" bucket on Neon Object Storage (S3-compatible).
// Credentials are injected into the function by Neon (AWS_* variables) and
// never leave it: the app uploads through the function and reads through
// short-lived presigned links.

import { AwsClient } from "aws4fetch";

export const BUCKET = "documents";
export const MAX_BYTES = 8 * 1024 * 1024;
export const ALLOWED_MIME = ["image/jpeg", "image/png", "application/pdf"] as const;
export const SIGNED_URL_SECONDS = 600;

export class StorageError extends Error {}

export interface Storage {
  put(key: string, body: Uint8Array<ArrayBuffer>, mime: string): Promise<void>;
  get(key: string): Promise<Uint8Array>;
  signedUrl(key: string, seconds?: number): Promise<string>;
}

export function s3Storage(env = process.env): Storage {
  const endpoint = env.AWS_ENDPOINT_URL_S3?.replace(/\/$/, "");
  const accessKeyId = env.AWS_ACCESS_KEY_ID;
  const secretAccessKey = env.AWS_SECRET_ACCESS_KEY;
  const unavailable = () => {
    throw new StorageError("Object Storage is not enabled on this branch.");
  };
  if (!endpoint || !accessKeyId || !secretAccessKey) {
    return { put: unavailable, get: unavailable, signedUrl: unavailable };
  }
  const aws = new AwsClient({
    accessKeyId,
    secretAccessKey,
    region: env.AWS_REGION ?? "us-east-2",
    service: "s3",
  });
  // Path-style addressing: <endpoint>/<bucket>/<key>
  const url = (key: string) =>
    `${endpoint}/${BUCKET}/${key.split("/").map(encodeURIComponent).join("/")}`;

  return {
    async put(key, body, mime) {
      const res = await aws.fetch(url(key), {
        method: "PUT",
        body,
        headers: { "Content-Type": mime },
      });
      if (!res.ok) throw new StorageError(`Upload failed (${res.status}).`);
    },
    async get(key) {
      const res = await aws.fetch(url(key));
      if (!res.ok) throw new StorageError(`Download failed (${res.status}).`);
      return new Uint8Array(await res.arrayBuffer());
    },
    async signedUrl(key, seconds = SIGNED_URL_SECONDS) {
      const signed = await aws.sign(`${url(key)}?X-Amz-Expires=${seconds}`, {
        method: "GET",
        aws: { signQuery: true },
      });
      return signed.url;
    },
  };
}

/** `<uid>/<kind>-<ms>-<safe name>` — every applicant's files sit under their id. */
export function objectKey(uid: string, kind: string, name: string, now = Date.now()) {
  const safe = name.replace(/[^A-Za-z0-9._-]/g, "_").slice(-100) || "file";
  return `${uid}/${kind}-${now}-${safe}`;
}

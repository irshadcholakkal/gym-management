import { ECDH } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

export function validateVapidPublicKey(value = '') {
  const key = value.trim();
  if (!key) return '';
  try {
    if (!/^[A-Za-z0-9_-]{87}=?$/.test(key)) throw new Error();
    const bytes = Buffer.from(key, 'base64url');
    if (bytes.length !== 65 || bytes[0] !== 4) throw new Error();
    ECDH.convertKey(bytes, 'prime256v1');
    return key.replace(/=+$/, '');
  } catch {
    throw new Error('VAPID_PUBLIC_KEY must be a base64url-encoded P-256 public key (65 bytes). Use the public key matching the private key in Supabase Edge secrets, then rebuild the app.');
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  let input = '';
  for await (const chunk of process.stdin) input += chunk;
  try { validateVapidPublicKey(input); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}

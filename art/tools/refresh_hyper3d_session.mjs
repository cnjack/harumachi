// Reuse the installed CLI's existing OAuth provider. No device flow or account switch.
import { execFileSync } from 'node:child_process';
import { realpath, readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

const executable = execFileSync('which', ['hyper3d'], { encoding: 'utf8' }).trim();
const entry = await realpath(executable);
const distribution = dirname(entry);
const pkg = JSON.parse(await readFile(join(distribution, '..', 'package.json'), 'utf8'));
if (pkg.name !== '@hyper3d/cli') throw new Error('Unexpected Hyper3D executable; stop');
const { loadCredentials, createProvider, CLI_CLIENT_ID } = await import(pathToFileURL(join(distribution, 'auth.js')).href);
const { endpoints } = await import(pathToFileURL(join(distribution, 'endpoints.js')).href);
const saved = await loadCredentials(endpoints.mcp);
if (saved.clientId !== CLI_CLIENT_ID || !saved.tokens?.access_token) {
  throw new Error('Existing CLI credentials missing or belong to another client; stop');
}
if (saved.expiresAt === undefined || saved.expiresAt > Date.now() + 120000) {
  console.log(JSON.stringify({ refreshed: false, reason: 'existing token is current' }));
  process.exit(0);
}
if (!saved.tokens?.refresh_token) throw new Error('Existing session needs user login; no refresh token');
const require = createRequire(entry);
const { auth } = await import(pathToFileURL(require.resolve('@modelcontextprotocol/sdk/client/auth.js')).href);
const events = [];
const read = async (input, init) => {
  const response = await fetch(input, init);
  events.push({ path: new URL(typeof input === 'string' ? input : input.url || String(input)).pathname, status: response.status });
  return response;
};
const provider = createProvider(endpoints.mcp, saved, read);
const result = await auth(provider, { serverUrl: endpoints.mcp, fetchFn: provider.fetch });
const latest = await loadCredentials(endpoints.mcp);
if (result !== 'AUTHORIZED' || !latest.tokens?.access_token) throw new Error('Same-session refresh failed; do not generate');
console.log(JSON.stringify({ refreshed: true, result, expires_at: latest.expiresAt, scope: latest.tokens?.scope, events }));

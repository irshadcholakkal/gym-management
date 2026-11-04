import { createClient as makeClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';
import { isSupportedPushEndpoint } from '../_shared/push_endpoint.ts';
type Dependencies = { createClient: typeof makeClient; push: typeof webpush; env: (name: string) => string | undefined };
export function testPushHandler(deps: Dependencies = { createClient: makeClient, push: webpush, env: name => Deno.env.get(name) }) {
const { createClient, push: webpush, env } = deps;
const origin = env('APP_ORIGIN') ?? 'http://localhost:8080';
const headers = { 'Access-Control-Allow-Origin': origin, 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Vary': 'Origin' };
const reply = (error: string, status: number) => new Response(JSON.stringify({ error }), { status, headers });
return async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers });
  if (req.method !== 'POST') return reply('Method not allowed', 405);
  const authorization = req.headers.get('Authorization');
  if (!authorization) return reply('Authentication required', 401);
  const client = createClient(env('SUPABASE_URL')!, env('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: { user }, error: authError } = await client.auth.getUser();
  if (authError || !user) return reply('Invalid session', 401);
  try {
    const input = await req.json();
    if (typeof input.gym_id !== 'string' || !/^[a-f0-9-]{36}$/i.test(input.gym_id) || typeof input.endpoint !== 'string' || input.endpoint.length > 4096) return reply('Valid gym and device subscription required', 400);
    // RLS and explicit recipient filtering restrict tests to this user's own active subscription.
    const { data: subscription, error } = await client.from('push_subscriptions').select('endpoint,keys').eq('gym_id', input.gym_id).eq('user_id', user.id).eq('endpoint', input.endpoint).eq('enabled', true).maybeSingle();
    if (error || !subscription) return reply('Enable push notifications on this device first', 409);
    if (!isSupportedPushEndpoint(subscription.endpoint)) return reply('Unsupported push provider', 400);
    const publicKey = env('VAPID_PUBLIC_KEY'), privateKey = env('VAPID_PRIVATE_KEY'), subject = env('VAPID_SUBJECT');
    if (!publicKey || !privateKey || !subject) return reply('Server push is not configured', 503);
    try {
      webpush.setVapidDetails(subject, publicKey, privateKey);
    } catch {
      return reply('Server push credentials are invalid', 503);
    }
    try {
      await webpush.sendNotification(subscription, JSON.stringify({ type: 'test', gym_id: input.gym_id }), { TTL: 60, timeout: 10000 });
    } catch (failure) {
      const code = (failure as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) {
        await client.rpc('remove_push', { p_gym: input.gym_id, p_endpoint: input.endpoint });
        return reply('Push subscription expired', 410);
      }
      if (code === 401 || code === 403) {
        return reply('Push provider rejected the server credentials. Verify the VAPID key pair and reconnect this device.', 422);
      }
      return reply('Push provider could not accept the test', 502);
    }
    return new Response(JSON.stringify({ sent: true }), { headers });
  } catch { return reply('Unable to send test push', 400); }
};
}

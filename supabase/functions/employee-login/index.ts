import { createClient } from 'npm:@supabase/supabase-js@2';
const origin = Deno.env.get('APP_ORIGIN') ?? 'http://localhost:8080';
const headers = { 'Access-Control-Allow-Origin': origin, 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Vary': 'Origin' };
const failure = () => new Response(JSON.stringify({ error: 'Invalid employee ID, username or password.' }), { status: 401, headers });
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers });
  if (req.method !== 'POST') return new Response(null, { status: 405, headers });
  try {
    const input = await req.json();
    if (typeof input.identifier !== 'string' || input.identifier.length > 128 || typeof input.password !== 'string' || !input.password || input.password.length > 1024) return failure();
    const identifier = input.identifier.trim().toLowerCase();
    const url = Deno.env.get('SUPABASE_URL')!;
    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false, autoRefreshToken: false } });
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(identifier));
    const key = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, '0')).join('');
    const { data: allowed, error: limitError } = await admin.rpc('allow_employee_login', { p_key: key });
    if (limitError) return failure();
    if (!allowed) return new Response(JSON.stringify({ error: 'Too many sign-in attempts. Try again in 15 minutes.' }), { status: 429, headers: { ...headers, 'Retry-After': '900' } });
    const { data: userId, error } = await admin.rpc('resolve_employee_login', { p_identifier: identifier });
    if (error || !userId) return failure();
    const { data: account, error: accountError } = await admin.auth.admin.getUserById(userId);
    if (accountError || !account.user?.email) return failure();
    const client = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data, error: signInError } = await client.auth.signInWithPassword({ email: account.user.email, password: input.password });
    if (signInError || !data.session) return failure();
    // Recheck active access after password verification, including concurrent deactivation.
    const { data: stillActive } = await admin.rpc('resolve_employee_login', { p_identifier: identifier });
    if (stillActive !== userId) return failure();
    return new Response(JSON.stringify({ refresh_token: data.session.refresh_token }), { headers });
  } catch { return failure(); }
});

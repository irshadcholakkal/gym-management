import { createClient } from 'npm:@supabase/supabase-js@2';

const origin = Deno.env.get('APP_ORIGIN') ?? 'http://localhost:8080';
const headers = { 'Access-Control-Allow-Origin': origin, 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Content-Type': 'application/json', 'Vary': 'Origin' };
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers });
  if (req.method !== 'POST') return new Response('{"error":"Method not allowed"}', { status: 405, headers });
  const authorization = req.headers.get('Authorization');
  if (!authorization) return new Response('{"error":"Authentication required"}', { status: 401, headers });
  const url = Deno.env.get('SUPABASE_URL')!;
  const caller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authorization } } });
  const { data: { user }, error: authError } = await caller.auth.getUser();
  if (authError || !user) return new Response('{"error":"Invalid session"}', { status: 401, headers });
  try {
    const input = await req.json();
    const { data: allowed, error: permissionError } = await caller.rpc('can_administer', { p_gym: input.gym_id });
    if (permissionError || !allowed) return new Response('{"error":"Administrator permission required"}', { status: 403, headers });
    if (!['admin', 'manager', 'trainer', 'receptionist', 'staff'].includes(input.role) ||
      typeof input.full_name !== 'string' || !input.full_name.trim() ||
      typeof input.email !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.email.trim())) {
      return new Response('{"error":"Valid name, email and role required"}', { status: 400, headers });
    }
    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
    const { data, error } = await admin.auth.admin.inviteUserByEmail(input.email.trim().toLowerCase(), {
      data: { full_name: input.full_name.trim(), requires_password_setup: true }, redirectTo: `${origin}/#/recovery`,
    });
    if (error) throw error;
    const { error: attachError } = await admin.rpc('attach_invited_employee', {
      p_gym: input.gym_id, p_actor: user.id, p_user: data.user.id,
      p_name: input.full_name.trim(), p_email: input.email.trim().toLowerCase(),
      p_role: input.role, p_phone: input.phone ?? '', p_designation: input.designation ?? '',
    });
    if (attachError) {
      // Never delete an Auth identity as compensation: it may have other tenants.
      console.error('Invitation requires reconciliation', data.user.id, input.gym_id, attachError.code);
      return new Response('{"error":"Invitation sent, but gym access could not be assigned. Contact your administrator for reconciliation."}', { status: 409, headers });
    }
    return new Response(JSON.stringify({ user_id: data.user.id, invited: true }), { headers });
  } catch (error) {
    console.error('Invitation failed', error instanceof Error ? error.name : 'unknown');
    return new Response('{"error":"Unable to invite employee. Check the address and existing account status."}', { status: 400, headers });
  }
});

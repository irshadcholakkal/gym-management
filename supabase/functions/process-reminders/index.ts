import { createClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

Deno.serve(async (req: Request) => {
  const secret = Deno.env.get('REMINDER_JOB_SECRET');
  if (!secret || req.headers.get('Authorization') !== `Bearer ${secret}`) return new Response('Unauthorized', { status: 401 });
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
  const { error: reminderError } = await client.rpc('process_expiry_reminders');
  if (reminderError) return new Response('Reminder generation failed', { status: 500 });
  // In-app reminders are committed even if VAPID has not been configured.
  const publicKey = Deno.env.get('VAPID_PUBLIC_KEY'), privateKey = Deno.env.get('VAPID_PRIVATE_KEY');
  if (!publicKey || !privateKey) return Response.json({ in_app: true, push: 'not_configured' });
  webpush.setVapidDetails(Deno.env.get('VAPID_SUBJECT')!, publicKey, privateKey);
  const { data: jobs, error } = await client.rpc('claim_push_deliveries');
  if (error) return new Response('Unable to claim delivery jobs', { status: 500 });
  for (const job of jobs ?? []) {
    let success = false, gone = false, message = '';
    try {
      const endpoint = new URL(job.subscription.endpoint);
      const host = endpoint.hostname;
      if (!(host === 'fcm.googleapis.com' || host.endsWith('.push.services.mozilla.com') || host === 'updates.push.services.mozilla.com' || host.endsWith('.push.apple.com') || host.endsWith('.notify.windows.com'))) {
        gone = true; throw new Error('Unsupported push endpoint');
      }
      await webpush.sendNotification(job.subscription, JSON.stringify({ type: 'gym_update' }), { TTL: 3600, timeout: 10000 });
      success = true;
    } catch (error) {
      const code = (error as { statusCode?: number }).statusCode;
      gone ||= code === 404 || code === 410;
      message = code ? `Push provider status ${code}` : 'Push delivery failed';
    }
    await client.rpc('complete_push_delivery', { p_id: job.id, p_attempt: job.attempt, p_success: success, p_gone: gone, p_error: message });
  }
  return Response.json({ processed: jobs?.length ?? 0 });
});

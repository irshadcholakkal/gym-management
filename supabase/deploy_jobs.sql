-- Run ONLY in the hosted project's SQL editor after setting these Vault secrets:
-- gympro_project_url = https://<project>.supabase.co
-- gympro_reminder_job_secret = the same value as REMINDER_JOB_SECRET in Edge secrets
-- This script was not executed against a hosted project by the implementation.
create extension if not exists pg_cron;
create extension if not exists pg_net;
select cron.schedule('gympro-push-delivery','*/5 * * * *', $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name='gympro_project_url') || '/functions/v1/process-reminders',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='gympro_reminder_job_secret')),
    body := '{}'::jsonb
  );
$job$);

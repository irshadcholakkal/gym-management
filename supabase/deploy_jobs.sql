-- Run ONLY in the hosted project's SQL editor after setting these Vault secrets:
-- gympro_project_url = https://<project>.supabase.co
-- gympro_reminder_job_secret = the same value as REMINDER_JOB_SECRET in Edge secrets
-- Re-running this updates the named job without creating a second schedule.
create extension if not exists pg_cron;
create extension if not exists pg_net;
select cron.schedule('gympro-push-delivery','*/5 * * * *', $job$
  select net.http_post(
    url := rtrim(btrim((select decrypted_secret from vault.decrypted_secrets where name='gympro_project_url'), E' \t\r\n'), '/') || '/functions/v1/process-reminders',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||btrim((select decrypted_secret from vault.decrypted_secrets where name='gympro_reminder_job_secret'), E' \t\r\n')),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
$job$);

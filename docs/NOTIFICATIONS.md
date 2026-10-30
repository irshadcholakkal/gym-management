# Notifications

Membership alerts are generated on the server for 7, 3, and 1 days before the last valid membership day, on that last day, and after expiry. Expired memberships from the last seven days are caught up if a job was missed. Paused memberships do not generate expiry alerts. Old reminders are superseded when membership dates or states change. Repeated job runs do not recreate the same current alert. Owners, admins, managers, and receptionists receive alerts for their own gym.

The bell displays the unread count. Notifications supports unread, warnings, and reminders filters, marking an alert read, and opening the related membership. Push taps open the specific inbox alert; the login flow preserves this destination. Records remain restricted by the signed-in user's gym and recipient. Lock-screen messages do not contain member names or phone numbers.

## Deployment

1. Apply migrations, including `202610300001_notification_reminders.sql`.
2. Set Edge Function secrets `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` (a valid `mailto:` contact), and `REMINDER_JOB_SECRET`.
3. Deploy `process-reminders` (JWT verification is disabled in `supabase/config.toml`; the function verifies its own job secret).
4. Set Vault secrets `gympro_project_url` and `gympro_reminder_job_secret`, then run `supabase/deploy_jobs.sql` to schedule delivery every five minutes.
5. Build the PWA with the matching **public** VAPID key using `tool/build_web.ps1` and deploy over HTTPS. The build script versions the service worker cache.
6. In Notifications, choose **Enable push on this device**, then allow browser notifications. Each device must subscribe separately. If permission is blocked, change the browser site setting. On iPhone/iPad, install the PWA on the Home Screen and enable push from the installed app.

In-app notifications remain available without push permission or VAPID configuration. The app synchronizes while open; server jobs generate and deliver alerts while it is closed. The enable action confirms browser registration, not end-to-end server delivery.

## Hosted verification

Use a test membership with last valid day today/tomorrow and invoke the reminder job with its job secret. Check the inbox and delivery records; repeat the job to confirm no duplicates. Close the PWA and wait for push delivery. Tap the notification, sign in if needed, and use View membership. Verify that a second user cannot see another recipient's alert and that paused or renewed dates retire obsolete alerts.

Local checks: `flutter analyze`, `flutter test`, and `node --test test/push_worker_test.mjs`. SQL and real browser delivery require a configured Supabase project and subscribed device.

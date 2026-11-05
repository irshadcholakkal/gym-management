# Notifications

Membership alerts are generated on the server for 7, 3, and 1 days before the last valid membership day, on that last day, and after expiry. Expired memberships from the last seven days are caught up if a job was missed. Paused memberships do not generate expiry alerts. Old reminders are superseded when membership dates or states change. Repeated job runs do not recreate the same current alert. Owners, admins, managers, and receptionists receive alerts for their own gym.

The bell displays the unread count. Notifications supports unread, warnings, and reminders filters, marking an alert read, and opening the related membership. Push taps open the specific inbox alert; the login flow preserves this destination. Records remain restricted by the signed-in user's gym and recipient. Lock-screen messages do not contain member names or phone numbers.

## Deployment

1. Apply migrations, including `202610300001_notification_reminders.sql` and `202611010002_reminder_query_alias.sql`. The alias fix is required for reminder generation on PostgreSQL.
2. Set Edge Function secrets `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` (a valid `mailto:` contact), and `REMINDER_JOB_SECRET`.
3. Deploy `process-reminders` (JWT verification is disabled in `supabase/config.toml`; the function verifies its own job secret).
4. Set Vault secrets `gympro_project_url` and `gympro_reminder_job_secret`, then run `supabase/deploy_jobs.sql` to schedule delivery every five minutes.
5. Build the PWA with the matching **public** VAPID key using `tool/build_web.ps1` and deploy over HTTPS. The build script versions the service worker cache.
6. In Notifications, choose **Enable push on this device**, then allow browser notifications. Each device must subscribe separately. If permission is blocked, change the browser site setting. On iPhone/iPad, install the PWA on the Home Screen and enable push from the installed app.

In-app notifications remain available without push permission or VAPID configuration. The app synchronizes while open; server jobs generate and deliver alerts while it is closed. The enable action confirms browser registration, not end-to-end server delivery.

The scheduling SQL trims accidental whitespace from Vault configuration and allows 60 seconds for the delivery request. A successful cron run only confirms that the HTTP request was queued; inspect `net._http_response` and `notification_deliveries` to verify processing and provider acceptance.

## Test by entering a membership

Use a separate test member and a one-day package. Set the membership start date to today's date in the gym timezone and leave it active. Its last valid day is today, so it qualifies for `expiry_0`. For a tomorrow reminder, use a two-day package starting today (`expiry_1`). Wait for synchronization and the next five-minute delivery run, then check the in-app inbox and the device notification center. Owners, admins, managers, and receptionists receive these reminders; paused memberships do not qualify.

Keep the reminder unread while testing push: read or superseded reminders are excluded from delivery. Re-running the job does not send an already delivered reminder again. Use a new test membership for a fresh end-to-end test; do not change real membership dates just to trigger a notification.

## Hosted verification

Use a test membership with last valid day today/tomorrow and invoke the reminder job with its job secret. Check the inbox and delivery records; repeat the job to confirm no duplicates. Close the PWA and wait for push delivery. Tap the notification, sign in if needed, and use View membership. Verify that a second user cannot see another recipient's alert and that paused or renewed dates retire obsolete alerts.

Local checks: `flutter analyze`, `flutter test`, and `node --test test/push_worker_test.mjs`. SQL and real browser delivery require a configured Supabase project and subscribed device.

## Diagnosing a missing test notification

Settings provides two separate checks:

- **Test device display** asks this browser's active service worker to display a local notification. It does not contact the push server or confirm remote delivery. If the request succeeds but nothing appears, check the browser/site and operating system notification settings, notification center, and Do Not Disturb.
- **Test notification** sends through the authenticated `test-push` function to the current device only. Acceptance by the provider does not prove that the operating system displayed a notification.

The server reports missing/invalid VAPID configuration as HTTP 503, expired subscriptions as 410, and provider rejection of credentials as 422. For credential rejection, verify that the deployed server's public/private VAPID keys match the public key compiled into the web app, configure a valid VAPID subject, then reconnect the device. A temporary provider failure remains 502. Server diagnostics never return private keys or raw provider responses.

Deploy the updated `test-push` function and rebuild/redeploy the web app to publish these diagnostics and the display check. Existing deployed clients do not gain them from local code changes.

Firebase Cloud Messaging can replace the delivery transport, but is not configured in this repository. A migration needs a Firebase project, web app configuration, web push credentials, server-side sending credentials, token registration/refresh and reminder delivery changes. Web FCM still depends on notification permission and a service worker; it does not bypass device notification settings. Keep existing Supabase authentication and recipient authorization if adding FCM.

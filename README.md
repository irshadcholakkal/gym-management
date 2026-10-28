# GymPro UAE

Flutter Web gym-management application with Supabase tenancy, a Drift SQLite cache, durable sync operations, subscription transactions, manual collections, and PDF receipts. No demo records or administrator keys are embedded in the client.

**Implementation status:** this is an integrated implementation in progress, not a completed production release of the entire specification. Local checks and backend PostgreSQL tests are available. Hosted Supabase Auth, invitations, Realtime, browser push delivery, and production deployment require a configured project and separate acceptance verification. See [implementation status](docs/IMPLEMENTATION_STATUS.md) for exact boundaries.

## Run

For the local `.env` workflow, set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`, then run `./tool/run_web.ps1`, or choose **GymPro UAE (Supabase from .env)** in VS Code and press F5. The prelaunch task regenerates ignored `config.local.json` using an explicit public-key allow-list. Never pass the original `.env` to Flutter or bundle it as an asset: it may contain server secrets. Legacy `SUPABASE_ANON_KEY` remains supported.

Use the Flutter SDK's bundled Dart. This machine also has an older standalone Dart on PATH, which cannot run these native-asset dependencies.

```powershell
flutter pub get
flutter pub run build_runner build
Copy-Item config.example.json config.local.json
# Replace the public configuration values in config.local.json.
flutter run -d chrome --web-port 8080 --dart-define-from-file=config.local.json
```

Running without configuration displays an actionable setup page. It does not bypass authentication or seed artificial business data. Only public publishable/anon and VAPID public keys belong in Flutter's configuration. Service-role, VAPID private, and job secrets belong exclusively in Supabase's environment/Vault.

## Supabase setup

Hosted email redirects are maintained separately in [deploy/production](deploy/production/README.md). Use that scoped configuration for production Auth URLs; the root Supabase configuration intentionally retains localhost for local development.

1. Install the Supabase CLI and Docker for local hosted-service testing, or link a development Supabase project.
2. Apply all files in `supabase/migrations` in lexical order (`supabase db reset` locally, or `supabase db push` against a linked development project).
3. Register an owner using Create account, confirm the email, and sign in. On **Set up your gym**, enter the gym name and choose **Create gym workspace**. The checked RPC creates a new tenant for the verified caller; it cannot grant access to someone else's gym. Operator-only bootstrap remains available through `select public.bootstrap_gym('OWNER_AUTH_UUID'::uuid, 'Your gym name');` if needed.
4. Configure Auth Site URL and redirect allow-list for the application's actual HTTPS URL and `/#/recovery` callback. Enable email signup and email confirmation for the Create account flow; configure production SMTP. Registration creates only an Auth account; tenant membership and roles must be assigned by an administrator. Local invitation email is inspected in Supabase's local mail UI.
5. Disable public Realtime channels in Supabase Realtime settings. The application subscribes to private `gym:<uuid>` channels; RLS permits only active tenant members to receive generic invalidations.
6. Deploy `invite-employee` and `process-reminders`. Set `APP_ORIGIN`, `REMINDER_JOB_SECRET`, `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, and `VAPID_SUBJECT` (a valid `mailto:` contact) in Edge secrets. Supabase supplies the server-side project/service-role environment.
7. Seven-day in-app reminders are scheduled hourly when `pg_cron` is available. For push delivery, create the two named Vault secrets and execute [deploy_jobs.sql](supabase/deploy_jobs.sql). Keep the app open only for client synchronization; server reminder generation does not depend on an open browser.

Employee invitations use a server-side Auth administration call followed by a checked transactional gym attachment. If attachment fails after the email is sent, the function reports a reconciliation error and never deletes a potentially shared Auth identity. Creating a gym owner is a separate operator workflow.

## Build and host the PWA

### Vercel (Git deployment)

The root `vercel.json` configures Flutter rather than treating this repository as an already-built static site. Set **Root Directory** to the repository root and **Framework Preset** to **Other**. The checked-in build command is `node tool/vercel_build.mjs`; its output is `build/web`. The script downloads the pinned Flutter 3.47.2 SDK, resolves dependencies, builds the web application, and prepares the versioned offline worker. Do not set the root directory to `web` or `build/web`.

In Vercel **Settings → Environment Variables**, add `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` for Production (and Preview if needed). Set `AUTH_REDIRECT_URL` to `https://gym-management-indol.vercel.app/#/recovery`; `VAPID_PUBLIC_KEY` is optional until push is configured. Then redeploy. Local `.env` and `config.local.json` are ignored and are not automatically available to Vercel builds. Server secret keys must never be compiled into Flutter; the build explicitly exports only public settings.

The deployment configuration serves the generated `index.html` for application routes, preserves real static assets, and sets revalidation headers for safe PWA updates. A missing asset with a filename extension still returns 404 instead of accidentally serving HTML as JavaScript/WASM. A Vercel `404 NOT_FOUND` at `/` occurs before Flutter runs; ensure the deployment build succeeded and is serving the configured output directory.

```powershell
./tool/build_web.ps1 -SupabaseUrl 'https://PROJECT.supabase.co' `
  -SupabaseAnonKey 'PUBLIC_KEY' -AuthRedirectUrl 'https://APP/#/recovery' `
  -VapidPublicKey 'PUBLIC_VAPID_KEY'
```

Host `build/web` over HTTPS. Serve `.wasm` as `application/wasm`; do not rewrite missing asset requests to HTML. Set `Cache-Control: no-cache` on HTML, the worker, bootstrap scripts, and the manifest. Do not add another Flutter service worker. The build script versions the custom worker and discovers bundled public assets, fonts, and shaders for offline precaching. It includes the local CanvasKit engine, Drift worker, and SQLite WASM; it never caches Supabase API responses. An update waits for the user to select the update button before activation.

`web/sqlite3.wasm` comes from the sqlite3.dart `sqlite3-3.8.0` release. `web/drift_worker.dart.js` is the worker distributed with Drift `2.35.3`. Update these together with their Dart dependencies and retest browser persistence. Original package licenses apply. Browser OPFS/IndexedDB availability varies; storage may be evicted. Synchronization resumes when the app runs, and is not guaranteed while it is closed. The current policy requires online authorization to unlock a restored session.

## Verification

```powershell
flutter analyze
flutter test
npm ci --prefix tool/database
npm test --prefix tool/database
flutter build web --pwa-strategy=none --no-web-resources-cdn --no-wasm-dry-run
node tool/prepare_web.mjs
npm ci --prefix tool/browser
npm test --prefix tool/browser
```

The database suite executes migrations and RPCs in PostgreSQL WASM (PGlite), with minimal Auth/Storage/Realtime adapters. It validates real PostgreSQL constraints, roles, RLS, transactions, and idempotency, but cannot validate the hosted services themselves. Browser smoke checks use installed Chrome; they cover the unauthenticated setup shell and offline precaching. They do not imply that all 20 requested end-to-end scenarios passed.

## Code map and invariants

Membership creation and the dedicated **Renew membership** action support an optional **Special discount** amount and required reason for owners, admins and managers. Discounts apply to the membership price before tax, not the enrollment fee; the original package price remains in the snapshot. Invoices/receipts preserve the discount, and **Discounts given this month** totals discounts granted on non-void invoices in the current Dubai calendar month. Resume paused memberships before scheduling a renewal. The schema change is in `202610280001_membership_discounts.sql`.

- `lib/core`: application/router, design system, scoped local database, optimistic repository, synchronization, durable server command identities, shared directory/detail/editor widgets.
- `lib/features/auth`: Supabase authentication repository, session Cubit, role access, login/reset/recovery forms.
- `lib/features/members`: generated Freezed/JSON member model.
- `lib/features/subscriptions`: calendar preview logic and protected operations repository; PostgreSQL is authoritative for transitions.
- `lib/features/payments`, `lib/features/receipts`: exact money helpers and final-receipt PDF rendering.
- `lib/features/dashboard`, `lib/features/notifications`: reactive collections chart and browser push adapter.
- `supabase/migrations`: tenant schema, RLS, subscription/invoice/payment operations, receipt snapshots, reminders, delivery claims, bootstrap.
- `supabase/functions`: trusted employee invitation and VAPID push delivery.

Memberships use exclusive end dates and calendar-aware PostgreSQL intervals. Pause ranges are half-open and cannot overlap. Payments and package charges use integer minor units and tenant transaction locks. A package update never changes a historical invoice. Collection retries reuse durable operation IDs, including across dialogs and refreshes. Server-only financial commands wait for authorization and are never silently converted into finalized offline payments. Receipt numbers and snapshots are issued inside the payment transaction; reversal voids the receipt while preserving the payment and allocations.

Delta cursors are durable. Every application write acquires the tenant advisory lock before allocating change-log cursors, so commit ordering cannot skip an earlier transaction. Future trusted write paths must follow the same invariant. Broadcasts are invalidation hints, not an event history. No table-write grants are issued to browser clients; mutations go through checked RPCs.

Local caches/outboxes are isolated by gym, authenticated user, and role. Offline member/package changes and outbox entries are atomic. Conflicts retain local data and require review; the interface can discard an uncommitted local record and fetch the server version. Financial confirmation commands cannot be changed into ordinary outbox retries. They retain their request identity until the server explicitly confirms them or definitively rejects the transaction.

Official reference APIs consulted: [Supabase Flutter](https://supabase.com/docs/reference/dart/introduction), [Drift Web](https://drift.simonbinder.eu/platforms/web/), [GoRouter](https://pub.dev/packages/go_router), [Flutter BLoC](https://pub.dev/packages/flutter_bloc), [Freezed](https://pub.dev/packages/freezed), [Realtime authorization](https://supabase.com/docs/guides/realtime/authorization), [printing](https://pub.dev/packages/printing), and [PGlite extensions](https://pglite.dev/extensions/).
# gym-management

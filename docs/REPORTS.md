# Monthly and yearly reports

Open **Reports** in the navigation menu. Choose Monthly or Yearly, select the
year and optional month, then choose **Generate report**. Download PDF, Excel
(`.xlsx`) or CSV from the generated report. PDF includes all sections; Excel
has one worksheet per section with numeric amounts, frozen headers and filters.
CSV is one document with section headings and protected text values.

For specific dates, choose **Custom**, tap the date range button and select
the start and end dates on the calendar. Tap **Use dates**, then
**Generate report**. Both selected dates are included; selecting the same date
twice generates a single-day report. Custom ranges can cross months and years,
and all export formats show the selected dates in the report and filename.
Apply `202611080004_custom_date_reports.sql` to enable custom dates on the
server. Monthly and yearly reports share the same date-range engine.

The preview shows up to 50 rows per section; exports include all rows. Empty
periods can also be exported. Generating requires an internet connection and
financial operations access. Sync local pending changes first.

## Database deployment

Apply the repository migrations in order before deploying the client. Reports
require `202611080002_plan_change_accounting.sql` (the member credit ledger)
and `202611080003_period_reports.sql` (the report RPC). The migrations are
additive. Review any older pending migrations before pushing to a hosted
database; do not assume a linked production database is up to date.

`get_period_report` verifies the caller's financial permission and gym
membership on the server. It reads a single database snapshot and returns full
results without the REST table row limit. It never creates financial entries.

## Report basis

- Periods follow the gym's configured timezone, with an inclusive start and
  exclusive next-month or next-year boundary.
- Invoices belong to their issue period. Billing totals exclude voided invoices.
  The detail sheet retains voided invoices for reference.
- Gross collections use payment creation dates. Refunds and reversals reduce
  collections in their own recording period, including reversals of older
  payments. A payment subsequently reversed still appears in its original
  collection period; it is not silently removed from both reports.
- Totals are separated by currency. Payments and receipts are not added together.
- Invoice amounts, payment allocations, credits, outstanding balances and
  record statuses are current at generation. These are **not** reconstructed
  historical closing balances. Outstanding amounts relate only to invoices
  issued in the selected period, not all gym receivables.
- New members use joining date; membership starts use start date. Cancelled
  and deleted memberships remain in the detail with their stored current status.
- Credits have separate detail sections and are not cash collections.
- Expenses and profit are outside the available accounting data.

## Validation

Run `flutter test test/period_report_test.dart test/reports_page_test.dart
test/access_test.dart`, `node tool/database/integration.mjs`, and
`flutter analyze`. The database suite checks timezone boundaries, leap months,
yearly selection, over 1,000 rows, cross-period reversals, tenant isolation and
restricted roles. Export tests check amounts, real XLSX/XML structure, literal
text handling, CSV escaping and multi-page PDF generation. Hosted deployment
and physical-device save dialogs require separate acceptance checks.

For browser download checks, run the report tests first to create the test
fixture, build the web client using `config.local.json`, run
`node tool/prepare_web.mjs`, then `node tool/browser/reports_ui_test.mjs`.
This test intercepts all backend traffic and downloads real PDF, XLSX and CSV
files from the rendered app using simulated report data.

# Production Auth redirects

The hosted Supabase project uses `https://gym-management-indol.vercel.app` as its Auth Site URL. Production email confirmation and password recovery destinations are in the redirect allow-list. Local development on port 8080 is allowed explicitly, but is not the default email destination.

This directory declares only the two hosted redirect properties. Review and apply it with an authenticated Supabase CLI:

```powershell
npx supabase@latest config diff --project-ref npdwavyzkwkmyptcxawx --workdir deploy/production
npx supabase@latest config push --project-ref npdwavyzkwkmyptcxawx --workdir deploy/production --yes
```

The root `supabase/config.toml` is for local development and deliberately has a localhost Site URL. Do not push that development Auth configuration to production. The CLI leaves undeclared properties (including confirmation policy, email settings and MFA) unchanged when applying this scoped file.

Applied and checked on October 27, 2026. Both the default verification redirect and an explicitly requested production callback returned HTTP 303 to the production host when tested with an invalid dummy token. No real verification tokens were consumed and no emails were sent during this check.

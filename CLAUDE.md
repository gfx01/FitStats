# FitStats: notes for working on this repo

## Versions (every release)

A release is a push to `main`: it builds the IPA and, when `supabase/functions/**` changed,
deploys the server. With every release:

- **App version** (Settings → About → App): bump `MARKETING_VERSION` in `ios/project.yml` and add
  1 to `CURRENT_PROJECT_VERSION` (the build number in brackets). Keep `MARKETING_VERSION` the same
  as the server's version of that release, so the two read alike in Settings.
- **Server version** (Settings → About → Server): bump `VERSION` in
  `supabase/functions/fitstats/lib/version.ts` when the server changes; the deploy workflow
  checks the live function reports it.
- Minor version (1.10 → 1.11) for new features, patch (1.10.1 → 1.10.2) for fixes only.

## Before a release

- Server tests: `node --experimental-strip-types --no-warnings --test supabase/tests/*.test.ts`.
- UI tests: a push to `ui-check` runs them on GitHub's Macs (this repo has no local Xcode).
  `ios/ui-tests-only.txt` limits a run to some tests while fixing something; leave it empty for
  the full run before a release. Screenshots and errors land on the `ci-screenshots` branch.

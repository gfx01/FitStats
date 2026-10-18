# FitStats

A Bevel-style iPhone app for a Fitbit Air. It shows Recovery, Strain, Sleep
and Stress scores, plus trends, records, streaks and correlations for every
metric the Google Health API provides, and a Claude-powered coach that answers
questions about your data.

**To install and connect, follow [SETUP.md](SETUP.md).**

## How it works

```
Fitbit Air → Google Health app → Google Health API v4
                                        │  (every 5 min via pg_cron, and when the app opens)
                         Supabase Edge Function `fitstats`
                           ├─ OAuth (Google web client, PKCE)
                           ├─ sync + history backfill → fs_* tables
                           ├─ scores + statistics → fs_days / fs_cache
                           └─ coach → Claude API (streams to the app)
                                        │  (x-app-key)
                              iOS app (SwiftUI, Sideloadly)
```

| Path | What |
| --- | --- |
| `supabase/migrations/` | Tables (`fs_*`, RLS on, no anon access), sync lock, cron schedule |
| `supabase/functions/fitstats/` | Edge Function: routes, Google client, sync engine, scores, stats |
| `supabase/tests/` | `node:test` suites, including an end-to-end sync and coach run against fake Google, Claude and PostgREST servers |
| `ios/` | XcodeGen project (`project.yml`) and the SwiftUI app |
| `.github/workflows/ios.yml` | Builds an unsigned IPA on macOS and publishes it as the `build-latest` release |

## Development

Run the server logic tests (Node 22+):

```sh
node --experimental-strip-types --test supabase/tests/logic.test.ts supabase/tests/sync.test.ts supabase/tests/coach.test.ts
```

Deploy the function with the Supabase CLI:

```sh
supabase functions deploy fitstats --no-verify-jwt
```

The function authenticates its own routes, so JWT verification stays off.

Build the iOS app on a Mac:

```sh
brew install xcodegen
cd ios
xcodegen generate
open FitStats.xcodeproj
```

## Data sources

Data comes from the Google Health API v4 (`health.googleapis.com`), the
successor of the legacy Fitbit Web API, which shuts down on 2026-10-30.
Field mappings follow Google's v4 discovery document (revision 20261014).

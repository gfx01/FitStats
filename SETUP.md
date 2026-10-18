# FitStats setup

FitStats turns the data from your Fitbit Air into Recovery, Strain, Sleep and
Stress scores plus statistics for every metric. It has two parts:

- **Server (Supabase project EFBB).** It signs in to Google Health and checks
  for new data every 5 minutes, even when your phone is off, and again whenever
  you open the app. It computes the scores and statistics and stores everything
  in your own database.
- **iPhone app (installed with Sideloadly).** It shows what the server has
  computed.

You need to do steps 1–4 once. They take about 15–20 minutes.

**What you need:**

- The Google account your Fitbit Air is paired with.
- A Windows PC or Mac for Sideloadly, a USB cable for your iPhone, and your
  Apple ID (a free one is enough).
- Access to the EFBB project in your Supabase account.
- Optional, for the Coach: an Anthropic Console account with a few dollars of
  credit.

---

## 1. Google Cloud (lets the server read your Google Health data)

1. Create a project at <https://console.cloud.google.com/projectcreate>, for
   example named "FitStats".
2. Enable the API: open
   <https://console.cloud.google.com/apis/library/health.googleapis.com> and
   click **Enable**.
   - **If there is no Enable button, or Google says access is restricted or
     not available for new projects, stop here and tell me.** A few
     third-party reports from October 2026 say Google isn't onboarding new
     projects to this API right now; Google's own newsletter says it is
     available. I couldn't check this myself, and FitStats can't work without
     the API.
3. Open **Google Auth Platform** at <https://console.cloud.google.com/auth/overview>
   and click **Get started**:
   - App name: `FitStats`, support email: your email.
   - Audience: **External**.
   - Contact email: your email. Then finish and click **Create**.
4. **Audience → Test users → Add users.** Add the Google account your Fitbit
   Air uses.
5. **Data Access → Add or remove scopes.** Filter for `googlehealth` and tick
   these five scopes, then save:
   - `.../auth/googlehealth.activity_and_fitness.readonly`
   - `.../auth/googlehealth.health_metrics_and_measurements.readonly`
   - `.../auth/googlehealth.sleep.readonly`
   - `.../auth/googlehealth.profile.readonly`
   - `.../auth/googlehealth.settings.readonly`
6. **Clients → Create client:**
   - Application type: **Web application**.
   - Name: `FitStats server`.
   - Authorized redirect URIs → **Add URI**, exactly:
     `https://zkxnbcrayjwkeyxlungk.supabase.co/functions/v1/fitstats`
   - Click **Create**, then copy the **Client ID** and **Client secret**.

## 2. Supabase (give the server those two values)

Open <https://supabase.com/dashboard/project/zkxnbcrayjwkeyxlungk/functions/secrets>
(EFBB project → Edge Functions → Secrets) and add two secrets:

| Name | Value |
| --- | --- |
| `GOOGLE_CLIENT_ID` | the Client ID from step 1.6 |
| `GOOGLE_CLIENT_SECRET` | the Client secret from step 1.6 |

Nothing needs to be redeployed.

## 3. Install the app with Sideloadly

1. Download `FitStats.ipa` from this repository's **Releases** page, under
   "FitStats (latest build)":
   <https://github.com/terebesimihaly-maker/FitBit/releases/tag/build-latest>.
   Alternatively, take it from **Actions** → latest "iOS build" run →
   Artifacts → `FitStats-ipa`; that file is a zip containing the ipa.
2. Install Sideloadly from <https://sideloadly.io> and follow its install notes.
   On Windows it needs iTunes and iCloud.
3. Connect your iPhone by USB, drag `FitStats.ipa` into Sideloadly, enter your
   Apple ID and click **Start**.
4. On the iPhone:
   - Turn on Developer Mode: **Settings → Privacy & Security → Developer
     Mode**. The phone restarts.
   - Trust the app: **Settings → General → VPN & Device Management** → your
     Apple ID → **Trust**.

## 4. Connect

1. Open FitStats and tap **Connect Google Health**.
2. Choose your Google account. Google will warn **"Google hasn't verified this
   app"**. That's expected because it's your own app, so continue.
3. Allow **all** requested permissions.
4. You land back in the app. The server starts importing your history in the
   background.
   - Each run imports a few months of history, and runs repeat every 5
     minutes until the import is done. How fast this goes depends on Google's
     response times, which I couldn't measure without your account.
   - Settings shows the progress.
   - Recovery shows "Calibrating" until there are at least 5 nights of
     history.

---

## 5. Coach (optional, uses the Claude API)

The **Coach** tab chats with Claude about your data and writes a daily
briefing. You pay Anthropic per use, with no subscription. The key stays on
your Supabase server; the app never sees it.

1. Sign in to the Anthropic Console at <https://platform.claude.com> and add
   credits under billing.
2. Create an API key (it starts with `sk-ant-`). Don't paste it anywhere
   except the next step: not in a chat and not in the app.
3. On the same Supabase secrets page as step 2, add:

   | Name | Value |
   | --- | --- |
   | `ANTHROPIC_API_KEY` | your key |

4. Open the Coach tab. You choose the model in **Settings → Coach**:

   | Model | Price per million tokens (input / output) | My estimate per question |
   | --- | --- | --- |
   | Claude Sonnet 5.5 (default) | $2 / $10 | about 1–5 ¢ |
   | Claude Opus 5.5 | $4 / $20 | about 2–10 ¢ |
   | Claude Haiku 5.5 | $0.10 / $0.50 | well under 1 ¢ |

   Prices are from Anthropic's pricing page as of October 2026. The
   per-question figures are my estimates, not measurements. A question sends
   about 5,000 tokens of instructions and data summary, which are cached for
   5 minutes so follow-ups cost less. Claude may look up more data, and its
   hidden thinking is billed as output. **Settings → Coach** shows this
   month's estimated cost from real token counts. The Console shows the exact
   bill, and you can set a spend limit there. The server also stops at 100
   coach messages a day.

What the coach sends to Anthropic: your question, earlier messages in the
same conversation, a summary of your last 14 days and 30/90-day averages,
plus whatever it looks up with its tools (any metric, day or workout in your
FitStats database).

---

## 6. Live heart rate (optional)

FitStats can show your heart rate live, straight from the band over Bluetooth, while the app is
open. Google's servers only get heart rate after the band syncs, so this is the only way to see it
second by second.

1. In the Google Health app, open your Fitbit Air → **Share heart rate**, and turn on **Always
   visible** (or keep that screen open while you connect).
2. In FitStats, tap the heart button at the top of **Today**, and allow Bluetooth when asked.
3. FitStats finds the band and remembers it. You can also add a **Live heart rate** card to Home.

Live heart rate isn't saved, and it stops when you leave FitStats. If the band also sends
beat-to-beat intervals, FitStats shows a live HRV estimate too.

---

## Weekly upkeep (honest version)

- **Apple:** apps installed with a free Apple ID expire after **7 days**.
  Re-sign them in Sideloadly; your data is kept. Sideloadly can refresh
  automatically over Wi-Fi while your computer is on.
- **Google:** while the Google app is in **Testing** mode, Google ends the
  server's access **7 days** after you signed in. FitStats then shows a
  **Reconnect** button. Tap it and sign in again; nothing is lost. You can try
  **Google Auth Platform → Audience → Publish app** to avoid this, but I could
  not confirm that Google allows unverified personal apps with these Health
  permissions in production.
- **Supabase:** free projects pause after a period of inactivity. If the app
  says it can't reach the server, open the Supabase dashboard and restore
  the project.

## Troubleshooting

| Message | Fix |
| --- | --- |
| "The Google client ID and secret are not set in Supabase yet" | Step 2 is missing or misspelled. |
| `redirect_uri_mismatch` (Google error page) | The redirect URI in step 1.6 must match exactly, without a trailing slash. |
| "Access blocked" / `access_denied` | Add your Google account as a test user (step 1.4). |
| "Some Google Health permissions were not granted" | Reconnect and tick every permission box. |
| "Google access has expired" | Tap Reconnect (see Weekly upkeep). |
| Coach: "The coach needs a Claude API key" | Add `ANTHROPIC_API_KEY` (step 5), then tap Check again. |
| Coach: "Anthropic rejected the API key" | The key was mistyped or revoked; create a new one and replace the secret. |
| Coach: "… isn't available for this API key" | Pick another model in Settings → Coach. |
| Steps on a finished day are a little lower than in the Google Health app | Expected: up to about 1% on some days. FitStats shows the total Google gives other apps, which is your band's own count. The Google Health app sometimes adds a few more steps from data it doesn't share; on Oct 15–17, 2026 it was 0, 26 and 196 steps more. |
| Today's numbers look behind | FitStats only sees what has reached Google. The line under Today says when your band last synced to your phone; open the Google Health app to sync it, then pull down in FitStats. |

## What is stored, and where

- Your health data and the Google refresh token live in the EFBB Supabase
  project, in tables starting with `fs_`.
  - Row-level security is on and the public API roles have no access; only
    the `fitstats` Edge Function can read them.
  - Your other tables in that project (`efbb.*`, `apex_*`) are untouched.
- The app proves who it is with a random key created when you sign in. The key
  is stored in the iPhone Keychain.
- Coach conversations are stored in `fs_coach_threads` / `fs_coach_messages`.
  Swipe a conversation away in the Coach history to delete it.
- Journal entries (tags and notes) are stored in `fs_journal`. Open a day's
  journal and tap "Remove this day's entry" to delete one.
- **Settings → Delete all synced data** removes everything FitStats stored on
  the server, coach conversations and journal included.

## What the scores are

The scores are FitStats' own, transparent formulas, explained in the app under
**Settings → How the scores work**. They are not Bevel's or Fitbit's scores
(both are proprietary) and they are not medical advice. Google Health does
not provide daytime HRV, so Stress is estimated from your heart rate while
you are still.

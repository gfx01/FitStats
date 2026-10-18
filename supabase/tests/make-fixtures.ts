// Writes API-shaped JSON for the iOS app's fixture mode (UI screenshots in CI).
// Usage: node --experimental-strip-types supabase/tests/make-fixtures.ts <outDir>
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { type Row, tables } from "./fakes.ts";

const out = process.argv[2];
if (!out) throw new Error("usage: make-fixtures.ts <outDir>");
mkdirSync(out, { recursive: true });

const { runSync, clockFor, loadSettings, rebuildStats, recomputeScores } = await import("../functions/fitstats/lib/sync.ts");
const { addDays } = await import("../functions/fitstats/lib/util.ts");
const { mainSleepOf } = await import("../functions/fitstats/lib/transform.ts");
const { JOURNAL_TAGS, journalEntries, saveJournalEntry } = await import("../functions/fitstats/lib/journal.ts");
const log = await runSync("fixtures", true, 95_000);
if (log.status !== "ok") throw new Error(`sync failed: ${JSON.stringify(log)}`);

const acc = tables.fs_account[0];
const state = tables.fs_sync_state[0];
const today = clockFor(acc as never).today();

// Demo journal for the screenshots: "alcohol" sits on the days before the 8 worst
// sleep scores of the last 45 nights, and those mornings get a lower HRV and a
// higher resting heart rate, so that tag shows a clear (and plausible) effect.
// The other tags are spread evenly and show none.
const scoreAfter = (d: string) => Number(tables.fs_days.find((r) => r.date === addDays(d, 1))?.sleep_score ?? 100);
const logged = Array.from({ length: 45 }, (_, i) => addDays(today, -45 + i));
const alcohol = new Set([...logged].sort((a, b) => scoreAfter(a) - scoreAfter(b)).slice(0, 8));
for (const date of alcohol) {
  const morning = tables.fs_days.find((r) => r.date === addDays(date, 1));
  if (!morning) continue;
  if (typeof morning.hrv_rmssd === "number") morning.hrv_rmssd -= 12;
  if (typeof morning.rhr === "number") morning.rhr += 4;
}
await recomputeScores(addDays(today, -45), today, await loadSettings());
// The screenshots' past day (the latest workout day before today) stays unlogged, to show "Log day".
const unlogged = tables.fs_exercise.map((x) => String(x.date)).filter((d) => d < today).sort().at(-1);
for (const [i, date] of logged.entries()) {
  if (date === unlogged) continue;
  const tags = [
    ...(alcohol.has(date) ? ["alcohol"] : []),
    ...(i % 6 === 1 ? ["late_caffeine"] : []),
    ...(i % 9 === 4 ? ["stressful_day"] : []),
    ...(i % 10 === 2 ? ["Cold shower"] : []),
  ];
  await saveJournalEntry({ date, tags }, today);
}
await saveJournalEntry({ date: today, tags: ["late_caffeine", "stressful_day"], note: "Long day at work, coffee at 4 pm." }, today);
await rebuildStats(today, await loadSettings());
const byDate = (a: Row, b: Row) => String(a.date).localeCompare(String(b.date));
const days = [...tables.fs_days].sort(byDate);
const write = (name: string, value: unknown) => writeFileSync(join(out, name), JSON.stringify(value));

write("status.json", {
  version: "fixture",
  serverTime: new Date().toISOString(),
  today,
  timeZone: acc.time_zone,
  connection: { status: "ok", email: "you@example.com", connectedAt: new Date().toISOString(), error: null, missingScopes: [] },
  sync: {
    running: false,
    lastRunAt: new Date().toISOString(),
    lastRunStatus: "ok",
    lastRecentSyncAt: state.last_recent_sync_at,
    backfillOldest: state.backfill_oldest,
    backfillTarget: state.backfill_target,
    backfillDone: true,
    backfillProgress: 1,
    lastRunLog: null,
  },
  devices: [{ name: "Fitbit Air", type: "TRACKER", batteryLevel: 81, batteryStatus: "High", lastSyncTime: new Date(Date.now() - 12 * 60000).toISOString() }],
  profile: { age: 31 },
  settings: tables.fs_user_settings[0],
  maxHr: typeof state.max_hr_used === "number" ? { value: state.max_hr_used, source: state.max_hr_source } : null,
});
write("days.json", { from: days[0]?.date ?? today, to: today, today, days });
write("stats.json", tables.fs_cache.find((c) => c.key === "stats")!.value);
write("journal.json", { tags: JOURNAL_TAGS, entries: await journalEntries(addDays(today, -400)) });

for (let i = 0; i < 7; i++) {
  const date = addDays(today, -i);
  const sleeps = tables.fs_sleep.filter((s) => s.date === date).sort((a, b) => String(a.start_time).localeCompare(String(b.start_time)));
  const day = tables.fs_days.find((d) => d.date === date) ?? null;
  const main = mainSleepOf(sleeps, day?.sleep_main_id);
  const samples: Record<string, [number, number][]> = {};
  if (main) {
    for (const s of tables.fs_samples) {
      const t = String(s.t);
      if (t < String(main.start_time) || t > String(main.end_time)) continue;
      (samples[String(s.metric)] ??= []).push([Math.round(Date.parse(t) / 1000), Number(s.value)]);
    }
  }
  const intra = tables.fs_intraday.find((r) => r.date === date);
  write(`day-${date}.json`, {
    date,
    day,
    intraday: intra ? { hr: intra.hr, steps: intra.steps } : null,
    sleeps,
    exercises: tables.fs_exercise.filter((x) => x.date === date),
    samples,
  });
}
// Coach: the real coach code against the fake Claude API (see fakes.ts).
const coach = await import("../functions/fitstats/lib/coach.ts");
const ask = async (body: unknown) => {
  const res = await coach.handleCoach(new Request("https://fixtures.invalid/coach", { method: "POST", body: JSON.stringify(body) }));
  const text = await res.text();
  if (!text.includes('"type":"done"')) throw new Error(`coach fixture failed: ${text.slice(0, 500)}`);
};
await ask({ message: "How has my sleep been this week, and is it affecting my HRV?" });
await ask({ kind: "brief" });
write("coach-status.json", await coach.coachStatus());
write("coach-threads.json", await coach.coachThreads());
write("coach-thread.json", await (await coach.coachThread(String(tables.fs_coach_threads[0].id))).json());
write("coach-brief.json", await coach.coachBrief());

console.log(`fixtures for ${today} written to ${out} (${days.length} days, ${tables.fs_coach_messages.length} coach messages)`);

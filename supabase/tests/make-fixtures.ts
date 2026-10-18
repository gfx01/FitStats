// Writes API-shaped JSON for the iOS app's fixture mode (UI screenshots in CI).
// Usage: node --experimental-strip-types supabase/tests/make-fixtures.ts <outDir>
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { type Row, tables } from "./fakes.ts";

const out = process.argv[2];
if (!out) throw new Error("usage: make-fixtures.ts <outDir>");
mkdirSync(out, { recursive: true });

const { runSync, clockFor } = await import("../functions/fitstats/lib/sync.ts");
const { addDays } = await import("../functions/fitstats/lib/util.ts");
const log = await runSync("fixtures", true, 95_000);
if (log.status !== "ok") throw new Error(`sync failed: ${JSON.stringify(log)}`);

const acc = tables.fs_account[0];
const state = tables.fs_sync_state[0];
const today = clockFor(acc as never).today();
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
  devices: [{ name: "Fitbit Air", type: "TRACKER", batteryLevel: 81, batteryStatus: "High", lastSyncTime: new Date().toISOString() }],
  profile: { age: 31 },
  settings: tables.fs_user_settings[0],
});
write("days.json", { from: days[0]?.date ?? today, to: today, today, days });
write("stats.json", tables.fs_cache.find((c) => c.key === "stats")!.value);

for (let i = 0; i < 7; i++) {
  const date = addDays(today, -i);
  const sleeps = tables.fs_sleep.filter((s) => s.date === date).sort((a, b) => String(a.start_time).localeCompare(String(b.start_time)));
  const main = sleeps.find((s) => s.is_main) ?? sleeps[0];
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
    day: tables.fs_days.find((d) => d.date === date) ?? null,
    intraday: intra ? { hr: intra.hr, steps: intra.steps } : null,
    sleeps,
    exercises: tables.fs_exercise.filter((x) => x.date === date),
    samples,
  });
}
console.log(`fixtures for ${today} written to ${out} (${days.length} days)`);

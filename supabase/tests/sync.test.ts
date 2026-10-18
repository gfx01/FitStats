// End-to-end sync run against an in-memory PostgREST and a fake Google Health API.
// Run: node --experimental-strip-types --test supabase/tests/sync.test.ts
import assert from "node:assert/strict";
import { test } from "node:test";

import { calls, dbWrites, fakeData, FIRST_DATA_DAY, LOW_WEAR_DAY, NAP_MAIN_DAY, type Row, tables, VO2_SAMPLE_DAY, ZERO_AZM_DAY } from "./fakes.ts";

test("full sync: backfill, scores and stats", async () => {
  const { runSync } = await import("../functions/fitstats/lib/sync.ts");
  const log = await runSync("test", true, 95_000);
  assert.equal(log.status, "ok", JSON.stringify(log.ranges.filter((r) => r.failed.length), null, 1) + (log.message ?? ""));
  const state = tables.fs_sync_state[0];
  assert.equal(state.backfill_done, true);
  assert.equal(state.backfill_target, "2026-08-01");
  assert.equal(state.lock_until, null);

  const acc = tables.fs_account[0];
  assert.equal(acc.time_zone, "Europe/Budapest");
  assert.equal(acc.access_token, "access-1");

  const days = new Map(tables.fs_days.map((d) => [String(d.date), d]));
  assert.ok(!days.has("2026-08-10"), "no empty rows before data starts");
  const d = days.get("2026-10-10")!;
  assert.ok(d, "day row exists");
  assert.equal(typeof d.steps, "number");
  assert.equal(typeof d.rhr, "number");
  assert.equal(typeof d.hrv_rmssd, "number");
  assert.equal(d.sleep_has_stages, true);
  assert.equal(typeof d.sleep_asleep_min, "number");
  assert.ok((d.sleep_bedtime_min as number) < 0, "bedtime before midnight");
  assert.equal(typeof d.strain, "number");
  assert.equal(typeof d.stress, "number");
  assert.equal(typeof d.recovery, "number", "recovery after baseline period");
  assert.equal(typeof d.sleep_score, "number");
  assert.equal(d.weight_kg, null, "no scale data stays null");
  const details = d.score_details as Row;
  assert.ok(Array.isArray((details.recovery as Row).components));

  const first = days.get(FIRST_DATA_DAY)!;
  assert.equal(first.recovery, null, "no baseline on the first day");

  assert.ok(tables.fs_sleep.length >= 55, `sleep sessions ${tables.fs_sleep.length}`);

  // VO2 max: Google's daily value, else a vo2-max sample (with how it was measured).
  assert.deepEqual([d.vo2max, d.vo2max_source, d.vo2max_method], [46.5, "daily", null]);
  const v = days.get(VO2_SAMPLE_DAY)!;
  assert.deepEqual([v.vo2max, v.vo2max_source, v.vo2max_method], [44.1, "sample", "GOOGLE_DEMOGRAPHIC"]);

  // Workouts carry their heart-rate coverage, minute steps and where they came from.
  const workout = tables.fs_exercise.find((x) => x.date === "2026-10-10") ?? tables.fs_exercise.at(-1)!;
  assert.equal(workout.recording_method, "ACTIVELY_MEASURED");
  assert.equal(workout.source_device, "Fitbit Air");
  assert.equal(workout.hr_minutes, 60);
  assert.equal(typeof workout.steps_minute, "number");

  // Temporary steps diagnostic on the recent range: the raw points add up to the minute steps.
  const diag = log.ranges.find((r) => r.diag)!.diag!.steps as Record<string, Row>;
  const [dd, dv] = Object.entries(diag).find(([, v]) => (v.list as number) > 0)!;
  const minuteSum = (tables.fs_intraday.find((r) => r.date === dd)!.steps as (number | null)[]).reduce<number>((a, v) => a + (v ?? 0), 0);
  assert.equal(dv.list, minuteSum);
  assert.equal(dv.reconcile, minuteSum);
  assert.equal(typeof dv.fitstats, "number");
  assert.equal(typeof dv.wearables, "number");
  assert.deepEqual(Object.keys(dv.by_source as Row), ["FITBIT|PASSIVELY_MEASURED|Fitbit Air"]);

  // The run log keeps what each request returned ([points, dates] for daily types).
  const counts = log.ranges.find((r) => r.counts)!.counts!;
  assert.ok(Array.isArray(counts["daily-resting-heart-rate"]));
  assert.equal(typeof counts["intraday:hr"], "number");

  // Awakenings leave out falling asleep (every fake night starts awake) and the final wake-up.
  const night = tables.fs_sleep.find((s) => s.id === d.sleep_main_id)!;
  const stages = night.stages as [number, number, number][];
  assert.equal(d.sleep_awakenings, (night.awake_count as number) - 1 - (stages.at(-1)![0] === 0 ? 1 : 0));
  assert.equal(typeof d.sleep_waso_min, "number");

  // A nap Google also flags as main sleep, listed before the night, does not replace the night.
  const napDay = days.get(NAP_MAIN_DAY)!;
  const ofNapDay = tables.fs_sleep.filter((s) => s.date === NAP_MAIN_DAY);
  const nap = ofNapDay.find((s) => s.is_nap === true)!;
  const realNight = ofNapDay.find((s) => s.is_nap !== true)!;
  assert.equal(nap.is_main, true);
  assert.equal(napDay.sleep_main_id, realNight.id);
  assert.equal(napDay.sleep_asleep_min, realNight.minutes_asleep);
  assert.equal(napDay.nap_min, 22);
  assert.equal(typeof napDay.sleep_score, "number");
  assert.deepEqual([nap.deep_min, nap.rem_min, nap.light_min, nap.awake_count], [0, 0, 22, 2], "a STAGES session without deep or REM has 0, not null");
  assert.ok(tables.fs_exercise.length >= 10);
  const intra = tables.fs_intraday.find((r) => r.date === "2026-10-10")!;
  assert.equal((intra.hr as unknown[]).length, 1440);
  const nightHr = (intra.hr as (number | null)[])[60]!;
  assert.ok(nightHr >= 48 && nightHr <= 58, `01:00 heart rate ${nightHr}`);
  assert.ok(tables.fs_samples.some((s) => s.metric === "hrv"));

  // Wear time, the steps shape and the low-wear flag.
  assert.equal(d.wear_min, 1440);
  assert.equal(d.low_wear, false);
  const byHour = d.steps_by_hour as number[];
  assert.equal(byHour.length, 24);
  assert.equal(byHour[23], (intra.steps as (number | null)[]).reduce<number>((a, v) => a + (v ?? 0), 0));
  assert.ok(byHour.every((v, i) => i === 0 || v >= byHour[i - 1]), "cumulative");
  const lowDay = days.get(LOW_WEAR_DAY)!;
  assert.equal(lowDay.wear_min, 600, "worn 00:00–10:00");
  assert.equal(lowDay.low_wear, true);
  assert.equal(first.low_wear, null, "fewer than 5 worn days before it, but a full day");

  // A worn day without Active Zone Minutes has 0, not "no data".
  const zeroAzm = days.get(ZERO_AZM_DAY)!;
  assert.equal(zeroAzm.wear_min, 1440);
  assert.deepEqual([zeroAzm.azm_fat_burn, zeroAzm.azm_cardio, zeroAzm.azm_peak], [0, 0, 0]);
  assert.equal(typeof d.azm_fat_burn, "number");

  // Each workout's own load from its minutes (the fake runs sit at 150–161 bpm).
  const run = tables.fs_exercise.find((x) => x.date === "2026-10-10") ?? tables.fs_exercise.find((x) => x.date !== LOW_WEAR_DAY)!;
  assert.equal(typeof run.trimp, "number");
  assert.ok((run.strain as number) > 0);
  assert.ok((run.hr_max as number) >= 150);
  assert.equal((run.hrr_zone_min as number[]).reduce((a, b) => a + b, 0), 60);

  const stats = tables.fs_cache.find((c) => c.key === "stats")!.value as Row;
  const metrics = stats.metrics as Record<string, Row>;
  assert.ok(((metrics.steps.ranges as Record<string, Row>)["30"].n as number) >= 25);
  assert.ok(Array.isArray(stats.correlations));
  assert.deepEqual(stats.journal, []);
  const today = String(stats.today);
  const countable = tables.fs_days.filter((r) => typeof r.steps === "number" && String(r.date) < today && r.low_wear !== true).length;
  assert.equal((metrics.steps.ranges as Record<string, Row>).all.n, countable, "low-wear days are left out of day totals");
  assert.deepEqual(metrics.azm_total.worst, { value: 0, date: ZERO_AZM_DAY }, "the zero-AZM day counts");

  // A second run with nothing stale only refreshes recent days.
  calls.length = 0;
  const again = await runSync("cron", false, 95_000);
  assert.equal(again.status, "ok");
  assert.equal(calls.length, 0, "fresh recent sync and finished backfill -> no API calls");
});

test("recent sync: unchanged data writes nothing; new data updates rows and scores, stats within the hour", async () => {
  const { runSync, clockFor } = await import("../functions/fitstats/lib/sync.ts");
  const { addDays } = await import("../functions/fitstats/lib/util.ts");
  // The first run finished the history import and then rebuilt the stress baselines over
  // it, so the next recent sync rewrites the recent days once; after that they settle.
  const settle = await runSync("app", true, 95_000);
  assert.notEqual(settle.ranges[0].unchanged, true);
  const fingerprint = tables.fs_sync_state[0].recent_fingerprint;
  assert.match(String(fingerprint), /^[0-9a-f]{64}$/);
  const device = (tables.fs_account[0].devices as Row[])[0];
  assert.equal(device.deviceType, "TRACKER");
  assert.equal(typeof device.lastSyncTime, "string", "band sync time stored with the recent sync");

  const yesterday = addDays(clockFor(tables.fs_account[0] as never).today(), -1);
  const day = () => tables.fs_days.find((d) => d.date === yesterday)!;
  const stepsStats = () => ((tables.fs_cache.find((c) => c.key === "stats")!.value as Row).metrics as Record<string, Row>).steps;
  const stepsBefore = day().steps as number;
  const statsBefore = JSON.stringify(stepsStats());
  const recoveryBefore = day().recovery;

  // The app asks again: Google is called, but the data is the same, so nothing is written.
  calls.length = 0;
  dbWrites.length = 0;
  const same = await runSync("app", true, 95_000);
  assert.equal(same.status, "ok");
  assert.ok(calls.some((c) => c.includes("dataTypes/steps")), "recent days fetched");
  assert.equal(same.ranges[0].unchanged, true);
  assert.deepEqual(dbWrites.filter((w) => !/fs_sync_state|fs_account/.test(w)), [], "no data rows, scores or stats written");
  assert.equal(tables.fs_sync_state[0].recent_fingerprint, fingerprint);

  // New steps at Google: rows and scores follow at once; stats were built moments ago,
  // so their rebuild is owed rather than done (it reads the whole history).
  fakeData.extraSteps = 1234;
  dbWrites.length = 0;
  const changed = await runSync("app", true, 95_000);
  assert.equal(changed.status, "ok");
  assert.notEqual(changed.ranges[0].unchanged, true);
  assert.ok(dbWrites.includes("POST fs_days"), dbWrites.join(", "));
  assert.ok(!dbWrites.includes("POST fs_cache"), "stats rebuild throttled");
  assert.equal(day().steps, stepsBefore + 1234);
  assert.equal(day().recovery, recoveryBefore, "scores recomputed (steps do not move recovery)");
  assert.equal(JSON.stringify(stepsStats()), statsBefore);
  assert.equal(tables.fs_sync_state[0].stats_dirty, true);
  assert.notEqual(tables.fs_sync_state[0].recent_fingerprint, fingerprint);

  // An hour later the next run rebuilds them, even though the recent data is unchanged.
  const cache = tables.fs_cache.find((c) => c.key === "stats")!;
  cache.updated_at = new Date(Date.now() - 61 * 60_000).toISOString();
  const later = await runSync("cron", true, 95_000);
  assert.equal(later.ranges[0].unchanged, true);
  assert.notEqual(JSON.stringify(stepsStats()), statsBefore, "stats rebuilt");
  assert.equal(tables.fs_sync_state[0].stats_dirty, false);
  fakeData.extraSteps = 0;
});

test("low wear: days without minute heart rate count once the band has been worn", async () => {
  const { loadSettings, recomputeScores } = await import("../functions/fitstats/lib/sync.ts");
  const settings = await loadSettings();
  // Phone-only days (steps, no minute heart rate) long before the band: no worn day in their window.
  const phone = ["2026-06-01", "2026-06-02", "2026-06-03"];
  for (const date of phone) tables.fs_days.push({ date, steps: 9000, wear_min: 0, low_wear: null });
  const lowWearOf = () => phone.map((date) => tables.fs_days.find((r) => r.date === date)!.low_wear);
  try {
    await recomputeScores(phone[0], phone[2], settings);
    assert.deepEqual(lowWearOf(), [true, true, null], "the account has worn days later on; the last day is unfinished");

    // An account that never records minute heart rate keeps its day totals.
    const wear = new Map(tables.fs_days.map((r) => [r, r.wear_min]));
    for (const r of tables.fs_days) if (typeof r.wear_min === "number") r.wear_min = 0;
    try {
      await recomputeScores(phone[0], phone[2], settings);
      assert.deepEqual(lowWearOf(), [null, null, null]);
    } finally {
      for (const [r, w] of wear) r.wear_min = w;
    }
  } finally {
    tables.fs_days = tables.fs_days.filter((r) => !phone.includes(String(r.date)));
  }
});

test("optional data types: one Google rejects is logged and the run stays ok", async () => {
  const { runSync } = await import("../functions/fitstats/lib/sync.ts");
  fakeData.rejectTypes = ["sedentary-period:rollUp"];
  try {
    const log = await runSync("test", true, 95_000);
    assert.equal(log.status, "ok", JSON.stringify(log.ranges, null, 1));
    assert.ok(log.ranges.some((r) => (r.skipped ?? []).some((t) => t.name === "intraday:sedentary")), "the rejected type is logged");
    assert.ok(log.ranges.every((r) => r.failed.length === 0));
  } finally {
    fakeData.rejectTypes = [];
  }
});

test("max heart rate in use: kept within 2 bpm of the saved value, otherwise the history is recomputed", async () => {
  const { clockFor, loadSettings, maxHrInUse } = await import("../functions/fitstats/lib/sync.ts");
  const acc = tables.fs_account[0] as never;
  const settings = await loadSettings();
  const today = clockFor(acc).today();
  const state = tables.fs_sync_state[0];
  const eff = await maxHrInUse(acc, settings, today, null);
  assert.equal(eff.changed, true, "nothing saved yet");
  assert.equal(state.max_hr_used, eff.value, "the finished import saved the value it used");
  assert.equal(state.max_hr_source, eff.source);
  const kept = await maxHrInUse(acc, settings, today, { max_hr_used: eff.value + 1, max_hr_source: eff.source });
  assert.deepEqual([kept.value, kept.changed], [eff.value + 1, false]);
  const moved = await maxHrInUse(acc, settings, today, { max_hr_used: eff.value + 3, max_hr_source: eff.source });
  assert.deepEqual([moved.value, moved.changed], [eff.value, true]);
  const unset = await maxHrInUse(acc, settings, today, { max_hr_used: eff.value + 1, max_hr_source: "override" });
  assert.deepEqual([unset.value, unset.source, unset.changed], [eff.value, eff.source, true], "removing an override recomputes");
});

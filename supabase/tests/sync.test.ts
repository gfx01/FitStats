// End-to-end sync run against an in-memory PostgREST and a fake Google Health API.
// Run: node --experimental-strip-types --test supabase/tests/sync.test.ts
import assert from "node:assert/strict";
import { test } from "node:test";

import { calls, dbWrites, fakeData, FIRST_DATA_DAY, type Row, tables } from "./fakes.ts";

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
  assert.ok(tables.fs_exercise.length >= 10);
  const intra = tables.fs_intraday.find((r) => r.date === "2026-10-10")!;
  assert.equal((intra.hr as unknown[]).length, 1440);
  const nightHr = (intra.hr as (number | null)[])[60]!;
  assert.ok(nightHr >= 48 && nightHr <= 58, `01:00 heart rate ${nightHr}`);
  assert.ok(tables.fs_samples.some((s) => s.metric === "hrv"));

  const stats = tables.fs_cache.find((c) => c.key === "stats")!.value as Row;
  const metrics = stats.metrics as Record<string, Row>;
  assert.ok(((metrics.steps.ranges as Record<string, Row>)["30"].n as number) >= 25);
  assert.ok(Array.isArray(stats.correlations));

  // A second run with nothing stale only refreshes recent days.
  calls.length = 0;
  const again = await runSync("cron", false, 95_000);
  assert.equal(again.status, "ok");
  assert.equal(calls.length, 0, "fresh recent sync and finished backfill -> no API calls");
});

test("recent sync: unchanged data writes nothing, new data updates rows, scores and stats", async () => {
  const { runSync, clockFor } = await import("../functions/fitstats/lib/sync.ts");
  const { addDays } = await import("../functions/fitstats/lib/util.ts");
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

  // New steps at Google: rows, scores and stats follow.
  fakeData.extraSteps = 1234;
  dbWrites.length = 0;
  const changed = await runSync("app", true, 95_000);
  assert.equal(changed.status, "ok");
  assert.notEqual(changed.ranges[0].unchanged, true);
  assert.ok(dbWrites.includes("POST fs_days") && dbWrites.includes("POST fs_cache"), dbWrites.join(", "));
  assert.equal(day().steps, stepsBefore + 1234);
  assert.equal(day().recovery, recoveryBefore, "scores recomputed (steps do not move recovery)");
  assert.notEqual(JSON.stringify(stepsStats()), statsBefore, "stats rebuilt");
  assert.notEqual(tables.fs_sync_state[0].recent_fingerprint, fingerprint);
  fakeData.extraSteps = 0;
});

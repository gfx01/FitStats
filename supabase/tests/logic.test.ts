// Run: node --experimental-strip-types --test supabase/tests/
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  addDays,
  daysBetween,
  durationSeconds,
  LocalClock,
  num,
  round,
  weekdayIndex,
  zoneOffsetSeconds,
} from "../functions/fitstats/lib/util.ts";
import {
  awakeAfterOnset,
  dailyPointsToPatches,
  type ExerciseRow,
  exercisePointToRow,
  fallAsleepMinutes,
  mainSleepOf,
  maxHeartRate,
  minutesBetween,
  placeMinuteRollups,
  rollupPointsToPatches,
  samplePointsToRows,
  sleepDayPatch,
  sleepPointToRow,
  stepsByHour,
  chooseMaxHr,
  type IntradayDay,
  sustainedPeak,
  wearMinutes,
} from "../functions/fitstats/lib/transform.ts";
import {
  computeRecovery,
  computeSleepScore,
  computeStrain,
  computeStress,
  computeWorkoutLoad,
  coolDownMinutes,
  despike,
  heartRateRecovery,
  sedentaryMask,
  strainTarget,
  stressBaseline,
} from "../functions/fitstats/lib/scores.ts";
import {
  bedtimeAnalysis,
  buildStats,
  countsToward,
  hrrHistory,
  journalImpacts,
  lowerFirst,
  METRIC_BY_KEY,
  pearson,
  streak,
  trainingLoad,
} from "../functions/fitstats/lib/stats.ts";
import { normalizeTags } from "../functions/fitstats/lib/journal.ts";
import { sleepPlan, usualWake, wakeTimesFrom } from "../functions/fitstats/lib/planner.ts";
import { lowWear, workoutRecovery } from "../functions/fitstats/lib/sync.ts";

const budapest = new LocalClock("Europe/Budapest");

test("util: int64 strings, durations, dates", () => {
  assert.equal(num("62"), 62);
  assert.equal(num(""), null);
  assert.equal(num("abc"), null);
  assert.equal(durationSeconds("3600s"), 3600);
  assert.equal(durationSeconds("-7200s"), -7200);
  assert.equal(durationSeconds("1.5s"), 1.5);
  assert.equal(addDays("2026-02-28", 1), "2026-03-01");
  assert.equal(addDays("2024-02-28", 1), "2024-02-29");
  assert.equal(daysBetween("2026-10-01", "2026-10-18"), 17);
  assert.equal(weekdayIndex("2026-10-19"), 0); // Monday
  assert.equal(weekdayIndex("2026-10-18"), 6); // Sunday
});

test("util: time zone offsets and DST", () => {
  assert.equal(zoneOffsetSeconds("Europe/Budapest", Date.parse("2026-07-01T12:00:00Z")), 7200);
  assert.equal(zoneOffsetSeconds("Europe/Budapest", Date.parse("2026-01-15T12:00:00Z")), 3600);
  // 2026-10-25 03:00 CEST -> 02:00 CET (01:00 UTC)
  assert.equal(budapest.locate(Date.parse("2026-10-25T00:30:00Z")).minute, 150); // 02:30 CEST
  assert.equal(budapest.locate(Date.parse("2026-10-25T01:30:00Z")).minute, 150); // 02:30 CET
  assert.equal(budapest.midnightMs("2026-10-18"), Date.parse("2026-10-17T22:00:00Z"));
  assert.equal(budapest.midnightMs("2026-12-01"), Date.parse("2026-11-30T23:00:00Z"));
  const loc = budapest.locate(Date.parse("2026-10-17T22:05:00Z"));
  assert.deepEqual(loc, { date: "2026-10-18", minute: 5 });
});

test("transform: daily summary types", () => {
  const rhr = dailyPointsToPatches("daily-resting-heart-rate", [
    { dailyRestingHeartRate: { date: { year: 2026, month: 10, day: 17 }, beatsPerMinute: "54" } },
  ]);
  assert.deepEqual(rhr.get("2026-10-17"), { rhr: 54 });

  const hrv = dailyPointsToPatches("daily-heart-rate-variability", [
    {
      dailyHeartRateVariability: {
        date: { year: 2026, month: 10, day: 17 },
        averageHeartRateVariabilityMilliseconds: 48.7,
        nonRemHeartRateBeatsPerMinute: "52",
        deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds: 61.2,
        entropy: 2.9,
      },
    },
  ]);
  assert.deepEqual(hrv.get("2026-10-17"), { hrv_rmssd: 48.7, hrv_deep_rmssd: 61.2, hrv_entropy: 2.9, non_rem_hr: 52 });

  const temp = dailyPointsToPatches("daily-sleep-temperature-derivations", [
    {
      dailySleepTemperatureDerivations: {
        date: { year: 2026, month: 10, day: 17 },
        nightlyTemperatureCelsius: 34.1,
        baselineTemperatureCelsius: 33.8,
        relativeNightlyStddev30dCelsius: 0.25,
      },
    },
  ]);
  assert.equal(temp.get("2026-10-17")!.skin_temp_c, 34.1);

  const vo2 = dailyPointsToPatches("daily-vo2-max", [
    { dailyVo2Max: { date: { year: 2026, month: 10, day: 16 }, vo2Max: 47.5, cardioFitnessLevel: "GOOD", estimated: false } },
  ]);
  assert.deepEqual(vo2.get("2026-10-16"), { vo2max: 47.5, vo2max_level: "GOOD", vo2max_estimated: false, vo2max_source: "daily" });
});

test("transform: daily rollups (missing value = no data, not zero)", () => {
  const steps = rollupPointsToPatches("steps", [
    { civilStartTime: { date: { year: 2026, month: 10, day: 16 } }, civilEndTime: { date: { year: 2026, month: 10, day: 17 } }, steps: { countSum: "9221" } },
    { civilStartTime: { date: { year: 2026, month: 10, day: 17 } }, civilEndTime: { date: { year: 2026, month: 10, day: 18 } } },
    { civilStartTime: { date: { year: 2026, month: 10, day: 18 } }, steps: { countSum: "0" } },
  ]);
  assert.equal(steps.get("2026-10-16")!.steps, 9221);
  assert.equal(steps.has("2026-10-17"), false);
  assert.equal(steps.get("2026-10-18")!.steps, 0);

  const zones = rollupPointsToPatches("time-in-heart-rate-zone", [
    {
      civilStartTime: { date: { year: 2026, month: 10, day: 16 } },
      timeInHeartRateZone: { timeInHeartRateZones: [{ heartRateZone: "LIGHT", duration: "3600s" }, { heartRateZone: "PEAK", duration: "300s" }] },
    },
  ]);
  assert.deepEqual(zones.get("2026-10-16"), { zone_light_min: 60, zone_moderate_min: 0, zone_vigorous_min: 0, zone_peak_min: 5 });

  const active = rollupPointsToPatches("active-minutes", [
    {
      civilStartTime: { date: { year: 2026, month: 10, day: 16 } },
      activeMinutes: { activeMinutesRollupByActivityLevel: [{ activityLevel: "MODERATE", activeMinutesSum: "25" }] },
    },
  ]);
  assert.deepEqual(active.get("2026-10-16"), { active_light_min: 0, active_moderate_min: 25, active_vigorous_min: 0 });

  const dist = rollupPointsToPatches("distance", [
    { civilStartTime: { date: { year: 2026, month: 10, day: 16 } }, distance: { millimetersSum: "7250000" } },
  ]);
  assert.equal(dist.get("2026-10-16")!.distance_m, 7250);
});

const sleepPoint = {
  name: "users/me/dataTypes/sleep/dataPoints/abc-123",
  sleep: {
    interval: {
      startTime: "2026-10-17T21:30:00Z",
      startUtcOffset: "7200s",
      endTime: "2026-10-18T05:30:00Z",
      endUtcOffset: "7200s",
      civilStartTime: { date: { year: 2026, month: 10, day: 17 }, time: { hours: 23, minutes: 30 } },
      civilEndTime: { date: { year: 2026, month: 10, day: 18 }, time: { hours: 7, minutes: 30 } },
    },
    type: "STAGES",
    metadata: { mainSleep: true, nap: false, processed: true, stagesStatus: "SUCCEEDED" },
    stages: [
      { type: "LIGHT", startTime: "2026-10-17T21:30:00Z", endTime: "2026-10-17T22:30:00Z" },
      { type: "DEEP", startTime: "2026-10-17T22:30:00Z", endTime: "2026-10-17T23:40:00Z" },
      { type: "AWAKE", startTime: "2026-10-17T23:40:00Z", endTime: "2026-10-18T00:00:00Z" },
      { type: "REM", startTime: "2026-10-18T00:00:00Z", endTime: "2026-10-18T01:30:00Z" },
      { type: "LIGHT", startTime: "2026-10-18T01:30:00Z", endTime: "2026-10-18T05:30:00Z" },
    ],
    summary: {
      minutesAsleep: "460",
      minutesAwake: "20",
      minutesInSleepPeriod: "480",
      minutesToFallAsleep: "8",
      stagesSummary: [
        { type: "LIGHT", minutes: "300", count: "2" },
        { type: "DEEP", minutes: "70", count: "1" },
        { type: "REM", minutes: "90", count: "1" },
        { type: "AWAKE", minutes: "20", count: "1" },
      ],
    },
  },
};

test("transform: sleep session and day patch", () => {
  const row = sleepPointToRow(sleepPoint, budapest)!;
  assert.equal(row.id, "abc-123");
  assert.equal(row.date, "2026-10-18");
  assert.equal(row.minutes_asleep, 460);
  assert.equal(row.deep_min, 70);
  assert.equal(row.awake_count, 1);
  assert.equal(row.stages.length, 5);
  assert.equal(row.stages[0][0], 1);
  const patch = sleepDayPatch("2026-10-18", [row], budapest);
  assert.equal(patch.sleep_bedtime_min, -30); // 23:30 the evening before
  assert.equal(patch.sleep_waketime_min, 450); // 07:30
  assert.equal(patch.sleep_efficiency, 460 / 480);
  assert.equal(patch.sleep_has_stages, true);
  assert.equal(patch.sleep_main_id, "abc-123");
  assert.equal(patch.sleep_awakenings, 1, "the 20-minute wake-up at 01:40");
  assert.equal(patch.sleep_waso_min, 20);
});

// An afternoon nap Google flags as main sleep too, listed before the night (2026-08-11 and
// 2026-09-08 in real data). A STAGES nap without deep or REM has no DEEP/REM summary entry.
const napPoint = {
  name: "users/me/dataTypes/sleep/dataPoints/nap-1",
  sleep: {
    interval: {
      startTime: "2026-10-18T13:00:00Z", startUtcOffset: "7200s", endTime: "2026-10-18T13:40:00Z", endUtcOffset: "7200s",
      civilEndTime: { date: { year: 2026, month: 10, day: 18 }, time: { hours: 15, minutes: 40 } },
    },
    type: "STAGES",
    metadata: { mainSleep: true, nap: true, processed: true },
    stages: [
      { type: "AWAKE", startTime: "2026-10-18T13:00:00Z", endTime: "2026-10-18T13:05:00Z" },
      { type: "LIGHT", startTime: "2026-10-18T13:05:00Z", endTime: "2026-10-18T13:35:00Z" },
      { type: "AWAKE", startTime: "2026-10-18T13:35:00Z", endTime: "2026-10-18T13:40:00Z" },
    ],
    summary: {
      minutesAsleep: "30", minutesAwake: "10", minutesInSleepPeriod: "40",
      stagesSummary: [{ type: "LIGHT", minutes: "30", count: "1" }, { type: "AWAKE", minutes: "10", count: "2" }],
    },
  },
};

test("transform: main sleep ranking, naps, STAGES zeros", () => {
  const nap = sleepPointToRow(napPoint, budapest)!;
  const night = sleepPointToRow(sleepPoint, budapest)!;
  assert.deepEqual([nap.deep_min, nap.rem_min, nap.light_min, nap.awake_min, nap.awake_count], [0, 0, 30, 10, 2]);

  const patch = sleepDayPatch("2026-10-18", [nap, night], budapest);
  assert.equal(patch.sleep_main_id, "abc-123", "the night, not the nap listed first");
  assert.equal(patch.sleep_asleep_min, 460);
  assert.equal(patch.sleep_bedtime_min, -30);
  assert.equal(patch.nap_min, 30, "every other session counts as a nap");

  const napOnly = sleepDayPatch("2026-10-18", [nap], budapest);
  assert.equal(napOnly.sleep_has_stages, true, "from the session type");
  assert.equal(napOnly.sleep_deep_min, 0);
  assert.equal(napOnly.sleep_awakenings, 0, "falling asleep and waking up are not awakenings");
  assert.equal(napOnly.sleep_waso_min, 0);
  assert.equal(napOnly.nap_min, null);

  assert.equal(mainSleepOf([nap, night])!.id, "abc-123");
  assert.equal(mainSleepOf([nap, night], "nap-1")!.id, "nap-1", "the stored choice wins");
  assert.equal(mainSleepOf([nap, night], "gone")!.id, "abc-123", "unknown id: ranked again");
  const split = { ...night, id: "split", is_main: false, minutes_asleep: 500 };
  assert.equal(mainSleepOf([split, night])!.id, "abc-123", "flagged main beats longer");
  assert.equal(mainSleepOf([nap, split])!.id, "split", "not a nap beats flagged main");
  assert.equal(mainSleepOf([]), null);
});

test("transform: awakenings and time awake after falling asleep", () => {
  // awake 10 min, light, awake 5 + 2 min (touching: one awakening), deep, awake 5, REM, final awake 5
  const stages = [[0, 0, 600], [1, 600, 3600], [0, 3600, 3900], [0, 3900, 4020], [2, 4020, 7200], [0, 7200, 7500], [3, 7500, 9000], [0, 9000, 9300]];
  assert.deepEqual(awakeAfterOnset(stages), { awakenings: 2, wasoMin: 12 });
  assert.deepEqual(awakeAfterOnset([[0, 0, 600]]), { awakenings: 0, wasoMin: 0 }, "never fell asleep");
  assert.deepEqual(awakeAfterOnset([[5, 0, 300], [4, 300, 900], [0, 900, 960], [4, 960, 2000]]), { awakenings: 1, wasoMin: 1 }, "classic: restless before onset");
  assert.equal(awakeAfterOnset([]), null);
  assert.equal(awakeAfterOnset(null), null);
});

test("transform: exercise, intraday placement, samples", () => {
  const ex = exercisePointToRow({
    name: "users/me/dataTypes/exercise/dataPoints/9",
    exercise: {
      interval: { startTime: "2026-10-17T15:00:00Z", endTime: "2026-10-17T15:45:00Z", startUtcOffset: "7200s", civilStartTime: { date: { year: 2026, month: 10, day: 17 } } },
      exerciseType: "RUNNING",
      displayName: "Run",
      activeDuration: "2640.5s",
      metricsSummary: {
        caloriesKcal: 512.5, steps: "6800", distanceMillimeters: 7400000, averageHeartRateBeatsPerMinute: "152",
        activeZoneMinutes: "70", heartRateZoneDurations: { moderateTime: "600s", vigorousTime: "1500s", peakTime: "300s" },
      },
    },
  }, budapest)!;
  assert.equal(ex.duration_s, 2700);
  assert.equal(ex.distance_m, 7400);
  assert.equal(ex.avg_hr, 152);
  assert.equal(ex.zone_vigorous_s, 1500);
  assert.equal(ex.active_duration_s, 2641, "fractional seconds are rounded for integer columns");

  const into = new Map<string, IntradayDay>();
  placeMinuteRollups([
    { startTime: "2026-10-17T22:00:00Z", endTime: "2026-10-17T22:01:00Z", heartRate: { beatsPerMinuteAvg: 58.4 } },
    { startTime: "2026-10-17T21:59:00Z", endTime: "2026-10-17T22:00:00Z", heartRate: { beatsPerMinuteAvg: 61 } },
  ], "hr", budapest, into);
  placeMinuteRollups([{ startTime: "2026-10-18T06:00:00Z", steps: { countSum: "42" } }], "steps", budapest, into);
  assert.equal(into.get("2026-10-18")!.hr[0], 58);
  assert.equal(into.get("2026-10-17")!.hr[1439], 61);
  assert.equal(into.get("2026-10-18")!.steps[480], 42);

  const rows = samplePointsToRows("respiratory-rate-sleep-summary", [
    {
      respiratoryRateSleepSummary: {
        sampleTime: { physicalTime: "2026-10-18T05:30:00Z", utcOffset: "7200s", civilTime: { date: { year: 2026, month: 10, day: 18 } } },
        fullSleepStats: { breathsPerMinute: 14.2 },
        deepSleepStats: { breathsPerMinute: 13.1 },
        remSleepStats: { breathsPerMinute: 0 },
      },
    },
  ], budapest);
  assert.deepEqual(rows.map((r) => r.metric), ["resp_full", "resp_deep"], "Google's 0 (not computed) is not a breathing rate");
  assert.equal(maxHeartRate(30, null), 187);
  assert.equal(maxHeartRate(null, 195), 195);
});

test("scores: strain grows with intensity and saturates", () => {
  const rest = new Array(1440).fill(62);
  const easy = computeStrain(rest, 55, 187, "male")!;
  assert.equal(easy.trimp, 0);
  assert.equal(easy.strain, 0);

  const run = [...rest];
  for (let m = 1000; m < 1045; m++) run[m] = 154; // ~75 % HRR for 45 min
  const r = computeStrain(run, 55, 187, "male")!;
  assert.ok(r.strain > 40 && r.strain < 70, `run strain ${r.strain}`);
  const hard = [...run];
  for (let m = 600; m < 690; m++) hard[m] = 160;
  assert.ok(computeStrain(hard, 55, 187, "male")!.strain > r.strain);
  assert.equal(computeStrain(new Array(1440).fill(null), 55, 187, "male"), null);
  assert.deepEqual(strainTarget(80), [55, 80]);
  assert.deepEqual(strainTarget(20), [10, 35]);
});

test("scores: stress ignores movement, sleep and exercise", () => {
  const hr = new Array(1440).fill(null);
  const steps = new Array(1440).fill(0);
  for (let m = 480; m < 1320; m++) hr[m] = 66; // calm day
  const calm = computeStress(hr, steps, 55, 187, new Array(1440).fill(false));
  assert.ok(calm.stress !== null && calm.stress < 20, `calm ${calm.stress}`);

  const tense = [...hr];
  for (let m = 600; m < 900; m++) tense[m] = 95;
  const t = computeStress(tense, steps, 55, 187, new Array(1440).fill(false));
  assert.ok(t.stress! > calm.stress!);
  assert.equal(t.hourly.length, 24);

  const walking = [...steps];
  for (let m = 600; m < 900; m++) walking[m] = 90;
  const w = computeStress(tense, walking, 55, 187, new Array(1440).fill(false));
  assert.ok(w.stress! < t.stress!, "walking minutes are not stress");
  assert.equal(computeStress(hr, new Array(1440).fill(null), 55, 187, new Array(1440).fill(false)).stress, null);
});

test("scores: stress is relative to your usual still heart rate, and only sedentary minutes count", () => {
  const steps = new Array(1440).fill(0);
  const hr = new Array(1440).fill(null);
  for (let m = 480; m < 1320; m++) hr[m] = 75; // still and awake, 14 % of reserve above a resting 55 (max 197)
  const none = new Array(1440).fill(false);
  const usual = computeStress(hr, steps, 55, 197, none, (75 - 55) / 142);
  assert.equal(usual.stress, 0, "your usual still heart rate is no stress");
  assert.equal(usual.stillHrr, round(20 / 142, 4));
  const elevated = computeStress(hr, steps, 55, 197, none, 0.05);
  assert.ok(elevated.stress! > 50, `the same minutes against a lower baseline: ${elevated.stress}`);

  // Fitbit's sedentary seconds: a minute without steps that Fitbit did not count as sedentary is activity.
  const sedentary = new Array(1440).fill(0);
  for (let m = 480; m < 900; m++) sedentary[m] = 60;
  const active = [...hr];
  for (let m = 900; m < 1320; m++) active[m] = 120;
  const withMask = computeStress(active, steps, 55, 197, none, 0.14, sedentary);
  const withoutMask = computeStress(active, steps, 55, 197, none, 0.14);
  assert.equal(withMask.minutes, 420);
  assert.ok(withMask.stress! < withoutMask.stress!, `${withMask.stress} < ${withoutMask.stress}`);

  // Google's real format: each sedentary period's whole duration at the minute it starts.
  const periods = new Array(1440).fill(null);
  periods[480] = 420 * 60; // 08:00 for 7 hours
  const fromPeriods = computeStress(active, steps, 55, 197, none, 0.14, periods);
  assert.equal(fromPeriods.minutes, 420, "the period covers 08:00-15:00, not just its first minute");
  assert.equal(fromPeriods.stress, withMask.stress);
  assert.deepEqual(sedentaryMask([null, 90, null, null, 50, 30])!.slice(0, 6), [false, true, true, false, true, false]);
  assert.equal(sedentaryMask(new Array(1440).fill(null)), null);

  // Baseline: the median of the previous 30 days' still levels, fixed until there are 7.
  const still = new Map<string, number>();
  for (let i = 1; i <= 6; i++) still.set(addDays("2026-10-18", -i), 0.2);
  assert.deepEqual(stressBaseline("2026-10-18", still), { hrr: 0.14, days: 6 });
  still.set("2026-10-11", 0.1);
  assert.deepEqual(stressBaseline("2026-10-18", still), { hrr: 0.2, days: 7 });
  still.set("2026-09-01", 0.9);
  assert.equal(stressBaseline("2026-10-18", still).days, 7, "older than 30 days is left out");
});

test("scores: recovery after a workout is left out of stress until heart rate is back", () => {
  const before = new Array(30).fill(80);
  // Heart rate stays near 105 for 2 hours after a long game, then drops back to 80.
  const after = [...new Array(120).fill(105), ...new Array(80).fill(80)];
  assert.equal(coolDownMinutes(before, after, 55, 197, 0.14), 120);
  assert.equal(coolDownMinutes(before, new Array(200).fill(80), 55, 197, 0.14), 30, "at least 30 minutes");
  assert.equal(coolDownMinutes(before, new Array(200).fill(130), 55, 197, 0.14), 180, "at most 180 minutes");
  // A warm-up before the start does not raise the level to recover to.
  assert.equal(coolDownMinutes(new Array(30).fill(140), after, 55, 197, 0.14), 120);
});

test("max heart rate: the age estimate, raised by a sustained peak, never by a spike", () => {
  const hr: (number | null)[] = new Array(1440).fill(null);
  for (let m = 600; m < 660; m++) hr[m] = 150;
  hr[620] = 132; hr[621] = 194; hr[622] = 134; // optical spike
  assert.equal(sustainedPeak(hr), 150);
  hr[640] = 185; hr[641] = 199; hr[642] = 183; // the top minute of a sprint
  assert.equal(sustainedPeak(hr), 199);
  assert.equal(sustainedPeak(new Array(1440).fill(null)), null);
  assert.deepEqual(chooseMaxHr(17, null, 199), { value: 199, source: "observed" });
  assert.deepEqual(chooseMaxHr(17, null, 190), { value: 196, source: "age" });
  assert.deepEqual(chooseMaxHr(17, 205, 199), { value: 205, source: "override" });
});

function day(date: string, extra: Record<string, unknown>) {
  return { date, ...extra };
}

test("scores: sleep score components", () => {
  const prev = ["2026-10-14", "2026-10-15", "2026-10-16", "2026-10-17"].map((d) =>
    day(d, { sleep_bedtime_min: -30, sleep_waketime_min: 450 })
  );
  const good = computeSleepScore(day("2026-10-18", {
    sleep_asleep_min: 470, sleep_in_bed_min: 490, sleep_deep_min: 80, sleep_rem_min: 100,
    sleep_has_stages: true, sleep_bedtime_min: -25, sleep_waketime_min: 455,
  }), prev, 480);
  assert.equal(good.status, "ok");
  assert.ok(good.score! >= 90, `good ${good.score}`);
  // Efficiency spreads over Fitbit's 85–98 % range (the sleep period starts when you settle).
  const efficiency = (asleep: number) =>
    computeSleepScore(day("2026-10-18", { sleep_asleep_min: asleep, sleep_in_bed_min: 500 }), prev, 480).components.find((c) => c.key === "efficiency")!.value;
  assert.deepEqual([efficiency(420), efficiency(425), efficiency(460), efficiency(480), efficiency(490), efficiency(500)], [0, 0, 54, 85, 100, 100]);

  const short = computeSleepScore(day("2026-10-18", {
    sleep_asleep_min: 300, sleep_in_bed_min: 400, sleep_deep_min: 30, sleep_rem_min: 40,
    sleep_has_stages: true, sleep_bedtime_min: 90, sleep_waketime_min: 400,
  }), prev, 480);
  assert.ok(short.score! < good.score! - 30, `short ${short.score}`);
  assert.equal(computeSleepScore(day("2026-10-18", {}), prev, 480).status, "no_data");
});

test("scores: recovery reacts to HRV and resting HR", () => {
  const prev = Array.from({ length: 30 }, (_, i) =>
    day(addDays("2026-09-18", i), { hrv_rmssd: 50 + (i % 5) - 2, rhr: 55 + (i % 3) - 1, resp_rate: 14 + (i % 2) * 0.2 })
  );
  const high = computeRecovery(day("2026-10-18", { hrv_rmssd: 62, rhr: 52, resp_rate: 14 }), prev, 85);
  const low = computeRecovery(day("2026-10-18", { hrv_rmssd: 38, rhr: 60, resp_rate: 16.5 }), prev, 55);
  assert.equal(high.status, "ok");
  assert.ok(high.score! >= 80, `high ${high.score}`);
  assert.ok(low.score! <= 30, `low ${low.score}`);
  const cal = computeRecovery(day("2026-10-18", { hrv_rmssd: 50, rhr: 55 }), prev.slice(0, 2), null);
  assert.equal(cal.status, "calibrating");
  assert.equal(cal.score, null);
});

test("stats: pearson, streaks, full payload", () => {
  assert.equal(pearson([1, 2, 3, 4], [2, 4, 6, 8]), 1);
  assert.equal(pearson([1, 1, 1], [1, 2, 3]), null);

  const today = "2026-10-18";
  const days = Array.from({ length: 120 }, (_, i) => {
    const date = addDays(today, -119 + i);
    return day(date, {
      steps: 6000 + (i % 7) * 1000,
      sleep_asleep_min: 400 + (i % 5) * 20,
      sleep_score: 60 + (i % 5) * 8,
      recovery: 40 + (i % 9) * 6,
      strain: 30 + ((i + 3) % 9) * 5,
      hrv_rmssd: 45 + (i % 9) * 2,
      rhr: 56 - (i % 4),
      azm_fat_burn: 10, azm_cardio: (i % 3) * 10, azm_peak: 0,
    });
  });
  const s = buildStats(days, today, { sleep_need_min: 480, step_goal: 10000 });
  assert.equal(s.dayCount, 120);
  const steps = s.metrics.steps;
  assert.equal(steps.ranges["7"].n, 7, "the 7 complete days before today; today's partial steps are excluded");
  assert.ok(steps.ranges["30"].mean! > 6000);
  assert.equal(steps.weekday.length, 7);
  assert.ok(s.metrics.recovery.ranges["7"].n === 7);
  assert.ok(s.correlations.length >= 10);
  const rec = s.correlations.find((c) => c.x === "strain" && c.y === "recovery")!;
  assert.ok(rec.n >= 100);
  assert.ok(Array.isArray(s.insights));
  const st = streak("x", "x", days, today, (d) => (d.steps as number) >= 12000, false);
  assert.ok(st.longest >= 1);
  // An include-today streak keeps yesterday's run while today has no value yet.
  const run = [day(addDays(today, -2), { recovery: 70 }), day(addDays(today, -1), { recovery: 80 }), day(today, {})];
  const green = (d: Record<string, unknown>) => (typeof d.recovery === "number" ? d.recovery >= 67 : null);
  assert.equal(streak("g", "g", run, today, green, true).current, 2);
  assert.equal(streak("g", "g", run.slice(0, 2), today, green, true).current, 2, "no row for today yet");
  assert.equal(streak("g", "g", [...run.slice(0, 2), day(today, { recovery: 50 })], today, green, true).current, 0);
  assert.equal(JSON.parse(JSON.stringify(s)).today, today);
});

test("stats: day totals over complete days, absolute change for clock times and deviations", () => {
  const today = "2026-10-18"; // a Sunday
  const days = Array.from({ length: 60 }, (_, i) => {
    const date = addDays(today, -59 + i);
    const recent = date >= addDays(today, -6);
    return day(date, {
      steps: date === today ? 300 : date >= addDays(today, -7) ? 12000 : 8000,
      rhr: recent ? 50 : 56,
      sleep_bedtime_min: recent ? 30 : -30,
      skin_temp_c: recent ? 34.0 : 34.1,
      skin_temp_baseline_c: 34.2,
    });
  });
  const s = buildStats(days, today, { sleep_need_min: 480, step_goal: 10000 });

  // Day totals: "7" is the 7 complete days before today, as in the insights.
  const steps = s.metrics.steps.ranges;
  assert.deepEqual([steps["7"].n, steps["7"].mean, steps["7"].prevMean, steps["7"].change, steps["7"].changePct], [7, 12000, 8000, 4000, 50]);
  assert.equal(steps["30"].n, 30);
  assert.equal(steps["30"].mean, 8933.3, "(23 × 8,000 + 7 × 12,000) ÷ 30");
  const trend = s.insights.find((i) => i.id === "trend_steps")!;
  assert.equal(trend.body, "7-day average 12,000, versus 8,933 over the last 30 days.", "the same windows as Trends");
  assert.equal(steps.all.change, null, "no previous period");

  // Averages keep today's window.
  const rhr = s.metrics.rhr.ranges["7"];
  assert.deepEqual([rhr.n, rhr.mean, rhr.prevMean, rhr.change, rhr.changePct], [7, 50, 56, -6, -10.7]);

  // A percent of minutes from midnight, or of a deviation around zero, means nothing.
  const bed = s.metrics.sleep_bedtime_min.ranges["7"];
  assert.deepEqual([bed.mean, bed.prevMean, bed.change, bed.changePct], [30, -30, 60, null]);
  assert.equal(s.metrics.sleep_waketime_min.ranges["7"].changePct, null);
  const skin = s.metrics.skin_temp_dev.ranges["7"];
  assert.deepEqual([skin.mean, skin.prevMean, skin.change, skin.changePct], [-0.2, -0.1, -0.1, null]);
});

test("insights: sleep debt counts naps, the best night is named after its evening", () => {
  const today = "2026-10-18"; // a Sunday
  const days = Array.from({ length: 63 }, (_, i) => {
    const date = addDays(today, -62 + i);
    const wake = weekdayIndex(date); // sleep is dated by the wake-up day
    const naps: Record<string, number> = { "2026-10-13": 30, "2026-10-15": 60, "2026-10-16": 90 };
    return day(date, { sleep_asleep_min: 420, nap_min: naps[date] ?? null, sleep_score: wake === 6 ? 90 : wake === 1 ? 70 : 80 });
  });
  const s = buildStats(days, today, { sleep_need_min: 480, step_goal: 10000 });
  const debt = s.insights.find((i) => i.id === "sleep_debt")!;
  assert.equal(debt.title, "Sleep debt 4h 30m", "7 × 60 min short − 30 − 60 − 60 (a nap longer than the shortfall clears only that day)");
  assert.equal(debt.body, "Over the last 7 tracked nights, counting naps, you were 4h 30m short of your 8h 0m sleep need in total.");
  const night = s.insights.find((i) => i.id === "sleep_weekday")!;
  assert.equal(night.title, "You sleep best on Saturday nights", "waking up on Sunday");
  assert.equal(night.body, "Average sleep score: Saturday nights 90, Monday nights 70 (last 90 days).");
});

test("wear, steps by hour, workout minutes and workout load", () => {
  const hr: (number | null)[] = new Array(1440).fill(null);
  for (let m = 0; m < 600; m++) hr[m] = 60;
  assert.equal(wearMinutes(hr), 600);
  const steps: (number | null)[] = new Array(1440).fill(null);
  assert.equal(stepsByHour(steps), null, "no step data");
  steps[30] = 100;
  steps[61] = 50;
  steps[1439] = 7;
  const byHour = stepsByHour(steps)!;
  assert.equal(byHour.length, 24);
  assert.deepEqual(byHour.slice(0, 3), [100, 150, 150]);
  assert.equal(byHour[23], 157);

  // 23:50–00:20 local spans two days of minute slots.
  const start = budapest.midnightMs("2026-10-18") - 10 * 60000;
  const day1 = new Array(1440).fill(null), day2 = new Array(1440).fill(null);
  day1[1430] = 140;
  day2[5] = 150;
  const mins = minutesBetween(start, start + 30 * 60000, budapest, (d) => (d === "2026-10-17" ? day1 : d === "2026-10-18" ? day2 : null));
  assert.equal(mins.length, 30);
  assert.equal(mins[0], 140);
  assert.equal(mins[15], 150);

  const run = computeWorkoutLoad(new Array(40).fill(160), 55, 190, "male");
  assert.ok(run.trimp! > 50 && run.strain! > 30, JSON.stringify(run));
  assert.equal(run.hr_max, 160);
  assert.equal(run.hrr_zone_min!.reduce((a, b) => a + b, 0), 40);
  assert.equal(run.hrr_zone_min![2], 40, "160 bpm is 78% of reserve: zone 70–80%");
  assert.deepEqual(computeWorkoutLoad([150, 150, null], 55, 190, "male"), { trimp: null, strain: null, hr_max: null, hrr_zone_min: null, hr_minutes: 2 });
  // A one-minute optical spike is neither the peak nor a zone 5 minute.
  const spiky = new Array(20).fill(140);
  spiky[10] = 194;
  const sp = computeWorkoutLoad(spiky, 55, 190, "male");
  assert.equal(sp.hr_max, 140);
  assert.equal(sp.hrr_zone_min![4], 0);
  assert.equal(sp.hr_minutes, 20);
  assert.deepEqual(despike([100, 104, 137, 111]), [100, 104, 137, 111], "a 30 bpm jump between sets stays");
});

test("low wear: relative to your usual wear, never on unfinished days", () => {
  const usual = (n: number, wear: number) => Array.from({ length: n }, (_, i) => day(addDays("2026-10-01", i), { wear_min: wear }));
  // Under 5 worn days of history (the band's first days) an absolute 10 h rule applies.
  assert.equal(lowWear(500, usual(4, 1400), true, true), true, "under 5 days of history: under 10 h is low");
  assert.equal(lowWear(900, usual(4, 1400), true, true), null, "under 5 days of history: not judged otherwise");
  assert.equal(lowWear(500, usual(10, 1400), true, true), true);
  assert.equal(lowWear(900, usual(10, 1400), true, true), false);
  assert.equal(lowWear(500, usual(10, 1400), false, true), null, "today is unfinished");
  assert.equal(lowWear(100, usual(10, 400), true, true), null, "usually worn under 10 h: not judged");
  assert.equal(lowWear(null, usual(10, 1400), true, true), null);

  // Real first sync: 08-05..08-09 phone only (wear 0), band first worn the evening of 08-10 (205 min).
  const preBand = usual(5, 0);
  assert.equal(lowWear(0, [], true, true), true, "no minute heart rate on an account that has worn the band");
  assert.equal(lowWear(0, [], true, false), null, "an account that never records minute heart rate keeps its stats");
  assert.equal(lowWear(0, preBand, false, true), null, "today is unfinished");
  assert.equal(lowWear(205, preBand, true, true), true, "0-wear days are not usual wear");
  assert.equal(lowWear(1401, [...preBand, day("2026-10-06", { wear_min: 205 })], true, true), null);
  assert.equal(lowWear(800, [...preBand, ...usual(5, 1400)], true, true), true, "usual wear is the median of worn days only (1400, not 700)");
  assert.equal(lowWear(900, [...preBand, ...usual(5, 1400)], true, true), false);
  assert.equal(lowWear(700, [...usual(10, 0), ...usual(5, 1400)], true, true), true);

  const today = "2026-10-18";
  const days = Array.from({ length: 40 }, (_, i) => day(addDays(today, -39 + i), { steps: 8000, low_wear: false }));
  days[30] = day(days[30].date, { steps: 900, low_wear: true });
  const steps = METRIC_BY_KEY.get("steps")!, rhr = METRIC_BY_KEY.get("rhr")!;
  assert.equal(countsToward(steps, days[30], today), false);
  assert.equal(countsToward(rhr, days[30], today), true, "only day totals are affected");
  assert.equal(countsToward(steps, days[39], today), false, "today is still growing");
  const s = buildStats(days, today, { sleep_need_min: 480, step_goal: 10000 });
  assert.equal(s.metrics.steps.ranges["30"].mean, 8000, "the low-wear day is left out");
  assert.equal(s.metrics.steps.worst!.value, 8000);
});

test("journal: tags are normalized, effects need 3+ days on each side", () => {
  assert.deepEqual(normalizeTags(["Alcohol", " late   meal ", "alcohol", "Cold shower", ""]), ["alcohol", "late_meal", "Cold shower"]);
  assert.deepEqual(normalizeTags([]), []);
  assert.equal(normalizeTags("alcohol"), null);
  assert.equal(normalizeTags([1]), null);
  assert.equal(normalizeTags(Array.from({ length: 21 }, (_, i) => `t${i}`)), null);
  assert.equal(normalizeTags(["x".repeat(40)])![0].length, 30);

  const today = "2026-10-18";
  const days = Array.from({ length: 60 }, (_, i) => day(addDays(today, -59 + i), { sleep_score: 80 + (i % 3), hrv_rmssd: 50 }));
  const entries = Array.from({ length: 40 }, (_, i) => ({ date: addDays(today, -40 + i), tags: i % 4 === 0 ? ["alcohol"] : i % 13 === 0 ? ["travel"] : [] }));
  // Nights after alcohol days score ~12 lower.
  for (const e of entries) {
    if (!e.tags.includes("alcohol")) continue;
    const next = days.find((d) => d.date === addDays(e.date, 1))! as Record<string, unknown>;
    next.sleep_score = (next.sleep_score as number) - 12;
  }
  const impacts = journalImpacts(days, entries, today);
  const alcohol = impacts.find((i) => i.tag === "alcohol")!;
  assert.equal(alcohol.label, "Alcohol");
  assert.equal(alcohol.days, 10);
  const score = alcohol.effects.find((e) => e.metric === "sleep_score")!;
  assert.ok(score.diff < -10 && score.clear, JSON.stringify(score));
  assert.equal(score.nWith, 10);
  const hrv = alcohol.effects.find((e) => e.metric === "hrv_rmssd")!;
  assert.equal(hrv.diff, 0);
  assert.equal(hrv.clear, false);
  const travel = impacts.find((i) => i.tag === "travel")!;
  assert.equal(travel.days, 3);
  assert.equal(travel.effects.length, 2, "3 tagged days are enough; only outcomes with data (sleep score, HRV)");
  const stats = buildStats(days, today, { sleep_need_min: 480, step_goal: 10000 }, entries);
  assert.equal(stats.journal.length, 2);
  const insight = stats.insights.find((i) => i.id === "journal_alcohol_sleep_score")!;
  assert.match(insight.title, /^After alcohol days: sleep score lower by \d+$/);
  assert.equal(insight.tone, "negative");
  assert.equal(lowerFirst("HRV (RMSSD)"), "HRV (RMSSD)");
  assert.equal(lowerFirst("Sleep score"), "sleep score");
});

test("sleep plan: need from strain, debt and naps; bedtime from the usual wake time", () => {
  const today = "2026-10-18"; // a Sunday, so tomorrow is a weekday
  const nights = (extra: (date: string, i: number) => Record<string, unknown>) =>
    Array.from({ length: 28 }, (_, i) => {
      const date = addDays(today, -27 + i);
      return day(date, { sleep_asleep_min: 480, sleep_efficiency: 0.9, sleep_waketime_min: weekdayIndex(date) >= 5 ? 540 : 400, ...extra(date, i) });
    });
  const base = sleepPlan(nights(() => ({})), today, 480);
  assert.deepEqual([base.needMin, base.strainMin, base.debtMin, base.napMin], [480, 0, 0, 0]);
  assert.equal(base.inBedMin, 535, "480 ÷ 0.9 = 533 → 535");
  assert.equal(base.wakeBasis, "weekday");
  assert.equal(base.wakeMin, 400);
  assert.equal(base.bedtimeMin, -135, "06:40 − 8h 55m = 21:45 the evening before");

  const hard = sleepPlan(nights((date) => (date === today ? { strain: 85, nap_min: 22 } : date >= addDays(today, -6) ? { sleep_asleep_min: 420 } : {})), today, 480);
  assert.equal(hard.strainMin, 45);
  assert.equal(hard.debtMin, 60, "6 nights × 60 min short ÷ 4 = 90, capped at 60");
  assert.equal(hard.napMin, 20);
  assert.equal(hard.needMin, 480 + 45 + 60 - 20);

  // Naps on the days before today count as sleep in the debt; today's only through napMin.
  const napped = sleepPlan(nights((date) => (date === today ? { sleep_asleep_min: 420, nap_min: 40 } : date >= addDays(today, -6) ? { sleep_asleep_min: 420, nap_min: 60 } : {})), today, 480);
  assert.equal(napped.debtMin, 15, "only today's 60 min short: 60 ÷ 4");
  assert.equal(napped.napMin, 40);
  assert.equal(napped.needMin, 480 + 15 - 40);

  const few = sleepPlan([day(today, { strain: 10 })], today, 450);
  assert.equal(few.needMin, 450);
  assert.equal(few.efficiency, 0.9);
  assert.equal(few.wakeMin, null);
  assert.equal(few.bedtimeMin, null);
});

test("training: logged workouts paired with the band's recordings of the same sessions", async () => {
  const { pairBandWorkouts } = await import("../functions/fitstats/lib/training.ts");
  const log = (id: string, date: string, start: string | null, end: string | null) =>
    ({ id, date, started_at: start, ended_at: end, routine_id: null, name: id, exercises: [], notes: null, effort: null, created_at: "", updated_at: "" });
  const band = [
    { id: "run", date: "2026-10-14", start_time: "2026-10-14T06:00:00Z", end_time: "2026-10-14T06:40:00Z" },
    { id: "gym", date: "2026-10-14", start_time: "2026-10-14T16:10:00Z", end_time: "2026-10-14T17:05:00Z" },
    { id: "walk", date: "2026-10-15", start_time: "2026-10-15T12:00:00Z", end_time: "2026-10-15T12:30:00Z" },
  ];
  const pairs = pairBandWorkouts([
    log("push", "2026-10-14", "2026-10-14T16:00:00Z", "2026-10-14T17:00:00Z"),
    // Starts during the run but no end: an hour is assumed.
    log("strong", "2026-10-14", "2026-10-14T06:20:00Z", null),
    // No times: the day's only band workout.
    log("manual", "2026-10-15", null, null),
    log("none", "2026-10-16", "2026-10-16T10:00:00Z", null),
  ], band);
  assert.deepEqual(Object.fromEntries([...pairs].map(([k, v]) => [k, v.id])), { push: "gym", strong: "run", manual: "walk" });
});

test("sleep plan: a wake-up time set by hand for tomorrow wins over the usual one", () => {
  const today = "2026-10-18"; // a Sunday: tomorrow is Monday (index 0)
  const rows = Array.from({ length: 28 }, (_, i) => {
    const date = addDays(today, -27 + i);
    return day(date, { sleep_asleep_min: 480, sleep_efficiency: 0.9, sleep_waketime_min: weekdayIndex(date) >= 5 ? 540 : 400 });
  });
  const set = sleepPlan(rows, today, 480, [360, 360, 360, 360, 360, null, null]);
  assert.equal(set.wakeBasis, "set");
  assert.equal(set.wakeMin, 360);
  assert.equal(set.bedtimeMin, 360 - 535, "06:00 − 8h 55m = 21:05 the evening before");
  // Friday night: Saturday has no time set, so the usual weekend one is used.
  const friday = "2026-10-16";
  const free = sleepPlan(rows, friday, 480, [360, 360, 360, 360, 360, null, null]);
  assert.equal(free.wakeBasis, "weekend");
  assert.equal(free.wakeMin, 540);
  assert.deepEqual(usualWake(rows, today, false), { wakeMin: 400, basis: "weekday" });
  assert.equal(usualWake([], today, true), null);

  assert.equal(wakeTimesFrom(null), null);
  assert.equal(wakeTimesFrom([null, null, null, null, null, null, null]), null, "all empty = none set");
  assert.deepEqual(wakeTimesFrom([390, 390, 390, 390, 390, 480, null]), [390, 390, 390, 390, 390, 480, null]);
  assert.throws(() => wakeTimesFrom([390, 390]));
  assert.throws(() => wakeTimesFrom([390, 390, 390, 390, 390, 1440, null]));
  assert.throws(() => wakeTimesFrom([390, 390, 390, 390, 390, "7:00", null]));
});

test("sleep: time to fall asleep from the stages when Google reports 0", () => {
  const start = "2026-10-17T21:30:00.000Z";
  const t = Date.parse(start) / 1000;
  const stages = [[0, t, t + 420], [1, t + 420, t + 1800], [0, t + 1800, t + 1900], [2, t + 1900, t + 3000]];
  assert.equal(fallAsleepMinutes({ start_time: start, minutes_to_fall_asleep: 0, stages }), 7);
  assert.equal(fallAsleepMinutes({ start_time: start, minutes_to_fall_asleep: 12, stages }), 12, "a real value wins");
  assert.equal(fallAsleepMinutes({ start_time: start, minutes_to_fall_asleep: 0, stages: [[1, t, t + 600]] }), 0, "asleep from the start");
  assert.equal(fallAsleepMinutes({ start_time: start, minutes_to_fall_asleep: 0, stages: [] }), null, "nothing to measure");
  assert.equal(fallAsleepMinutes({ start_time: start, minutes_to_fall_asleep: 0, stages: [[5, t, t + 300], [4, t + 300, t + 900]] }), 5, "classic: restless counts as not yet asleep");
});

test("training load: fitness, fatigue and form from daily TRIMP", () => {
  const today = "2026-10-18";
  const yesterday = addDays(today, -1);
  // Daily TRIMP for the days up to yesterday, oldest first.
  const days = (values: (number | null)[]) => values.map((trimp, i) => day(addDays(today, -values.length + i), { trimp }));
  const repeat = (v: number | null, n: number) => new Array(n).fill(v);
  assert.deepEqual(trainingLoad([day(today, { trimp: 80 })], today), { series: [], latest: null, status: "calibrating", spike: false, days: 0 }, "today is still growing");

  // Until 42 (or 7) days exist, fitness and fatigue are the plain mean so far, then one step each day.
  const step = trainingLoad(days([...repeat(30, 28), 72]), today);
  assert.deepEqual(step.latest, { date: yesterday, trimp: 72, ctl: 31.4, atl: 36, form: -4.6, acwr: 1.14 }, "30 + 42/29, 30 + 42/7; (6 × 30 + 72)/7 ÷ (27 × 30 + 72)/28");
  assert.deepEqual([step.status, step.spike, step.days, step.series.length], ["productive", false, 29, 29], "form ÷ fitness = −0.15");
  assert.deepEqual(trainingLoad(days([80, 40]), today).latest!.ctl, 60, "the mean so far, not a step from 0");
  assert.deepEqual(trainingLoad([...days([...repeat(30, 28), 72]), day(today, { trimp: 500 })], today), step, "today's TRIMP is left out");
  assert.equal(trainingLoad(days(repeat(30, 27)), today).status, "calibrating", "27 days since the first TRIMP day");
  assert.equal(trainingLoad([day("2026-01-01", { trimp: null }), ...days(repeat(30, 27))], today).series.length, 27, "the series starts at the first day with TRIMP");

  // A day without TRIMP counts as 0 load, in the load ratio's means too, but stays null in the series.
  const gap = trainingLoad(days([...repeat(30, 28), null, 72]), today);
  assert.deepEqual(gap.series.at(-2), { date: addDays(today, -2), trimp: null, ctl: 29, atl: 25.7, form: 3.3, acwr: 0.89 }, "30 − 30/29, 30 − 30/7; (6 × 30)/7 ÷ (27 × 30)/28");
  assert.equal(gap.days, 29);
  const back = trainingLoad(days([...repeat(100, 81), ...repeat(null, 6), 160]), today);
  assert.deepEqual([back.latest!.acwr, back.spike], [0.28, false], "160/7 ÷ (21 × 100 + 160)/28: one day back after a week off is no spike");
  assert.equal(trainingLoad(days([...repeat(100, 81), ...repeat(null, 7)]), today).latest!.acwr, 0, "21 of the last 28 days have TRIMP");
  assert.equal(trainingLoad(days(repeat(30, 21)), today).latest!.acwr, 1, "under 28 days of history, the longer mean is over the days there are");

  const steady = trainingLoad(days(repeat(50, 80)), today);
  assert.deepEqual([steady.latest!.ctl, steady.latest!.atl, steady.latest!.form, steady.latest!.acwr, steady.status], [50, 50, 0, 1, "neutral"]);
  const rested = trainingLoad(days([...repeat(50, 60), ...repeat(null, 14)]), today);
  assert.deepEqual([rested.latest!.ctl, rested.latest!.atl, rested.status], [35.7, 5.8, "fresh"], "50 × (41/42)^14, 50 × (6/7)^14");
  assert.equal(rested.latest!.acwr, null, "only 14 of the last 28 days have TRIMP");
  const hard = trainingLoad(days([...repeat(40, 60), ...repeat(120, 7)]), today);
  assert.deepEqual([hard.latest!.acwr, hard.spike, hard.status], [2, true, "overreaching"], "120 ÷ (21 × 40 + 7 × 120)/28");

  // The series keeps 180 days; the averages run over the whole history.
  const long = trainingLoad(days([...repeat(100, 20), ...repeat(50, 180)]), today);
  assert.deepEqual([long.series.length, long.series[0].date, long.days], [180, addDays(today, -180), 180]);
  assert.ok(long.series[0].ctl > 60, `the 20 harder days before the series still count: ${long.series[0].ctl}`);
});

test("bedtime: sleep by bedtime window, the best window and its insight", () => {
  const today = "2026-10-18";
  const bucketOf = (bed: number) =>
    bedtimeAnalysis([day(today, { sleep_bedtime_min: bed, sleep_score: 80 })], today).buckets.find((b) => b.nights === 1)!.label;
  assert.deepEqual(
    [-91, -90, -61, -60, -1, 0, 59, 60, 769].map(bucketOf),
    ["before 22:30", "22:30–23:00", "22:30–23:00", "23:00–23:30", "23:30–00:00", "00:00–00:30", "00:30–01:00", "after 01:00", "after 01:00"],
    "each window includes its start and excludes its end",
  );
  const one = bedtimeAnalysis([day(today, { sleep_bedtime_min: -50, sleep_score: 80, sleep_asleep_min: 450 })], today);
  assert.deepEqual(one.buckets[2], { label: "23:00–23:30", from: -60, to: -30, nights: 1, sleepScore: null, asleepMin: null, recovery: null }, "means need 3 nights");
  assert.equal(one.best, null);

  // 200 nights: the oldest 20 at 22:00 fall outside the last 180 scored nights, apart from the
  // newest of them (today has no sleep score yet). Then 23:10, 23:40 and 00:10 in turn; 23:10 sleeps best.
  const rows = Array.from({ length: 200 }, (_, i) => {
    const date = addDays(today, -199 + i);
    if (i < 20) return day(date, { sleep_bedtime_min: -120, sleep_score: 99, sleep_asleep_min: 480, recovery: 90 });
    const bed = [-50, -20, 10][i % 3];
    const early = bed === -50;
    return day(date, {
      sleep_bedtime_min: bed,
      sleep_score: i === 199 ? null : early ? 85 + (i % 2) * 2 : 76,
      sleep_asleep_min: early ? 420 : 400,
      recovery: early ? 70 : i % 2 ? 60 : null,
    });
  });
  const b = bedtimeAnalysis(rows, today);
  assert.equal(b.nights, 180);
  assert.deepEqual(b.buckets.map((x) => x.nights), [1, 0, 60, 59, 60, 0, 0]);
  assert.deepEqual(b.buckets[0], { label: "before 22:30", from: null, to: -90, nights: 1, sleepScore: null, asleepMin: null, recovery: null });
  assert.deepEqual(b.buckets[2], { label: "23:00–23:30", from: -60, to: -30, nights: 60, sleepScore: 86, asleepMin: 420, recovery: 70 });
  assert.deepEqual([b.buckets[3].sleepScore, b.buckets[3].asleepMin, b.buckets[3].recovery], [76, 400, 60], "recovery over the mornings that have one");
  assert.deepEqual(b.best, { label: "23:00–23:30", diff: 9.8, clear: true }, "86 − (119 × 76 + 99) ÷ 120");

  const insight = buildStats(rows, today, { sleep_need_min: 480, step_goal: 10000 }).insights.find((i) => i.id === "best_bedtime")!;
  assert.equal(insight.title, "You sleep best going to bed between 23:00 and 23:30");
  assert.equal(insight.body, "Average sleep score 86 on the 60 nights you went to bed between 23:00 and 23:30, versus 76 on your 120 other nights. A pattern in your data, not proof of cause.");
  assert.equal(insight.metric, "sleep_bedtime_min");
  const twelve = buildStats(rows, today, { sleep_need_min: 480, step_goal: 10000, clock_24h: false }).insights.find((i) => i.id === "best_bedtime")!;
  assert.equal(twelve.title, "You sleep best going to bed between 11:00 PM and 11:30 PM", "a 12-hour phone gets 12-hour times");

  // Not clear: the same means with a lot of scatter and few nights.
  const noisy = rows.slice(-12).map((d, i) => {
    const score = (d as Record<string, unknown>).sleep_score;
    return { ...d, sleep_score: typeof score === "number" ? score + (i % 2 ? 20 : -20) : null };
  });
  const unclear = bedtimeAnalysis(noisy, today);
  assert.equal(unclear.best?.clear, false, JSON.stringify(unclear.best));
  assert.equal(buildStats(noisy, today, { sleep_need_min: 480, step_goal: 10000 }).insights.some((i) => i.id === "best_bedtime"), false);
  // A single window with 3+ nights has nothing to be compared with.
  const lone = [...rows.slice(-10, -1).map((d) => ({ ...d, sleep_bedtime_min: -50 })), day(today, { sleep_bedtime_min: 10, sleep_score: 70 })];
  assert.deepEqual(bedtimeAnalysis(lone, today).buckets.map((x) => x.nights), [0, 0, 9, 0, 1, 0, 0]);
  assert.equal(bedtimeAnalysis(lone, today).best, null);
});

test("heart-rate recovery: the drop 1 and 2 minutes after a hard finish, only when the guards hold", () => {
  const rhr = 55, maxHr = 195; // halfway up the reserve: 125 bpm
  const none = { end_hr: null, hrr_1min: null, hrr_2min: null };
  const run = [...new Array(18).fill(150), 160, 161];
  assert.deepEqual(heartRateRecovery(run, [132, 116], rhr, maxHr, true), { end_hr: 161, hrr_1min: 29, hrr_2min: 45 }, "(160 + 161) ÷ 2 = 160.5 → 161");
  assert.deepEqual(heartRateRecovery(run.slice(-10), [132, 116], rhr, maxHr, true), { end_hr: 161, hrr_1min: 29, hrr_2min: 45 }, "10 minutes is enough");
  assert.deepEqual(heartRateRecovery(run.slice(-9), [132, 116], rhr, maxHr, true), none, "under 10 minutes");
  assert.deepEqual(heartRateRecovery(run, [168, 150], rhr, maxHr, true), none, "heart rate still rising after the recorded end is no recovery");
  assert.deepEqual(heartRateRecovery(run, [161, 150], rhr, maxHr, true), none, "a fall of 0 at 1 minute either");
  assert.deepEqual(heartRateRecovery(run.map((v, i) => (i < 6 ? null : v)), [132, 116], rhr, maxHr, true).hrr_1min, 29, "heart rate in 14 of 20 minutes (70%)");
  assert.deepEqual(heartRateRecovery(run.map((v, i) => (i < 7 ? null : v)), [132, 116], rhr, maxHr, true), none, "13 of 20 minutes");
  assert.deepEqual(heartRateRecovery([...run.slice(0, 18), 125, 125], [110, 100], rhr, maxHr, true), { end_hr: 125, hrr_1min: 15, hrr_2min: 25 });
  assert.deepEqual(heartRateRecovery([...run.slice(0, 18), 124, 124], [110, 100], rhr, maxHr, true), none, "an easy finish, below halfway up the reserve");
  assert.deepEqual(heartRateRecovery(run, [132, null], rhr, maxHr, true), none, "no heart rate 2 minutes after");
  assert.deepEqual(heartRateRecovery(run, [132], rhr, maxHr, true), none);
  assert.deepEqual(heartRateRecovery([...run.slice(0, 19), null], [132, 116], rhr, maxHr, true), none, "no heart rate in the last minute");
  assert.deepEqual(heartRateRecovery(run, [132, 116], rhr, maxHr, false), none, "another workout starts right after");
  // A one-minute optical spike at the end is replaced by its neighbours' mean: (150 + 148) ÷ 2.
  assert.deepEqual(heartRateRecovery([...new Array(19).fill(150), 190], [148, 130], rhr, maxHr, true), { end_hr: 150, hrr_1min: 2, hrr_2min: 20 });

  // In the sync: the workout's minute window and the 2 minutes after it.
  const date = "2026-10-17";
  const hr: (number | null)[] = new Array(1440).fill(70);
  for (let m = 600; m < 630; m++) hr[m] = 160; // 10:00–10:29
  hr[630] = 135;
  hr[631] = 118;
  const at = (min: number) => new Date(budapest.midnightMs(date) + min * 60000).toISOString();
  const workout = (id: string, from: number, to: number) => ({ id, date, start_time: at(from), end_time: at(to) }) as unknown as ExerciseRow;
  const x = workout("a", 600.2, 629.5); // ends 10:29:30, so the window's last minute is 10:29
  const hrFor = (d: string) => (d === date ? hr : null);
  const recovery = (others: ExerciseRow[]) => workoutRecovery(x, [x, ...others], budapest, hrFor, 55, 195);
  assert.deepEqual(recovery([]), { end_hr: 160, hrr_1min: 25, hrr_2min: 42 });
  assert.deepEqual(recovery([workout("b", 632, 660)]), none, "the next workout starts 2.5 minutes after the end");
  assert.deepEqual(recovery([workout("b", 620, 660)]), none, "another workout is still going at the end");
  assert.deepEqual(recovery([workout("b", 633, 660), workout("c", 500, 560)]).hrr_1min, 25, "3.5 minutes after the end, and one before it, are fine");
});

test("stats: training load, bedtime and heart-rate recovery in the payload", () => {
  const today = "2026-10-18";
  const days = Array.from({ length: 40 }, (_, i) =>
    day(addDays(today, -39 + i), { trimp: 50, sleep_score: 80 + (i % 3), sleep_bedtime_min: [-50, -20, 10][i % 3], sleep_asleep_min: 450 })
  );
  const workouts = [
    { id: "w3", date: "2026-10-12", start_time: "2026-10-12T16:00:00.000Z", exercise_type: "RUNNING", name: "Run", end_hr: 170, hrr_1min: 30, hrr_2min: 48 },
    { id: "old", date: addDays(today, -365), start_time: `${addDays(today, -365)}T16:00:00.000Z`, exercise_type: "RUNNING", name: "Run", end_hr: 160, hrr_1min: 25, hrr_2min: 40 },
    { id: "w2", date: "2026-10-12", start_time: "2026-10-12T08:00:00.000Z", exercise_type: "WALKING", name: null, end_hr: 130, hrr_1min: 20, hrr_2min: null },
    { id: "w1", date: addDays(today, -364), start_time: `${addDays(today, -364)}T16:00:00.000Z`, exercise_type: null, name: null, end_hr: 150, hrr_1min: 22, hrr_2min: 35 },
    { id: "easy", date: "2026-10-14", start_time: "2026-10-14T16:00:00.000Z", exercise_type: "WALKING", name: "Walk", end_hr: null, hrr_1min: null, hrr_2min: null },
  ];
  const s = buildStats(days, today, { sleep_need_min: 480, step_goal: 10000 }, [], workouts);
  assert.deepEqual(s.hrr, [
    { id: "w1", date: addDays(today, -364), exerciseType: null, name: null, hrr1: 22, hrr2: 35, endHr: 150 },
    { id: "w2", date: "2026-10-12", exerciseType: "WALKING", name: null, hrr1: 20, hrr2: null, endHr: 130 },
    { id: "w3", date: "2026-10-12", exerciseType: "RUNNING", name: "Run", hrr1: 30, hrr2: 48, endHr: 170 },
  ], "the last 365 days, oldest first, only workouts with a recovery");
  assert.deepEqual(hrrHistory(workouts, today), s.hrr);
  assert.deepEqual(buildStats(days, today, { sleep_need_min: 480, step_goal: 10000 }).hrr, []);

  assert.deepEqual([s.load.status, s.load.latest!.date, s.load.latest!.ctl, s.load.series.length, s.load.days], ["neutral", addDays(today, -1), 50, 39, 39]);
  assert.equal(s.bedtime.nights, 40);
  assert.deepEqual(s.bedtime.buckets.map((b) => b.label), ["before 22:30", "22:30–23:00", "23:00–23:30", "23:30–00:00", "00:00–00:30", "00:30–01:00", "after 01:00"]);
  const json = JSON.parse(JSON.stringify(s));
  assert.deepEqual(json.load, s.load);
  assert.deepEqual(json.bedtime, s.bedtime);
});

test("training: routines and logged workouts are validated", async () => {
  const { normalizeRoutine, normalizeLog, TrainingInputError, exerciseProgress, logText, routineText } = await import("../functions/fitstats/lib/training.ts");
  const now = "2026-10-19T10:00:00.000Z";
  const r = normalizeRoutine({
    name: "  Push   day ",
    exercises: [
      { name: "Bench press", kind: "strength", sets: "3", reps: 8, weight_kg: "62,5", rest_s: 90 },
      { name: "", kind: "strength" },
      { name: "Plank", kind: "nope", duration_min: 1.25, sets: 99 },
    ],
  }, null, "coach", now);
  assert.equal(r.name, "Push day");
  assert.equal(r.created_by, "coach");
  assert.match(r.id, /^[0-9a-f-]{36}$/);
  assert.deepEqual(r.exercises.map((e) => [e.name, e.kind, e.sets, e.reps, e.weight_kg]), [
    ["Bench press", "strength", 3, "8", 62.5],
    ["Plank", "strength", null, null, null],
  ], "unnamed exercises are dropped, unknown kinds become strength, out-of-range numbers are left out");
  assert.equal(r.exercises[1].duration_min, 1.3);
  const edited = normalizeRoutine({ name: "Push day", exercises: [] }, r, "user", now);
  assert.deepEqual([edited.id, edited.created_by], [r.id, "coach"], "an edit keeps the id and who made it");
  assert.throws(() => normalizeRoutine({ name: " ", exercises: [] }, null, "user", now), TrainingInputError);
  assert.throws(() => normalizeRoutine({ name: "x", exercises: "nope" }, null, "user", now), TrainingInputError);
  assert.match(routineText(r), /^Push day \[made by you, the coach\]: Bench press \(strength: 3 sets of 8 @ 62.5 kg rest 90 s; works chest \(helps: triceps, shoulders\)\)/);

  const log = normalizeLog({
    date: "2026-10-19", name: "Push day", effort: 7, started_at: "2026-10-19T16:00:00Z", ended_at: "2026-10-19T17:05:00Z",
    exercises: [{ name: "Bench press", sets: [{ reps: 8, weight_kg: 60 }, { reps: 8, weight_kg: 62.5 }, { reps: 6, weight_kg: 62.5, done: false }] }],
  }, null, "2026-10-19", now);
  assert.equal(log.exercises[0].sets.filter((s) => s.done).length, 2);
  assert.equal(logText(log), "2026-10-19 Push day (65 min, effort 7/10): Bench press: 8 reps × 60 kg, 8 reps × 62.5 kg");
  assert.throws(() => normalizeLog({ date: "2026-10-20", exercises: [{ name: "x" }] }, null, "2026-10-19", now), /not in the future/);
  assert.throws(() => normalizeLog({ date: "2026-10-19", exercises: [] }, null, "2026-10-19", now), /at least one exercise/);

  const later = normalizeLog({ date: "2026-10-22", exercises: [{ name: "bench press", sets: [{ reps: 10, weight_kg: 62.5 }] }] }, null, "2026-10-22", now);
  const progress = exerciseProgress([later, log]);
  assert.deepEqual([progress[0].sessions, progress[0].best, (progress[0].last as Row).date], [
    2, { date: "2026-10-22", reps: 10, weight_kg: 62.5, duration_min: null, distance_km: null }, "2026-10-22",
  ], "same exercise across case; heaviest then most reps is the best set");
});

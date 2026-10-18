// Run: node --experimental-strip-types --test supabase/tests/
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  addDays,
  daysBetween,
  durationSeconds,
  LocalClock,
  num,
  weekdayIndex,
  zoneOffsetSeconds,
} from "../functions/fitstats/lib/util.ts";
import {
  dailyPointsToPatches,
  exercisePointToRow,
  fallAsleepMinutes,
  maxHeartRate,
  minutesBetween,
  placeMinuteRollups,
  rollupPointsToPatches,
  samplePointsToRows,
  sleepDayPatch,
  sleepPointToRow,
  stepsByHour,
  type IntradayDay,
  wearMinutes,
} from "../functions/fitstats/lib/transform.ts";
import {
  computeRecovery,
  computeSleepScore,
  computeStrain,
  computeStress,
  computeWorkoutLoad,
  strainTarget,
} from "../functions/fitstats/lib/scores.ts";
import { buildStats, countsToward, journalImpacts, lowerFirst, METRIC_BY_KEY, pearson, streak } from "../functions/fitstats/lib/stats.ts";
import { normalizeTags } from "../functions/fitstats/lib/journal.ts";
import { sleepPlan } from "../functions/fitstats/lib/planner.ts";
import { lowWear } from "../functions/fitstats/lib/sync.ts";

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
  assert.deepEqual(vo2.get("2026-10-16"), { vo2max: 47.5, vo2max_level: "GOOD", vo2max_estimated: false });
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
      },
    },
  ], budapest);
  assert.deepEqual(rows.map((r) => r.metric), ["resp_full", "resp_deep"]);
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
  assert.equal(steps.ranges["7"].n, 6, "today's partial steps are excluded");
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
  assert.deepEqual(computeWorkoutLoad([150, 150, null], 55, 190, "male"), { trimp: null, strain: null, hr_max: null, hrr_zone_min: null });
});

test("low wear: relative to your usual wear, never on unfinished days", () => {
  const usual = (n: number, wear: number) => Array.from({ length: n }, (_, i) => day(addDays("2026-10-01", i), { wear_min: wear }));
  assert.equal(lowWear(500, usual(4, 1400), true), null, "under 5 days of history");
  assert.equal(lowWear(500, usual(10, 1400), true), true);
  assert.equal(lowWear(900, usual(10, 1400), true), false);
  assert.equal(lowWear(500, usual(10, 1400), false), null, "today is unfinished");
  assert.equal(lowWear(100, usual(10, 400), true), null, "usually worn under 10 h: not judged");
  assert.equal(lowWear(null, usual(10, 1400), true), null);

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

  const few = sleepPlan([day(today, { strain: 10 })], today, 450);
  assert.equal(few.needMin, 450);
  assert.equal(few.efficiency, 0.9);
  assert.equal(few.wakeMin, null);
  assert.equal(few.bedtimeMin, null);
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

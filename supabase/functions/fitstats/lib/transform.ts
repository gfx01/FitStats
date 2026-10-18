// Pure mapping from Google Health API v4 JSON to FitStats rows.
// Field names follow the v4 discovery document (revision 20261014).

import { durationSeconds, int, LocalClock, MINUTES_PER_DAY, num, utcMsToYmd, type Ymd, ymdFromGoogleDate } from "./util.ts";

export type Json = Record<string, unknown>;
export type DayPatch = Record<string, unknown>;

function obj(v: unknown): Json | null {
  return v && typeof v === "object" && !Array.isArray(v) ? (v as Json) : null;
}

function arr(v: unknown): Json[] {
  return Array.isArray(v) ? (v.filter((x) => x && typeof x === "object") as Json[]) : [];
}

function epochMs(v: unknown): number | null {
  if (typeof v !== "string") return null;
  const ms = Date.parse(v);
  return Number.isFinite(ms) ? ms : null;
}

/** Local date of a physical time, using an explicit UTC offset when the API gave one. */
function localDate(physical: unknown, utcOffset: unknown, clock: LocalClock): Ymd | null {
  const ms = epochMs(physical);
  if (ms === null) return null;
  const off = durationSeconds(utcOffset);
  if (off !== null) return utcMsToYmd(ms + off * 1000);
  return clock.locate(ms).date;
}

// ---------------------------------------------------------------- daily types

interface DailySpec {
  field: string;
  columns: string[];
  map: (v: Json) => DayPatch;
}

function zoneMap(v: Json): DayPatch {
  const zones: Record<string, [number | null, number | null]> = {};
  for (const z of arr(v.heartRateZones)) {
    const type = String(z.heartRateZoneType ?? "");
    if (type) zones[type] = [int(z.minBeatsPerMinute), int(z.maxBeatsPerMinute)];
  }
  return { hr_zones: Object.keys(zones).length ? zones : null };
}

/** Daily summary data types read with `list` and a `{type}.date` filter. */
export const DAILY_TYPES: Record<string, DailySpec> = {
  "daily-resting-heart-rate": {
    field: "dailyRestingHeartRate",
    columns: ["rhr"],
    map: (v) => ({ rhr: int(v.beatsPerMinute) }),
  },
  "daily-heart-rate-variability": {
    field: "dailyHeartRateVariability",
    columns: ["hrv_rmssd", "hrv_deep_rmssd", "hrv_entropy", "non_rem_hr"],
    map: (v) => ({
      hrv_rmssd: num(v.averageHeartRateVariabilityMilliseconds),
      hrv_deep_rmssd: num(v.deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds),
      hrv_entropy: num(v.entropy),
      non_rem_hr: int(v.nonRemHeartRateBeatsPerMinute),
    }),
  },
  "daily-oxygen-saturation": {
    field: "dailyOxygenSaturation",
    columns: ["spo2_avg", "spo2_lower", "spo2_upper"],
    map: (v) => ({
      spo2_avg: num(v.averagePercentage),
      spo2_lower: num(v.lowerBoundPercentage),
      spo2_upper: num(v.upperBoundPercentage),
    }),
  },
  "daily-respiratory-rate": {
    field: "dailyRespiratoryRate",
    columns: ["resp_rate"],
    map: (v) => ({ resp_rate: num(v.breathsPerMinute) }),
  },
  "daily-sleep-temperature-derivations": {
    field: "dailySleepTemperatureDerivations",
    columns: ["skin_temp_c", "skin_temp_baseline_c", "skin_temp_stddev_c"],
    map: (v) => ({
      skin_temp_c: num(v.nightlyTemperatureCelsius),
      skin_temp_baseline_c: num(v.baselineTemperatureCelsius),
      skin_temp_stddev_c: num(v.relativeNightlyStddev30dCelsius),
    }),
  },
  "daily-vo2-max": {
    field: "dailyVo2Max",
    // vo2max_source/method: filled from the vo2-max or run-vo2-max samples on days without this (vo2SamplePatches).
    columns: ["vo2max", "vo2max_level", "vo2max_estimated", "vo2max_source", "vo2max_method"],
    map: (v) => ({
      vo2max: num(v.vo2Max),
      vo2max_level: typeof v.cardioFitnessLevel === "string" ? v.cardioFitnessLevel : null,
      vo2max_estimated: typeof v.estimated === "boolean" ? v.estimated : null,
      vo2max_source: num(v.vo2Max) === null ? null : "daily",
    }),
  },
  "daily-heart-rate-zones": {
    field: "dailyHeartRateZones",
    columns: ["hr_zones"],
    map: zoneMap,
  },
};

/** Merges points of one daily type into per-date patches (first non-null value wins). */
export function dailyPointsToPatches(type: string, points: Json[]): Map<Ymd, DayPatch> {
  const spec = DAILY_TYPES[type];
  const out = new Map<Ymd, DayPatch>();
  if (!spec) return out;
  for (const p of points) {
    const v = obj(p[spec.field]);
    if (!v) continue;
    const date = ymdFromGoogleDate(v.date);
    if (!date) continue;
    const patch = spec.map(v);
    const prev = out.get(date) ?? {};
    for (const [k, val] of Object.entries(patch)) {
      if (prev[k] === undefined || prev[k] === null) prev[k] = val;
    }
    out.set(date, prev);
  }
  return out;
}

// ------------------------------------------------------------- daily rollups

interface RollupSpec {
  field: string;
  columns: string[];
  shortRange: boolean; // API caps the range at 14 days instead of 90
  map: (v: Json) => DayPatch;
}

const ZONE_COLUMN: Record<string, string> = {
  LIGHT: "zone_light_min",
  MODERATE: "zone_moderate_min",
  VIGOROUS: "zone_vigorous_min",
  PEAK: "zone_peak_min",
};

const ACTIVITY_COLUMN: Record<string, string> = {
  LIGHT: "active_light_min",
  MODERATE: "active_moderate_min",
  VIGOROUS: "active_vigorous_min",
};

/** Data types aggregated per local day with `dailyRollUp`. */
export const ROLLUP_TYPES: Record<string, RollupSpec> = {
  steps: { field: "steps", columns: ["steps"], shortRange: false, map: (v) => ({ steps: int(v.countSum) }) },
  distance: {
    field: "distance",
    columns: ["distance_m"],
    shortRange: false,
    map: (v) => {
      const mm = num(v.millimetersSum);
      return { distance_m: mm === null ? null : mm / 1000 };
    },
  },
  floors: { field: "floors", columns: ["floors"], shortRange: false, map: (v) => ({ floors: int(v.countSum) }) },
  "active-zone-minutes": {
    field: "activeZoneMinutes",
    columns: ["azm_fat_burn", "azm_cardio", "azm_peak"],
    shortRange: false,
    map: (v) => ({
      azm_fat_burn: int(v.sumInFatBurnHeartZone) ?? 0,
      azm_cardio: int(v.sumInCardioHeartZone) ?? 0,
      azm_peak: int(v.sumInPeakHeartZone) ?? 0,
    }),
  },
  "active-energy-burned": {
    field: "activeEnergyBurned",
    columns: ["calories_active"],
    shortRange: false,
    map: (v) => ({ calories_active: num(v.kcalSum) }),
  },
  "sedentary-period": {
    field: "sedentaryPeriod",
    columns: ["sedentary_min"],
    shortRange: false,
    map: (v) => {
      const s = durationSeconds(v.durationSum);
      return { sedentary_min: s === null ? null : s / 60 };
    },
  },
  "time-in-heart-rate-zone": {
    field: "timeInHeartRateZone",
    columns: Object.values(ZONE_COLUMN),
    shortRange: false,
    map: (v) => {
      const patch: DayPatch = {};
      for (const col of Object.values(ZONE_COLUMN)) patch[col] = 0;
      for (const z of arr(v.timeInHeartRateZones)) {
        const col = ZONE_COLUMN[String(z.heartRateZone)];
        const s = durationSeconds(z.duration);
        if (col && s !== null) patch[col] = s / 60;
      }
      return patch;
    },
  },
  weight: {
    field: "weight",
    columns: ["weight_kg"],
    shortRange: false,
    map: (v) => {
      const g = num(v.weightGramsAvg);
      return { weight_kg: g === null ? null : g / 1000 };
    },
  },
  "body-fat": {
    field: "bodyFat",
    columns: ["body_fat_pct"],
    shortRange: false,
    map: (v) => ({ body_fat_pct: num(v.bodyFatPercentageAvg) }),
  },
  "heart-rate": {
    field: "heartRate",
    columns: ["hr_min", "hr_avg", "hr_max"],
    shortRange: true,
    map: (v) => ({ hr_min: num(v.beatsPerMinuteMin), hr_avg: num(v.beatsPerMinuteAvg), hr_max: num(v.beatsPerMinuteMax) }),
  },
  "total-calories": {
    field: "totalCalories",
    columns: ["calories_total"],
    shortRange: true,
    map: (v) => ({ calories_total: num(v.kcalSum) }),
  },
  "active-minutes": {
    field: "activeMinutes",
    columns: Object.values(ACTIVITY_COLUMN),
    shortRange: true,
    map: (v) => {
      const patch: DayPatch = {};
      for (const col of Object.values(ACTIVITY_COLUMN)) patch[col] = 0;
      for (const a of arr(v.activeMinutesRollupByActivityLevel)) {
        const col = ACTIVITY_COLUMN[String(a.activityLevel)];
        const m = int(a.activeMinutesSum);
        if (col && m !== null) patch[col] = m;
      }
      return patch;
    },
  },
};

/**
 * Per-date patches from a dailyRollUp response. A bucket without a value
 * object means "no data" (device not worn), never zero. Active Zone Minutes
 * are the exception: Google sends nothing for a day without any, so syncRange
 * fills 0 on days the band was worn.
 */
export function rollupPointsToPatches(type: string, points: Json[]): Map<Ymd, DayPatch> {
  const spec = ROLLUP_TYPES[type];
  const out = new Map<Ymd, DayPatch>();
  if (!spec) return out;
  for (const p of points) {
    const v = obj(p[spec.field]);
    if (!v) continue;
    const start = obj(p.civilStartTime);
    const date = start ? ymdFromGoogleDate(start.date) : null;
    if (!date) continue;
    out.set(date, spec.map(v));
  }
  return out;
}

// --------------------------------------------------------------------- sleep

export const STAGE_CODE: Record<string, number> = {
  AWAKE: 0,
  LIGHT: 1,
  DEEP: 2,
  REM: 3,
  ASLEEP: 4,
  RESTLESS: 5,
};

export interface SleepRow {
  id: string;
  date: Ymd;
  start_time: string;
  end_time: string;
  start_offset_s: number | null;
  end_offset_s: number | null;
  is_main: boolean;
  is_nap: boolean;
  sleep_type: string | null;
  minutes_asleep: number | null;
  minutes_awake: number | null;
  minutes_in_period: number | null;
  minutes_to_fall_asleep: number | null;
  minutes_after_wakeup: number | null;
  deep_min: number | null;
  light_min: number | null;
  rem_min: number | null;
  awake_min: number | null;
  awake_count: number | null;
  stages: [number, number, number][];
}

function roundOrNull(v: number | null): number | null {
  return v === null ? null : Math.round(v);
}

function lastSegment(name: unknown, fallback: string): string {
  if (typeof name === "string" && name.includes("/")) {
    const s = name.split("/").pop();
    if (s) return s;
  }
  return fallback;
}

export function sleepPointToRow(p: Json, clock: LocalClock): SleepRow | null {
  const s = obj(p.sleep);
  if (!s) return null;
  const interval = obj(s.interval);
  if (!interval) return null;
  const startMs = epochMs(interval.startTime);
  const endMs = epochMs(interval.endTime);
  if (startMs === null || endMs === null) return null;

  const civilEnd = obj(interval.civilEndTime);
  const date = (civilEnd ? ymdFromGoogleDate(civilEnd.date) : null) ??
    localDate(interval.endTime, interval.endUtcOffset, clock);
  if (!date) return null;

  const stages: [number, number, number][] = [];
  for (const st of arr(s.stages)) {
    const a = epochMs(st.startTime), b = epochMs(st.endTime);
    const code = STAGE_CODE[String(st.type)];
    if (a === null || b === null || code === undefined || b <= a) continue;
    stages.push([code, Math.round(a / 1000), Math.round(b / 1000)]);
  }
  stages.sort((x, y) => x[1] - y[1]);

  const stageMinutes: Record<string, number> = {};
  const stageCounts: Record<string, number> = {};
  const summary = obj(s.summary);
  for (const ss of arr(summary?.stagesSummary)) {
    const t = String(ss.type);
    stageMinutes[t] = int(ss.minutes) ?? 0;
    stageCounts[t] = int(ss.count) ?? 0;
  }
  if (Object.keys(stageMinutes).length === 0 && stages.length > 0) {
    for (const [code, a, b] of stages) {
      const t = Object.keys(STAGE_CODE).find((k) => STAGE_CODE[k] === code)!;
      stageMinutes[t] = (stageMinutes[t] ?? 0) + Math.round((b - a) / 60);
      stageCounts[t] = (stageCounts[t] ?? 0) + 1;
    }
  }

  const meta = obj(s.metadata) ?? {};
  const type = typeof s.type === "string" ? s.type : null;
  // stagesSummary leaves out stage types with no minutes: in a STAGES session that is 0, not unknown.
  if (type === "STAGES") {
    for (const t of ["AWAKE", "LIGHT", "DEEP", "REM"]) {
      stageMinutes[t] ??= 0;
      stageCounts[t] ??= 0;
    }
  }
  const hasStages = type ? type === "STAGES" : stageMinutes.DEEP !== undefined || stageMinutes.REM !== undefined;
  let asleep = int(summary?.minutesAsleep);
  if (asleep === null) {
    asleep = hasStages
      ? (stageMinutes.LIGHT ?? 0) + (stageMinutes.DEEP ?? 0) + (stageMinutes.REM ?? 0)
      : (stageMinutes.ASLEEP ?? null);
  }
  const inPeriod = int(summary?.minutesInSleepPeriod) ?? Math.round((endMs - startMs) / 60000);

  return {
    id: lastSegment(p.name, `sleep-${interval.startTime}`),
    date,
    start_time: new Date(startMs).toISOString(),
    end_time: new Date(endMs).toISOString(),
    start_offset_s: roundOrNull(durationSeconds(interval.startUtcOffset)),
    end_offset_s: roundOrNull(durationSeconds(interval.endUtcOffset)),
    is_main: meta.mainSleep === true,
    is_nap: meta.nap === true,
    sleep_type: type,
    minutes_asleep: asleep,
    minutes_awake: int(summary?.minutesAwake) ?? (stageMinutes.AWAKE ?? null),
    minutes_in_period: inPeriod,
    minutes_to_fall_asleep: int(summary?.minutesToFallAsleep),
    minutes_after_wakeup: int(summary?.minutesAfterWakeUp),
    deep_min: stageMinutes.DEEP ?? null,
    light_min: stageMinutes.LIGHT ?? null,
    rem_min: stageMinutes.REM ?? null,
    awake_min: stageMinutes.AWAKE ?? null,
    awake_count: stageCounts.AWAKE ?? null,
    stages,
  };
}

/** Clock minutes of an instant relative to local midnight of `anchor` (negative = the evening before). */
export function minutesFromMidnight(epochMsValue: number, offsetSeconds: number, anchor: Ymd): number {
  const local = epochMsValue + offsetSeconds * 1000;
  const anchorMs = Date.parse(`${anchor}T00:00:00Z`);
  return Math.round((local - anchorMs) / 60000);
}

/**
 * Minutes from getting into bed to the first sleep stage. Google reports 0 for
 * automatically detected sleep (Fitbit does not measure it), so when it does,
 * the awake (or restless) stretch at the start of the session is used instead.
 * Null when there are no stages to measure from.
 */
export function fallAsleepMinutes(s: { start_time?: unknown; minutes_to_fall_asleep?: unknown; stages?: unknown }): number | null {
  if (typeof s.minutes_to_fall_asleep === "number" && s.minutes_to_fall_asleep > 0) return s.minutes_to_fall_asleep;
  const startMs = typeof s.start_time === "string" ? Date.parse(s.start_time) : NaN;
  if (!Number.isFinite(startMs) || !Array.isArray(s.stages)) return null;
  const first = (s.stages as unknown[]).find((st): st is [number, number, number] =>
    Array.isArray(st) && typeof st[0] === "number" && typeof st[1] === "number" && st[0] !== STAGE_CODE.AWAKE && st[0] !== STAGE_CODE.RESTLESS);
  if (!first) return null;
  return Math.max(0, Math.round((first[1] * 1000 - startMs) / 60000));
}

/**
 * Awakenings and minutes awake after falling asleep (WASO) from a session's stages:
 * the AWAKE segments after the first sleep stage starts and before the last one ends,
 * so falling asleep and the final wake-up do not count. Touching segments count once.
 * Null without stages.
 */
export function awakeAfterOnset(stages: unknown): { awakenings: number; wasoMin: number } | null {
  if (!Array.isArray(stages)) return null;
  const segs = (stages as unknown[]).filter((st): st is [number, number, number] =>
    Array.isArray(st) && typeof st[0] === "number" && typeof st[1] === "number" && typeof st[2] === "number");
  if (!segs.length) return null;
  const asleep = segs.filter((st) => st[0] !== STAGE_CODE.AWAKE && st[0] !== STAGE_CODE.RESTLESS);
  if (!asleep.length) return { awakenings: 0, wasoMin: 0 };
  const onset = Math.min(...asleep.map((st) => st[1]));
  const lastSleepEnd = Math.max(...asleep.map((st) => st[2]));
  let awakenings = 0;
  let seconds = 0;
  let prevEnd = -Infinity;
  for (const [code, a, b] of [...segs].sort((x, y) => x[1] - y[1])) {
    if (code !== STAGE_CODE.AWAKE || a < onset || b > lastSleepEnd) continue;
    if (a > prevEnd) awakenings++;
    seconds += b - a;
    prevEnd = b;
  }
  return { awakenings, wasoMin: Math.round(seconds / 60) };
}

type SleepLike = { id?: unknown; is_main?: unknown; is_nap?: unknown; minutes_asleep?: unknown; start_time?: unknown };

/**
 * A day's main sleep: the session `mainId` names (fs_days.sleep_main_id) when it is
 * there, otherwise the best ranked: not a nap, then flagged main sleep, then the
 * longest asleep. Google sometimes flags a nap as main sleep too, so neither flag
 * alone decides.
 */
export function mainSleepOf<T extends SleepLike>(sessions: T[], mainId: unknown = null): T | null {
  const named = typeof mainId === "string" ? sessions.find((s) => s.id === mainId) : undefined;
  if (named) return named;
  const rank = (s: T) => (s.is_nap === true ? 0 : 2) + (s.is_main === true ? 1 : 0);
  const asleep = (s: T) => (typeof s.minutes_asleep === "number" ? s.minutes_asleep : 0);
  return [...sessions].sort((a, b) =>
    rank(b) - rank(a) || asleep(b) - asleep(a) || String(a.start_time).localeCompare(String(b.start_time))
  )[0] ?? null;
}

/** fs_days sleep columns for one date from all sessions that ended on it. */
export function sleepDayPatch(date: Ymd, sessions: SleepRow[], clock: LocalClock): DayPatch {
  const ofDay = sessions.filter((s) => s.date === date);
  const main = mainSleepOf(ofDay);
  // Every session other than the main sleep is a nap, whatever Google's flags say.
  const napMin = ofDay.filter((s) => s !== main).reduce((acc, s) => acc + (s.minutes_asleep ?? 0), 0);
  if (!main) {
    return {
      sleep_main_id: null, sleep_start: null, sleep_end: null, sleep_asleep_min: null, sleep_in_bed_min: null,
      sleep_awake_min: null, sleep_deep_min: null, sleep_light_min: null, sleep_rem_min: null,
      sleep_latency_min: null, sleep_awakenings: null, sleep_waso_min: null, sleep_efficiency: null,
      sleep_bedtime_min: null, sleep_waketime_min: null, sleep_has_stages: null, nap_min: napMin || null,
    };
  }
  const awake = awakeAfterOnset(main.stages);
  const startMs = Date.parse(main.start_time);
  const endMs = Date.parse(main.end_time);
  const startOff = main.start_offset_s ?? clock.offsetSeconds(startMs);
  const endOff = main.end_offset_s ?? clock.offsetSeconds(endMs);
  const inBed = main.minutes_in_period ?? Math.round((endMs - startMs) / 60000);
  const asleep = main.minutes_asleep;
  return {
    sleep_main_id: main.id,
    sleep_start: main.start_time,
    sleep_end: main.end_time,
    sleep_asleep_min: asleep,
    sleep_in_bed_min: inBed,
    sleep_awake_min: main.minutes_awake,
    sleep_deep_min: main.deep_min,
    sleep_light_min: main.light_min,
    sleep_rem_min: main.rem_min,
    sleep_latency_min: fallAsleepMinutes(main),
    sleep_awakenings: awake?.awakenings ?? null,
    sleep_waso_min: awake?.wasoMin ?? null,
    sleep_efficiency: asleep !== null && inBed > 0 ? Math.min(1, asleep / inBed) : null,
    sleep_bedtime_min: minutesFromMidnight(startMs, startOff, date),
    sleep_waketime_min: minutesFromMidnight(endMs, endOff, date),
    sleep_has_stages: main.sleep_type ? main.sleep_type === "STAGES" : main.deep_min !== null || main.rem_min !== null,
    nap_min: napMin || null,
  };
}

export const SLEEP_DAY_COLUMNS = Object.keys(sleepDayPatch("2000-01-01", [], new LocalClock(null)));

// ------------------------------------------------------------------ exercise

export interface ExerciseRow {
  id: string;
  date: Ymd;
  start_time: string;
  end_time: string;
  utc_offset_s: number | null;
  exercise_type: string | null;
  name: string | null;
  duration_s: number;
  active_duration_s: number | null;
  calories: number | null;
  steps: number | null;
  distance_m: number | null;
  avg_hr: number | null;
  azm: number | null;
  zone_light_s: number | null;
  zone_moderate_s: number | null;
  zone_vigorous_s: number | null;
  zone_peak_s: number | null;
  elevation_gain_m: number | null;
  avg_speed_mps: number | null;
  run_vo2max: number | null;
  /** From DataPoint.dataSource: how it was recorded (PASSIVELY_MEASURED = auto-detected, MANUAL, …), by what. */
  recording_method: string | null;
  source_platform: string | null;
  source_device: string | null;
}

export function exercisePointToRow(p: Json, clock: LocalClock): ExerciseRow | null {
  const e = obj(p.exercise);
  if (!e) return null;
  const interval = obj(e.interval);
  if (!interval) return null;
  const startMs = epochMs(interval.startTime);
  const endMs = epochMs(interval.endTime);
  if (startMs === null || endMs === null) return null;
  const civilStart = obj(interval.civilStartTime);
  const date = (civilStart ? ymdFromGoogleDate(civilStart.date) : null) ??
    localDate(interval.startTime, interval.startUtcOffset, clock);
  if (!date) return null;
  const m = obj(e.metricsSummary) ?? {};
  const zones = obj(m.heartRateZoneDurations) ?? {};
  const source = obj(p.dataSource) ?? {};
  const str = (v: unknown) => (typeof v === "string" && v ? v : null);
  const mm = (v: unknown) => {
    const n = num(v);
    return n === null ? null : n / 1000;
  };
  // Durations may carry fractional seconds ("2640.5s"); the columns are integers.
  const secs = (v: unknown) => {
    const s = durationSeconds(v);
    return s === null ? null : Math.round(s);
  };
  return {
    id: lastSegment(p.name, `exercise-${interval.startTime}`),
    date,
    start_time: new Date(startMs).toISOString(),
    end_time: new Date(endMs).toISOString(),
    utc_offset_s: secs(interval.startUtcOffset),
    exercise_type: typeof e.exerciseType === "string" ? e.exerciseType : null,
    name: typeof e.displayName === "string" ? e.displayName : null,
    duration_s: Math.round((endMs - startMs) / 1000),
    active_duration_s: secs(e.activeDuration),
    calories: num(m.caloriesKcal),
    steps: int(m.steps),
    distance_m: mm(m.distanceMillimeters),
    avg_hr: int(m.averageHeartRateBeatsPerMinute),
    azm: int(m.activeZoneMinutes),
    zone_light_s: secs(zones.lightTime),
    zone_moderate_s: secs(zones.moderateTime),
    zone_vigorous_s: secs(zones.vigorousTime),
    zone_peak_s: secs(zones.peakTime),
    elevation_gain_m: mm(m.elevationGainMillimeters),
    avg_speed_mps: mm(m.averageSpeedMillimetersPerSecond),
    run_vo2max: num(m.runVo2Max),
    recording_method: str(source.recordingMethod),
    source_platform: str(source.platform),
    source_device: str(obj(source.device)?.displayName),
  };
}

// ------------------------------------------------------------------ intraday

export interface IntradayDay {
  hr: (number | null)[];
  steps: (number | null)[];
  /** Seconds of each minute Fitbit counted as sedentary. */
  sedentary: (number | null)[];
}

/** Minutes with heart-rate data: how long the band was worn. */
export function wearMinutes(hr: (number | null)[]): number {
  return hr.reduce<number>((n, v) => (typeof v === "number" && v > 0 ? n + 1 : n), 0);
}

/** A minute counts toward the sustained peak when a neighbouring minute is at most this much lower. */
export const PEAK_NEIGHBOUR_BPM = 15;

/**
 * Highest sustained heart rate of a day (fs_days.hr_peak_sustained): the highest minute
 * average with a neighbouring minute at most 15 bpm below it, so an isolated optical
 * spike (132, 194, 134) does not count but the top minute of a hard effort does.
 */
export function sustainedPeak(hr: (number | null)[]): number | null {
  const at = (m: number) => (typeof hr[m] === "number" && hr[m]! > 0 ? hr[m]! : null);
  let peak: number | null = null;
  for (let m = 0; m < hr.length; m++) {
    const v = at(m);
    if (v === null || (peak !== null && v <= peak)) continue;
    const near = Math.max(at(m - 1) ?? 0, at(m + 1) ?? 0);
    if (near >= v - PEAK_NEIGHBOUR_BPM) peak = v;
  }
  return peak;
}

/** Cumulative minute steps at the end of each local hour (24 values), or null without step data. */
export function stepsByHour(steps: (number | null)[]): number[] | null {
  let any = false;
  let total = 0;
  const out: number[] = [];
  for (let h = 0; h < 24; h++) {
    for (let m = h * 60; m < h * 60 + 60; m++) {
      const v = steps[m];
      if (typeof v === "number") {
        total += v;
        any = true;
      }
    }
    out.push(total);
  }
  return any ? out : null;
}

/** Minute heart rate between two instants, read from per-local-day minute slots. */
export function minutesBetween(
  startMs: number,
  endMs: number,
  clock: LocalClock,
  hrFor: (date: Ymd) => (number | null)[] | null | undefined,
): (number | null)[] {
  const out: (number | null)[] = [];
  for (let t = Math.floor(startMs / 60000) * 60000; t < endMs; t += 60000) {
    const { date, minute } = clock.locate(t);
    out.push(hrFor(date)?.[minute] ?? null);
  }
  return out;
}

export function emptyIntraday(): IntradayDay {
  return {
    hr: new Array(MINUTES_PER_DAY).fill(null),
    steps: new Array(MINUTES_PER_DAY).fill(null),
    sedentary: new Array(MINUTES_PER_DAY).fill(null),
  };
}

/**
 * Places 60 s rollUp windows into per-local-day minute slots.
 * `kind` picks the value: heart rate average, step count or sedentary seconds.
 */
export function placeMinuteRollups(
  points: Json[],
  kind: "hr" | "steps" | "sedentary",
  clock: LocalClock,
  into: Map<Ymd, IntradayDay>,
): void {
  for (const p of points) {
    const startMs = epochMs(p.startTime);
    if (startMs === null) continue;
    let value: number | null = null;
    if (kind === "hr") {
      const v = obj(p.heartRate);
      value = v ? num(v.beatsPerMinuteAvg) : null;
      if (value !== null) value = Math.round(value);
    } else if (kind === "sedentary") {
      const v = obj(p.sedentaryPeriod);
      value = v ? durationSeconds(v.durationSum) : null;
      if (value !== null) value = Math.round(value);
    } else {
      const v = obj(p.steps);
      value = v ? int(v.countSum) : null;
    }
    if (value === null) continue;
    const { date, minute } = clock.locate(startMs);
    let day = into.get(date);
    if (!day) {
      day = emptyIntraday();
      into.set(date, day);
    }
    day[kind][minute] = Math.min(value, 32767);
  }
}

// ------------------------------------------------------------------- samples

export interface SampleRow {
  metric: string;
  t: string;
  date: Ymd;
  value: number;
}

function sampleBase(v: Json, clock: LocalClock): { t: string; date: Ymd } | null {
  const st = obj(v.sampleTime);
  if (!st) return null;
  const ms = epochMs(st.physicalTime);
  if (ms === null) return null;
  const civil = obj(st.civilTime);
  const date = (civil ? ymdFromGoogleDate(civil.date) : null) ?? localDate(st.physicalTime, st.utcOffset, clock);
  if (!date) return null;
  return { t: new Date(ms).toISOString(), date };
}

/**
 * fs_days VO2 max patches from the vo2-max or run-vo2-max samples (the latest of each
 * local day), for days without Google's daily-vo2-max value. vo2max_method is
 * Google's measurementMethod; GOOGLE_DEMOGRAPHIC means estimated from the profile.
 */
export function vo2SamplePatches(type: "vo2-max" | "run-vo2-max", points: Json[], clock: LocalClock): Map<Ymd, DayPatch> {
  const out = new Map<Ymd, DayPatch>();
  const latest = new Map<Ymd, string>();
  for (const p of points) {
    const v = obj(type === "vo2-max" ? p.vo2Max : p.runVo2Max);
    const base = v && sampleBase(v, clock);
    const val = v ? num(type === "vo2-max" ? v.vo2Max : v.runVo2Max) : null;
    if (!base || val === null || val <= 0) continue;
    if ((latest.get(base.date) ?? "") > base.t) continue;
    latest.set(base.date, base.t);
    const method = type === "vo2-max" && typeof v!.measurementMethod === "string" ? v!.measurementMethod : null;
    out.set(base.date, { vo2max: val, vo2max_source: type === "vo2-max" ? "sample" : "run", vo2max_method: method });
  }
  return out;
}

export function samplePointsToRows(type: string, points: Json[], clock: LocalClock): SampleRow[] {
  const rows: SampleRow[] = [];
  for (const p of points) {
    if (type === "heart-rate-variability") {
      const v = obj(p.heartRateVariability);
      const base = v && sampleBase(v, clock);
      const val = v ? num(v.rootMeanSquareOfSuccessiveDifferencesMilliseconds) : null;
      if (base && val !== null) rows.push({ metric: "hrv", ...base, value: val });
    } else if (type === "oxygen-saturation") {
      const v = obj(p.oxygenSaturation);
      const base = v && sampleBase(v, clock);
      const val = v ? num(v.percentage) : null;
      if (base && val !== null) rows.push({ metric: "spo2", ...base, value: val });
    } else if (type === "respiratory-rate-sleep-summary") {
      const v = obj(p.respiratoryRateSleepSummary);
      const base = v && sampleBase(v, clock);
      if (!v || !base) continue;
      const stats: [string, unknown][] = [
        ["resp_full", v.fullSleepStats],
        ["resp_deep", v.deepSleepStats],
        ["resp_light", v.lightSleepStats],
        ["resp_rem", v.remSleepStats],
      ];
      for (const [metric, s] of stats) {
        const val = num(obj(s)?.breathsPerMinute);
        // Google sends 0 when it could not compute a stage's rate; no one breathes 0 times a minute.
        if (val !== null && val > 0) rows.push({ metric, ...base, value: val });
      }
    }
  }
  return rows;
}

// ------------------------------------------------------------------- profile

export function maxHeartRate(age: number | null, override: number | null): number {
  if (override) return override;
  if (age && age > 5 && age < 110) return Math.round(208 - 0.7 * age); // Tanaka et al. 2001
  return 190;
}

export interface MaxHr {
  value: number;
  source: "override" | "observed" | "age";
}

/**
 * The max heart rate strain, stress and zones use: the override, else the higher of the
 * age estimate and `observedPeak` (the highest sustained heart rate of the last year,
 * see sustainedPeak). Formulas underestimate some people, teenagers especially.
 */
export function chooseMaxHr(age: number | null, override: number | null, observedPeak: number | null): MaxHr {
  if (override) return { value: override, source: "override" };
  const estimate = maxHeartRate(age, null);
  if (observedPeak !== null && observedPeak > estimate) return { value: observedPeak, source: "observed" };
  return { value: estimate, source: "age" };
}

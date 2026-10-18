// FitStats scores. These are our own transparent formulas, not Bevel's or
// Fitbit's (both proprietary). Every component is returned so the app can
// show exactly how a number was built.

import { addDays, clamp, mean, median, MINUTES_PER_DAY, round, stdDev, type Ymd } from "./util.ts";

export type DayRow = Record<string, unknown> & { date: string };

function n(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

// --------------------------------------------------------------------- strain

/** Banister TRIMP weighting (a·e^(b·HRR)). */
export function trimpCoefficients(sex: string): [number, number] {
  return sex === "female" ? [0.86, 1.67] : [0.64, 1.92];
}

/** Heart-rate-reserve bands used for the zone breakdown: 50/60/70/80/90 %. */
export const HRR_ZONE_EDGES = [0.5, 0.6, 0.7, 0.8, 0.9];

export const STRAIN_SCALE = 120; // TRIMP at which strain reaches 63 %
export const TRIMP_MIN_HRR = 0.3; // ignore minutes below 30 % HRR (normal daily life)

export interface StrainResult {
  strain: number;
  trimp: number;
  hrMinutes: number;
  zoneMinutes: number[]; // 5 HRR zones
}

interface HrLoad {
  trimp: number;
  hrMinutes: number;
  zoneMinutes: number[];
  maxBpm: number | null;
}

/** A minute more than this above both neighbours is an optical glitch, not effort. */
export const SPIKE_BPM = 30;

/** Minute heart rate with single-minute spikes (over 30 bpm above both non-null neighbours) replaced by the neighbours' mean. */
export function despike(hr: (number | null)[]): (number | null)[] {
  const out = hr.slice();
  for (let m = 1; m + 1 < hr.length; m++) {
    const v = hr[m], a = hr[m - 1], b = hr[m + 1];
    if (typeof v !== "number" || typeof a !== "number" || typeof b !== "number" || a <= 0 || b <= 0) continue;
    if (v - a > SPIKE_BPM && v - b > SPIKE_BPM) out[m] = Math.round((a + b) / 2);
  }
  return out;
}

/** TRIMP, minutes with data and HRR zone minutes for any stretch of minute heart rate (spikes removed). */
function hrLoad(hr: (number | null)[], rhr: number, reserve: number, sex: string): HrLoad {
  const [a, b] = trimpCoefficients(sex);
  let trimp = 0;
  let hrMinutes = 0;
  let maxBpm: number | null = null;
  const zoneMinutes = [0, 0, 0, 0, 0];
  for (const bpm of despike(hr)) {
    if (bpm === null || bpm === undefined || bpm <= 0) continue;
    hrMinutes++;
    if (maxBpm === null || bpm > maxBpm) maxBpm = bpm;
    const hrr = clamp((bpm - rhr) / reserve, 0, 1.1);
    if (hrr >= TRIMP_MIN_HRR) trimp += hrr * a * Math.exp(b * hrr);
    for (let z = HRR_ZONE_EDGES.length - 1; z >= 0; z--) {
      if (hrr >= HRR_ZONE_EDGES[z]) {
        zoneMinutes[z]++;
        break;
      }
    }
  }
  return { trimp, hrMinutes, zoneMinutes, maxBpm };
}

/** 100 × (1 − e^(−TRIMP / 120)) */
export function strainFromTrimp(trimp: number): number {
  return round(100 * (1 - Math.exp(-trimp / STRAIN_SCALE)), 1)!;
}

/**
 * Strain 0–100 from minute heart rate: 100 × (1 − e^(−TRIMP / 120)).
 * TRIMP sums HRR · a · e^(b·HRR) per minute at or above 30 % heart-rate reserve.
 */
export function computeStrain(
  hr: (number | null)[],
  rhr: number,
  maxHr: number,
  sex: string,
): StrainResult | null {
  const reserve = maxHr - rhr;
  if (reserve < 20) return null;
  const load = hrLoad(hr, rhr, reserve, sex);
  if (load.hrMinutes < 120) return null; // under two hours of wear: not a meaningful day total
  return {
    strain: strainFromTrimp(load.trimp),
    trimp: round(load.trimp, 1)!,
    hrMinutes: load.hrMinutes,
    zoneMinutes: load.zoneMinutes,
  };
}

export interface WorkoutLoad {
  trimp: number | null;
  strain: number | null;
  /** Highest minute average after removing spikes ("Peak minute HR"). */
  hr_max: number | null;
  hrr_zone_min: number[] | null;
  /** Minutes of the workout window with heart rate. */
  hr_minutes: number;
}

/**
 * The same load for one workout's minutes. Strain is what the workout alone
 * would score on the day scale; day strain is not the sum of workout strains.
 */
export function computeWorkoutLoad(hr: (number | null)[], rhr: number, maxHr: number, sex: string): WorkoutLoad {
  const hrMinutes = hr.filter((v) => typeof v === "number" && v > 0).length;
  const reserve = maxHr - rhr;
  const load = reserve >= 20 ? hrLoad(hr, rhr, reserve, sex) : null;
  if (!load || load.hrMinutes < 5) return { trimp: null, strain: null, hr_max: null, hrr_zone_min: null, hr_minutes: hrMinutes };
  return {
    trimp: round(load.trimp, 1),
    strain: strainFromTrimp(load.trimp),
    hr_max: load.maxBpm,
    hrr_zone_min: load.zoneMinutes,
    hr_minutes: hrMinutes,
  };
}

/** Heart-rate recovery needs a workout window this long (minutes), with heart rate in this share of its minutes, */
export const HRR_MIN_WINDOW = 10;
export const HRR_MIN_COVERAGE = 0.7;
/** heart rate at the end at least this far up the heart-rate reserve (still working hard), */
export const HRR_MIN_END_RESERVE = 0.5;
/** and no other workout starting within this many minutes after the end. */
export const HRR_CLEAR_MIN = 3;

export interface WorkoutRecovery {
  end_hr: number | null;
  hrr_1min: number | null;
  hrr_2min: number | null;
}

/**
 * Heart-rate recovery after a workout. `hr` is the workout's minute window (as minutesBetween
 * gives it), `after` the 2 minutes that follow it; spikes are removed from both together.
 * end_hr is the mean of the window's last 2 minutes, hrr_1min / hrr_2min how far heart rate
 * fell by the 1st / 2nd minute after. All null unless the window is 10+ minutes with heart
 * rate in 70 % of them, both last minutes and both minutes after have heart rate, end_hr is
 * at least halfway up the heart-rate reserve, and `clear` (no other workout starts within
 * 3 minutes after the end). A fall of 0 or less at 1 minute is not a recovery but a recorded
 * end before the real one (heart rate kept rising), so it is left out too.
 */
export function heartRateRecovery(
  hr: (number | null)[],
  after: (number | null)[],
  rhr: number,
  maxHr: number,
  clear: boolean,
): WorkoutRecovery {
  const none = { end_hr: null, hrr_1min: null, hrr_2min: null };
  const has = (v: number | null | undefined): v is number => typeof v === "number" && v > 0;
  if (!clear || hr.length < HRR_MIN_WINDOW || after.length < 2) return none;
  if (hr.filter(has).length < HRR_MIN_COVERAGE * hr.length) return none;
  const all = despike([...hr, after[0], after[1]]);
  const n = hr.length;
  const a = all[n - 2], b = all[n - 1], first = all[n], second = all[n + 1];
  if (!has(a) || !has(b) || !has(first) || !has(second)) return none;
  const end = Math.round((a + b) / 2);
  if (end < rhr + HRR_MIN_END_RESERVE * (maxHr - rhr) || end - first <= 0) return none;
  return { end_hr: end, hrr_1min: end - first, hrr_2min: end - second };
}

/** Recommended strain band for a recovery score. */
export function strainTarget(recovery: number | null): [number, number] | null {
  if (recovery === null) return null;
  if (recovery >= 67) return [55, 80];
  if (recovery >= 34) return [35, 60];
  return [10, 35];
}

// --------------------------------------------------------------------- stress

/** A still minute scores 0 at your usual still heart rate and 100 this far (in heart-rate reserve) above it. */
export const STRESS_SPAN_HRR = 0.15;
/** Usual still HRR until there are STRESS_BASELINE_MIN_DAYS days of your own (pooled real data: median 0.14). */
export const STRESS_BASELINE_HRR = 0.14;
export const STRESS_BASELINE_DAYS = 30;
export const STRESS_BASELINE_MIN_DAYS = 7;
/** Seconds of a minute Fitbit must count as sedentary for the minute to be still (per-minute data). */
export const SEDENTARY_MIN_S = 45;
/** Workouts and the recovery after them are left out of stress for 30–180 minutes after the end. */
export const COOL_DOWN_MIN = 30;
export const COOL_DOWN_MAX = 180;
/** Recovered: heart rate back within this much reserve of the level before the workout. */
export const COOL_DOWN_HRR = 0.1;

export interface StressResult {
  stress: number | null;
  minutes: number;
  hourly: (number | null)[];
  /** Median HRR of the qualifying minutes (60 or more); later days' baselines are built from it. */
  stillHrr: number | null;
}

/**
 * Your usual still heart rate as heart-rate reserve: the median of the previous 30 days'
 * still-minute medians (`still`, by date), or STRESS_BASELINE_HRR with fewer than 7 of them.
 * `days` is how many of those days there were.
 */
export function stressBaseline(date: Ymd, still: Map<Ymd, number>): { hrr: number; days: number } {
  const from = addDays(date, -STRESS_BASELINE_DAYS);
  const vals = [...still].filter(([d]) => d >= from && d < date).map(([, v]) => v);
  return { hrr: vals.length >= STRESS_BASELINE_MIN_DAYS ? median(vals)! : STRESS_BASELINE_HRR, days: vals.length };
}

/**
 * Minutes after a workout's end that stress still leaves out: until heart rate is back,
 * 2 minutes in a row, within 10 % of reserve of the level before the workout; at least
 * 30, at most 180. The level before is the median of `before` (the 30 minutes before the
 * start), or your usual still heart rate (`baselineHrr`) when that is lower or `before`
 * has under 10 minutes: people walk or warm up before a game, and after long, hard
 * sessions heart rate can sit 20–30 bpm above normal for 2–3 hours. `after` holds the
 * minutes from the end on.
 */
export function coolDownMinutes(
  before: (number | null)[],
  after: (number | null)[],
  rhr: number,
  maxHr: number,
  baselineHrr: number,
): number {
  const reserve = maxHr - rhr;
  const pre = before.filter((v): v is number => typeof v === "number" && v > 0);
  const usual = rhr + baselineHrr * reserve;
  const level = pre.length >= 10 ? Math.min(median(pre)!, usual) : usual;
  const limit = level + COOL_DOWN_HRR * reserve;
  const recovered = (v: number | null | undefined) => typeof v === "number" && v > 0 && v <= limit;
  for (let m = COOL_DOWN_MIN; m < COOL_DOWN_MAX; m++) {
    if (recovered(after[m]) && recovered(after[m + 1])) return m;
  }
  return COOL_DOWN_MAX;
}

/**
 * The minutes Fitbit counted as sedentary, or null without any. Google's 60 s rollUp puts
 * each sedentary period's whole duration in the minute it starts (periods of 10 minutes or
 * more, adding up to the day's sedentary time), so a value over 60 s covers the minutes
 * after it too; a value up to 60 s is that minute's own seconds.
 */
export function sedentaryMask(sedentary: (number | null)[] | null): boolean[] | null {
  if (!sedentary?.some((v) => typeof v === "number" && v > 0)) return null;
  const mask = new Array(MINUTES_PER_DAY).fill(false);
  for (let m = 0; m < MINUTES_PER_DAY; m++) {
    const v = sedentary[m];
    if (typeof v !== "number" || v <= 0) continue;
    if (v <= 60) {
      if (v >= SEDENTARY_MIN_S) mask[m] = true;
      continue;
    }
    for (let k = m; k < Math.min(MINUTES_PER_DAY, m + Math.round(v / 60)); k++) mask[k] = true;
  }
  return mask;
}

/**
 * Stress 0–100 estimated from heart-rate elevation while still and awake.
 * Google Health exposes no daytime HRV, so this uses heart rate only:
 * per qualifying minute, s = clamp((HRR − baseline) / 15 %, 0, 1); stress = 100 × mean(s),
 * where `baselineHrr` is your usual still HRR (stressBaseline).
 * A minute qualifies when it is outside sleep, workouts and their recovery (`excluded`),
 * no steps were taken in it or the 3 minutes before, and, when the day has Fitbit's
 * minute sedentary data (`sedentary`, seconds), at least 45 s of it were sedentary.
 */
export function computeStress(
  hr: (number | null)[],
  steps: (number | null)[],
  rhr: number,
  maxHr: number,
  excluded: boolean[],
  baselineHrr = STRESS_BASELINE_HRR,
  sedentary: (number | null)[] | null = null,
): StressResult {
  const hourlySum = new Array(24).fill(0);
  const hourlyCount = new Array(24).fill(0);
  const reserve = maxHr - rhr;
  const hasSteps = steps.some((s) => s !== null && s !== undefined);
  const still = sedentaryMask(sedentary);
  const hrrs: number[] = [];
  let sum = 0;
  if (reserve >= 20 && hasSteps) {
    for (let m = 0; m < MINUTES_PER_DAY; m++) {
      const bpm = hr[m];
      if (bpm === null || bpm === undefined || excluded[m]) continue;
      let moving = false;
      for (let k = Math.max(0, m - 3); k <= m; k++) {
        if ((steps[k] ?? 0) > 0) {
          moving = true;
          break;
        }
      }
      if (moving) continue;
      if (still && !still[m]) continue;
      const hrr = (bpm - rhr) / reserve;
      const s = clamp((hrr - baselineHrr) / STRESS_SPAN_HRR, 0, 1);
      sum += s;
      hrrs.push(hrr);
      const h = Math.floor(m / 60);
      hourlySum[h] += s;
      hourlyCount[h]++;
    }
  }
  const count = hrrs.length;
  return {
    stress: count >= 60 ? round((100 * sum) / count, 1) : null,
    minutes: count,
    hourly: hourlySum.map((s, h) => (hourlyCount[h] >= 10 ? round((100 * s) / hourlyCount[h], 0) : null)),
    stillHrr: count >= 60 ? round(median(hrrs), 4) : null,
  };
}

// ---------------------------------------------------------------------- sleep

export interface ScoreComponent {
  key: string;
  label: string;
  value: number; // 0–100
  weight: number;
  detail: string;
}

export interface ScoreResult {
  score: number | null;
  status: "ok" | "partial" | "calibrating" | "no_data";
  components: ScoreComponent[];
}

function combine(components: ScoreComponent[]): number | null {
  const w = components.reduce((acc, c) => acc + c.weight, 0);
  if (w <= 0) return null;
  return round(components.reduce((acc, c) => acc + c.value * c.weight, 0) / w, 0);
}

function fmtMin(min: number): string {
  const h = Math.floor(min / 60);
  const m = Math.round(min % 60);
  return `${h}h ${m}m`;
}

/**
 * Sleep score 0–100:
 *  duration 50 % (asleep ÷ sleep need), efficiency 15 % (asleep ÷ sleep period: 85 %→0 … 98 %→100;
 *  Fitbit's sleep period is auto-detected, not real time in bed, so most nights sit at 92–99 %),
 *  restoration 20 % (deep ≥ 15 % and REM ≥ 20 % of sleep score full marks),
 *  consistency 15 % (bed + wake time drift vs your 14-night median; 2 h drift → 0).
 */
export function computeSleepScore(day: DayRow, previous: DayRow[], sleepNeedMin: number): ScoreResult {
  const asleep = n(day.sleep_asleep_min);
  const inBed = n(day.sleep_in_bed_min);
  if (asleep === null || asleep < 60) return { score: null, status: "no_data", components: [] };
  const comps: ScoreComponent[] = [];

  comps.push({
    key: "duration",
    label: "Duration",
    value: round(clamp((asleep / sleepNeedMin) * 100, 0, 100), 0)!,
    weight: 0.5,
    detail: `${fmtMin(asleep)} of ${fmtMin(sleepNeedMin)} needed`,
  });

  if (inBed !== null && inBed > 0) {
    const eff = asleep / inBed;
    comps.push({
      key: "efficiency",
      label: "Efficiency",
      value: round(clamp(((eff - 0.85) / 0.13) * 100, 0, 100), 0)!,
      weight: 0.15,
      detail: `${Math.round(eff * 100)}% of time in bed asleep`,
    });
  }

  const deep = n(day.sleep_deep_min);
  const rem = n(day.sleep_rem_min);
  if (day.sleep_has_stages === true && deep !== null && rem !== null) {
    const deepPct = deep / asleep;
    const remPct = rem / asleep;
    const v = (clamp(deepPct / 0.15, 0, 1) + clamp(remPct / 0.2, 0, 1)) / 2;
    comps.push({
      key: "restoration",
      label: "Deep + REM",
      value: round(v * 100, 0)!,
      weight: 0.2,
      detail: `Deep ${Math.round(deepPct * 100)}% · REM ${Math.round(remPct * 100)}%`,
    });
  }

  const bed = n(day.sleep_bedtime_min);
  const wake = n(day.sleep_waketime_min);
  const prevBeds = previous.map((d) => n(d.sleep_bedtime_min)).filter((x): x is number => x !== null);
  const prevWakes = previous.map((d) => n(d.sleep_waketime_min)).filter((x): x is number => x !== null);
  if (bed !== null && wake !== null && prevBeds.length >= 4 && prevWakes.length >= 4) {
    const drift = Math.abs(bed - median(prevBeds)!) + Math.abs(wake - median(prevWakes)!);
    comps.push({
      key: "consistency",
      label: "Consistency",
      value: round(clamp((1 - drift / 120) * 100, 0, 100), 0)!,
      weight: 0.15,
      detail: `${Math.round(drift)} min off your usual bed/wake times`,
    });
  }

  return { score: combine(comps), status: comps.length === 4 ? "ok" : "partial", components: comps };
}

// ------------------------------------------------------------------- recovery

function zComponent(z: number): number {
  return round(clamp(50 + 25 * z, 0, 100), 0)!;
}

/**
 * Recovery 0–100 for the morning of `day`:
 *  HRV 45 % (ln RMSSD vs your previous 30 nights, z-score → 50 + 25z),
 *  resting HR 25 % (lower than your 30-day mean is better, same mapping),
 *  sleep 20 % (sleep score),
 *  vitals 10 % (skin temperature and breathing rate: penalised when they
 *  deviate more than 1 SD from your baseline).
 * Needs 5+ prior nights for a baseline; without HRV the score is partial.
 */
export function computeRecovery(day: DayRow, previous: DayRow[], sleepScore: number | null): ScoreResult {
  const comps: ScoreComponent[] = [];

  const hrv = n(day.hrv_rmssd);
  const hrvBase = previous.map((d) => n(d.hrv_rmssd)).filter((x): x is number => x !== null && x > 0);
  if (hrv !== null && hrv > 0 && hrvBase.length >= 5) {
    const logs = hrvBase.map(Math.log);
    const mu = mean(logs)!;
    const sd = Math.max(stdDev(logs) ?? 0, 0.05);
    const baseline = Math.exp(mu);
    comps.push({
      key: "hrv",
      label: "HRV",
      value: zComponent((Math.log(hrv) - mu) / sd),
      weight: 0.45,
      detail: `${Math.round(hrv)} ms vs ${Math.round(baseline)} ms baseline`,
    });
  }

  const rhr = n(day.rhr);
  const rhrBase = previous.map((d) => n(d.rhr)).filter((x): x is number => x !== null && x > 0);
  if (rhr !== null && rhrBase.length >= 5) {
    const mu = mean(rhrBase)!;
    const sd = Math.max(stdDev(rhrBase) ?? 0, 1);
    comps.push({
      key: "rhr",
      label: "Resting HR",
      value: zComponent((mu - rhr) / sd),
      weight: 0.25,
      detail: `${rhr} bpm vs ${round(mu, 0)} bpm baseline`,
    });
  }

  if (sleepScore !== null) {
    comps.push({ key: "sleep", label: "Sleep", value: sleepScore, weight: 0.2, detail: `Sleep score ${sleepScore}` });
  }

  const vitals: number[] = [];
  const vitalNotes: string[] = [];
  const temp = n(day.skin_temp_c);
  const tempBase = n(day.skin_temp_baseline_c);
  if (temp !== null && tempBase !== null) {
    const dev = temp - tempBase;
    const sd = Math.max(n(day.skin_temp_stddev_c) ?? 0.3, 0.1);
    vitals.push(clamp(100 - 30 * Math.max(0, Math.abs(dev) / sd - 1), 0, 100));
    vitalNotes.push(`skin temp ${dev >= 0 ? "+" : ""}${dev.toFixed(1)}°C`);
  }
  const rr = n(day.resp_rate);
  const rrBase = previous.map((d) => n(d.resp_rate)).filter((x): x is number => x !== null);
  if (rr !== null && rrBase.length >= 5) {
    const mu = mean(rrBase)!;
    const sd = Math.max(stdDev(rrBase) ?? 0, 0.3);
    vitals.push(clamp(100 - 30 * Math.max(0, (rr - mu) / sd - 1), 0, 100));
    vitalNotes.push(`breathing ${rr.toFixed(1)} vs ${mu.toFixed(1)} /min`);
  }
  if (vitals.length > 0) {
    comps.push({
      key: "vitals",
      label: "Vitals",
      value: round(mean(vitals)!, 0)!,
      weight: 0.1,
      detail: vitalNotes.join(" · "),
    });
  }

  // Sleep and vitals alone are not a recovery signal: require HRV or resting HR.
  const hasHrv = comps.some((c) => c.key === "hrv");
  const hasCore = hasHrv || comps.some((c) => c.key === "rhr");
  if (!hasCore || comps.length < 2) {
    const calibrating = (hrv !== null && hrvBase.length < 5) || (rhr !== null && rhrBase.length < 5);
    return { score: null, status: calibrating ? "calibrating" : "no_data", components: comps };
  }
  return { score: combine(comps), status: hasHrv ? "ok" : "partial", components: comps };
}

// FitStats scores. These are our own transparent formulas, not Bevel's or
// Fitbit's (both proprietary). Every component is returned so the app can
// show exactly how a number was built.

import { clamp, mean, median, MINUTES_PER_DAY, round, stdDev } from "./util.ts";

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
  const [a, b] = trimpCoefficients(sex);
  const reserve = maxHr - rhr;
  if (reserve < 20) return null;
  let trimp = 0;
  let hrMinutes = 0;
  const zoneMinutes = [0, 0, 0, 0, 0];
  for (const bpm of hr) {
    if (bpm === null || bpm === undefined || bpm <= 0) continue;
    hrMinutes++;
    const hrr = clamp((bpm - rhr) / reserve, 0, 1.1);
    if (hrr >= TRIMP_MIN_HRR) trimp += hrr * a * Math.exp(b * hrr);
    for (let z = HRR_ZONE_EDGES.length - 1; z >= 0; z--) {
      if (hrr >= HRR_ZONE_EDGES[z]) {
        zoneMinutes[z]++;
        break;
      }
    }
  }
  if (hrMinutes < 120) return null; // under two hours of wear: not a meaningful day total
  return {
    strain: round(100 * (1 - Math.exp(-trimp / STRAIN_SCALE)), 1)!,
    trimp: round(trimp, 1)!,
    hrMinutes,
    zoneMinutes,
  };
}

/** Recommended strain band for a recovery score. */
export function strainTarget(recovery: number | null): [number, number] | null {
  if (recovery === null) return null;
  if (recovery >= 67) return [55, 80];
  if (recovery >= 34) return [35, 60];
  return [10, 35];
}

// --------------------------------------------------------------------- stress

export const STRESS_FLOOR_HRR = 0.05;
export const STRESS_SPAN_HRR = 0.25;

export interface StressResult {
  stress: number | null;
  minutes: number;
  hourly: (number | null)[];
}

/**
 * Stress 0–100 estimated from heart-rate elevation while still and awake.
 * Google Health exposes no daytime HRV, so this uses heart rate only:
 * per qualifying minute, s = clamp((HRR − 5 %) / 25 %, 0, 1); stress = 100 × mean(s).
 * A minute qualifies when it is outside sleep/exercise (`excluded`) and no
 * steps were taken in it or the 3 minutes before.
 */
export function computeStress(
  hr: (number | null)[],
  steps: (number | null)[],
  rhr: number,
  maxHr: number,
  excluded: boolean[],
): StressResult {
  const hourlySum = new Array(24).fill(0);
  const hourlyCount = new Array(24).fill(0);
  const reserve = maxHr - rhr;
  const hasSteps = steps.some((s) => s !== null && s !== undefined);
  let sum = 0;
  let count = 0;
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
      const hrr = (bpm - rhr) / reserve;
      const s = clamp((hrr - STRESS_FLOOR_HRR) / STRESS_SPAN_HRR, 0, 1);
      sum += s;
      count++;
      const h = Math.floor(m / 60);
      hourlySum[h] += s;
      hourlyCount[h]++;
    }
  }
  return {
    stress: count >= 60 ? round((100 * sum) / count, 1) : null,
    minutes: count,
    hourly: hourlySum.map((s, h) => (hourlyCount[h] >= 10 ? round((100 * s) / hourlyCount[h], 0) : null)),
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
 *  duration 50 % (asleep ÷ sleep need), efficiency 15 % (70 %→0 … 95 %→100),
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
      value: round(clamp(((eff - 0.7) / 0.25) * 100, 0, 100), 0)!,
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

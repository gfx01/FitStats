// Tonight's sleep need and bedtime: FitStats' own transparent rule, shared with
// the app (ios/FitStats/Core/SleepPlanner.swift, keep the two in step).
//
//   need     = your sleep need
//            + 0–45 min for today's strain (0 at strain 35 or less, 45 at 85 or more)
//            + a quarter of the last 7 nights' sleep debt (at most 60 min; naps on the
//              days before today count as sleep)
//            − today's naps (at most 60 min)
//   in bed   = need ÷ your typical sleep efficiency (median of the last 14 nights, else 90 %)
//   bedtime  = the wake-up time you set for tomorrow (Settings → Wake-up times), else
//              your usual wake time for tomorrow's kind of day (weekday or weekend,
//              median of the last 28 nights) − time in bed
//
// Extras, time in bed and bedtime are rounded to 5 minutes.

import type { DayRow } from "./scores.ts";
import { addDays, clamp, median, weekdayIndex, type Ymd } from "./util.ts";

export interface SleepPlan {
  needMin: number;
  baseMin: number;
  strainMin: number;
  debtMin: number;
  napMin: number;
  efficiency: number;
  inBedMin: number;
  /** Minutes from local midnight; null without enough recent wake times. */
  wakeMin: number | null;
  /** Minutes from local midnight of tomorrow (negative = this evening). */
  bedtimeMin: number | null;
  /** "set": the wake-up time set for tomorrow by hand; otherwise which nights the usual one is from. */
  wakeBasis: "set" | "weekday" | "weekend" | "all" | null;
}

/** Wake-up times set by hand, Monday first: minutes from midnight, or null for a day without one. */
export type WakeTimes = (number | null)[];

/**
 * Seven wake-up times (Monday … Sunday, each 0–1439 minutes or null) from a request or the
 * settings row; null when there are none. Throws on anything else.
 */
export function wakeTimesFrom(v: unknown): WakeTimes | null {
  if (v === null || v === undefined) return null;
  if (!Array.isArray(v) || v.length !== 7) throw new Error("wake_times must be 7 entries, Monday first");
  const out = v.map((x) => {
    if (x === null) return null;
    if (typeof x !== "number" || !Number.isInteger(x) || x < 0 || x > 1439) throw new Error("each wake time is minutes from midnight (0–1439) or null");
    return x;
  });
  return out.some((x) => x !== null) ? out : null;
}

const MIN_NIGHTS = 3;

function num(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

const to5 = (v: number) => Math.round(v / 5) * 5;

export function sleepPlan(days: DayRow[], today: Ymd, sleepNeedMin: number, wakeTimes: WakeTimes | null = null): SleepPlan {
  const byDate = new Map(days.map((d) => [d.date, d]));
  const todayRow = byDate.get(today);

  const strain = num(todayRow?.strain) ?? 0;
  const strainMin = to5(45 * clamp((strain - 35) / 50, 0, 1));

  // Today's naps come off only through napMin below, so they are not counted twice.
  let debt = 0;
  for (let d = addDays(today, -6); d <= today; d = addDays(d, 1)) {
    const row = byDate.get(d);
    const asleep = num(row?.sleep_asleep_min);
    if (asleep === null) continue;
    const naps = d < today ? (num(row?.nap_min) ?? 0) : 0;
    debt += Math.max(0, sleepNeedMin - asleep - naps);
  }
  const debtMin = Math.min(60, to5(debt / 4));
  const napMin = Math.min(60, to5(num(todayRow?.nap_min) ?? 0));
  const needMin = sleepNeedMin + strainMin + debtMin - napMin;

  const efficiencies: number[] = [];
  for (let d = addDays(today, -13); d <= today; d = addDays(d, 1)) {
    const e = num(byDate.get(d)?.sleep_efficiency);
    if (e !== null && e > 0) efficiencies.push(e);
  }
  const efficiency = clamp(efficiencies.length >= MIN_NIGHTS ? median(efficiencies)! : 0.9, 0.7, 1);
  const inBedMin = to5(needMin / efficiency);

  const tomorrow = addDays(today, 1);
  const set = wakeTimes?.[weekdayIndex(tomorrow)] ?? null;
  const usual = usualWake(days, today, weekdayIndex(tomorrow) >= 5);
  let wakeMin: number | null = null;
  let wakeBasis: SleepPlan["wakeBasis"] = null;
  if (set !== null) {
    wakeMin = set;
    wakeBasis = "set";
  } else if (usual) {
    wakeMin = usual.wakeMin;
    wakeBasis = usual.basis;
  }
  return {
    needMin,
    baseMin: sleepNeedMin,
    strainMin,
    debtMin,
    napMin,
    efficiency,
    inBedMin,
    wakeMin: wakeMin === null ? null : Math.round(wakeMin),
    bedtimeMin: wakeMin === null ? null : to5(wakeMin - inBedMin),
    wakeBasis,
  };
}

/**
 * The usual wake time from the band for a weekday or a weekend morning: the median of that kind
 * of the last 28 mornings up to `today`, else of all of them; null under 3 mornings.
 */
export function usualWake(days: DayRow[], today: Ymd, weekendMorning: boolean): { wakeMin: number; basis: "weekday" | "weekend" | "all" } | null {
  const byDate = new Map(days.map((d) => [d.date, d]));
  const weekend = (d: Ymd) => weekdayIndex(d) >= 5;
  const sameKind: number[] = [], all: number[] = [];
  for (let d = addDays(today, -27); d <= today; d = addDays(d, 1)) {
    const wake = num(byDate.get(d)?.sleep_waketime_min);
    if (wake === null) continue;
    all.push(wake);
    if (weekend(d) === weekendMorning) sameKind.push(wake);
  }
  if (sameKind.length >= MIN_NIGHTS) return { wakeMin: median(sameKind)!, basis: weekendMorning ? "weekend" : "weekday" };
  if (all.length >= MIN_NIGHTS) return { wakeMin: median(all)!, basis: "all" };
  return null;
}


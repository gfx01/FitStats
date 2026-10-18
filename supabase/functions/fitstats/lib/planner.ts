// Tonight's sleep need and bedtime: FitStats' own transparent rule, shared with
// the app (ios/FitStats/Core/SleepPlanner.swift, keep the two in step).
//
//   need     = your sleep need
//            + 0–45 min for today's strain (0 at strain 35 or less, 45 at 85 or more)
//            + a quarter of the last 7 nights' sleep debt (at most 60 min; naps on the
//              days before today count as sleep)
//            − today's naps (at most 60 min)
//   in bed   = need ÷ your typical sleep efficiency (median of the last 14 nights, else 90 %)
//   bedtime  = your usual wake time for tomorrow's kind of day (weekday or weekend,
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
  wakeBasis: "weekday" | "weekend" | "all" | null;
}

const MIN_NIGHTS = 3;

function num(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

const to5 = (v: number) => Math.round(v / 5) * 5;

export function sleepPlan(days: DayRow[], today: Ymd, sleepNeedMin: number): SleepPlan {
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

  const weekend = (d: Ymd) => weekdayIndex(d) >= 5;
  const tomorrowWeekend = weekend(addDays(today, 1));
  const sameKind: number[] = [], all: number[] = [];
  for (let d = addDays(today, -27); d <= today; d = addDays(d, 1)) {
    const wake = num(byDate.get(d)?.sleep_waketime_min);
    if (wake === null) continue;
    all.push(wake);
    if (weekend(d) === tomorrowWeekend) sameKind.push(wake);
  }
  let wakeMin: number | null = null;
  let wakeBasis: SleepPlan["wakeBasis"] = null;
  if (sameKind.length >= MIN_NIGHTS) {
    wakeMin = median(sameKind);
    wakeBasis = tomorrowWeekend ? "weekend" : "weekday";
  } else if (all.length >= MIN_NIGHTS) {
    wakeMin = median(all);
    wakeBasis = "all";
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

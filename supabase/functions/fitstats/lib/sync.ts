// Sync engine: pulls Google Health data into fs_* tables, then recomputes
// scores and the statistics cache. Runs from cron every 15 minutes and on
// demand from the app; a database lock prevents overlapping runs.

import * as db from "./db.ts";
import { GoogleApiError, HealthClient, refreshAccessToken } from "./google.ts";
import { computeRecovery, computeSleepScore, computeStrain, computeStress, type DayRow, strainTarget } from "./scores.ts";
import { buildStats } from "./stats.ts";
import {
  DAILY_TYPES,
  dailyPointsToPatches,
  type DayPatch,
  type ExerciseRow,
  exercisePointToRow,
  type IntradayDay,
  type Json,
  maxHeartRate,
  placeMinuteRollups,
  ROLLUP_TYPES,
  rollupPointsToPatches,
  type SampleRow,
  samplePointsToRows,
  SLEEP_DAY_COLUMNS,
  sleepDayPatch,
  sleepPointToRow,
  type SleepRow,
} from "./transform.ts";
import { addDays, dateRange, LocalClock, median, MINUTES_PER_DAY, type Ymd, ymdFromGoogleDate } from "./util.ts";

export interface Account {
  google_sub: string | null;
  google_email: string | null;
  refresh_token: string | null;
  access_token: string | null;
  access_token_expires_at: string | null;
  token_status: string;
  time_zone: string | null;
  profile: Json | null;
  google_settings: Json | null;
  meta_fetched_at: string | null;
}

export interface UserSettings {
  sex: string;
  max_hr_override: number | null;
  sleep_need_min: number;
  step_goal: number;
  backfill_days: number;
}

interface SyncState {
  backfill_oldest: Ymd | null;
  backfill_target: Ymd | null;
  backfill_done: boolean;
  backfill_empty_chunks: number;
  last_recent_sync_at: string | null;
}

interface TaskResult {
  name: string;
  ok: boolean;
  count?: number;
  error?: string;
}

interface RangeLog {
  range: string;
  ms: number;
  points: number;
  failed: TaskResult[];
}

export interface RunLog {
  reason: string;
  started: string;
  finished?: string;
  status: "ok" | "partial" | "skipped" | "token_expired" | "error" | "not_connected";
  calls: number;
  ranges: RangeLog[];
  message?: string;
}

export class TokenExpiredError extends Error {}

const BACKFILL_CHUNK_DAYS = 14;
const EMPTY_CHUNKS_TO_STOP = 8;
const RECENT_DAYS = 3;

function nowIso(): string {
  return new Date().toISOString();
}

export async function loadAccount(): Promise<Account | null> {
  return await db.selectOne<Account>("fs_account", "select=*&id=eq.1");
}

export async function loadSettings(): Promise<UserSettings> {
  const s = await db.selectOne<UserSettings>("fs_user_settings", "select=*&id=eq.1");
  return s ?? { sex: "unspecified", max_hr_override: null, sleep_need_min: 480, step_goal: 10000, backfill_days: 730 };
}

export function clockFor(account: Account | null): LocalClock {
  const tz = account?.time_zone ?? null;
  if (tz) return new LocalClock(tz);
  const off = account?.google_settings?.utcOffset;
  const seconds = typeof off === "string" ? Number(off.replace(/s$/, "")) : 0;
  return new LocalClock(null, Number.isFinite(seconds) ? seconds : 0);
}

async function accessToken(acc: Account, force = false): Promise<string> {
  const exp = acc.access_token_expires_at ? Date.parse(acc.access_token_expires_at) : 0;
  if (!force && acc.access_token && exp - Date.now() > 120_000) return acc.access_token;
  if (!acc.refresh_token) throw new TokenExpiredError("No refresh token stored; connect Google again.");
  try {
    const t = await refreshAccessToken(acc.refresh_token, db.env("GOOGLE_CLIENT_ID"), db.env("GOOGLE_CLIENT_SECRET"));
    const expiresAt = new Date(Date.now() + (t.expires_in ?? 3600) * 1000).toISOString();
    const patch: Record<string, unknown> = {
      access_token: t.access_token,
      access_token_expires_at: expiresAt,
      token_status: "ok",
      token_error: null,
      updated_at: nowIso(),
    };
    if (t.refresh_token) patch.refresh_token = t.refresh_token;
    await db.update("fs_account", "id=eq.1", patch);
    acc.access_token = t.access_token;
    acc.access_token_expires_at = expiresAt;
    return t.access_token;
  } catch (e) {
    if (e instanceof GoogleApiError && (e.reason === "invalid_grant" || e.status === 401)) {
      await db.update("fs_account", "id=eq.1", {
        token_status: "expired",
        token_error: e.message,
        access_token: null,
        updated_at: nowIso(),
      });
      throw new TokenExpiredError(e.message);
    }
    throw e;
  }
}

async function refreshMeta(client: HealthClient, acc: Account): Promise<void> {
  const fresh = acc.meta_fetched_at && Date.now() - Date.parse(acc.meta_fetched_at) < 6 * 3_600_000;
  if (fresh) return;
  const patch: Record<string, unknown> = { meta_fetched_at: nowIso(), updated_at: nowIso() };
  try {
    const p = await client.getProfile();
    patch.profile = p;
    acc.profile = p;
  } catch (e) {
    console.warn("profile", String(e));
  }
  try {
    const s = await client.getSettings();
    patch.google_settings = s;
    acc.google_settings = s;
    if (typeof s.timeZone === "string" && s.timeZone) {
      patch.time_zone = s.timeZone;
      acc.time_zone = s.timeZone;
    }
  } catch (e) {
    console.warn("settings", String(e));
  }
  try {
    const d = await client.listDevices();
    patch.devices = d.pairedDevices ?? [];
  } catch (e) {
    console.warn("devices", String(e));
  }
  await db.update("fs_account", "id=eq.1", patch);
}

async function pool<T>(items: T[], size: number, fn: (item: T) => Promise<void>): Promise<void> {
  let next = 0;
  const workers = Array.from({ length: Math.min(size, items.length) }, async () => {
    while (next < items.length) {
      const item = items[next++];
      await fn(item);
    }
  });
  await Promise.all(workers);
}

interface Task {
  name: string;
  columns: string[];
  run: () => Promise<number>;
}

const STRAIN_COLUMNS = ["trimp", "strain", "intraday_details"];
const STRESS_COLUMNS = ["stress", "stress_minutes"];

/** Minute mask (true = skip for stress) for sleep and exercise (+30 min cool-down) on one local day. */
function exclusionMask(date: Ymd, sleeps: SleepRow[], exercises: ExerciseRow[], clock: LocalClock): boolean[] {
  const mask = new Array(MINUTES_PER_DAY).fill(false);
  const dayStart = clock.midnightMs(date);
  const dayEnd = clock.midnightMs(addDays(date, 1));
  const mark = (a: number, b: number) => {
    const s = Math.max(a, dayStart), e = Math.min(b, dayEnd);
    if (e <= s) return;
    const from = Math.floor((s - dayStart) / 60000);
    const to = Math.min(MINUTES_PER_DAY, Math.ceil((e - dayStart) / 60000));
    for (let m = from; m < to; m++) mask[m] = true;
  };
  for (const s of sleeps) mark(Date.parse(s.start_time), Date.parse(s.end_time));
  for (const x of exercises) mark(Date.parse(x.start_time), Date.parse(x.end_time) + 30 * 60000);
  return mask;
}

/** Fetches every data type for [start, end) and writes it. Returns the number of data points seen. */
async function syncRange(
  client: HealthClient,
  start: Ymd,
  end: Ymd,
  clock: LocalClock,
  acc: Account,
  settings: UserSettings,
  log: RunLog,
): Promise<number> {
  const t0 = Date.now();
  const patches = new Map<string, Map<Ymd, DayPatch>>();
  const results: TaskResult[] = [];
  const minute = new Map<Ymd, IntradayDay>();
  const samples: SampleRow[] = [];
  let sleeps: SleepRow[] = [];
  let exercises: ExerciseRow[] = [];
  const startMs = clock.midnightMs(start);
  const endMs = clock.midnightMs(end);

  const tasks: Task[] = [];
  for (const [type, spec] of Object.entries(DAILY_TYPES)) {
    tasks.push({
      name: type,
      columns: spec.columns,
      run: async () => {
        const pts = await client.listDaily(type, start, end, type === "daily-heart-rate-zones");
        patches.set(type, dailyPointsToPatches(type, pts));
        return pts.length;
      },
    });
  }
  for (const [type, spec] of Object.entries(ROLLUP_TYPES)) {
    tasks.push({
      name: `rollup:${type}`,
      columns: spec.columns,
      run: async () => {
        const pts = await client.dailyRollup(type, start, end);
        const m = rollupPointsToPatches(type, pts);
        patches.set(`rollup:${type}`, m);
        return m.size;
      },
    });
  }
  tasks.push({
    name: "sleep",
    columns: SLEEP_DAY_COLUMNS,
    run: async () => {
      // One extra day so the evening part of the next night is known for stress exclusion.
      const pts = await client.listSleep(start, addDays(end, 1));
      sleeps = pts.map((p) => sleepPointToRow(p, clock)).filter((x): x is SleepRow => x !== null);
      return sleeps.length;
    },
  });
  tasks.push({
    name: "exercise",
    columns: [],
    run: async () => {
      const pts = await client.listExercise(start, end);
      exercises = pts.map((p) => exercisePointToRow(p, clock)).filter((x): x is ExerciseRow => x !== null);
      return exercises.length;
    },
  });
  tasks.push({
    name: "intraday:hr",
    columns: [],
    run: async () => {
      const pts = await client.rollup("heart-rate", startMs, endMs, "60s");
      placeMinuteRollups(pts, "hr", clock, minute);
      return pts.length;
    },
  });
  tasks.push({
    name: "intraday:steps",
    columns: [],
    run: async () => {
      const pts = await client.rollup("steps", startMs, endMs, "60s");
      placeMinuteRollups(pts, "steps", clock, minute);
      return pts.length;
    },
  });
  for (const type of ["heart-rate-variability", "oxygen-saturation", "respiratory-rate-sleep-summary"]) {
    tasks.push({
      name: `samples:${type}`,
      columns: [],
      run: async () => {
        const pts = await client.listSamples(type, startMs, endMs);
        const rows = samplePointsToRows(type, pts, clock);
        samples.push(...rows);
        return rows.length;
      },
    });
  }

  const ok = new Set<string>();
  await pool(tasks, 4, async (task) => {
    try {
      const count = await task.run();
      ok.add(task.name);
      results.push({ name: task.name, ok: true, count });
    } catch (e) {
      if (e instanceof TokenExpiredError) throw e;
      results.push({ name: task.name, ok: false, error: String((e as Error).message ?? e).slice(0, 300) });
    }
  });

  const inRange = (d: Ymd) => d >= start && d < end;
  let points = 0;

  // Each write is isolated so one unexpected record cannot abort the whole range.
  const writeFailures: TaskResult[] = [];
  const write = async (name: string, fn: () => Promise<void>) => {
    try {
      await fn();
    } catch (e) {
      writeFailures.push({ name: `write:${name}`, ok: false, error: String((e as Error).message ?? e).slice(0, 300) });
    }
  };

  // Sessions and samples.
  if (ok.has("sleep")) {
    await write("fs_sleep", async () => {
      const rows = sleeps.map((s) => ({ ...s, updated_at: nowIso() }));
      if (rows.length) await db.upsert("fs_sleep", rows, "id");
      const keep = sleeps.filter((s) => inRange(s.date)).map((s) => s.id);
      const notIn = keep.length ? `&id=not.in.${db.inList(keep)}` : "";
      await db.remove("fs_sleep", `date=gte.${start}&date=lt.${end}${notIn}`);
    });
    points += sleeps.length;
  }
  if (ok.has("exercise")) {
    await write("fs_exercise", async () => {
      const rows = exercises.map((x) => ({ ...x, updated_at: nowIso() }));
      if (rows.length) await db.upsert("fs_exercise", rows, "id");
      const keep = exercises.map((x) => x.id);
      const notIn = keep.length ? `&id=not.in.${db.inList(keep)}` : "";
      await db.remove("fs_exercise", `date=gte.${start}&date=lt.${end}${notIn}`);
    });
    points += exercises.length;
  }
  if (samples.length) {
    await write("fs_samples", async () => {
      const unique = new Map(samples.map((s) => [`${s.metric}|${s.t}`, s]));
      await db.upsert("fs_samples", [...unique.values()].map((s) => ({ ...s })), "metric,t", 1000);
    });
    points += samples.length;
  }

  // Minute data.
  const hrOk = ok.has("intraday:hr"), stepsOk = ok.has("intraday:steps");
  if (hrOk || stepsOk) {
    const rows: Record<string, unknown>[] = [];
    for (const [date, d] of minute) {
      if (!inRange(date)) continue;
      const row: Record<string, unknown> = { date, updated_at: nowIso() };
      if (hrOk) row.hr = d.hr;
      if (stepsOk) row.steps = d.steps;
      rows.push(row);
    }
    if (rows.length) await write("fs_intraday", () => db.upsert("fs_intraday", rows, "date", 50));
  }

  // Day rows: columns of failed tasks are left untouched in the database.
  const columns = new Set<string>();
  for (const task of tasks) if (ok.has(task.name)) for (const c of task.columns) columns.add(c);
  if (hrOk) for (const c of STRAIN_COLUMNS) columns.add(c);
  if (hrOk && stepsOk) for (const c of STRESS_COLUMNS) columns.add(c);

  const rangeRhr = median(
    [...(patches.get("daily-resting-heart-rate")?.values() ?? [])]
      .map((p) => p.rhr)
      .filter((v): v is number => typeof v === "number"),
  ) ?? 60;
  const age = typeof acc.profile?.age === "number" ? acc.profile.age : null;
  const maxHr = maxHeartRate(age, settings.max_hr_override);

  const dayRows: Record<string, unknown>[] = [];
  for (const date of dateRange(start, end)) {
    const row: Record<string, unknown> = { date };
    for (const c of columns) row[c] = null;
    for (const task of tasks) {
      if (!ok.has(task.name) || task.columns.length === 0) continue;
      const p = patches.get(task.name)?.get(date);
      if (p) Object.assign(row, p);
    }
    if (ok.has("sleep")) Object.assign(row, sleepDayPatch(date, sleeps, clock));

    const m = minute.get(date);
    if (hrOk && m) {
      const rhr = typeof row.rhr === "number" ? row.rhr : rangeRhr;
      const strain = computeStrain(m.hr, rhr, maxHr, settings.sex);
      const details: Record<string, unknown> = { maxHr, rhrUsed: rhr };
      if (strain) {
        row.trimp = strain.trimp;
        row.strain = strain.strain;
        details.hrMinutes = strain.hrMinutes;
        details.hrrZoneMinutes = strain.zoneMinutes;
      }
      if (stepsOk) {
        const mask = exclusionMask(date, sleeps, exercises.filter((x) => x.date === date), clock);
        const stress = computeStress(m.hr, m.steps, rhr, maxHr, mask);
        row.stress = stress.stress;
        row.stress_minutes = stress.minutes;
        details.stressHourly = stress.hourly;
      }
      row.intraday_details = details;
    }

    const hasData = Object.entries(row).some(([k, v]) => k !== "date" && k !== "intraday_details" && v !== null);
    if (hasData) {
      row.updated_at = nowIso();
      dayRows.push(row);
    }
  }
  if (dayRows.length) await write("fs_days", () => db.upsert("fs_days", dayRows, "date", 100));
  points += dayRows.length;

  log.ranges.push({
    range: `${start}..${end}`,
    ms: Date.now() - t0,
    points,
    failed: [...results.filter((r) => !r.ok), ...writeFailures],
  });
  return points;
}

/** Recomputes sleep score + recovery for dates >= from (baselines need the previous 30 days). */
export async function recomputeScores(from: Ymd, to: Ymd, settings: UserSettings): Promise<number> {
  const cols = [
    "date", "hrv_rmssd", "rhr", "resp_rate", "skin_temp_c", "skin_temp_baseline_c", "skin_temp_stddev_c",
    "sleep_asleep_min", "sleep_in_bed_min", "sleep_deep_min", "sleep_rem_min", "sleep_has_stages",
    "sleep_bedtime_min", "sleep_waketime_min",
  ].join(",");
  const rows = await db.select<DayRow>("fs_days", `select=${cols}&date=gte.${addDays(from, -31)}&date=lte.${to}&order=date.asc`);
  const out: Record<string, unknown>[] = [];
  for (let i = 0; i < rows.length; i++) {
    const day = rows[i];
    if (day.date < from) continue;
    const prev30: DayRow[] = [];
    const prev14: DayRow[] = [];
    const min30 = addDays(day.date, -30), min14 = addDays(day.date, -14);
    for (let j = i - 1; j >= 0 && rows[j].date >= min30; j--) {
      prev30.push(rows[j]);
      if (rows[j].date >= min14) prev14.push(rows[j]);
    }
    const sleep = computeSleepScore(day, prev14, settings.sleep_need_min);
    const recovery = computeRecovery(day, prev30, sleep.score);
    out.push({
      date: day.date,
      sleep_score: sleep.score,
      recovery: recovery.score,
      score_details: { sleep, recovery, strainTarget: strainTarget(recovery.score) },
    });
  }
  if (out.length) await db.upsert("fs_days", out, "date", 200);
  return out.length;
}

/** Recomputes strain and stress from stored minute data (after sex / max HR changes). */
export async function recomputeIntraday(from: Ymd, to: Ymd, settings: UserSettings, acc: Account): Promise<number> {
  const clock = clockFor(acc);
  const age = typeof acc.profile?.age === "number" ? acc.profile.age : null;
  const maxHr = maxHeartRate(age, settings.max_hr_override);
  const info = await db.select<DayRow>("fs_days", `select=date,rhr&date=gte.${from}&date=lte.${to}`);
  const rhrByDate = new Map(info.map((d) => [d.date, typeof d.rhr === "number" ? d.rhr : null]));
  const fallbackRhr = median([...rhrByDate.values()].filter((v): v is number => v !== null)) ?? 60;
  const sleeps = await db.select<SleepRow>("fs_sleep", `select=date,start_time,end_time&date=gte.${from}&date=lte.${addDays(to, 1)}`);
  const exercises = await db.select<ExerciseRow>("fs_exercise", `select=date,start_time,end_time&date=gte.${from}&date=lte.${to}`);
  let count = 0;
  for (let s = from; s <= to; s = addDays(s, 30)) {
    const rows = await db.select<{ date: Ymd; hr: (number | null)[] | null; steps: (number | null)[] | null }>(
      "fs_intraday",
      `select=date,hr,steps&date=gte.${s}&date=lt.${addDays(s, 30)}&order=date.asc`,
    );
    const out: Record<string, unknown>[] = [];
    for (const r of rows) {
      if (r.date > to || !r.hr) continue;
      const rhr = rhrByDate.get(r.date) ?? fallbackRhr;
      const strain = computeStrain(r.hr, rhr, maxHr, settings.sex);
      const details: Record<string, unknown> = {
        maxHr,
        rhrUsed: rhr,
        hrMinutes: strain?.hrMinutes ?? null,
        hrrZoneMinutes: strain?.zoneMinutes ?? null,
      };
      const row: Record<string, unknown> = {
        date: r.date,
        trimp: strain?.trimp ?? null,
        strain: strain?.strain ?? null,
        stress: null,
        stress_minutes: null,
        intraday_details: details,
      };
      if (r.steps) {
        const nearby = sleeps.filter((x) => x.date === r.date || x.date === addDays(r.date, 1));
        const mask = exclusionMask(r.date, nearby, exercises.filter((x) => x.date === r.date), clock);
        const st = computeStress(r.hr, r.steps, rhr, maxHr, mask);
        row.stress = st.stress;
        row.stress_minutes = st.minutes;
        details.stressHourly = st.hourly;
      }
      out.push(row);
    }
    if (out.length) await db.upsert("fs_days", out, "date", 100);
    count += out.length;
  }
  return count;
}

export async function rebuildStats(today: Ymd, settings: UserSettings): Promise<void> {
  const days = await db.select<DayRow>("fs_days", "select=*&order=date.asc");
  const stats = buildStats(days, today, settings);
  await db.upsert("fs_cache", [{ key: "stats", value: stats, updated_at: nowIso() }], "key");
}

/** One sync run within `budgetMs`. Safe to call concurrently (second caller is skipped). */
export async function runSync(reason: string, force: boolean, budgetMs = 95_000): Promise<RunLog> {
  const started = Date.now();
  const log: RunLog = { reason, started: new Date(started).toISOString(), status: "ok", calls: 0, ranges: [] };
  const locked = await db.rpc<boolean>("fs_try_lock", { p_seconds: Math.ceil(budgetMs / 1000) + 60 });
  if (!locked) return { ...log, status: "skipped", message: "another sync is running" };

  let client: HealthClient | null = null;
  try {
    const acc = await loadAccount();
    if (!acc || !acc.refresh_token || acc.token_status === "disconnected") {
      log.status = "not_connected";
      return log;
    }
    const settings = await loadSettings();
    const token = await accessToken(acc);
    client = new HealthClient(token, () => accessToken(acc, true), started + budgetMs);
    await refreshMeta(client, acc);
    const clock = clockFor(acc);
    const today = clock.today();

    const state = (await db.selectOne<SyncState>("fs_sync_state", "select=*&id=eq.1"))!;
    if (!state.backfill_target) {
      let target = addDays(today, -settings.backfill_days);
      const member = ymdFromGoogleDate(acc.profile?.membershipStartDate);
      if (member && member > target) target = member;
      state.backfill_target = target;
    }
    if (!state.backfill_oldest) state.backfill_oldest = addDays(today, -RECENT_DAYS);

    let earliestTouched: Ymd | null = null;
    const recentStale = !state.last_recent_sync_at || Date.now() - Date.parse(state.last_recent_sync_at) > 12 * 60_000;
    if (force || recentStale) {
      const from = addDays(today, -RECENT_DAYS);
      await syncRange(client, from, addDays(today, 1), clock, acc, settings, log);
      state.last_recent_sync_at = nowIso();
      earliestTouched = from;
    }

    while (!state.backfill_done && Date.now() - started < budgetMs - 35_000) {
      const end = state.backfill_oldest!;
      let start = addDays(end, -BACKFILL_CHUNK_DAYS);
      if (start < state.backfill_target!) start = state.backfill_target!;
      if (start >= end) {
        state.backfill_done = true;
        break;
      }
      const points = await syncRange(client, start, end, clock, acc, settings, log);
      state.backfill_oldest = start;
      state.backfill_empty_chunks = points === 0 ? (state.backfill_empty_chunks ?? 0) + 1 : 0;
      if (start <= state.backfill_target! || state.backfill_empty_chunks >= EMPTY_CHUNKS_TO_STOP) {
        state.backfill_done = true;
      }
      earliestTouched = start;
      await db.update("fs_sync_state", "id=eq.1", {
        backfill_oldest: state.backfill_oldest,
        backfill_target: state.backfill_target,
        backfill_done: state.backfill_done,
        backfill_empty_chunks: state.backfill_empty_chunks,
        updated_at: nowIso(),
      });
    }

    if (earliestTouched) {
      await recomputeScores(earliestTouched, today, settings);
      await rebuildStats(today, settings);
    }
    if (log.ranges.some((r) => r.failed.length > 0)) log.status = "partial";

    await db.update("fs_sync_state", "id=eq.1", {
      backfill_oldest: state.backfill_oldest,
      backfill_target: state.backfill_target,
      backfill_done: state.backfill_done,
      backfill_empty_chunks: state.backfill_empty_chunks ?? 0,
      last_recent_sync_at: state.last_recent_sync_at,
      updated_at: nowIso(),
    });
    return log;
  } catch (e) {
    log.status = e instanceof TokenExpiredError ? "token_expired" : "error";
    log.message = String((e as Error).message ?? e).slice(0, 500);
    return log;
  } finally {
    log.calls = client?.calls ?? 0;
    log.finished = nowIso();
    try {
      await db.update("fs_sync_state", "id=eq.1", {
        last_run_finished_at: log.finished,
        last_run_status: log.status,
        last_run_log: log,
        lock_until: null,
        updated_at: nowIso(),
      });
    } catch (e) {
      console.error("failed to save run log", String(e));
      await db.rpc("fs_unlock").catch(() => {});
    }
  }
}

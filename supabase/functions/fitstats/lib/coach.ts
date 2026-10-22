// FitStats coach: answers questions about the user's data with Claude (Anthropic
// Messages API). The API key stays in this function. The app sends a question and
// receives the reply as server-sent events. Claude gets a compact data summary in
// the system prompt and tools to look up anything else in the database.

import * as db from "./db.ts";
import { exerciseMuscles, LIBRARY, type MuscleId, MUSCLES } from "./exercises.ts";
import { type JournalEntry, journalEntries, tagLabel } from "./journal.ts";
import { sleepPlan, usualWake, wakeTimesFrom, type WakeTimes } from "./planner.ts";
import type { DayRow } from "./scores.ts";
import { fmtValue, lowerFirst, METRIC_BY_KEY, METRICS, type MetricDef } from "./stats.ts";
import { type Account, clockFor, loadAccount, loadSettings, maxHrInUse, type UserSettings } from "./sync.ts";
import {
  EXERCISE_KINDS,
  exerciseProgress,
  loadLogs,
  loadRoutines,
  logText,
  muscleSetsText,
  routineText,
  saveRoutine,
  TrainingInputError,
} from "./training.ts";
import { awakeAfterOnset, fallAsleepMinutes, type Json, mainSleepOf } from "./transform.ts";
import { addDays, daysBetween, round, type Ymd } from "./util.ts";

type Row = Record<string, unknown>;

export const COACH_MODELS = [
  { id: "claude-opus-5-5", label: "Claude Opus 5.5", note: "Most capable, about twice Sonnet's price" },
  { id: "claude-sonnet-5-5", label: "Claude Sonnet 5.5", note: "Fast and smart (default)" },
  { id: "claude-haiku-5-5", label: "Claude Haiku 5.5", note: "Fastest and cheapest" },
];
export const DEFAULT_COACH_MODEL = "claude-sonnet-5-5";

/** USD per million tokens from platform.claude.com pricing (October 2026): input, 5-minute cache write, cache read, output. */
const PRICES: Record<string, [number, number, number, number]> = {
  "claude-opus-5-5": [4, 5, 0.2, 20],
  "claude-sonnet-5-5": [2, 2.5, 0.1, 10],
  "claude-haiku-5-5": [0.1, 0.125, 0.01, 0.5],
};

export const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
export const DAILY_REQUEST_LIMIT = 100;
const MAX_ROUNDS = 6;
const MAX_TOKENS = 8000; // thinking (always on for these models) + the reply
const HISTORY_MESSAGES = 20;
/** An answer that takes longer is given up (Edge Functions stop at 150 s on the free plan). */
const ANSWER_TIMEOUT_MS = 140_000;
/** Screenshots per message, and their size as base64 (the app sends JPEGs of about 0.3–0.6 MB). */
const MAX_IMAGES = 3;
const MAX_IMAGE_CHARS = 4_000_000;
const MAX_THUMB_CHARS = 120_000;
const IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;

/**
 * The three coaches the app lets them choose from. Only the voice changes: the same
 * instructions, data and tools for all three. Not used for the daily briefing.
 */
export const COACH_PERSONAS: Record<string, { name: string; prompt: string }> = {
  nova: {
    name: "Nova",
    prompt: "You are Nova, the analytical coach: precise, curious and calm. Explain the why behind each answer with their numbers and baselines, " +
      "say how sure you are and what data is missing, and prefer a few short bullets. Never preachy.",
  },
  ace: {
    name: "Ace",
    prompt: "You are Ace, the tough-love performance coach: direct, energetic and demanding, but always on their side. Lead with the verdict in one short " +
      "sentence, then exactly what to do. Push them to train hard when recovery allows, and name missed sessions or slipping habits plainly, never with insults. " +
      "Short sentences; no hedging beyond what the data needs.",
  },
  kai: {
    name: "Kai",
    prompt: "You are Kai, the calm, recovery-first coach: warm, patient and reassuring. Put sleep, stress and recovery first, offer gentler options on " +
      "low days, and help them feel in control without false comfort.",
  },
};
export const DEFAULT_PERSONA = "nova";

function personaPrompt(id: string): string {
  const p = COACH_PERSONAS[id];
  return `Your personality\n${p.prompt} Your personality changes only your voice and emphasis: the facts, the rules above and what their data says ` +
    `stay the same. If they ask who you are: ${p.name}, one of the three FitStats coaches (Nova, Ace and Kai), who all read the same data.`;
}

export interface CoachImage {
  media_type: string;
  data: string;
  /** A small preview the app keeps with the message (the full image isn't stored). */
  thumb: string | null;
}

/** The screenshots of a chat request, or a message saying what is wrong with them. */
export function parseImages(v: unknown): CoachImage[] | string {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v)) return "images must be a list.";
  if (v.length > MAX_IMAGES) return `At most ${MAX_IMAGES} screenshots per message.`;
  const out: CoachImage[] = [];
  for (const raw of v) {
    const img = (raw ?? {}) as Row;
    const type = String(img.media_type ?? "");
    const data = typeof img.data === "string" ? img.data : "";
    const thumb = typeof img.thumb === "string" && img.thumb.length <= MAX_THUMB_CHARS && BASE64.test(img.thumb) ? img.thumb : null;
    if (!IMAGE_TYPES.has(type)) return "Screenshots must be JPEG, PNG, WebP or GIF.";
    if (!data || data.length > MAX_IMAGE_CHARS || !BASE64.test(data)) return "A screenshot is empty or too large.";
    out.push({ media_type: type, data, thumb });
  }
  return out;
}

/** A stored message as history for the next request: earlier screenshots are named, not resent. */
function historyContent(r: Row): string {
  const n = Array.isArray(r.attachments) ? r.attachments.length : 0;
  if (!n) return String(r.content);
  const note = `[They attached ${n === 1 ? "a screenshot" : `${n} screenshots`} to this message. You saw ${n === 1 ? "it" : "them"} then; ` +
    `${n === 1 ? "it isn't" : "they aren't"} shown again.]`;
  return r.content ? `${r.content}\n\n${note}` : note;
}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const YMD = /^\d{4}-\d{2}-\d{2}$/;

export function coachModel(settings: UserSettings): string {
  const m = settings.coach_model;
  return m && PRICES[m] ? m : DEFAULT_COACH_MODEL;
}

export function isCoachModel(id: unknown): id is string {
  return typeof id === "string" && id in PRICES;
}

export class CoachError extends Error {
  code: string;
  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

// ------------------------------------------------------------------ formatting

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function shortDate(ymd: unknown): string {
  if (typeof ymd !== "string" || !YMD.test(ymd)) return String(ymd ?? "");
  const [, m, d] = ymd.split("-").map(Number);
  return `${MONTHS[m - 1]} ${d}`;
}

function weekday(ymd: Ymd): string {
  return WEEKDAYS[new Date(`${ymd}T00:00:00Z`).getUTCDay()];
}

/** The wake-up times in the settings row; a malformed value counts as none. */
function savedWakeTimes(v: unknown): WakeTimes | null {
  try {
    return wakeTimesFrom(v);
  } catch {
    return null;
  }
}

/** Their wake-up times by day of the week, set by hand or not, with the band's usual times. */
export function wakeTimesText(wakeTimes: WakeTimes | null, days: DayRow[], today: Ymd): string {
  const usual = (weekend: boolean) => {
    const u = usualWake(days, today, weekend);
    return u ? clockText(u.wakeMin) : "not known yet";
  };
  const fromBand = `From the band, they usually wake at ${usual(false)} on weekdays and ${usual(true)} at weekends (median of the last 28 mornings).`;
  if (!wakeTimes) return `Wake-up times: none set by hand (Settings → Wake-up times), so the sleep plan uses the band's. ${fromBand}`;
  const names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  const list = wakeTimes.map((t, i) => `${names[i]} ${t === null ? "none (no fixed time: a morning they can sleep in)" : clockText(t)}`).join(", ");
  return `Wake-up times they set by hand (the morning of each day; Settings → Wake-up times): ${list}. ${fromBand}`;
}

function dur(min: number): string {
  const total = Math.round(Math.abs(min));
  const h = Math.floor(total / 60), m = total % 60;
  return h ? `${h}h ${m}m` : `${m}m`;
}

/** Minutes from local midnight (negative = the evening before) → "23:31". */
function clockText(min: number): string {
  let m = Math.round(min) % 1440;
  if (m < 0) m += 1440;
  return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
}

function localTime(iso: unknown, tz: string | null): string {
  if (typeof iso !== "string") return "";
  try {
    return new Intl.DateTimeFormat("en-GB", { timeZone: tz ?? "UTC", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
      .format(new Date(iso));
  } catch {
    return iso.slice(11, 16);
  }
}

/** Metrics that are deviations around zero, shown with a sign and compared in absolute terms. */
const DEVIATIONS = new Set(["skin_temp_dev"]);

function fmt(def: MetricDef, v: number): string {
  if (def.format === "clock") return clockText(v);
  if (DEVIATIONS.has(def.key)) return `${v >= 0 ? "+" : "−"}${fmtValue(def, Math.abs(v))}`;
  return fmtValue(def, v);
}

/** Change between two period means: minutes for clock times, absolute for deviations, else percent. */
function changeText(def: MetricDef, now: number, before: number, pct: number | null): string {
  if (def.format === "clock") {
    const d = Math.round(now - before);
    return d === 0 ? "same" : `${d > 0 ? "+" : "−"}${Math.abs(d)} min`;
  }
  if (DEVIATIONS.has(def.key)) {
    const d = round(now - before, def.decimals)!;
    return d === 0 ? "same" : `${d > 0 ? "+" : "−"}${fmtValue(def, Math.abs(d))}`;
  }
  if (pct === null || Math.round(Math.abs(pct)) === 0) return "about the same";
  return `${pct > 0 ? "+" : "−"}${Math.abs(pct).toFixed(0)}%`;
}

function slopeText(def: MetricDef, perWeek: number): string {
  const sign = perWeek >= 0 ? "+" : "−";
  if (def.format === "clock" || def.format === "duration") {
    const m = Math.round(Math.abs(perWeek));
    return m === 0 ? "flat" : `${sign}${m} min per week`;
  }
  const v = round(Math.abs(perWeek), def.decimals)!;
  return v === 0 ? "flat" : `${sign}${fmtValue(def, v)} per week`;
}

function dayCount(n: unknown): string {
  return Number(n) === 1 ? "1 day" : `${n} days`;
}

function num(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

function list(items: string[]): string {
  if (items.length <= 1) return items.join("");
  return `${items.slice(0, -1).join(", ")} and ${items[items.length - 1]}`;
}

// --------------------------------------------------------------------- context

interface Ctx {
  acc: Account | null;
  settings: UserSettings;
  today: Ymd;
  tz: string | null;
}

/** Google's workout steps, or the minute steps when Google's are missing or implausibly few (over 1 m per step). */
function workoutSteps(x: Row): { steps: number | null; from_minute_steps: boolean } {
  const steps = num(x.steps), minute = num(x.steps_minute), dist = num(x.distance_m);
  const useMinute = minute !== null && (steps === null || steps === 0 || (dist !== null && dist / steps > 1 && minute > steps));
  return { steps: useMinute ? minute : steps, from_minute_steps: useMinute };
}

const ORIGIN: Record<string, string> = {
  PASSIVELY_MEASURED: "auto-detected",
  ACTIVELY_MEASURED: "tracked",
  MANUAL: "logged manually",
  DERIVED: "derived",
};

function workoutSummary(x: Row, tz: string | null): Row {
  const seconds = num(x.active_duration_s) ?? num(x.duration_s) ?? 0;
  const window = Math.ceil((Date.parse(String(x.end_time)) - Math.floor(Date.parse(String(x.start_time)) / 60000) * 60000) / 60000);
  const hrMinutes = num(x.hr_minutes);
  return {
    date: x.date,
    start: localTime(x.start_time, tz),
    type: x.exercise_type ?? null,
    name: x.name ?? null,
    minutes: Math.round(seconds / 60),
    avg_hr: x.avg_hr ?? null,
    calories: num(x.calories) === null ? null : Math.round(x.calories as number),
    distance_km: num(x.distance_m) === null ? null : round((x.distance_m as number) / 1000, 2),
    active_zone_minutes: x.azm ?? null,
    ...workoutSteps(x),
    peak_minute_hr: x.hr_max ?? null,
    strain: x.strain ?? null,
    // How far heart rate fell 1 and 2 minutes after the end; null when the workout didn't qualify.
    hrr_1min: x.hrr_1min ?? null,
    hrr_2min: x.hrr_2min ?? null,
    // Strain and zones only cover the minutes with heart rate.
    hr_coverage: hrMinutes === null || !(window > 0) ? null : `${hrMinutes} of ${window} min`,
    origin: ORIGIN[String(x.recording_method)] ?? null,
  };
}

function journalText(entry: JournalEntry): string {
  const tags = entry.tags.length ? entry.tags.map(tagLabel).join(", ") : "nothing to note";
  return `journal: ${tags}${entry.note ? `; note "${entry.note}"` : ""}`;
}

const DAY_TOTALS = new Set(["strain", "stress", "steps", "azm_total"]);

function dayLine(row: Row, workouts: Row[], isToday: boolean, entry?: JournalEntry): string {
  const d = row as DayRow;
  const parts: string[] = [];
  const add = (key: string, label: string) => {
    const def = METRIC_BY_KEY.get(key)!;
    const v = def.get(d);
    if (v === null) return;
    parts.push(`${label} ${fmt(def, v)}${isToday && DAY_TOTALS.has(key) ? " so far" : ""}`);
  };
  add("recovery", "recovery");
  add("strain", "strain");
  const asleep = num(d.sleep_asleep_min);
  if (asleep !== null) {
    const bits = [dur(asleep)];
    const deep = num(d.sleep_deep_min), rem = num(d.sleep_rem_min);
    if (deep !== null && rem !== null) bits.push(`deep ${dur(deep)}, REM ${dur(rem)}`);
    const bed = num(d.sleep_bedtime_min), wake = num(d.sleep_waketime_min);
    if (bed !== null && wake !== null) bits.push(`${clockText(bed)}–${clockText(wake)}`);
    const score = num(d.sleep_score);
    parts.push(`sleep ${score === null ? "" : `${score} `}(${bits.join("; ")})`);
  }
  add("hrv_rmssd", "HRV");
  add("rhr", "RHR");
  add("stress", "stress");
  add("steps", "steps");
  add("azm_total", "AZM");
  if (workouts.length) {
    parts.push(`workouts: ${workouts.map((w) => `${w.name ?? w.type ?? "workout"} ${w.minutes} min${w.avg_hr ? ` @${w.avg_hr} bpm` : ""}${w.strain !== null ? `, strain ${w.strain}` : ""}`).join(", ")}`);
  }
  const wear = num(d.wear_min);
  if (d.low_wear === true && wear !== null) parts.push(`band worn only ${dur(wear)}, so day totals are incomplete and left out of averages`);
  if (entry) parts.push(journalText(entry));
  return `${row.date} ${weekday(String(row.date))}${isToday ? " (today)" : ""}: ${parts.length ? parts.join(" · ") : "no data"}`;
}

function componentsText(result: unknown): string | null {
  const r = result as Json | null | undefined;
  if (!r || !Array.isArray(r.components)) return null;
  const comps = (r.components as Json[]).map((c) => `${c.label} ${c.value}/100 (${c.detail})`);
  const score = num(r.score);
  return `${score === null ? `not available (${r.status})` : score}${comps.length ? `: ${comps.join("; ")}` : ""}`;
}

const SUMMARY_KEYS = [
  "recovery", "strain", "sleep_score", "stress", "hrv_rmssd", "rhr", "sleep_asleep_min", "sleep_deep_min",
  "sleep_rem_min", "sleep_bedtime_min", "sleep_waketime_min", "sleep_efficiency", "steps", "azm_total",
  "calories_active", "spo2_avg", "resp_rate", "skin_temp_dev", "vo2max", "weight_kg",
];

export async function buildContext(ctx: Ctx, stats: Json | null): Promise<string> {
  const from = addDays(ctx.today, -13);
  // 28 days for the sleep plan's usual wake time; 14 are listed.
  const [days, workouts, state, journal, routines, logs] = await Promise.all([
    db.select<Row>("fs_days", `select=*&date=gte.${addDays(ctx.today, -27)}&date=lte.${ctx.today}&order=date.asc`),
    db.select<Row>("fs_exercise", `select=*&date=gte.${from}&date=lte.${ctx.today}&order=start_time.asc`),
    db.selectOne<Row>("fs_sync_state", "select=*&id=eq.1"),
    journalEntries(from, ctx.today),
    loadRoutines(),
    loadLogs(addDays(ctx.today, -27), ctx.today),
  ]);
  const lines: string[] = [];
  let now = "";
  try {
    now = new Intl.DateTimeFormat("en-GB", { timeZone: ctx.tz ?? "UTC", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date());
  } catch {
    now = new Date().toISOString().slice(11, 16);
  }
  lines.push(`Now: ${weekday(ctx.today)} ${ctx.today}, ${now} (${ctx.tz ?? "time zone unknown"}).`);

  const age = num((ctx.acc?.profile as Json | null)?.age);
  // The same max heart rate the stored strain, stress and zones were computed with.
  const maxHr = await maxHrInUse(ctx.acc, ctx.settings, ctx.today, state);
  const maxHrNote = maxHr.source === "override"
    ? "set by the user"
    : maxHr.source === "observed"
    ? "the highest sustained heart rate they reached in the last year (a minute average backed by a neighbouring minute, so single spikes do not count), above the 208 − 0.7 × age estimate"
    : age === null
    ? "a default, since their age is unknown"
    : "estimated as 208 − 0.7 × age";
  lines.push(
    `Person: ${age === null ? "age unknown" : `age ${age}`}, sex ${ctx.settings.sex === "unspecified" ? "not set" : ctx.settings.sex}, ` +
      `sleep need ${dur(ctx.settings.sleep_need_min)}, step goal ${ctx.settings.step_goal.toLocaleString("en-US")}, ` +
      `max heart rate ${maxHr.value} bpm (${maxHrNote}).`,
  );
  const devices = Array.isArray((ctx.acc as unknown as Row | null)?.devices) ? ((ctx.acc as unknown as Row).devices as Json[]) : [];
  for (const dv of devices) {
    lines.push(`Device: ${dv.deviceVersion ?? "Fitbit"}${dv.batteryLevel !== undefined ? `, battery ${dv.batteryLevel}%` : ""}${dv.lastSyncTime ? `, last synced with the phone app ${String(dv.lastSyncTime).slice(0, 16).replace("T", " ")} UTC` : ""}.`);
  }
  if (state) {
    const imported = state.backfill_done ? `history imported back to ${state.backfill_oldest ?? "?"}` : `history import still running (back to ${state.backfill_oldest ?? "?"} so far)`;
    const last = typeof state.last_run_finished_at === "string" ? `${state.last_run_finished_at.slice(0, 16).replace("T", " ")} UTC` : "never";
    lines.push(`FitStats sync: last run ${last}, ${imported}.`);
  }

  lines.push("", "Last 14 days (strain, stress, steps and AZM are day totals; today's are partial; journal tags are what they did that day):");
  const byDate = new Map(days.map((d) => [String(d.date), d]));
  const entries = new Map(journal.map((e) => [e.date, e]));
  for (let d = from; d <= ctx.today; d = addDays(d, 1)) {
    const row = byDate.get(d) ?? { date: d };
    const ws = workouts.filter((w) => w.date === d).map((w) => workoutSummary(w, ctx.tz));
    lines.push(dayLine(row, ws, d === ctx.today, entries.get(d)));
  }

  const todayRow = byDate.get(ctx.today);
  const details = (todayRow?.score_details ?? null) as Json | null;
  if (details) {
    const rec = componentsText(details.recovery);
    if (rec) lines.push("", `How today's recovery was computed: ${rec}.`);
    const sl = componentsText(details.sleep);
    if (sl) lines.push(`How last night's sleep score was computed: ${sl}.`);
    if (Array.isArray(details.strainTarget)) lines.push(`Suggested strain for today: ${details.strainTarget[0]}–${details.strainTarget[1]}.`);
  }
  const wakeTimes = savedWakeTimes(ctx.settings.wake_times);
  const plan = sleepPlan(days as DayRow[], ctx.today, ctx.settings.sleep_need_min, wakeTimes);
  const extras = [
    plan.strainMin ? `+ ${plan.strainMin} min for today's strain` : "",
    plan.debtMin ? `+ ${plan.debtMin} min to repay debt` : "",
    plan.napMin ? `− ${plan.napMin} min of naps today` : "",
  ].filter(Boolean).join(" ");
  const wakeSource = plan.wakeBasis === "set"
    ? `the wake-up time they set for ${weekday(addDays(ctx.today, 1))}`
    : `their usual ${plan.wakeBasis === "all" ? "" : `${plan.wakeBasis} `}wake time`;
  const bedtime = plan.bedtimeMin !== null && plan.wakeMin !== null
    ? `in bed by ${clockText(plan.bedtimeMin)} to wake at ${clockText(plan.wakeMin)} (${wakeSource})`
    : "no bedtime yet (no wake-up time set for tomorrow and fewer than 3 recent wake times)";
  lines.push(
    `Tonight's sleep plan (FitStats' rule, shown in the app): need tonight ${dur(plan.needMin)} (base ${dur(plan.baseMin)}${extras ? ` ${extras}` : ""}); ` +
      `at ${Math.round(plan.efficiency * 100)}% sleep efficiency that is ${dur(plan.inBedMin)} in bed; ${bedtime}.`,
  );
  lines.push(wakeTimesText(wakeTimes, days as DayRow[], ctx.today));

  const metrics = (stats?.metrics ?? null) as Record<string, Json> | null;
  if (!metrics) {
    lines.push("", "No statistics yet: the first sync may still be running.");
  } else {
    lines.push("", "Averages (30 days vs the 30 before, 90 days, weekly trend over 30 days):");
    const missing: string[] = [];
    for (const key of SUMMARY_KEYS) {
      const def = METRIC_BY_KEY.get(key)!;
      const ranges = (metrics[key]?.ranges ?? {}) as Record<string, Json>;
      const r30 = ranges["30"], r90 = ranges["90"];
      const mean30 = num(r30?.mean);
      if (mean30 === null) {
        if (!num(ranges.all?.n)) missing.push(def.label);
        continue;
      }
      let line = `- ${def.label}: ${fmt(def, mean30)}`;
      const prev = num(r30.prevMean);
      if (prev !== null) line += ` (before: ${fmt(def, prev)}, ${changeText(def, mean30, prev, num(r30.changePct))})`;
      const mean90 = num(r90?.mean);
      if (mean90 !== null) line += `; 90 days ${fmt(def, mean90)}`;
      const slope = num(r30.slopePerWeek);
      if (slope !== null) line += `; trend ${slopeText(def, slope)}`;
      lines.push(line);
    }
    if (missing.length) lines.push(`- No data at all for: ${missing.join(", ")}.`);
  }

  const load = (stats?.load ?? null) as Json | null;
  const latest = (load?.latest ?? null) as Json | null;
  if (load && latest) {
    const form = Number(latest.form);
    const values = `fitness ${latest.ctl}, fatigue ${latest.atl}, form ${form > 0 ? "+" : form < 0 ? "−" : ""}${Math.abs(form)}`;
    const ratio = num(latest.acwr) === null ? "load ratio not available (fewer than 21 of the last 28 days with TRIMP)" : `load ratio ${latest.acwr}${load.spike ? " (a spike)" : ""}`;
    const first = String(((load.series ?? []) as Json[])[0]?.date ?? ctx.today);
    lines.push("", load.status === "calibrating"
      ? `Training load (shown in the app) up to ${latest.date}: calibrating (${daysBetween(first, ctx.today)} of the 28 days it needs since the first day with TRIMP); so far ${values}; ${ratio}.`
      : `Training load (shown in the app) up to ${latest.date}: ${values}, so ${load.status}; ${ratio}.`);
  }
  const bed = (stats?.bedtime ?? null) as Json | null;
  if (bed && num(bed.nights)) {
    const buckets = ((bed.buckets ?? []) as Json[]).filter((b) => num(b.nights)).map((b) => {
      const score = num(b.sleepScore), asleep = num(b.asleepMin), rec = num(b.recovery);
      const means = [
        score === null ? "" : `sleep score ${Math.round(score)}`,
        asleep === null ? "" : `asleep ${dur(asleep)}`,
        rec === null ? "" : `recovery ${Math.round(rec)}`,
      ].filter(Boolean);
      return `${b.label} ${b.nights === 1 ? "1 night" : `${b.nights} nights`}${means.length ? ` (${means.join(", ")})` : ""}`;
    });
    const best = (bed.best ?? null) as Json | null;
    const verdict = best
      ? `best ${best.label}, sleep score ${Number(best.diff) >= 0 ? "+" : "−"}${Math.abs(Number(best.diff))} vs all other nights (${best.clear ? "clear" : "not clear"})`
      : "no best bedtime yet (needs 3+ nights in at least 2 windows)";
    lines.push(`Bedtime vs sleep (shown in the app; last ${bed.nights} scored nights): ${verdict}. By bedtime: ${buckets.join("; ")}.`);
  }

  const insights = Array.isArray(stats?.insights) ? (stats!.insights as Json[]) : [];
  if (insights.length) {
    lines.push("", "Insights FitStats shows on its Insights screen:");
    for (const i of insights) lines.push(`- ${i.title}: ${i.body}`);
  }
  const corr = (Array.isArray(stats?.correlations) ? (stats!.correlations as Json[]) : [])
    .filter((c) => c.strength === "moderate" || c.strength === "strong");
  if (corr.length) {
    lines.push("", "Notable correlations over the last 180 days (Pearson r):");
    for (const c of corr) lines.push(`- ${c.title}: r = ${c.r} (${c.strength}, ${c.n} days)`);
  }
  const impacts = Array.isArray(stats?.journal) ? (stats!.journal as Json[]) : [];
  if (impacts.length) {
    lines.push("", "Journal tags: the night and morning after tagged days vs after other logged days (365 days; clear = Welch |t| ≥ 2):");
    for (const impact of impacts) {
      const effects = (Array.isArray(impact.effects) ? impact.effects : []) as Json[];
      if (!effects.length) {
        lines.push(`- ${impact.label}: tagged ${dayCount(impact.days)}, not enough logged days to compare yet (3+ with and 3+ without).`);
        continue;
      }
      const parts = effects.map((e) => {
        const def = METRIC_BY_KEY.get(String(e.metric))!;
        return `${lowerFirst(def.label)} ${fmt(def, Number(e.with))} vs ${fmt(def, Number(e.without))}${e.clear ? " (clear)" : " (not clear)"}`;
      });
      const first = effects[0];
      lines.push(`- ${impact.label} (${first.nWith} vs ${first.nWithout} days): ${parts.join("; ")}.`);
    }
  }
  const streaks = Array.isArray(stats?.streaks) ? (stats!.streaks as Json[]) : [];
  if (streaks.length) {
    lines.push("", `Streaks: ${streaks.map((s) => `${s.label} ${dayCount(s.current)} now (best ${dayCount(s.longest)})`).join("; ")}.`);
  }

  lines.push("", "Training tab (routines they keep and workouts they logged in the app; get_training has more):");
  if (!routines.length && !logs.length) lines.push("- No routines or logged workouts yet.");
  for (const r of routines.slice(0, 12)) lines.push(`- Routine (id ${r.id}) ${routineText(r)}`);
  if (routines.length > 12) lines.push(`- …and ${routines.length - 12} more routines.`);
  for (const l of logs.slice(0, 10)) lines.push(`- Logged ${logText(l)}`);
  if (routines.length && !logs.length) lines.push("- No workouts logged in the app in the last 4 weeks.");
  return lines.join("\n");
}

// ----------------------------------------------------------------------- tools

function metricHelp(d: MetricDef): string {
  let unit = d.unit;
  if (d.format === "duration") unit = "minutes";
  if (d.format === "clock") unit = "minutes from local midnight, negative = before midnight";
  return `${d.key}: ${d.label}${unit ? ` (${unit})` : ""}${d.agg === "sum" ? ", day total" : ""}`;
}

const METRIC_KEYS = METRICS.map((m) => m.key);

export const TOOLS: Json[] = [
  {
    name: "get_daily_metrics",
    description: "Daily values of up to 8 metrics for a date range (at most 400 days). Days without data are left out. " +
      `Metric keys:\n${METRICS.map(metricHelp).join("\n")}`,
    input_schema: {
      type: "object",
      properties: {
        from: { type: "string", description: "First day, YYYY-MM-DD" },
        to: { type: "string", description: "Last day (inclusive), YYYY-MM-DD" },
        metrics: { type: "array", items: { type: "string", enum: METRIC_KEYS }, minItems: 1, maxItems: 8 },
      },
      required: ["from", "to", "metrics"],
    },
  },
  {
    name: "get_metric_stats",
    description: "Statistics for one metric over the last 7, 30, 90 and 365 days and all data: mean, median, min and max with dates, " +
      "standard deviation, weekly trend, and change versus the previous period of the same length. Also weekday averages over 90 days and best/worst days.",
    input_schema: {
      type: "object",
      properties: { metric: { type: "string", enum: METRIC_KEYS } },
      required: ["metric"],
    },
  },
  {
    name: "get_day",
    description: "Everything recorded for one date: all metrics, how recovery and the sleep score were computed, sleep sessions with stage minutes and local times, " +
      "workouts (with their own strain, peak minute heart rate, heart-rate recovery, heart-rate coverage and origin), hourly heart rate, hourly stress, minutes in heart-rate-reserve zones (50–60/60–70/70–80/80–90/90+%), " +
      "wear time, and the journal entry (tags and note) for that day.",
    input_schema: {
      type: "object",
      properties: { date: { type: "string", description: "YYYY-MM-DD" } },
      required: ["date"],
    },
  },
  {
    name: "get_workouts",
    description: "Workouts between two dates (at most 400 days): date, local start time, type, duration, average heart rate, calories, distance, Active Zone Minutes, " +
      "strain and heart-rate recovery.",
    input_schema: {
      type: "object",
      properties: {
        from: { type: "string", description: "First day, YYYY-MM-DD" },
        to: { type: "string", description: "Last day (inclusive), YYYY-MM-DD" },
      },
      required: ["from", "to"],
    },
  },
  {
    name: "get_training",
    description: "Their Training tab: every routine (id, name, exercises with target sets, reps, kg, minutes, km, rest, notes, and whether you made it), " +
      "the workouts they logged in the app between two dates (default the last 90 days; set by set: reps, kg, minutes, km, done; effort 1–10; notes), " +
      "and per exercise over the last year: sessions logged, the best set with its date, and the last session with its volume (reps × kg). " +
      "Also the muscles each exercise works (from the app's exercise library, or chosen by them), done sets per muscle over the last 7 and 28 days " +
      "(a set counts 1 for the main muscles and 0.5 for helpers; cardio isn't counted), and the library's exercise names. " +
      "The band's own workouts (heart rate, strain) are in get_workouts.",
    input_schema: {
      type: "object",
      properties: {
        from: { type: "string", description: "First day of logged workouts, YYYY-MM-DD (optional)" },
        to: { type: "string", description: "Last day (inclusive), YYYY-MM-DD (optional)" },
      },
    },
  },
  {
    name: "save_routine",
    description: "Saves a routine to their Training tab, where they can start it and log it set by set. Use it only when they ask you to make or change a routine " +
      "(or agree to one you suggested). To change one of their routines, pass its id and the whole routine as it should be; leave id out to make a new one. " +
      "Weights in kg, distance in km, durations in minutes, rest in seconds. Reps is text so it can be a range (\"8-12\") or \"AMRAP\". " +
      "Name exercises as the app's exercise library does (get_training lists the names) so the app can show the muscles they work; " +
      "for an exercise outside the library, pass the muscles it works.",
    input_schema: {
      type: "object",
      properties: {
        id: { type: "string", description: "An existing routine's id, to change it" },
        name: { type: "string", description: "Short name, e.g. \"Upper body A\"" },
        notes: { type: "string", description: "How and when to do it: warm-up, progression, which days" },
        exercises: {
          type: "array",
          maxItems: 40,
          items: {
            type: "object",
            properties: {
              name: { type: "string" },
              kind: { type: "string", enum: [...EXERCISE_KINDS] },
              sets: { type: "integer", minimum: 1, maximum: 30 },
              reps: { type: "string" },
              weight_kg: { type: "number" },
              duration_min: { type: "number" },
              distance_km: { type: "number" },
              rest_s: { type: "integer" },
              notes: { type: "string" },
              muscles: {
                type: "array",
                description: "Only for an exercise not in the library: the muscles it mainly works",
                items: { type: "string", enum: MUSCLES.map((m) => m.id) },
                maxItems: 6,
              },
            },
            required: ["name", "kind"],
          },
        },
      },
      required: ["name", "exercises"],
    },
  },
  {
    name: "get_journal",
    description: "Their journal entries between two dates (at most 400 days): the tags they logged for each day and their notes.",
    input_schema: {
      type: "object",
      properties: {
        from: { type: "string", description: "First day, YYYY-MM-DD" },
        to: { type: "string", description: "Last day (inclusive), YYYY-MM-DD" },
      },
      required: ["from", "to"],
    },
  },
];

/** Tools that change what the app shows: the app reloads its training data after them. */
export const TRAINING_WRITES = new Set(["save_routine"]);

class ToolError extends Error {}

function rangeArgs(input: Json): [Ymd, Ymd] {
  const from = String(input.from ?? ""), to = String(input.to ?? "");
  if (!YMD.test(from) || !YMD.test(to) || from > to) throw new ToolError("from and to must be YYYY-MM-DD dates with from <= to");
  if (daysBetween(from, to) > 400) throw new ToolError("the range is limited to 400 days; split it into smaller ranges");
  return [from, to];
}

function rnd(v: number | null, decimals: number): number | null {
  return v === null ? null : round(v, decimals);
}

export async function runTool(name: string, input: Json, ctx: Ctx, stats: Json | null): Promise<unknown> {
  switch (name) {
    case "get_daily_metrics": {
      const [from, to] = rangeArgs(input);
      const keys = Array.isArray(input.metrics) ? input.metrics.map(String) : [];
      const unknown = keys.filter((k) => !METRIC_BY_KEY.has(k));
      if (unknown.length || !keys.length) throw new ToolError(`unknown metrics: ${unknown.join(", ") || "(none given)"}`);
      const defs = keys.slice(0, 8).map((k) => METRIC_BY_KEY.get(k)!);
      const rows = await db.select<Row>("fs_days", `select=*&date=gte.${from}&date=lte.${to}&order=date.asc`);
      const out: Row[] = [];
      for (const r of rows) {
        const values = defs.map((d) => [d.key, rnd(d.get(r as DayRow), d.decimals + 1)] as const);
        if (values.some(([, v]) => v !== null)) out.push({ date: r.date, ...Object.fromEntries(values), ...(r.low_wear === true ? { low_wear: true } : {}) });
      }
      return { from, to, today: ctx.today, days: out };
    }
    case "get_metric_stats": {
      const key = String(input.metric ?? "");
      const def = METRIC_BY_KEY.get(key);
      if (!def) throw new ToolError(`unknown metric ${key}`);
      const m = (stats?.metrics as Record<string, unknown> | undefined)?.[key];
      if (!m) return { metric: key, note: "No statistics yet." };
      return { metric: key, label: def.label, unit: def.format === "duration" || def.format === "clock" ? "minutes" : def.unit, weekday_order: "Mon..Sun", ...(m as Json) };
    }
    case "get_day": {
      const date = String(input.date ?? "");
      if (!YMD.test(date)) throw new ToolError("date must be YYYY-MM-DD");
      const [row, intra, sleeps, workouts, journal] = await Promise.all([
        db.selectOne<Row>("fs_days", `select=*&date=eq.${date}`),
        db.selectOne<Row>("fs_intraday", `select=hr&date=eq.${date}`),
        db.select<Row>("fs_sleep", `select=*&date=eq.${date}&order=start_time.asc`),
        db.select<Row>("fs_exercise", `select=*&date=eq.${date}&order=start_time.asc`),
        journalEntries(date, date),
      ]);
      const entry = journal[0] ? { tags: journal[0].tags.map(tagLabel), note: journal[0].note } : null;
      if (!row && !sleeps.length && !workouts.length && !entry) return { date, note: "Nothing was recorded on this date." };
      const metrics: Row = {};
      if (row) {
        for (const d of METRICS) {
          const v = d.get(row as DayRow);
          if (v !== null) metrics[d.key] = round(v, d.decimals + 1);
        }
      }
      const hr = Array.isArray(intra?.hr) ? (intra!.hr as (number | null)[]) : null;
      const hourlyHr = hr
        ? Array.from({ length: 24 }, (_, h) => {
          const vals = hr.slice(h * 60, h * 60 + 60).filter((v): v is number => typeof v === "number");
          return vals.length >= 10 ? Math.round(vals.reduce((a, b) => a + b, 0) / vals.length) : null;
        })
        : null;
      const scores = (row?.score_details ?? null) as Json | null;
      const intraday = (row?.intraday_details ?? null) as Json | null;
      // The day's sleep metrics come from the main session; every other one counts as a nap.
      const mainSleep = mainSleepOf(sleeps, row?.sleep_main_id);
      return {
        date,
        is_today: date === ctx.today,
        metrics,
        recovery_breakdown: scores?.recovery ?? null,
        sleep_score_breakdown: scores?.sleep ?? null,
        strain_target: scores?.strainTarget ?? null,
        sleep_sessions: sleeps.map((s) => {
          const awake = awakeAfterOnset(s.stages);
          return {
            main: s === mainSleep, nap: s !== mainSleep, start: localTime(s.start_time, ctx.tz), end: localTime(s.end_time, ctx.tz),
            asleep_min: s.minutes_asleep, awake_incl_falling_asleep_min: s.minutes_awake, deep_min: s.deep_min, light_min: s.light_min,
            rem_min: s.rem_min, awakenings: awake?.awakenings ?? null, awake_after_falling_asleep_min: awake?.wasoMin ?? null,
            fell_asleep_after_min: fallAsleepMinutes(s),
          };
        }),
        workouts: workouts.map((w) => workoutSummary(w, ctx.tz)),
        hourly_heart_rate: hourlyHr,
        hourly_stress: intraday?.stressHourly ?? null,
        hr_reserve_zone_minutes: intraday?.hrrZoneMinutes ?? null,
        max_hr_used: intraday?.maxHr ?? null,
        wear_minutes: row?.wear_min ?? null,
        low_wear: row?.low_wear ?? null,
        journal: entry,
      };
    }
    case "get_workouts": {
      const [from, to] = rangeArgs(input);
      const rows = await db.select<Row>("fs_exercise", `select=*&date=gte.${from}&date=lte.${to}&order=start_time.asc`);
      return { from, to, workouts: rows.map((w) => workoutSummary(w, ctx.tz)) };
    }
    case "get_training": {
      const [from, to] = input.from || input.to ? rangeArgs(input) : [addDays(ctx.today, -89), ctx.today];
      const [routines, logs, year] = await Promise.all([loadRoutines(), loadLogs(from, to), loadLogs(addDays(ctx.today, -364), ctx.today)]);
      const withMuscles = <T extends { name: string; muscles?: MuscleId[] | null }>(e: T) => {
        const m = exerciseMuscles(e.name, e.muscles);
        return { ...e, muscles: undefined, works: m.primary, helps: m.secondary };
      };
      return {
        routines: routines.map((r) => ({ id: r.id, name: r.name, made_by: r.created_by === "coach" ? "you (the coach)" : "them", notes: r.notes, exercises: r.exercises.map(withMuscles) })),
        logged_workouts: { from, to, workouts: logs.map((l) => ({ ...l, created_at: undefined, updated_at: undefined, exercises: l.exercises.map(withMuscles) })) },
        exercise_progress_last_year: exerciseProgress(year),
        muscle_sets_last_7_days: muscleSetsText(year.filter((l) => l.date > addDays(ctx.today, -7))),
        muscle_sets_last_28_days: muscleSetsText(year.filter((l) => l.date > addDays(ctx.today, -28))),
        library_exercises: LIBRARY.map((e) => e.name),
      };
    }
    case "save_routine": {
      try {
        const routine = await saveRoutine(input as Row, "coach");
        return { saved: true, note: "It is in their Training tab now.", routine: { id: routine.id, name: routine.name, exercises: routine.exercises.length } };
      } catch (e) {
        if (e instanceof TrainingInputError) throw new ToolError(e.message);
        throw e;
      }
    }
    case "get_journal": {
      const [from, to] = rangeArgs(input);
      const entries = await journalEntries(from, to);
      return { from, to, entries: entries.map((e) => ({ date: e.date, tags: e.tags.map(tagLabel), note: e.note })) };
    }
    default:
      throw new ToolError(`unknown tool ${name}`);
  }
}

function toolStatus(name: unknown, input: Json): string {
  const range = input.from && input.to ? `, ${shortDate(input.from)} – ${shortDate(input.to)}` : "";
  switch (name) {
    case "get_daily_metrics": {
      const labels = (Array.isArray(input.metrics) ? input.metrics : [])
        .map((k) => lowerFirst(METRIC_BY_KEY.get(String(k))?.label ?? String(k)));
      return `Looking at ${labels.length ? list(labels) : "your data"}${range}`;
    }
    case "get_metric_stats":
      return `Checking your ${lowerFirst(METRIC_BY_KEY.get(String(input.metric))?.label ?? "data")} statistics`;
    case "get_day":
      return `Opening ${shortDate(input.date)}`;
    case "get_workouts":
      return `Looking at your workouts${range}`;
    case "get_training":
      return "Looking at your routines and logged workouts";
    case "save_routine":
      return `Saving “${String(input.name ?? "your routine").slice(0, 40)}” to Training`;
    case "get_journal":
      return `Reading your journal${range}`;
    default:
      return "Looking at your data";
  }
}

// ---------------------------------------------------------------- Claude API

export const INSTRUCTIONS = `You are the FitStats coach: a friendly, knowledgeable sleep, recovery and training coach for one person who wears a Fitbit Air. You talk with them inside the FitStats app.

What you know
- A summary of their data is at the end of this prompt, refreshed on every message. Use the tools to look up anything else: any metric for any date range, one day in detail (sleep stages, workouts, hourly heart rate and stress), workouts, and full statistics per metric. Look things up rather than guess.
- Their journal: tags they log for a day (alcohol, late meal, …) and short notes. Tag effects compare the night and morning after tagged days with those after other logged days; with few days they are hints, not findings.
- Days they wore the band for under 60% of their usual time are "low wear": their day totals are incomplete and left out of averages.
- Recovery, strain, sleep score and stress are FitStats' own formulas, defined below. They are not Bevel's, Whoop's or Fitbit's scores.
- Everything the app shows is yours to read: the Today cards, sleep (with naps), recovery, strain, stress, trends, insights, the journal, and the Training tab. When their message starts with "About …", they asked from that screen of the app.

Training
- The Training tab holds their routines (plans of exercises with target sets, reps, kg, minutes or km) and the workouts they log there set by set (reps, kg, minutes, km, effort 1–10). The band records workouts too (heart rate, strain, heart-rate recovery; get_workouts and get_day). A logged gym session and a band workout on the same day at about the same time are usually the same session: read both.
- Use get_training to see routines, logged workouts and each exercise's progress before you judge or change their training.
- To make or change a routine, design it for them: their goal if they said one, how often they train, what they have logged, recovery and training load. Then save it with save_routine and say it's in the Training tab. To change one of theirs, pass its id. Don't save a routine they didn't ask for; suggest it first.
- When reviewing workouts, be concrete: compare with their earlier sessions of the same exercise (more reps or kg at the same effort is progress), weekly volume, effort, and how recovery and strain looked the days after. Suggest the next session's numbers.
- The app shows which muscles each exercise works (its exercise library) and done sets per muscle on a body map. get_training has the same numbers: use them to spot muscles trained much more or less than the rest, and keep routines balanced unless they want a focus.

Screenshots
- They can attach screenshots to a message: from this app, another app (a workout, a nutrition label, a lab result) or anything else. Read them carefully and use what matters for their question; say plainly if something is unreadable or cut off. An earlier message's screenshots aren't shown again later in the conversation: rely on what you said about them then.

How to answer
- Lead with the answer, then the two or three numbers from their data that support it, with dates. Be specific to them; skip generic advice.
- Keep it short: usually under 120 words. Use short paragraphs or a few "- " bullets. Bold at most two key numbers. No headings and no tables.
- Make suggestions concrete (a bedtime, an intensity or strain range, a number of easy days) and say why, from their data.
- Never invent data. If something is missing or not tracked (for example no weight data), say so plainly. Today's day totals are partial until the day ends.
- Correlation is not causation: say "linked with", not "caused by".
- You are not a doctor. For symptoms, worrying readings (for example blood oxygen repeatedly below 90%, or resting heart rate up sharply for several days together with feeling ill) or medical questions, suggest seeing a healthcare professional, calmly.
- Reply in the language the user writes in. Use metric units and 24-hour times.

Score definitions
- Recovery (0–100, each morning): HRV 45% (ln RMSSD against the previous 30 nights as a z-score), resting heart rate 25%, sleep score 20%, skin temperature and breathing rate 10%. 67+ is green ("ready to perform"), 34–66 yellow, below 34 red. It needs 5 nights of baseline first.
- Strain (0–100, day total): 100 × (1 − e^(−TRIMP/120)), where TRIMP is Banister's training impulse from minute heart rate above 30% of heart-rate reserve. Suggested strain: 55–80 on green recovery, 35–60 on yellow, 10–35 on red.
- Sleep score (0–100): duration against their sleep need 50%, efficiency 15% (share of Fitbit's detected sleep period spent asleep: 85% or less scores 0, 98% or more full marks), deep + REM share 20%, bed and wake time consistency 15%.
- Stress (0–100): how far heart rate sits above their usual still level while awake, still and not exercising (Google Health has no daytime HRV). A minute counts when it is outside sleep, workouts and the recovery after them (until heart rate is back near the level before the workout, 30–180 minutes), has no steps in it or the 3 minutes before and, when Fitbit's minute sedentary data is there, is marked sedentary. Each minute scores 0 at or below their usual still heart rate (median of the last 30 days; a fixed 14% of heart-rate reserve above resting until there are 7 days) and 100 at 15% of heart-rate reserve above it; the day is the average. Below 25 is low, 25–49 moderate, 50–74 high, 75 or more very high.
- Training load (shown in the app): fitness is the 42-day exponentially weighted average of daily TRIMP (the same impulse as strain; today is left out, days without it count as 0), fatigue the 7-day one, form = fitness − fatigue. For the first 42 (or 7) days each is the plain mean of the days so far. Form ÷ fitness above 0.1 is fresh, −0.1 to 0.1 neutral, −0.3 to −0.1 productive (building fitness), below −0.3 overreaching; "calibrating" for the first 28 days. The load ratio is the last 7 days' mean TRIMP ÷ the last 28 days' (days without TRIMP count as 0; it needs 21 of the 28 days with TRIMP); 1.5 or more is a spike, a week much harder than they are used to.
- Heart-rate recovery (per workout): how many bpm heart rate fell 1 and 2 minutes after the end, from the mean of the workout's last 2 minutes. Only for workouts of 10+ minutes that ended hard (at least halfway up the heart-rate reserve), with heart rate just after and no other workout right after. A bigger drop generally goes with better aerobic fitness; compare their own workouts of the same kind over time. A small drop usually means they kept moving after the recorded end; a drop of 0 or less is not reported.
- Bedtime vs sleep (shown in the app): the last 180 scored nights grouped by bedtime (before 22:30, half-hour windows to 01:00, after 01:00); the best window has the highest mean sleep score among windows with 3+ nights, compared with all other nights (clear = Welch t ≥ 2).
- HRV is Fitbit's nightly RMSSD and resting heart rate is Fitbit's daily value.
- Awakenings count only times awake after falling asleep and before the final wake-up; "awake after falling asleep" is the minutes of those. Fitbit's awake time also includes the stretch of falling asleep.
- Sleep plan (shown in the app as "Tonight"): need tonight = their sleep need setting (the base) + 0–45 min for the day's strain (0 at 35 or less, 45 at 85 or more) + a quarter of the last 7 nights' sleep debt (at most 60 min; earlier days' naps count as sleep) − today's naps (at most 60 min); time in bed = need tonight ÷ their typical sleep efficiency; bedtime = the wake-up time they set for tomorrow (else their usual wake time for tomorrow's kind of day) − time in bed. Use its numbers when suggesting a bedtime; call the plan's total "need tonight", not their sleep need.
- Wake-up times they set by hand are when they have to be up. A morning with a later time, or with none, is one they can sleep in: when they are short of sleep, point those out as the chance to catch up, and keep the plan's bedtime for nights before an early morning.`;

export const BRIEF_PROMPT = `Write my briefing for today. Three or four short lines, no greeting, each starting with a bold label: **Recovery**, **Today**, **Tonight**, and only if there is something worth saying, **Trend**. Recovery: today's score and its main drivers. Today: how hard to train (the strain range) and one concrete suggestion. Tonight: the bedtime and the need tonight from tonight's sleep plan. Trend: one notable change over the last weeks. Under 90 words. If today's recovery isn't available yet, say so and base the advice on the last few days.`;

export interface CoachUsage {
  requests: number;
  input: number;
  output: number;
  cache_read: number;
  cache_write: number;
  cost_usd: number;
}

function emptyUsage(): CoachUsage {
  return { requests: 0, input: 0, output: 0, cache_read: 0, cache_write: 0, cost_usd: 0 };
}

interface CallResult {
  content: Json[];
  stopReason: string;
  usage: { input: number; output: number; cacheRead: number; cacheWrite: number };
}

interface StreamHooks {
  onTextStart: () => void;
  onText: (text: string) => void;
  onToolUse: (block: Json) => void;
}

/** Server-sent events from a fetch body → parsed `data:` payloads. */
export async function* readSse(body: ReadableStream<Uint8Array>): AsyncGenerator<Json> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer = (buffer + decoder.decode(value, { stream: true })).replace(/\r\n/g, "\n");
      let cut: number;
      while ((cut = buffer.indexOf("\n\n")) >= 0) {
        const raw = buffer.slice(0, cut);
        buffer = buffer.slice(cut + 2);
        const data = raw.split("\n").filter((l) => l.startsWith("data:")).map((l) => l.slice(5).trimStart()).join("\n");
        if (data) yield JSON.parse(data) as Json;
      }
    }
  } finally {
    reader.releaseLock();
  }
}

function apiError(status: number, text: string, model: string): CoachError {
  let type = `http_${status}`, message = text.slice(0, 300);
  try {
    const err = (JSON.parse(text) as Json).error as Json | undefined;
    if (err) {
      type = String(err.type ?? type);
      message = String(err.message ?? message);
    }
  } catch {
    // not JSON
  }
  if (status === 401) return new CoachError("invalid_api_key", "Anthropic rejected the API key. Check the ANTHROPIC_API_KEY secret in Supabase.");
  if (status === 404 || (status === 400 && /model/i.test(message))) {
    return new CoachError("model_unavailable", `${model} isn't available for this API key (${message}). Pick another model in Settings → Coach.`);
  }
  if (status === 429) return new CoachError("rate_limited", "Anthropic's rate limit was reached. Try again in a minute.");
  if (status === 529 || type === "overloaded_error") return new CoachError("overloaded", "Claude is overloaded right now. Try again shortly.");
  return new CoachError(type, `Claude API error ${status}: ${message}`);
}

async function callClaude(apiKey: string, payload: Json, model: string, signal: AbortSignal, hooks: StreamHooks): Promise<CallResult> {
  const res = await fetch(ANTHROPIC_URL, {
    method: "POST",
    headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ ...payload, stream: true }),
    signal,
  });
  if (!res.ok || !res.body) throw apiError(res.status, await res.text().catch(() => ""), model);

  const blocks: Json[] = [];
  const partialJson: string[] = [];
  const usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
  let stopReason = "end_turn";
  for await (const ev of readSse(res.body)) {
    switch (ev.type) {
      case "message_start": {
        const u = ((ev.message as Json | undefined)?.usage ?? {}) as Json;
        usage.input = num(u.input_tokens) ?? 0;
        usage.cacheRead = num(u.cache_read_input_tokens) ?? 0;
        usage.cacheWrite = num(u.cache_creation_input_tokens) ?? 0;
        usage.output = num(u.output_tokens) ?? 0;
        break;
      }
      case "content_block_start": {
        const i = Number(ev.index);
        blocks[i] = { ...(ev.content_block as Json) };
        partialJson[i] = "";
        if (blocks[i].type === "text") hooks.onTextStart();
        break;
      }
      case "content_block_delta": {
        const i = Number(ev.index);
        const d = (ev.delta ?? {}) as Json;
        const b = blocks[i];
        if (!b) break;
        if (d.type === "text_delta") {
          b.text = String(b.text ?? "") + String(d.text ?? "");
          hooks.onText(String(d.text ?? ""));
        } else if (d.type === "input_json_delta") {
          partialJson[i] += String(d.partial_json ?? "");
        } else if (d.type === "thinking_delta") {
          b.thinking = String(b.thinking ?? "") + String(d.thinking ?? "");
        } else if (d.type === "signature_delta") {
          b.signature = String(d.signature ?? "");
        }
        break;
      }
      case "content_block_stop": {
        const i = Number(ev.index);
        const b = blocks[i];
        if (b?.type === "tool_use") {
          try {
            b.input = partialJson[i] ? JSON.parse(partialJson[i]) : {};
          } catch {
            b.input = {};
          }
          hooks.onToolUse(b);
        }
        break;
      }
      case "message_delta": {
        const d = (ev.delta ?? {}) as Json;
        if (typeof d.stop_reason === "string") stopReason = d.stop_reason;
        const u = (ev.usage ?? {}) as Json;
        if (num(u.output_tokens) !== null) usage.output = num(u.output_tokens)!;
        break;
      }
      case "error": {
        const err = (ev.error ?? {}) as Json;
        const type = String(err.type ?? "api_error");
        if (type === "overloaded_error") throw new CoachError("overloaded", "Claude is overloaded right now. Try again shortly.");
        throw new CoachError(type, `Claude stopped with an error: ${String(err.message ?? type)}`);
      }
    }
  }
  return { content: blocks.filter(Boolean), stopReason, usage };
}

function addUsage(total: CoachUsage, model: string, u: CallResult["usage"]): void {
  const [pin, pwrite, pread, pout] = PRICES[model] ?? PRICES[DEFAULT_COACH_MODEL];
  total.requests += 1;
  total.input += u.input;
  total.output += u.output;
  total.cache_read += u.cacheRead;
  total.cache_write += u.cacheWrite;
  total.cost_usd = round(total.cost_usd + (u.input * pin + u.cacheWrite * pwrite + u.cacheRead * pread + u.output * pout) / 1e6, 5)!;
}

// --------------------------------------------------------------------- usage

interface UsageRecord extends CoachUsage {
  month: string;
  day: Ymd;
  day_requests: number;
}

async function loadUsage(today: Ymd): Promise<UsageRecord> {
  const row = await db.selectOne<Row>("fs_cache", "select=value&key=eq.coach_usage");
  const month = today.slice(0, 7);
  const fresh: UsageRecord = { ...emptyUsage(), month, day: today, day_requests: 0 };
  const saved = (row?.value ?? null) as UsageRecord | null;
  const u: UsageRecord = saved && saved.month === month ? { ...fresh, ...saved } : fresh;
  if (u.day !== today) {
    u.day = today;
    u.day_requests = 0;
  }
  return u;
}

async function saveUsage(today: Ymd, add: CoachUsage): Promise<void> {
  const u = await loadUsage(today);
  u.day_requests += 1;
  u.requests += add.requests;
  u.input += add.input;
  u.output += add.output;
  u.cache_read += add.cache_read;
  u.cache_write += add.cache_write;
  u.cost_usd = round(u.cost_usd + add.cost_usd, 5)!;
  await db.upsert("fs_cache", [{ key: "coach_usage", value: u, updated_at: new Date().toISOString() }], "key");
}

// -------------------------------------------------------------------- routes

function titleFrom(message: string): string {
  const line = message.split("\n")[0].trim();
  return line.length > 60 ? `${line.slice(0, 57).trimEnd()}…` : line || "Chat";
}

async function context(): Promise<Ctx> {
  const [acc, settings] = await Promise.all([loadAccount(), loadSettings()]);
  return { acc, settings, today: clockFor(acc).today(), tz: acc?.time_zone ?? null };
}

export async function coachStatus(): Promise<Row> {
  const ctx = await context();
  return {
    configured: !!db.optionalEnv("ANTHROPIC_API_KEY"),
    model: coachModel(ctx.settings),
    models: COACH_MODELS,
    usage: await loadUsage(ctx.today),
    daily_limit: DAILY_REQUEST_LIMIT,
  };
}

export async function coachThreads(): Promise<Row> {
  const threads = await db.select<Row>("fs_coach_threads", "select=id,title,created_at,updated_at&order=updated_at.desc");
  return { threads: threads.slice(0, 100) };
}

export async function coachThread(id: string): Promise<Response> {
  if (!UUID.test(id)) return jsonResponse({ error: "bad_request", message: "id must be a UUID" }, 400);
  const thread = await db.selectOne<Row>("fs_coach_threads", `select=id,title,created_at,updated_at&id=eq.${id}`);
  if (!thread) return jsonResponse({ error: "not_found", message: "No such conversation." }, 404);
  const messages = await db.select<Row>("fs_coach_messages", `select=id,role,content,persona,attachments,created_at&thread_id=eq.${id}&order=created_at.asc`);
  return jsonResponse({ thread, messages });
}

export async function coachDelete(id: string): Promise<Response> {
  if (!UUID.test(id)) return jsonResponse({ error: "bad_request", message: "id must be a UUID" }, 400);
  await db.remove("fs_coach_messages", `thread_id=eq.${id}`);
  await db.remove("fs_coach_threads", `id=eq.${id}`);
  return jsonResponse({ deleted: true });
}

export async function coachBrief(): Promise<Row> {
  const ctx = await context();
  const row = await db.selectOne<Row>("fs_cache", "select=value&key=eq.coach_brief");
  const brief = (row?.value ?? null) as Json | null;
  return { brief: brief && brief.date === ctx.today ? brief : null };
}

/**
 * POST {message, thread_id?, persona?, images?} for chat, or {kind: "brief"} for today's briefing.
 * persona: nova (default), ace or kai. images: up to 3 screenshots, {media_type, data (base64),
 * thumb (a small base64 JPEG kept with the message)}.
 * Streams `data: {...}` events: status (a tool is running), text (reply text as it
 * arrives), changed (a tool saved something the app shows: what = "training"), done (saved;
 * includes thread_id or brief, and usage) or error.
 */
export async function handleCoach(req: Request): Promise<Response> {
  const body = (await req.json().catch(() => ({}))) as Row;
  const kind = body.kind === "brief" ? "brief" : "chat";
  const message = typeof body.message === "string" ? body.message.trim() : "";
  const threadId = typeof body.thread_id === "string" && UUID.test(body.thread_id) ? body.thread_id : null;
  const persona = typeof body.persona === "string" && COACH_PERSONAS[body.persona] ? body.persona : DEFAULT_PERSONA;
  const images = kind === "chat" ? parseImages(body.images) : [];
  if (typeof images === "string") return jsonResponse({ error: "bad_request", message: images }, 400);
  if (kind === "chat" && ((message.length === 0 && !images.length) || message.length > 4000)) {
    return jsonResponse({ error: "bad_request", message: "A message of 1–4000 characters (or a screenshot) is needed." }, 400);
  }
  const apiKey = db.optionalEnv("ANTHROPIC_API_KEY");
  if (!apiKey) {
    return jsonResponse({ error: "coach_not_configured", message: "Add an Anthropic API key as the ANTHROPIC_API_KEY secret in Supabase (see SETUP.md)." }, 503);
  }
  const ctx = await context();
  const usage = await loadUsage(ctx.today);
  if (usage.day_requests >= DAILY_REQUEST_LIMIT) {
    return jsonResponse({ error: "daily_limit", message: `The coach answers at most ${DAILY_REQUEST_LIMIT} messages a day. Try again tomorrow.` }, 429);
  }
  let history: Json[] = [];
  if (kind === "chat" && threadId) {
    const rows = await db.select<Row>("fs_coach_messages", `select=role,content,attachments,created_at&thread_id=eq.${threadId}&order=created_at.asc`);
    if (!rows.length) return jsonResponse({ error: "not_found", message: "No such conversation." }, 404);
    history = rows.slice(-HISTORY_MESSAGES).map((r) => ({ role: r.role, content: historyContent(r) }));
    while (history.length && history[0].role !== "user") history.shift();
  }

  const encoder = new TextEncoder();
  let closed = false;
  const sink: { out?: ReadableStreamDefaultController<Uint8Array> } = {};
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      sink.out = controller;
    },
    // The app went away (backgrounded, lost the network): the answer is still written and
    // saved, and the app picks it up from the thread ("started" told it which).
    cancel() {
      closed = true;
    },
  });
  const write = (chunk: string) => {
    if (closed || !sink.out) return;
    try {
      sink.out.enqueue(encoder.encode(chunk));
    } catch {
      closed = true;
    }
  };
  const send = (event: Row) => write(`data: ${JSON.stringify(event)}\n\n`);
  const work = (async () => {
    // Claude can think for a while without output; SSE comments keep the connection open.
    const keepAlive = setInterval(() => write(": keep-alive\n\n"), 10_000);
    try {
      await converse({ kind, message, images, persona, threadId, history, ctx, apiKey, signal: AbortSignal.timeout(ANSWER_TIMEOUT_MS), send });
    } catch (e) {
      console.error("coach", String(e));
      send({ type: "error", code: e instanceof CoachError ? e.code : "server_error", message: String((e as Error).message ?? e).slice(0, 400) });
    } finally {
      clearInterval(keepAlive);
      if (!closed) {
        closed = true;
        try {
          sink.out?.close();
        } catch {
          // already closed by the client
        }
      }
    }
  })();
  // Keeps the function running until the answer is saved, after the response has gone.
  (globalThis as { EdgeRuntime?: { waitUntil(p: Promise<unknown>): void } }).EdgeRuntime?.waitUntil(work);
  return new Response(stream, {
    headers: { "Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-store" },
  });
}

async function converse(o: {
  kind: "chat" | "brief";
  message: string;
  images: CoachImage[];
  persona: string;
  threadId: string | null;
  history: Json[];
  ctx: Ctx;
  apiKey: string;
  signal: AbortSignal;
  send: (event: Row) => void;
}): Promise<void> {
  const startedAt = new Date().toISOString();
  const model = coachModel(o.ctx.settings);
  const stats = ((await db.selectOne<Row>("fs_cache", "select=value&key=eq.stats"))?.value ?? null) as Json | null;
  const system: Json[] = [
    { type: "text", text: INSTRUCTIONS },
    { type: "text", text: `Their data\n\n${await buildContext(o.ctx, stats)}`, cache_control: { type: "ephemeral" } },
  ];
  // After the cached part, so switching coaches keeps the cache.
  if (o.kind === "chat") system.push({ type: "text", text: personaPrompt(o.persona) });
  const question: Json[] | string = o.images.length
    ? [
      ...o.images.map((img) => ({ type: "image", source: { type: "base64", media_type: img.media_type, data: img.data } })),
      ...(o.message ? [{ type: "text", text: o.message }] : []),
    ]
    : o.message;
  const messages: Json[] = [...o.history, { role: "user", content: o.kind === "brief" ? BRIEF_PROMPT : question }];
  const usage = emptyUsage();
  let text = "";

  // A chat question is saved first and the app told its thread, so an answer that finishes
  // after the app went away can be read from the thread. A failed answer keeps nothing.
  let threadId = o.threadId;
  const newThread = o.kind === "chat" && !threadId;
  const questionId = crypto.randomUUID();
  if (o.kind === "chat") {
    if (!threadId) {
      threadId = crypto.randomUUID();
      await db.insert("fs_coach_threads", [{ id: threadId, title: titleFrom(o.message || "Screenshot"), created_at: startedAt, updated_at: startedAt }]);
    }
    const attachments = o.images.length
      ? o.images.map((img) => ({ media_type: img.thumb?.startsWith("iVBORw0KGgo") ? "image/png" : "image/jpeg", thumb: img.thumb }))
      : null;
    await db.insert("fs_coach_messages", [
      { id: questionId, thread_id: threadId, role: "user", content: o.message, model: null, usage: null, persona: null, attachments, created_at: startedAt },
    ]);
    o.send({ type: "started", thread_id: threadId, message_id: questionId });
  }
  try {
    for (let round = 0; round < MAX_ROUNDS; round++) {
      const result = await callClaude(o.apiKey, {
        model,
        max_tokens: MAX_TOKENS,
        system,
        tools: TOOLS,
        // The last round must answer with what it has.
        ...(round === MAX_ROUNDS - 1 ? { tool_choice: { type: "none" } } : {}),
        output_config: { effort: "medium" },
        messages,
      }, model, o.signal, {
        onTextStart: () => {
          if (text && !text.endsWith("\n")) {
            text += "\n\n";
            o.send({ type: "text", text: "\n\n" });
          }
        },
        onText: (t) => {
          text += t;
          o.send({ type: "text", text: t });
        },
        onToolUse: (b) => o.send({ type: "status", text: toolStatus(b.name, (b.input ?? {}) as Json) }),
      });
      addUsage(usage, model, result.usage);
      if (result.stopReason !== "tool_use") break;

      const results: Json[] = [];
      for (const b of result.content.filter((c) => c.type === "tool_use")) {
        try {
          const out = await runTool(String(b.name), (b.input ?? {}) as Json, o.ctx, stats);
          results.push({ type: "tool_result", tool_use_id: b.id, content: JSON.stringify(out) });
          if (TRAINING_WRITES.has(String(b.name))) o.send({ type: "changed", what: "training" });
        } catch (e) {
          results.push({ type: "tool_result", tool_use_id: b.id, content: String((e as Error).message ?? e), is_error: true });
        }
      }
      // Thinking blocks go back unchanged with the tool results, as the API requires.
      messages.push({ role: "assistant", content: result.content });
      messages.push({ role: "user", content: results });
    }

    text = text.trim();
    if (!text) throw new CoachError("empty_reply", "Claude returned no answer. Try again.");
  } catch (e) {
    if (o.kind === "chat") {
      await db.remove("fs_coach_messages", `id=eq.${questionId}`);
      if (newThread) await db.remove("fs_coach_threads", `id=eq.${threadId}`);
    }
    throw e;
  }

  const now = new Date().toISOString();
  if (o.kind === "brief") {
    const brief = { date: o.ctx.today, text, created_at: now, model };
    await db.upsert("fs_cache", [{ key: "coach_brief", value: brief, updated_at: now }], "key");
    await saveUsage(o.ctx.today, usage);
    o.send({ type: "done", brief, model, usage });
    return;
  }
  await db.update("fs_coach_threads", `id=eq.${threadId}`, { updated_at: now });
  const messageId = crypto.randomUUID();
  await db.insert("fs_coach_messages", [
    { id: messageId, thread_id: threadId, role: "assistant", content: text, model, usage, persona: o.persona, attachments: null, created_at: now },
  ]);
  await saveUsage(o.ctx.today, usage);
  o.send({ type: "done", thread_id: threadId, message_id: messageId, model, persona: o.persona, usage });
}

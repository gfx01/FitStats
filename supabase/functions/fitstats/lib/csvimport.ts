// Workouts from a CSV file attached in the coach chat, saved to the Training log
// (fs_workout_logs) like workouts logged in the app, so the Training tab and the coach see them.
//
// Two shapes are read:
// - one row per set (Strong, Hevy and similar apps): a date or start time, the workout's name,
//   the exercise, and the set's weight, reps, distance or time;
// - one row per workout (Apple Health exporters and similar): a date or start time, the kind of
//   workout, its duration and distance (calories and heart rate go into its notes).
// Columns are found by their headers; commas, semicolons or tabs. Warm-up sets are left out (the
// Training log has no warm-up sets). Each workout gets an id made from its start and name, so
// importing the same file again updates those workouts instead of adding them twice.

import * as db from "./db.ts";
import { findExercise } from "./exercises.ts";
import type { ExerciseKind, LoggedExercise, LoggedSet, WorkoutLog } from "./training.ts";
import { addDays, daysBetween, type Ymd, zoneOffsetSeconds } from "./util.ts";

type Row = Record<string, unknown>;

/** Characters per file and files per message. */
export const MAX_FILE_CHARS = 5_000_000;
export const MAX_FILES = 3;
const MAX_ROWS = 200_000;
const MAX_WORKOUTS = 5000;
const MAX_EXERCISES = 40;
const MAX_SETS = 30;
const LB = 0.45359237;
const MILE = 1.609344;

export interface CsvFile {
  name: string;
  text: string;
}

export interface CsvImport {
  file: string;
  /** "a Strong export", "a Hevy export", "one row per set", "one row per workout". */
  format: string | null;
  workouts: WorkoutLog[];
  warmups: number;
  future: number;
  unreadable: number;
  /** What was assumed (units, the order of day and month). */
  assumed: string[];
  error: string | null;
  /** The file's first lines, when nothing could be read from it. */
  head: string | null;
}

/** The files of a chat request, or a message saying what is wrong with them. */
export function parseFiles(v: unknown): CsvFile[] | string {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v)) return "files must be a list.";
  if (v.length > MAX_FILES) return `At most ${MAX_FILES} files per message.`;
  const out: CsvFile[] = [];
  for (const raw of v) {
    const f = (raw ?? {}) as Row;
    const name = typeof f.name === "string" ? f.name.trim().slice(0, 120) : "";
    const text = typeof f.text === "string" ? f.text : "";
    if (!name || !text.trim()) return "A file is empty.";
    if (text.length > MAX_FILE_CHARS) return `${name} is too large (at most about 5 MB).`;
    out.push({ name, text });
  }
  return out;
}

// ------------------------------------------------------------------ CSV text

/** Rows of cells. Quotes ("a, b", "say ""hi""") as in RFC 4180; the delimiter is the one the header uses most. */
export function parseCsv(text: string): string[][] {
  const t = text.replace(/^﻿/, "");
  const firstLine = t.slice(0, t.search(/\r?\n/) < 0 ? t.length : t.search(/\r?\n/));
  const counts = [",", ";", "\t"].map((d) => [d, firstLine.split(d).length] as const);
  const delimiter = counts.sort((a, b) => b[1] - a[1])[0][0];
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let quoted = false;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (quoted) {
      if (c === '"') {
        if (t[i + 1] === '"') {
          cell += '"';
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell += c;
      }
    } else if (c === '"') {
      quoted = true;
    } else if (c === delimiter) {
      row.push(cell);
      cell = "";
    } else if (c === "\n" || c === "\r") {
      if (c === "\r" && t[i + 1] === "\n") i++;
      row.push(cell);
      if (row.some((x) => x.trim())) rows.push(row);
      row = [];
      cell = "";
      if (rows.length > MAX_ROWS) break;
    } else {
      cell += c;
    }
  }
  row.push(cell);
  if (row.some((x) => x.trim())) rows.push(row);
  return rows;
}

/** "Weight (kg)", "weight_kg" and "WEIGHT KG" are the same header. */
function header(h: string): string {
  return h.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

// ----------------------------------------------------------------- values

function numberIn(s: string | undefined): number | null {
  if (s === undefined) return null;
  const t = s.trim().replace(/\s/g, "");
  if (!t) return null;
  // "1.234,5" and "1,234.5": the last separator is the decimal one.
  const lastComma = t.lastIndexOf(","), lastDot = t.lastIndexOf(".");
  let n = t;
  if (lastComma > lastDot) n = t.replace(/\./g, "").replace(",", ".");
  else if (lastComma >= 0) n = t.replace(/,/g, "");
  const v = Number(n.replace(/[^0-9.eE+-]/g, ""));
  return Number.isFinite(v) ? v : null;
}

/** Minutes from "1h 5m", "45m", "1:05:00", "00:45", "3900s" or a plain number (minutes, or seconds with `plainIsSeconds`). */
export function durationMinutes(s: string | undefined, plainIsSeconds = false): number | null {
  if (!s || !s.trim()) return null;
  const t = s.trim().toLowerCase();
  const hms = t.match(/^(\d+):(\d{1,2})(?::(\d{1,2}(?:\.\d+)?))?$/);
  if (hms) {
    const [a, b, c] = [Number(hms[1]), Number(hms[2]), hms[3] === undefined ? null : Number(hms[3])];
    return c === null ? a + b / 60 : a * 60 + b + c / 60;
  }
  const parts = [...t.matchAll(/(\d+(?:[.,]\d+)?)\s*(h|hr|hrs|hours?|m|min|mins|minutes?|s|sec|secs|seconds?)\b/g)];
  if (parts.length) {
    let min = 0;
    for (const p of parts) {
      const v = Number(p[1].replace(",", "."));
      min += p[2].startsWith("h") ? v * 60 : p[2].startsWith("s") ? v / 60 : v;
    }
    return min;
  }
  const v = numberIn(t);
  if (v === null) return null;
  // A plain number is minutes, unless it is too big to be (then seconds, as some apps write).
  return plainIsSeconds || v > 600 ? v / 60 : v;
}

const MONTHS: Record<string, number> = {
  jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, sept: 9, oct: 10, nov: 11, dec: 12,
};

interface When {
  date: Ymd;
  /** The instant, when the time of day is known. */
  iso: string | null;
}

/**
 * A date or date and time as apps write them: ISO (with or without a zone), "2024-01-15 07:30",
 * "2024. 01. 15. 7:30", "15 Jan 2024, 07:30", "Jan 15, 2024 at 7:30 PM", "15.01.2024" and
 * "15/01/2024" or "01/15/2024" (`dayFirst` decides). Local times are in `tz`.
 */
export function parseWhen(raw: string | undefined, tz: string | null, dayFirst: boolean): When | null {
  if (!raw || !raw.trim()) return null;
  const s = raw.trim();
  let y = 0, mo = 0, d = 0;
  let rest = "";
  let m: RegExpMatchArray | null;
  if ((m = s.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$/))) {
    const t = Date.parse(m[7] === "Z" || m[7].includes(":") ? s : s.replace(/([+-]\d{2})(\d{2})$/, "$1:$2"));
    if (!Number.isFinite(t)) return null;
    const off = tz ? zoneOffsetSeconds(tz, t) : 0;
    return { date: new Date(t + off * 1000).toISOString().slice(0, 10), iso: new Date(t).toISOString() };
  }
  if ((m = s.match(/^(\d{4})[-/.]\s?(\d{1,2})[-/.]\s?(\d{1,2})\.?[T\s,]*(.*)$/))) {
    [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
    rest = m[4];
  } else if ((m = s.match(/^(\d{1,2})[\s-]([A-Za-z]{3,9})\.?[\s-](\d{4}),?\s*(.*)$/))) {
    [d, mo, y] = [Number(m[1]), MONTHS[m[2].slice(0, 3).toLowerCase()] ?? 0, Number(m[3])];
    rest = m[4];
  } else if ((m = s.match(/^([A-Za-z]{3,9})\.?\s(\d{1,2}),?\s(\d{4}),?\s*(?:at\s)?(.*)$/i))) {
    [mo, d, y] = [MONTHS[m[1].slice(0, 3).toLowerCase()] ?? 0, Number(m[2]), Number(m[3])];
    rest = m[4];
  } else if ((m = s.match(/^(\d{1,2})([./-])(\d{1,2})\2(\d{2,4})[,\s]*(.*)$/))) {
    const [a, b] = [Number(m[1]), Number(m[3])];
    const first = m[2] === "." ? true : dayFirst;
    [d, mo] = first ? [a, b] : [b, a];
    y = Number(m[4]) < 100 ? 2000 + Number(m[4]) : Number(m[4]);
    rest = m[5];
  } else {
    return null;
  }
  if (!(y >= 1990 && y <= 2100 && mo >= 1 && mo <= 12 && d >= 1 && d <= 31)) return null;
  const date = `${y}-${String(mo).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
  const tm = rest.match(/^(\d{1,2})[:.](\d{2})(?:[:.](\d{2}))?\s*(am|pm|de|du)?/i);
  if (!tm) return { date, iso: null };
  let h = Number(tm[1]);
  const ampm = (tm[4] ?? "").toLowerCase();
  if ((ampm === "pm" || ampm === "du") && h < 12) h += 12;
  if ((ampm === "am" || ampm === "de") && h === 12) h = 0;
  const local = Date.UTC(y, mo - 1, d, h, Number(tm[2]), Number(tm[3] ?? 0));
  const off = tz ? zoneOffsetSeconds(tz, local) : 0;
  return { date, iso: new Date(local - off * 1000).toISOString() };
}

/** Whether "01/02/2024"-style dates in a column are day first: a first number over 12 says so, a second one over 12 says not. */
function dayFirstIn(values: string[]): { dayFirst: boolean; known: boolean } {
  let first = false, second = false, any = false;
  for (const v of values) {
    const m = v.trim().match(/^(\d{1,2})\/(\d{1,2})\/\d{2,4}/);
    if (!m) continue;
    any = true;
    if (Number(m[1]) > 12) first = true;
    if (Number(m[2]) > 12) second = true;
  }
  if (first !== second) return { dayFirst: first, known: true };
  return { dayFirst: true, known: !any };
}

/** A UUID made from a text, so the same workout gets the same id on every import. */
async function stableId(key: string): Promise<string> {
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(key)));
  const h = [...hash.slice(0, 16)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-5${h.slice(13, 16)}-a${h.slice(17, 20)}-${h.slice(20, 32)}`;
}

function round(v: number | null, decimals: number): number | null {
  if (v === null || !Number.isFinite(v)) return null;
  const f = 10 ** decimals;
  return Math.round(v * f) / f;
}

// ------------------------------------------------------------------ reading

/** Reads the workouts in a CSV file (nothing is saved). */
export async function readWorkoutCsv(file: CsvFile, tz: string | null, today: Ymd): Promise<CsvImport> {
  const out: CsvImport = { file: file.name, format: null, workouts: [], warmups: 0, future: 0, unreadable: 0, assumed: [], error: null, head: null };
  const rows = parseCsv(file.text);
  const fail = (error: string) => {
    out.error = error;
    out.head = file.text.replace(/^﻿/, "").split(/\r?\n/).slice(0, 12).join("\n").slice(0, 2000);
    return out;
  };
  if (rows.length < 2) return fail("it has no rows under its header");
  const headers = rows[0].map(header);
  const col = (...names: (string | RegExp)[]): number => {
    for (const n of names) {
      const i = headers.findIndex((h) => typeof n === "string" ? h === n : n.test(h));
      if (i >= 0) return i;
    }
    return -1;
  };
  const c = {
    start: col("start time", "start", "start date", "date", "workout date", "date time", "started", "start time local", "begin", /^(start|date)\b/),
    end: col("end time", "end", "end date", "finished", "end time local", /^end\b/),
    title: col("workout name", "title", "workout title", "workout", "routine", "routine name", "session", "name"),
    type: col("workout type", "activity type", "type", "activity", "sport"),
    exercise: col("exercise name", "exercise title", "exercise", "movement", "exercise name en"),
    set: col("set order", "set index", "set", "set number", "set no"),
    setType: col("set type", "type of set"),
    weight: col("weight kg", "weight kgs", "weight", "weight lbs", "weight lb", "kg", "lbs", "load", /^weight\b/),
    weightUnit: col("weight unit", "unit", "units"),
    reps: col("reps", "repetitions", "rep"),
    distance: col("distance km", "distance", "distance mi", "distance miles", "distance m", "distance meters", /^distance\b/),
    distanceUnit: col("distance unit"),
    seconds: col("seconds", "duration seconds", "duration s", "time seconds", "time s", "duration sec"),
    duration: col("duration", "duration min", "duration minutes", "total duration", "elapsed time", "moving time", "time", /^duration\b/),
    notes: col("notes", "exercise notes", "set notes"),
    workoutNotes: col("workout notes", "description", "comment", "comments"),
    calories: col(/^(active )?(energy|calories|kcal)\b/, "calories burned"),
    heartRate: col(/^(avg|average) (heart rate|hr)\b/, "heart rate avg", "avg hr"),
  };
  if (c.start < 0) return fail("it has no date or start-time column");
  const perSet = c.exercise >= 0 && (c.weight >= 0 || c.reps >= 0 || c.distance >= 0 || c.seconds >= 0);
  if (!perSet && c.type < 0 && c.title < 0 && c.duration < 0) return fail("it has neither an exercise column with sets nor workouts with a type or duration");
  out.format = perSet
    ? headers.includes("workout name") && headers.includes("set order") ? "a Strong export"
    : headers.includes("exercise title") && headers.includes("set index") ? "a Hevy export"
    : "one row per set"
    : "one row per workout";

  const data = rows.slice(1);
  // Newer Strong exports have no Seconds column: their Duration is each set's time in seconds
  // (900 for 15 minutes on a machine). Older ones have Seconds per set and the workout's length
  // in Duration ("1h 5m"). A Duration of plain numbers in a set-by-set file is the set's time.
  if (perSet && c.seconds < 0 && c.duration >= 0) {
    const values = data.map((r) => (r[c.duration] ?? "").trim()).filter(Boolean);
    if (values.length && values.every((v) => /^\d+(?:[.,]\d+)?$/.test(v))) {
      c.seconds = c.duration;
      c.duration = -1;
    }
  }
  const order = dayFirstIn(data.map((r) => r[c.start] ?? ""));
  if (!order.known) out.assumed.push("dates written like 03/04/2025 are day first (3 April)");
  const weightHeader = c.weight >= 0 ? headers[c.weight] : "";
  const lbsHeader = /\blbs?\b/.test(weightHeader);
  const distanceHeader = c.distance >= 0 ? headers[c.distance] : "";
  const unitsSeen = new Set<string>();
  const kg = (r: string[]): number | null => {
    const v = numberIn(r[c.weight]);
    if (v === null) return null;
    const unit = c.weightUnit >= 0 ? (r[c.weightUnit] ?? "").trim().toLowerCase() : "";
    if (unit) unitsSeen.add(unit);
    const lbs = unit ? /^lb/.test(unit) : lbsHeader;
    return round(lbs ? v * LB : v, 2);
  };
  const km = (r: string[]): number | null => {
    const v = numberIn(r[c.distance]);
    if (v === null) return null;
    const unit = (c.distanceUnit >= 0 ? (r[c.distanceUnit] ?? "") : "").trim().toLowerCase() || distanceHeader.replace(/^distance ?/, "");
    if (/^(mi|mile|miles)$/.test(unit)) return round(v * MILE, 2);
    if (/^(m|meter|meters|metre|metres)$/.test(unit)) return round(v / 1000, 3);
    return round(v, 2);
  };
  if (perSet && c.weight >= 0 && c.weightUnit < 0) out.assumed.push(lbsHeader ? "weights in pounds (converted to kg)" : "weights in kg");

  interface Draft {
    key: string;
    when: When;
    name: string;
    end: When | null;
    minutes: number | null;
    exercises: Map<string, LoggedExercise>;
    notes: string[];
  }
  const drafts = new Map<string, Draft>();
  const list: Draft[] = [];

  for (const r of data) {
    const when = parseWhen(r[c.start], tz, order.dayFirst);
    if (!when) {
      out.unreadable++;
      continue;
    }
    if (when.date > today) {
      out.future++;
      continue;
    }
    const cell = (i: number) => (i >= 0 ? (r[i] ?? "").trim() : "");
    if (perSet) {
      const exercise = cell(c.exercise);
      if (!exercise) continue;
      const setLabel = cell(c.set).toLowerCase();
      if (setLabel.includes("rest")) continue;
      const setType = cell(c.setType).toLowerCase();
      if (setType.startsWith("warm") || setLabel === "w") {
        out.warmups++;
        continue;
      }
      const set: LoggedSet = {
        reps: (() => {
          const v = numberIn(cell(c.reps));
          return v === null || v < 0 || v > 1000 ? null : Math.round(v);
        })(),
        weight_kg: kg(r),
        duration_min: c.seconds >= 0 ? round(durationMinutes(cell(c.seconds), true), 1) : null,
        distance_km: c.distance >= 0 ? km(r) : null,
        done: true,
      };
      // Apps write 0 for an empty cell: no weight (bodyweight), no reps, no time or distance.
      if (set.reps === 0) set.reps = null;
      if (set.weight_kg === 0) set.weight_kg = null;
      if (set.duration_min === 0) set.duration_min = null;
      if (set.distance_km === 0) set.distance_km = null;
      if (set.reps === null && set.weight_kg === null && set.duration_min === null && set.distance_km === null) continue;
      const name = cell(c.title) || "Workout";
      const key = `${cell(c.start)}|${name}`;
      let w = drafts.get(key);
      if (!w) {
        w = {
          key, when, name: name.slice(0, 80), end: parseWhen(cell(c.end), tz, order.dayFirst),
          minutes: c.duration >= 0 ? durationMinutes(cell(c.duration)) : null, exercises: new Map(), notes: [],
        };
        const wn = cell(c.workoutNotes);
        if (wn) w.notes.push(wn);
        drafts.set(key, w);
        list.push(w);
      }
      const exKey = exercise.toLowerCase();
      let e = w.exercises.get(exKey);
      if (!e) {
        if (w.exercises.size >= MAX_EXERCISES) continue;
        e = { name: exercise.slice(0, 80), kind: "strength", sets: [], notes: null };
        w.exercises.set(exKey, e);
      }
      const note = cell(c.notes);
      if (note && !e.notes) e.notes = note.slice(0, 300);
      if (e.sets.length < MAX_SETS) e.sets.push(set);
    } else {
      const kind = cell(c.type) || cell(c.title) || "Workout";
      const name = (cell(c.title) || kind).slice(0, 80);
      const end = parseWhen(cell(c.end), tz, order.dayFirst);
      let minutes = c.duration >= 0 ? durationMinutes(cell(c.duration)) : null;
      if (minutes === null && when.iso && end?.iso) minutes = (Date.parse(end.iso) - Date.parse(when.iso)) / 60000;
      const distance = c.distance >= 0 ? km(r) : null;
      const extras = [
        c.calories >= 0 && numberIn(cell(c.calories)) !== null ? `${Math.round(numberIn(cell(c.calories))!)} kcal` : "",
        c.heartRate >= 0 && numberIn(cell(c.heartRate)) !== null ? `avg heart rate ${Math.round(numberIn(cell(c.heartRate))!)} bpm` : "",
      ].filter(Boolean);
      const key = `${cell(c.start)}|${name}`;
      if (drafts.has(key)) continue;
      const lib = findExercise(kind);
      const exKind: ExerciseKind = lib?.kind === "strength" ? "other" : lib?.kind === "mobility" ? "mobility" : "cardio";
      const w: Draft = {
        key, when, name, end, minutes,
        exercises: new Map([[kind.toLowerCase(), {
          name: kind.slice(0, 80), kind: exKind, notes: null,
          sets: [{ reps: null, weight_kg: null, duration_min: round(minutes, 1), distance_km: distance, done: true }],
        }]]),
        notes: extras.length ? [extras.join(", ")] : [],
      };
      drafts.set(key, w);
      list.push(w);
    }
    if (list.length > MAX_WORKOUTS) break;
  }
  if (perSet && c.weightUnit >= 0 && unitsSeen.size) {
    out.assumed.push(`weights in ${[...unitsSeen].join(" and ")} as the file says${[...unitsSeen].some((u) => u.startsWith("lb")) ? " (pounds converted to kg)" : ""}`);
  }

  const now = new Date().toISOString();
  for (const w of list.slice(0, MAX_WORKOUTS)) {
    const exercises = [...w.exercises.values()];
    for (const e of exercises) {
      // Sets with only time or distance are cardio, unless the library knows the exercise
      // (a plank is a timed strength hold).
      const lib = findExercise(e.name);
      const lifted = e.sets.some((s) => s.reps !== null || s.weight_kg !== null);
      if (!lifted && e.kind === "strength") e.kind = lib ? lib.kind : "cardio";
    }
    if (!exercises.length) continue;
    const started = w.when.iso;
    let ended = w.end?.iso ?? null;
    if (!ended && started && w.minutes && w.minutes > 0 && w.minutes < 24 * 60) ended = new Date(Date.parse(started) + w.minutes * 60000).toISOString();
    out.workouts.push({
      id: await stableId(`csv|${w.key}`),
      date: w.when.date,
      started_at: started,
      ended_at: ended,
      routine_id: null,
      name: w.name,
      exercises,
      notes: [`Imported from ${file.name}`, ...w.notes].join(" · ").slice(0, 1000),
      effort: null,
      created_at: now,
      updated_at: now,
    });
  }
  out.workouts.sort((a, b) => a.date.localeCompare(b.date));
  if (!out.workouts.length) return fail("no workouts with a readable date and at least one set were found");
  return out;
}

/** Reads a file and saves its workouts to the Training log. */
export async function importWorkoutCsv(file: CsvFile, tz: string | null, today: Ymd): Promise<CsvImport> {
  const result = await readWorkoutCsv(file, tz, today);
  if (result.workouts.length) await db.upsert("fs_workout_logs", result.workouts as unknown as Row[], "id");
  return result;
}

// ------------------------------------------------------------- for the coach

/** What the coach is told about an imported file: what was saved, and how often they trained. */
export function importSummary(r: CsvImport, today: Ymd): string {
  if (r.error) {
    return `FitStats couldn't read workouts from ${r.file}: ${r.error}. Nothing was saved. A file needs a date or start-time column and either ` +
      `one row per set (exercise, weight, reps…) or one row per workout (type, duration…). Its first lines:\n${r.head ?? ""}`;
  }
  const w = r.workouts;
  const first = w[0].date, last = w.at(-1)!.date;
  const parts = [
    `FitStats read ${r.file} (${r.format}) and saved ${w.length} workout${w.length === 1 ? "" : "s"} from ${first} to ${last} to their Training log, ` +
    `next to the ones they log in the app (importing the same file again updates these instead of adding them twice).`,
  ];
  if (r.assumed.length) parts.push(`Assumed: ${r.assumed.join("; ")}.`);
  const left = [
    r.warmups ? `${r.warmups} warm-up sets` : "",
    r.future ? `${r.future} rows dated in the future` : "",
    r.unreadable ? `${r.unreadable} rows without a readable date` : "",
  ].filter(Boolean);
  if (left.length) parts.push(`Left out: ${left.join(", ")}.`);
  const since = (days: number) => w.filter((x) => x.date > addDays(today, -days)).length;
  const span = Math.max(1, daysBetween(first, today) + 1);
  const weekly = (n: number, days: number) => (n / (days / 7)).toFixed(1);
  parts.push(
    `How often they trained (this file only): last 4 weeks ${since(28)} (${weekly(since(28), 28)} a week), last 12 weeks ${since(84)} ` +
      `(${weekly(since(84), 84)} a week), last year ${since(365)} (${weekly(since(365), Math.min(365, span))} a week), ` +
      `all of it ${w.length} over ${Math.round(span / 7)} weeks (${weekly(w.length, span)} a week).`,
  );
  const months = new Map<string, number>();
  for (const x of w) months.set(x.date.slice(0, 7), (months.get(x.date.slice(0, 7)) ?? 0) + 1);
  const lastMonths = [...months.entries()].sort((a, b) => a[0].localeCompare(b[0])).slice(-12);
  parts.push(`Workouts per month (last 12 with any): ${lastMonths.map(([m, n]) => `${m} ${n}`).join(", ")}.`);
  const sessions = new Map<string, { name: string; n: number }>();
  for (const x of w) {
    for (const e of x.exercises) {
      const k = e.name.toLowerCase();
      const s = sessions.get(k) ?? { name: e.name, n: 0 };
      s.n++;
      sessions.set(k, s);
    }
  }
  const top = [...sessions.values()].sort((a, b) => b.n - a.n).slice(0, 8);
  parts.push(`Most logged: ${top.map((s) => `${s.name} ${s.n}×`).join(", ")}.`);
  parts.push("get_training now includes the imported workouts (up to a year back); for older history use the totals above.");
  return parts.join(" ");
}

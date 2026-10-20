// Training: the user's routines (plans of exercises with target sets, reps and weights) and
// the workouts they log in the app set by set, next to the workouts the band records
// (fs_exercise). The app's Training tab shows all three; the coach reads them and can save
// routines (created_by "coach").

import * as db from "./db.ts";
import { exerciseMuscles, LIBRARY, muscleList, type MuscleId, MUSCLES, muscleSets } from "./exercises.ts";
import { addDays, type Ymd } from "./util.ts";

type Row = Record<string, unknown>;

export const EXERCISE_KINDS = ["strength", "cardio", "mobility", "other"] as const;
export type ExerciseKind = typeof EXERCISE_KINDS[number];

export interface RoutineExercise {
  name: string;
  kind: ExerciseKind;
  /** Planned sets. */
  sets: number | null;
  /** Planned reps per set as written: "8", "8-12", "AMRAP". */
  reps: string | null;
  weight_kg: number | null;
  /** Cardio, or a timed hold. */
  duration_min: number | null;
  distance_km: number | null;
  rest_s: number | null;
  notes: string | null;
  /** Muscles chosen for an exercise outside the library (exercises.ts); null = the library's. */
  muscles?: MuscleId[] | null;
}

export interface Routine {
  id: string;
  name: string;
  notes: string | null;
  exercises: RoutineExercise[];
  created_by: "user" | "coach";
  position: number;
  created_at: string;
  updated_at: string;
}

export interface LoggedSet {
  reps: number | null;
  weight_kg: number | null;
  duration_min: number | null;
  distance_km: number | null;
  done: boolean;
}

export interface LoggedExercise {
  name: string;
  kind: ExerciseKind;
  sets: LoggedSet[];
  notes: string | null;
  /** As RoutineExercise.muscles. */
  muscles?: MuscleId[] | null;
}

export interface WorkoutLog {
  id: string;
  date: Ymd;
  started_at: string | null;
  ended_at: string | null;
  /** The routine it was started from, if any. */
  routine_id: string | null;
  name: string;
  exercises: LoggedExercise[];
  notes: string | null;
  /** How hard it felt, 1–10. */
  effort: number | null;
  created_at: string;
  updated_at: string;
}

export class TrainingInputError extends Error {}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const YMD = /^\d{4}-\d{2}-\d{2}$/;
const MAX_EXERCISES = 40;
const MAX_SETS = 30;
/** Logged workouts the app and the coach get, by date. */
export const LOG_DAYS = 365;
/** Band workouts listed in the Training tab. */
export const BAND_DAYS = 120;

function text(v: unknown, max: number): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim().replace(/[ \t]+/g, " ").slice(0, max);
  return t || null;
}

/** A finite number within [min, max], rounded to `decimals`; anything else is null. */
function number(v: unknown, min: number, max: number, decimals = 0): number | null {
  const n = typeof v === "number" ? v : typeof v === "string" && v.trim() ? Number(v.replace(",", ".")) : NaN;
  if (!Number.isFinite(n) || n < min || n > max) return null;
  const f = 10 ** decimals;
  return Math.round(n * f) / f;
}

function kind(v: unknown): ExerciseKind {
  return EXERCISE_KINDS.includes(v as ExerciseKind) ? v as ExerciseKind : "strength";
}

function isoOrNull(v: unknown): string | null {
  if (typeof v !== "string" || !v) return null;
  const t = Date.parse(v);
  return Number.isFinite(t) ? new Date(t).toISOString() : null;
}

function exercisesFrom<T>(v: unknown, one: (e: Row) => T | null): T[] {
  if (!Array.isArray(v)) throw new TrainingInputError("exercises must be a list");
  if (v.length > MAX_EXERCISES) throw new TrainingInputError(`at most ${MAX_EXERCISES} exercises`);
  return v.flatMap((e) => {
    if (!e || typeof e !== "object") return [];
    const out = one(e as Row);
    return out ? [out] : [];
  });
}

export function normalizeRoutineExercise(e: Row): RoutineExercise | null {
  const name = text(e.name, 80);
  if (!name) return null;
  return {
    name,
    kind: kind(e.kind),
    sets: number(e.sets, 1, MAX_SETS),
    reps: text(e.reps === undefined || e.reps === null ? null : String(e.reps), 20),
    weight_kg: number(e.weight_kg, 0, 2000, 2),
    duration_min: number(e.duration_min, 0, 1440, 1),
    distance_km: number(e.distance_km, 0, 1000, 2),
    rest_s: number(e.rest_s, 0, 3600),
    notes: text(e.notes, 300),
    muscles: muscleList(e.muscles),
  };
}

export function normalizeLoggedExercise(e: Row): LoggedExercise | null {
  const name = text(e.name, 80);
  if (!name) return null;
  const sets = Array.isArray(e.sets) ? e.sets : [];
  if (sets.length > MAX_SETS) throw new TrainingInputError(`at most ${MAX_SETS} sets per exercise`);
  return {
    name,
    kind: kind(e.kind),
    sets: sets.filter((s) => s && typeof s === "object").map((s) => {
      const r = s as Row;
      return {
        reps: number(r.reps, 0, 1000),
        weight_kg: number(r.weight_kg, 0, 2000, 2),
        duration_min: number(r.duration_min, 0, 1440, 1),
        distance_km: number(r.distance_km, 0, 1000, 2),
        done: r.done !== false,
      };
    }),
    notes: text(e.notes, 300),
    muscles: muscleList(e.muscles),
  };
}

/** A routine from the app or the coach. A new one gets an id; an existing one keeps who made it. */
export function normalizeRoutine(input: Row, existing: Routine | null, by: "user" | "coach", now: string, position = 0): Routine {
  const name = text(input.name, 80);
  if (!name) throw new TrainingInputError("a routine needs a name");
  return {
    id: existing?.id ?? crypto.randomUUID(),
    name,
    notes: text(input.notes, 1000),
    exercises: exercisesFrom(input.exercises ?? [], normalizeRoutineExercise),
    created_by: existing?.created_by ?? by,
    position: number(input.position, 0, 10_000) ?? existing?.position ?? position,
    created_at: existing?.created_at ?? now,
    updated_at: now,
  };
}

/** A logged workout from the app: a day that is not in the future, and at least one exercise. */
export function normalizeLog(input: Row, existing: WorkoutLog | null, today: Ymd, now: string): WorkoutLog {
  const date = String(input.date ?? "");
  if (!YMD.test(date) || date > today) throw new TrainingInputError("date must be a YYYY-MM-DD day that is not in the future");
  const exercises = exercisesFrom(input.exercises ?? [], normalizeLoggedExercise);
  if (!exercises.length) throw new TrainingInputError("a workout needs at least one exercise");
  const routineId = typeof input.routine_id === "string" && UUID.test(input.routine_id) ? input.routine_id : null;
  return {
    id: existing?.id ?? crypto.randomUUID(),
    date,
    started_at: isoOrNull(input.started_at),
    ended_at: isoOrNull(input.ended_at),
    routine_id: routineId,
    name: text(input.name, 80) ?? "Workout",
    exercises,
    notes: text(input.notes, 1000),
    effort: number(input.effort, 1, 10),
    created_at: existing?.created_at ?? now,
    updated_at: now,
  };
}

// ----------------------------------------------------------------- storage

export async function loadRoutines(): Promise<Routine[]> {
  const rows = await db.select<Routine>("fs_routines", "select=*&order=position.asc");
  return rows.map((r) => ({ ...r, exercises: Array.isArray(r.exercises) ? r.exercises : [] }))
    .sort((a, b) => a.position - b.position || String(a.created_at).localeCompare(String(b.created_at)));
}

export async function loadLogs(from: Ymd, to?: Ymd): Promise<WorkoutLog[]> {
  const until = to ? `&date=lte.${to}` : "";
  const rows = await db.select<WorkoutLog>("fs_workout_logs", `select=*&date=gte.${from}${until}&order=date.desc`);
  return rows.map((r) => ({ ...r, exercises: Array.isArray(r.exercises) ? r.exercises : [] }))
    .sort((a, b) => b.date.localeCompare(a.date) || String(b.started_at ?? b.created_at).localeCompare(String(a.started_at ?? a.created_at)));
}

/**
 * What the Training tab shows: routines, logged workouts, the band's workouts, and the exercise
 * library (which muscles each exercise works).
 */
export async function trainingData(today: Ymd): Promise<Row> {
  const [routines, logs, band] = await Promise.all([
    loadRoutines(),
    loadLogs(addDays(today, -LOG_DAYS)),
    db.select<Row>("fs_exercise", `select=*&date=gte.${addDays(today, -BAND_DAYS)}&order=start_time.desc`),
  ]);
  return { routines, logs, band_workouts: band, library: { muscles: MUSCLES, exercises: LIBRARY } };
}

export async function saveRoutine(input: Row, by: "user" | "coach"): Promise<Routine> {
  const id = typeof input.id === "string" && UUID.test(input.id) ? input.id : null;
  const all = await loadRoutines();
  const existing = id ? all.find((r) => r.id === id) ?? null : null;
  if (id && !existing && by === "coach") throw new TrainingInputError(`no routine with id ${id}; leave id out to make a new one`);
  const position = existing ? existing.position : (all.at(-1)?.position ?? -1) + 1;
  const routine = normalizeRoutine(input, existing, by, new Date().toISOString(), position);
  await db.upsert("fs_routines", [routine as unknown as Row], "id");
  return routine;
}

export async function deleteRoutine(id: string): Promise<void> {
  if (!UUID.test(id)) throw new TrainingInputError("id must be a UUID");
  await db.remove("fs_routines", `id=eq.${id}`);
}

/** Saves the routines' order: `ids` first to last. */
export async function reorderRoutines(ids: unknown): Promise<void> {
  if (!Array.isArray(ids) || ids.some((id) => typeof id !== "string" || !UUID.test(id))) {
    throw new TrainingInputError("ids must be a list of routine ids");
  }
  const now = new Date().toISOString();
  for (const [position, id] of (ids as string[]).entries()) {
    await db.update("fs_routines", `id=eq.${id}`, { position, updated_at: now });
  }
}

export async function saveLog(input: Row, today: Ymd): Promise<WorkoutLog> {
  const id = typeof input.id === "string" && UUID.test(input.id) ? input.id : null;
  const existing = id ? await db.selectOne<WorkoutLog>("fs_workout_logs", `select=*&id=eq.${id}`) : null;
  const log = normalizeLog(input, existing, today, new Date().toISOString());
  await db.upsert("fs_workout_logs", [log as unknown as Row], "id");
  return log;
}

export async function deleteLog(id: string): Promise<void> {
  if (!UUID.test(id)) throw new TrainingInputError("id must be a UUID");
  await db.remove("fs_workout_logs", `id=eq.${id}`);
}

// ----------------------------------------------------------- for the coach

/** "; works quads, glutes (helps: hamstrings)", or nothing for an exercise the library doesn't know. */
function musclesText(name: string, chosen?: MuscleId[] | null): string {
  const m = exerciseMuscles(name, chosen);
  if (!m.primary.length && !m.secondary.length) return "";
  return `; works ${m.primary.join(", ") || "—"}${m.secondary.length ? ` (helps: ${m.secondary.join(", ")})` : ""}`;
}

/** Sets per muscle, rounded to halves, largest first. */
export function muscleSetsText(logs: WorkoutLog[]): Row {
  const sets = muscleSets(logs);
  return Object.fromEntries(Object.entries(sets).sort((a, b) => b[1] - a[1]).map(([k, v]) => [k, Math.round(v * 2) / 2]));
}

/** "3×8 @ 60 kg", "5 km in 25 min", one set's or a plan's numbers in words. */
function setText(s: { reps?: number | string | null; weight_kg?: number | null; duration_min?: number | null; distance_km?: number | null }): string {
  const parts: string[] = [];
  if (s.reps !== null && s.reps !== undefined && s.reps !== "") parts.push(`${s.reps} reps`);
  if (s.weight_kg !== null && s.weight_kg !== undefined) parts.push(`${s.weight_kg} kg`);
  if (s.distance_km !== null && s.distance_km !== undefined) parts.push(`${s.distance_km} km`);
  if (s.duration_min !== null && s.duration_min !== undefined) parts.push(`${s.duration_min} min`);
  return parts.join(" × ") || "done";
}

export function routineText(r: Routine): string {
  const ex = r.exercises.map((e) => {
    const plan = [
      e.sets ? `${e.sets} sets` : "",
      e.reps ? `of ${e.reps}` : "",
      e.weight_kg !== null ? `@ ${e.weight_kg} kg` : "",
      e.duration_min !== null ? `${e.duration_min} min` : "",
      e.distance_km !== null ? `${e.distance_km} km` : "",
      e.rest_s !== null ? `rest ${e.rest_s} s` : "",
    ].filter(Boolean).join(" ");
    return `${e.name} (${e.kind}${plan ? `: ${plan}` : ""}${e.notes ? `; ${e.notes}` : ""}${musclesText(e.name, e.muscles)})`;
  });
  return `${r.name}${r.created_by === "coach" ? " [made by you, the coach]" : ""}: ${ex.join("; ") || "no exercises"}${r.notes ? ` — ${r.notes}` : ""}`;
}

export function logText(l: WorkoutLog): string {
  const minutes = l.started_at && l.ended_at ? Math.round((Date.parse(l.ended_at) - Date.parse(l.started_at)) / 60000) : null;
  const ex = l.exercises.map((e) => {
    const done = e.sets.filter((s) => s.done);
    return `${e.name}: ${done.length ? done.map(setText).join(", ") : "no sets done"}${e.notes ? ` (${e.notes})` : ""}`;
  });
  const extras = [minutes !== null && minutes > 0 ? `${minutes} min` : "", l.effort ? `effort ${l.effort}/10` : ""].filter(Boolean).join(", ");
  return `${l.date} ${l.name}${extras ? ` (${extras})` : ""}: ${ex.join("; ")}${l.notes ? ` — ${l.notes}` : ""}`;
}

/** Per exercise name: sessions logged, the best set (heaviest weight, then most reps) with its date, and the last session. */
export function exerciseProgress(logs: WorkoutLog[]): Row[] {
  const byName = new Map<string, { name: string; sessions: number; best: Row | null; last: Row | null }>();
  for (const l of [...logs].sort((a, b) => a.date.localeCompare(b.date))) {
    for (const e of l.exercises) {
      const key = e.name.toLowerCase();
      const entry = byName.get(key) ?? { name: e.name, sessions: 0, best: null, last: null };
      const done = e.sets.filter((s) => s.done);
      if (!done.length) continue;
      entry.sessions++;
      for (const s of done) {
        const better = !entry.best ||
          (s.weight_kg ?? -1) > Number(entry.best.weight_kg ?? -1) ||
          ((s.weight_kg ?? -1) === Number(entry.best.weight_kg ?? -1) && (s.reps ?? -1) > Number(entry.best.reps ?? -1));
        if (better) entry.best = { date: l.date, reps: s.reps, weight_kg: s.weight_kg, duration_min: s.duration_min, distance_km: s.distance_km };
      }
      const volume = done.reduce((sum, s) => sum + (s.reps ?? 0) * (s.weight_kg ?? 0), 0);
      entry.last = { date: l.date, sets: done.map(setText), volume_kg: volume || null };
      byName.set(key, entry);
    }
  }
  return [...byName.values()].sort((a, b) => b.sessions - a.sessions);
}

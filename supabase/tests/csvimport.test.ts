// Workout CSVs from other apps: Strong, Hevy, one row per workout, and files that can't be read.
// Run: node --experimental-strip-types --test supabase/tests/csvimport.test.ts
import assert from "node:assert/strict";
import { test } from "node:test";

import { tables } from "./fakes.ts";

const csv = await import("../functions/fitstats/lib/csvimport.ts");
const TODAY = "2026-10-20";
const TZ = "Europe/Budapest";

const STRONG = `Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
2026-10-14 18:02:11,"Push Day",1h 5m,"Bench Press (Barbell)",W,40,10,0,0,"","Felt strong",
2026-10-14 18:02:11,"Push Day",1h 5m,"Bench Press (Barbell)",1,80,5,0,0,"pause reps","Felt strong",
2026-10-14 18:02:11,"Push Day",1h 5m,"Bench Press (Barbell)",2,"82,5",5,0,0,"","Felt strong",
2026-10-14 18:02:11,"Push Day",1h 5m,"Running",1,0,0,2.5,900,"","Felt strong",
2026-10-16 07:30:00,"Legs",50m,"Squat (Barbell)",1,100,5,0,0,"","",
2026-10-16 07:30:00,"Legs",50m,"Squat (Barbell)",2,100,5,0,0,"","",
2027-01-01 07:30:00,"Legs",50m,"Squat (Barbell)",1,100,5,0,0,"","",
`;

const HEVY = `"title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_km","duration_seconds","rpe"
"Upper","15 Oct 2026, 17:00","15 Oct 2026, 18:10","","Pull Up","","","0","warmup","","5","","",""
"Upper","15 Oct 2026, 17:00","15 Oct 2026, 18:10","","Pull Up","","","1","normal","","8","","",""
"Upper","15 Oct 2026, 17:00","15 Oct 2026, 18:10","","Bench Press (Dumbbell)","","","0","normal","30","10","","",""
"Upper","15 Oct 2026, 17:00","15 Oct 2026, 18:10","","Plank","","","0","normal","","","","60",""
`;

const APPLE = `Workout Type;Start;End;Duration;Active Energy (kcal);Distance (km);Avg. Heart Rate (bpm)
Running;2026-10-12 07:00:00;2026-10-12 07:35:00;00:35:00;380;6,1;152
Traditional Strength Training;2026-10-13 18:00:00;2026-10-13 19:00:00;01:00:00;300;;120
`;

test("csv: a Strong export, set by set, with warm-ups left out", async () => {
  const r = await csv.readWorkoutCsv({ name: "strong.csv", text: STRONG }, TZ, TODAY);
  assert.equal(r.error, null);
  assert.equal(r.format, "a Strong export");
  assert.equal(r.workouts.length, 2);
  assert.deepEqual([r.warmups, r.future], [1, 1]);
  assert.deepEqual(r.assumed, ["weights in kg"]);
  const push = r.workouts[0];
  assert.deepEqual([push.date, push.name, push.started_at, push.ended_at], ["2026-10-14", "Push Day", "2026-10-14T16:02:11.000Z", "2026-10-14T17:07:11.000Z"]);
  assert.match(String(push.notes), /^Imported from strong\.csv · Felt strong$/);
  const [bench, run] = push.exercises;
  assert.equal(bench.name, "Bench Press (Barbell)");
  assert.deepEqual(bench.sets.map((s) => [s.weight_kg, s.reps]), [[80, 5], [82.5, 5]], "a decimal comma works too");
  assert.equal(bench.notes, "pause reps");
  assert.deepEqual([run.kind, run.sets[0].distance_km, run.sets[0].duration_min], ["cardio", 2.5, 15]);

  // The same file gives the same ids, so a second import updates instead of duplicating.
  const again = await csv.readWorkoutCsv({ name: "strong.csv", text: STRONG }, TZ, TODAY);
  assert.deepEqual(again.workouts.map((w) => w.id), r.workouts.map((w) => w.id));
  assert.match(r.workouts[0].id, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
});

test("csv: a Hevy export and the library's muscles for its exercise names", async () => {
  const r = await csv.readWorkoutCsv({ name: "hevy.csv", text: HEVY }, TZ, TODAY);
  assert.equal(r.format, "a Hevy export");
  assert.equal(r.warmups, 1);
  const w = r.workouts[0];
  assert.deepEqual([w.date, w.started_at, w.ended_at], ["2026-10-15", "2026-10-15T15:00:00.000Z", "2026-10-15T16:10:00.000Z"]);
  assert.deepEqual(w.exercises.map((e) => [e.name, e.kind, e.sets.length]), [["Pull Up", "strength", 1], ["Bench Press (Dumbbell)", "strength", 1], ["Plank", "strength", 1]]);
  assert.equal(w.exercises[2].sets[0].duration_min, 1);
  const { exerciseMuscles } = await import("../functions/fitstats/lib/exercises.ts");
  assert.ok(exerciseMuscles("Bench Press (Dumbbell)").primary.includes("chest"), "\"Name (Equipment)\" is found in the library");
});

test("csv: one row per workout, semicolons, durations and notes", async () => {
  const r = await csv.readWorkoutCsv({ name: "apple.csv", text: APPLE }, TZ, TODAY);
  assert.equal(r.format, "one row per workout");
  assert.equal(r.workouts.length, 2);
  const [run, lift] = r.workouts;
  assert.deepEqual([run.name, run.exercises[0].kind, run.exercises[0].sets[0].duration_min, run.exercises[0].sets[0].distance_km], ["Running", "cardio", 35, 6.1]);
  assert.match(String(run.notes), /380 kcal, avg heart rate 152 bpm/);
  assert.equal(lift.exercises[0].sets[0].duration_min, 60);
});

test("csv: dates, durations and files that can't be read", () => {
  assert.deepEqual(csv.parseWhen("2024. 01. 15. 7:30:00", "UTC", true), { date: "2024-01-15", iso: "2024-01-15T07:30:00.000Z" });
  assert.deepEqual(csv.parseWhen("Jan 15, 2024 at 7:30 PM", "UTC", true), { date: "2024-01-15", iso: "2024-01-15T19:30:00.000Z" });
  assert.deepEqual(csv.parseWhen("03/04/2024 08:00", "UTC", false), { date: "2024-03-04", iso: "2024-03-04T08:00:00.000Z" });
  assert.deepEqual(csv.parseWhen("03/04/2024", "UTC", true), { date: "2024-04-03", iso: null });
  assert.deepEqual(csv.parseWhen("2024-01-15T23:30:00Z", TZ, true), { date: "2024-01-16", iso: "2024-01-15T23:30:00.000Z" });
  assert.equal(csv.parseWhen("yesterday", TZ, true), null);
  assert.deepEqual(["1h 5m", "45m", "1:05:00", "35:10", "3900", "90"].map((d) => csv.durationMinutes(d)), [65, 45, 65, 35 + 10 / 60, 65, 90]);

  assert.equal(typeof csv.parseFiles([{ name: "a.csv", text: "" }]), "string");
  assert.equal(typeof csv.parseFiles("nope"), "string");
  assert.deepEqual(csv.parseFiles(undefined), []);
});

test("csv: what the coach is told", async () => {
  const bad = await csv.readWorkoutCsv({ name: "notes.csv", text: "foo,bar\n1,2\n" }, TZ, TODAY);
  assert.match(String(bad.error), /no date or start-time column/);
  assert.match(csv.importSummary(bad, TODAY), /^FitStats couldn't read workouts from notes\.csv: .*Its first lines:\nfoo,bar\n1,2/s);

  const r = await csv.importWorkoutCsv({ name: "strong.csv", text: STRONG }, TZ, TODAY);
  assert.equal(tables.fs_workout_logs.length, 2);
  await csv.importWorkoutCsv({ name: "strong.csv", text: STRONG }, TZ, TODAY);
  assert.equal(tables.fs_workout_logs.length, 2, "importing again doesn't duplicate");
  const text = csv.importSummary(r, TODAY);
  assert.match(text, /^FitStats read strong\.csv \(a Strong export\) and saved 2 workouts from 2026-10-14 to 2026-10-16 to their Training log/);
  assert.match(text, /Assumed: weights in kg\. Left out: 1 warm-up sets, 1 rows dated in the future\./);
  assert.match(text, /last 4 weeks 2 \(0\.5 a week\)/);
  assert.match(text, /Workouts per month \(last 12 with any\): 2026-10 2\./);
  assert.match(text, /Most logged: Bench Press \(Barbell\) 1×, Running 1×, Squat \(Barbell\) 1×\./);
  tables.fs_workout_logs.length = 0;
});

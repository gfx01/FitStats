// Coach end to end: a real sync fills the in-memory database, then chat and
// briefing requests run against the fake streaming Claude API.
// Run: node --experimental-strip-types --test supabase/tests/coach.test.ts
import assert from "node:assert/strict";
import { before, test } from "node:test";

import { claudeFailures, claudeRequests, env, FAKE_ROUTINE, NAP_MAIN_DAY, type Row, tables } from "./fakes.ts";

const coach = await import("../functions/fitstats/lib/coach.ts");

async function events(res: Response): Promise<Row[]> {
  assert.equal(res.headers.get("content-type"), "text/event-stream; charset=utf-8");
  const text = await res.text();
  return text.split("\n\n").filter((b) => b.startsWith("data: ")).map((b) => JSON.parse(b.slice(6)) as Row);
}

function post(body: unknown): Request {
  return new Request("https://example.supabase.co/functions/v1/fitstats?r=coach", { method: "POST", body: JSON.stringify(body) });
}

before(async () => {
  const { runSync } = await import("../functions/fitstats/lib/sync.ts");
  const log = await runSync("test", true, 95_000);
  assert.equal(log.status, "ok");
});

test("chat: tool round trip, streamed reply, saved thread and usage", async () => {
  const evs = await events(await coach.handleCoach(post({ message: "How has my sleep been this week, and is it affecting my HRV?" })));
  const status = evs.filter((e) => e.type === "status").map((e) => e.text);
  assert.equal(status.length, 1);
  assert.match(String(status[0]), /^Looking at HRV \(RMSSD\) and time asleep, \w{3} \d+ – \w{3} \d+$/);
  const streamed = evs.filter((e) => e.type === "text").map((e) => e.text).join("");
  assert.match(streamed, /^Let me look at your last week\.\n\nYour HRV averaged \*\*\d+ ms\*\*/);
  const done = evs.at(-1)!;
  assert.equal(done.type, "done", JSON.stringify(evs.filter((e) => e.type === "error")));

  // First request: cached system prompt with the data summary, tools, medium effort.
  const first = claudeRequests[0];
  assert.equal(first.model, "claude-sonnet-5-5");
  assert.equal((first.output_config as Row).effort, "medium");
  assert.deepEqual((first.tools as Row[]).map((t) => t.name), ["get_daily_metrics", "get_metric_stats", "get_day", "get_workouts", "get_training", "save_routine", "get_journal"]);
  const system = first.system as Row[];
  assert.deepEqual(system[1].cache_control, { type: "ephemeral" });
  assert.match(String(system[1].text), /Last 14 days/);
  assert.match(String(system[1].text), /HRV \(RMSSD\): \d+ ms/);
  assert.equal(first.tool_choice, undefined);

  const threads = tables.fs_coach_threads;
  assert.equal(threads.length, 1);
  assert.equal(threads[0].id, done.thread_id);
  assert.equal(threads[0].title, "How has my sleep been this week, and is it affecting my HRV?");
  const msgs = tables.fs_coach_messages.filter((m) => m.thread_id === done.thread_id);
  assert.deepEqual(msgs.map((m) => m.role), ["user", "assistant"]);
  assert.ok(String(msgs[0].created_at) < String(msgs[1].created_at));
  assert.equal(msgs[1].content, streamed.trim());
  assert.equal(msgs[1].id, done.message_id);

  const usage = done.usage as Row;
  assert.equal(usage.requests, 2);
  assert.equal(usage.cache_write, 5200);
  assert.equal(usage.cache_read, 5200);
  // 40×2 + 5200×2.5 + 1400×2 + 5200×0.1 + (210+140)×10, per million tokens
  assert.equal(usage.cost_usd, 0.0199);
  const saved = tables.fs_cache.find((c) => c.key === "coach_usage")!.value as Row;
  assert.equal(saved.day_requests, 1);
  assert.equal(saved.requests, 2);
});

test("chat: follow-up sends the thread history", async () => {
  const thread = tables.fs_coach_threads[0].id as string;
  claudeRequests.length = 0;
  const evs = await events(await coach.handleCoach(post({ message: "And what about this weekend?", thread_id: thread })));
  assert.equal(evs.at(-1)!.type, "done");
  const msgs = claudeRequests[0].messages as Row[];
  assert.deepEqual(msgs.map((m) => m.role), ["user", "assistant", "user"]);
  assert.equal(msgs[2].content, "And what about this weekend?");
  assert.equal(tables.fs_coach_messages.filter((m) => m.thread_id === thread).length, 4);

  const listed = await coach.coachThreads();
  assert.equal((listed.threads as Row[]).length, 1);
  const detail = await (await coach.coachThread(thread)).json() as Row;
  assert.equal((detail.messages as Row[]).length, 4);
});

test("briefing: cached for today", async () => {
  const evs = await events(await coach.handleCoach(post({ kind: "brief" })));
  const done = evs.at(-1)!;
  assert.equal(done.type, "done");
  const brief = done.brief as Row;
  assert.match(String(brief.text), /^\*\*Recovery\*\* \d+/);
  assert.match(String(brief.text), /\*\*Today\*\* Aim for strain \d+–\d+/);
  const cached = await coach.coachBrief();
  assert.deepEqual(cached.brief, brief);
});

test("errors: bad key, unknown thread, missing key, bad input", async () => {
  claudeFailures.push(401);
  const evs = await events(await coach.handleCoach(post({ message: "Hi" })));
  assert.deepEqual(evs.map((e) => e.type), ["error"]);
  assert.equal(evs[0].code, "invalid_api_key");

  const missing = await coach.handleCoach(post({ message: "Hi", thread_id: "00000000-0000-4000-8000-000000000000" }));
  assert.equal(missing.status, 404);

  const empty = await coach.handleCoach(post({ message: "   " }));
  assert.equal(empty.status, 400);

  delete env.ANTHROPIC_API_KEY;
  const notConfigured = await coach.handleCoach(post({ message: "Hi" }));
  assert.equal(notConfigured.status, 503);
  assert.equal(((await notConfigured.json()) as Row).error, "coach_not_configured");
  env.ANTHROPIC_API_KEY = "sk-ant-test";
});

test("tools: validation and data", async () => {
  const ctx = { acc: tables.fs_account[0] as never, settings: tables.fs_user_settings[0] as never, today: "2026-10-18", tz: "Europe/Budapest" };
  await assert.rejects(coach.runTool("get_daily_metrics", { from: "2026-01-01", to: "2027-06-01", metrics: ["steps"] }, ctx, null), /400 days/);
  await assert.rejects(coach.runTool("get_daily_metrics", { from: "2026-10-01", to: "2026-10-18", metrics: ["nope"] }, ctx, null), /unknown metrics: nope/);
  const day = await coach.runTool("get_day", { date: "2026-10-15" }, ctx, null) as Row;
  assert.equal((day.hourly_heart_rate as unknown[]).length, 24);
  assert.ok((day.sleep_sessions as Row[]).length >= 1);
  assert.match(String((day.sleep_sessions as Row[])[0].start), /^\d{2}:\d{2}$/);
  // The afternoon nap Google also flags as main sleep is a nap here too; the night is the main sleep.
  const napSessions = (await coach.runTool("get_day", { date: NAP_MAIN_DAY }, ctx, null) as Row).sleep_sessions as Row[];
  assert.deepEqual(napSessions.map((s) => [s.main, s.nap]), [[true, false], [false, true]]);
  assert.deepEqual([napSessions[1].start, napSessions[1].awakenings, napSessions[1].awake_after_falling_asleep_min], ["17:13", 0, 0]);
  const workouts = (await coach.runTool("get_workouts", { from: "2026-08-20", to: "2026-10-18" }, ctx, null) as Row).workouts as Row[];
  assert.ok(workouts.some((w) => typeof w.hrr_1min === "number" && typeof w.hrr_2min === "number"), "heart-rate recovery of the runs");
  const empty = await coach.runTool("get_day", { date: "2026-01-01" }, ctx, null) as Row;
  assert.equal(empty.note, "Nothing was recorded on this date.");
});

test("delete removes the thread and its messages", async () => {
  const thread = tables.fs_coach_threads[0].id as string;
  await coach.coachDelete(thread);
  assert.equal(tables.fs_coach_threads.length, 0);
  assert.equal(tables.fs_coach_messages.filter((m) => m.thread_id === thread).length, 0);
});

test("context: journal entries, tag effects and tonight's sleep plan", async () => {
  const { saveJournalEntry } = await import("../functions/fitstats/lib/journal.ts");
  const { clockFor } = await import("../functions/fitstats/lib/sync.ts");
  const today = clockFor(tables.fs_account[0] as never).today();
  const yesterday = new Date(Date.parse(`${today}T00:00:00Z`) - 86_400_000).toISOString().slice(0, 10);
  await saveJournalEntry({ date: yesterday, tags: ["Alcohol", "late meal"], note: "Birthday dinner" }, today);
  const before = claudeRequests.length;
  const evs = await events(await coach.handleCoach(post({ message: "Why did I sleep badly?" })));
  assert.equal(evs.at(-1)!.type, "done", JSON.stringify(evs.filter((e) => e.type === "error")));
  const text = String((claudeRequests[before].system as Row[])[1].text);
  assert.match(text, /journal: Alcohol, Late meal; note "Birthday dinner"/);
  assert.match(text, /Tonight's sleep plan \(FitStats' rule, shown in the app\): need tonight \d+h \d+m \(base 8h 0m/);
  assert.doesNotMatch(text, /sleep need \d+h \d+m \(/, "the plan's total is never called the sleep need");
  assert.match(text, /in bed by \d\d:\d\d to wake at \d\d:\d\d/);
  assert.match(text, /\nTraining load \(shown in the app\) up to \d{4}-\d{2}-\d{2}: fitness [\d.]+, fatigue [\d.]+, form [+−]?[\d.]+, so (fresh|neutral|productive|overreaching); load ratio [\d.]+\./);
  assert.match(text, /\nBedtime vs sleep \(shown in the app; last \d+ scored nights\): best \d\d:\d\d–\d\d:\d\d, sleep score [+−][\d.]+ vs all other nights \((clear|not clear)\)\. By bedtime: .*\d+ nights \(sleep score \d+, asleep \d+h \d+m, recovery \d+\)/);
  const instructions = String((claudeRequests[before].system as Row[])[0].text);
  assert.match(instructions, /- Training load \(shown in the app\): fitness is the 42-day/);
  assert.match(instructions, /- Heart-rate recovery \(per workout\)/);
});

test("training: the app saves routines and workouts, the coach reads them and saves a routine", async () => {
  const training = await import("../functions/fitstats/lib/training.ts");
  const ctx = { acc: tables.fs_account[0] as never, settings: tables.fs_user_settings[0] as never, today: "2026-10-18", tz: "Europe/Budapest" };
  const mine = await training.saveRoutine({ name: "Legs", exercises: [{ name: "Squat", kind: "strength", sets: 5, reps: "5", weight_kg: 80 }] }, "user");
  await training.saveLog({
    date: "2026-10-17", name: "Legs", routine_id: mine.id, effort: 8,
    exercises: [{ name: "Squat", kind: "strength", sets: [{ reps: 5, weight_kg: 80 }, { reps: 5, weight_kg: 85 }] }],
  }, "2026-10-18");
  await assert.rejects(training.saveLog({ date: "2026-10-19", exercises: [{ name: "Squat" }] }, "2026-10-18"), training.TrainingInputError);

  const data = await training.trainingData("2026-10-18");
  assert.deepEqual([(data.routines as Row[]).length, (data.logs as Row[]).length], [1, 1]);
  assert.ok((data.band_workouts as Row[]).length > 0, "the band's workouts of the last 120 days");

  const read = await coach.runTool("get_training", {}, ctx, null) as Row;
  const progress = read.exercise_progress_last_year as Row[];
  assert.deepEqual([progress[0].name, (progress[0].best as Row).weight_kg], ["Squat", 85]);
  const context = await coach.buildContext(ctx, null);
  assert.match(context, /Routine \(id [0-9a-f-]{36}\) Legs: Squat \(strength: 5 sets of 5 @ 80 kg\)/);
  assert.match(context, /Logged 2026-10-17 Legs \(effort 8\/10\): Squat: 5 reps × 80 kg, 5 reps × 85 kg/);
  await assert.rejects(coach.runTool("save_routine", { id: crypto.randomUUID(), name: "X", exercises: [] }, ctx, null), /no routine with id/);

  // The coach makes one; the app hears that training changed and reloads it.
  const evs = await events(await coach.handleCoach(post({ message: "Make me a routine for my upper body" })));
  assert.deepEqual(evs.filter((e) => e.type === "changed"), [{ type: "changed", what: "training" }]);
  assert.ok(evs.some((e) => e.type === "status" && /Saving “Upper body A” to Training/.test(String(e.text))));
  const saved = tables.fs_routines.find((r) => r.name === FAKE_ROUTINE.name)!;
  assert.equal(saved.created_by, "coach");
  assert.deepEqual((saved.exercises as Row[]).map((e) => e.name), ["Bench press", "Bent-over row", "Easy bike"]);
  assert.equal(saved.position, 1, "after the user's routine");
  const reply = evs.filter((e) => e.type === "text").map((e) => e.text).join("");
  assert.match(reply, /I saved \*\*Upper body A\*\* to your Training tab\./);

  await training.reorderRoutines([String(saved.id), mine.id]);
  assert.deepEqual((await training.loadRoutines()).map((r) => r.name), ["Upper body A", "Legs"]);
  await training.deleteRoutine(mine.id);
  assert.deepEqual((await training.loadRoutines()).map((r) => r.name), ["Upper body A"]);
});

// Coach end to end: a real sync fills the in-memory database, then chat and
// briefing requests run against the fake streaming Claude API.
// Run: node --experimental-strip-types --test supabase/tests/coach.test.ts
import assert from "node:assert/strict";
import { before, test } from "node:test";

import { claudeFailures, claudeRequests, env, type Row, tables } from "./fakes.ts";

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
  assert.equal((first.tools as Row[]).length, 4);
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
  const empty = await coach.runTool("get_day", { date: "2026-01-01" }, ctx, null) as Row;
  assert.equal(empty.note, "Nothing was recorded on this date.");
});

test("delete removes the thread and its messages", async () => {
  const thread = tables.fs_coach_threads[0].id as string;
  await coach.coachDelete(thread);
  assert.equal(tables.fs_coach_threads.length, 0);
  assert.equal(tables.fs_coach_messages.filter((m) => m.thread_id === thread).length, 0);
});

// Fake Google Health API, fake Claude API and in-memory PostgREST used by the
// tests and the app screenshot fixtures. Importing this module installs a fake
// global fetch.
import assert from "node:assert/strict";

export type Row = Record<string, unknown>;

const SUPABASE_URL = "https://example.supabase.co";
export const env: Record<string, string> = {
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY: "sb_secret_test",
  GOOGLE_CLIENT_ID: "cid",
  GOOGLE_CLIENT_SECRET: "csecret",
  ANTHROPIC_API_KEY: "sk-ant-test",
};
(globalThis as unknown as { Deno: unknown }).Deno = { env: { get: (k: string) => env[k] } };

// ------------------------------------------------------------ fake PostgREST

export const tables: Record<string, Row[]> = {
  fs_account: [{
    id: 1, token_status: "ok", refresh_token: "refresh-1", access_token: null, access_token_expires_at: null,
    time_zone: null, profile: null, google_settings: null, meta_fetched_at: null, google_sub: "sub", google_email: "me@example.com",
  }],
  fs_user_settings: [{ id: 1, sex: "unspecified", max_hr_override: null, sleep_need_min: 480, step_goal: 10000, backfill_days: 730 }],
  fs_sync_state: [{
    id: 1, backfill_oldest: null, backfill_target: null, backfill_done: false, backfill_empty_chunks: 0,
    last_recent_sync_at: null, recent_fingerprint: null, lock_until: null,
  }],
  fs_days: [], fs_sleep: [], fs_exercise: [], fs_intraday: [], fs_samples: [], fs_cache: [],
  fs_coach_threads: [], fs_coach_messages: [],
};

function matches(row: Row, key: string, expr: string): boolean {
  const v = row[key];
  const s = v === null || v === undefined ? null : String(v);
  const listOf = (e: string) => e.slice(1, -1).split(",").map((x) => x.replace(/^"|"$/g, ""));
  if (expr.startsWith("not.in.")) return s === null || !listOf(expr.slice(7)).includes(s);
  if (expr.startsWith("in.")) return s !== null && listOf(expr.slice(3)).includes(s);
  if (expr === "not.is.null") return s !== null;
  if (expr === "is.null") return s === null;
  const [op, ...rest] = expr.split(".");
  const val = rest.join(".");
  if (s === null) return false;
  switch (op) {
    case "eq": return s === val;
    case "gte": return s >= val;
    case "gt": return s > val;
    case "lte": return s <= val;
    case "lt": return s < val;
    default: throw new Error(`unsupported filter ${expr}`);
  }
}

const RESERVED = new Set(["select", "order", "limit", "offset", "on_conflict"]);

function filterRows(rows: Row[], params: URLSearchParams): Row[] {
  return rows.filter((r) => {
    for (const [k, v] of params) if (!RESERVED.has(k) && !matches(r, k, v)) return false;
    return true;
  });
}

/** "METHOD table" for every write, for assertions. */
export const dbWrites: string[] = [];

function postgrest(url: URL, init: RequestInit): Response {
  const path = url.pathname.replace("/rest/v1/", "");
  const params = url.searchParams;
  const method = init.method ?? "GET";
  if (method !== "GET" && !path.startsWith("rpc/")) dbWrites.push(`${method} ${path}`);
  const hdrs = init.headers as Record<string, string>;
  assert.equal(hdrs.apikey, "sb_secret_test");
  assert.equal(hdrs.Authorization, undefined, "secret keys must not be sent as Bearer tokens");
  if (path === "rpc/fs_try_lock") return Response.json(true);
  if (path === "rpc/fs_unlock") return new Response("", { status: 200 });
  const table = tables[path];
  if (!table) return new Response(`no table ${path}`, { status: 404 });
  const body = init.body ? JSON.parse(String(init.body)) : null;
  if (method === "GET") {
    let rows = filterRows(table, params);
    const order = params.get("order");
    if (order) {
      const [col, dir] = order.split(".");
      rows = [...rows].sort((a, b) => (String(a[col]) < String(b[col]) ? -1 : String(a[col]) > String(b[col]) ? 1 : 0) * (dir === "desc" ? -1 : 1));
    }
    const offset = Number(params.get("offset") ?? 0), limit = Number(params.get("limit") ?? 1000);
    rows = rows.slice(offset, offset + limit);
    const sel = params.get("select");
    if (sel && sel !== "*") {
      const cols = sel.split(",");
      rows = rows.map((r) => Object.fromEntries(cols.map((c) => [c, r[c] ?? null])));
    }
    return Response.json(rows);
  }
  if (method === "POST") {
    const items = body as Row[];
    const keys = Object.keys(items[0] ?? {}).sort().join(",");
    for (const it of items) assert.equal(Object.keys(it).sort().join(","), keys, `${path}: rows in one upsert must share keys`);
    const conflict = params.get("on_conflict");
    for (const it of items) {
      if (conflict) {
        const cols = conflict.split(",");
        const existing = table.find((r) => cols.every((c) => String(r[c]) === String(it[c])));
        if (existing) {
          Object.assign(existing, it);
          continue;
        }
      }
      table.push({ ...it });
    }
    return new Response("", { status: 201 });
  }
  if (method === "PATCH") {
    for (const r of filterRows(table, params)) Object.assign(r, body);
    return new Response(null, { status: 204 });
  }
  if (method === "DELETE") {
    const drop = new Set(filterRows(table, params));
    tables[path] = table.filter((r) => !drop.has(r));
    return new Response(null, { status: 204 });
  }
  throw new Error(`unsupported ${method}`);
}

// --------------------------------------------------------- fake Google APIs

const TZ_OFFSET_S = 7200; // fake data uses fixed CEST wall clock for simplicity
export const calls: string[] = [];
/** Knobs to change what the fake API returns between runs. */
export const fakeData = { extraSteps: 0 };
const ymdParts = (ymd: string) => {
  const [year, month, day] = ymd.split("-").map(Number);
  return { year, month, day };
};
const addDaysLocal = (ymd: string, n: number) => new Date(Date.parse(`${ymd}T00:00:00Z`) + n * 86_400_000).toISOString().slice(0, 10);
const datesBetween = (a: string, b: string) => {
  const out: string[] = [];
  for (let d = a; d < b; d = addDaysLocal(d, 1)) out.push(d);
  return out;
};
const iso = (ms: number) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
const localMs = (ymd: string, hh: number, mm = 0) => Date.parse(`${ymd}T00:00:00Z`) + (hh * 60 + mm) * 60000 - TZ_OFFSET_S * 1000;
const seed = (s: string) => [...s].reduce((a, c) => (a * 31 + c.charCodeAt(0)) % 1000, 7);
export const FIRST_DATA_DAY = "2026-08-20";

function filterDates(filter: string): [string, string] {
  const m = /([\w.]+) >= "([^"]+)" AND [\w.]+ < "([^"]+)"/.exec(filter);
  assert.ok(m, `bad filter ${filter}`);
  return [m![2].slice(0, 10), m![3].slice(0, 10)];
}

function dailyPoint(type: string, date: string): Row | null {
  if (date < FIRST_DATA_DAY) return null;
  const k = seed(date);
  const d = ymdParts(date);
  switch (type) {
    case "daily-resting-heart-rate": return { dailyRestingHeartRate: { date: d, beatsPerMinute: String(54 + (k % 5)) } };
    case "daily-heart-rate-variability": return { dailyHeartRateVariability: { date: d, averageHeartRateVariabilityMilliseconds: 40 + (k % 20), nonRemHeartRateBeatsPerMinute: "52" } };
    case "daily-oxygen-saturation": return { dailyOxygenSaturation: { date: d, averagePercentage: 95 + (k % 3), lowerBoundPercentage: 93, upperBoundPercentage: 98 } };
    case "daily-respiratory-rate": return { dailyRespiratoryRate: { date: d, breathsPerMinute: 14 + (k % 10) / 10 } };
    case "daily-sleep-temperature-derivations": return { dailySleepTemperatureDerivations: { date: d, nightlyTemperatureCelsius: 34 + (k % 7) / 10, baselineTemperatureCelsius: 34.2, relativeNightlyStddev30dCelsius: 0.3 } };
    case "daily-vo2-max": return { dailyVo2Max: { date: d, vo2Max: 46.5, cardioFitnessLevel: "GOOD" } };
    case "daily-heart-rate-zones": return { dailyHeartRateZones: { date: d, heartRateZones: [{ heartRateZoneType: "LIGHT", minBeatsPerMinute: "100", maxBeatsPerMinute: "120" }] } };
    default: return null;
  }
}

function rollupValue(type: string, date: string): Row | null {
  if (date < FIRST_DATA_DAY) return null;
  const k = seed(date);
  switch (type) {
    case "steps": return { steps: { countSum: String(5000 + k * 7 + fakeData.extraSteps) } };
    case "distance": return { distance: { millimetersSum: String((5000 + k * 7) * 750) } };
    case "floors": return { floors: { countSum: String(k % 15) } };
    case "active-zone-minutes": return { activeZoneMinutes: { sumInFatBurnHeartZone: "12", sumInCardioHeartZone: String(k % 30) } };
    case "active-energy-burned": return { activeEnergyBurned: { kcalSum: 400 + k / 2 } };
    case "total-calories": return { totalCalories: { kcalSum: 2200 + k } };
    case "sedentary-period": return { sedentaryPeriod: { durationSum: "30000s" } };
    case "time-in-heart-rate-zone": return { timeInHeartRateZone: { timeInHeartRateZones: [{ heartRateZone: "LIGHT", duration: "5400s" }] } };
    case "heart-rate": {
      const hr = dayHeartRate(date);
      return hr && { heartRate: { beatsPerMinuteMin: hr.min, beatsPerMinuteAvg: hr.avg, beatsPerMinuteMax: hr.max } };
    }
    case "active-minutes": return { activeMinutes: { activeMinutesRollupByActivityLevel: [{ activityLevel: "LIGHT", activeMinutesSum: "180" }] } };
    default: return null; // weight / body-fat: no scale
  }
}

/** ~90-minute cycles: deep sleep early in the night, longer REM towards morning, a few short wakes. */
function sleepStages(start: number, end: number, k: number): { type: string; startTime: string; endTime: string }[] {
  const out: { type: string; startTime: string; endTime: string }[] = [];
  let t = start;
  const push = (type: string, min: number) => {
    const e = Math.min(end, t + min * 60000);
    if (e > t) out.push({ type, startTime: iso(t), endTime: iso(e) });
    t = e;
  };
  push("AWAKE", 6 + (k % 9));
  for (let cycle = 0; t < end; cycle++) {
    push("LIGHT", 22 + ((k + cycle * 7) % 14));
    push("DEEP", Math.max(4, 30 - cycle * 9 + (k % 7)));
    push("LIGHT", 12 + ((k + cycle * 3) % 10));
    push("REM", 9 + cycle * 7 + (k % 7));
    if (cycle % 2 === 1) push("AWAKE", 2 + ((k + cycle) % 5));
  }
  return out;
}

function sleepFor(date: string): Row | null {
  if (date < FIRST_DATA_DAY) return null;
  const k = seed(date);
  const start = localMs(addDaysLocal(date, -1), 22, 50 + (k % 45));
  const end = localMs(date, 6, 40 + (k % 50));
  const stages = sleepStages(start, end, k);
  const minutes: Record<string, number> = {}, counts: Record<string, number> = {};
  for (const st of stages) {
    minutes[st.type] = (minutes[st.type] ?? 0) + (Date.parse(st.endTime) - Date.parse(st.startTime)) / 60000;
    counts[st.type] = (counts[st.type] ?? 0) + 1;
  }
  const inPeriod = Math.round((end - start) / 60000);
  const awake = Math.round(minutes.AWAKE ?? 0);
  return {
    name: `users/me/dataTypes/sleep/dataPoints/s-${date}`,
    sleep: {
      interval: { startTime: iso(start), endTime: iso(end), startUtcOffset: `${TZ_OFFSET_S}s`, endUtcOffset: `${TZ_OFFSET_S}s`, civilEndTime: { date: ymdParts(date) } },
      type: "STAGES",
      metadata: { mainSleep: true, nap: false, processed: true },
      stages,
      summary: {
        minutesAsleep: String(inPeriod - awake),
        minutesInSleepPeriod: String(inPeriod),
        minutesAwake: String(awake),
        minutesToFallAsleep: String(Math.round((Date.parse(stages[0].endTime) - start) / 60000)),
        stagesSummary: ["DEEP", "REM", "LIGHT", "AWAKE"].map((type) => ({
          type, minutes: String(Math.round(minutes[type] ?? 0)), count: String(counts[type] ?? 0),
        })),
      },
    },
  };
}

/** Minute heart rates of one local day (for the day rollup, consistent with the minute data). */
function dayHeartRate(date: string): { min: number; avg: number; max: number } | null {
  const vals: number[] = [];
  for (let t = localMs(date, 0); t < localMs(date, 24); t += 60000) {
    const hr = minuteHr(t);
    if (hr !== null) vals.push(hr);
  }
  if (!vals.length) return null;
  return { min: Math.min(...vals), avg: Math.round(vals.reduce((a, b) => a + b, 0) / vals.length), max: Math.max(...vals) };
}

function minuteHr(ms: number): number | null {
  const local = new Date(ms + TZ_OFFSET_S * 1000);
  const date = local.toISOString().slice(0, 10);
  if (date < FIRST_DATA_DAY) return null;
  const h = local.getUTCHours();
  if (h < 7) return Math.round(52 + 3 * Math.sin((h * 60 + local.getUTCMinutes()) / 37) + (seed(date) % 3));
  if (h === 18 && seed(date) % 3 === 0) return 150 + (local.getUTCMinutes() % 12); // a run every few days
  const m = h * 60 + local.getUTCMinutes();
  return Math.round(70 + 7 * Math.sin(m / 47) + 3 * Math.sin(m / 9) + (seed(date) % 7));
}

function googleFetch(url: URL, init: RequestInit): Response {
  const method = init.method ?? "GET";
  if (url.hostname === "oauth2.googleapis.com") {
    const form = new URLSearchParams(String(init.body));
    assert.equal(form.get("grant_type"), "refresh_token");
    assert.equal(form.get("client_secret"), "csecret");
    return Response.json({ access_token: "access-1", expires_in: 3599 });
  }
  assert.equal(url.hostname, "health.googleapis.com");
  assert.equal((init.headers as Record<string, string>).Authorization, "Bearer access-1");
  const path = url.pathname.replace("/v4/", "");
  calls.push(`${method} ${path}`);
  if (path === "users/me/profile") return Response.json({ age: 31, membershipStartDate: { year: 2026, month: 8, day: 1 } });
  if (path === "users/me/settings") return Response.json({ timeZone: "Europe/Budapest", utcOffset: "7200s" });
  if (path === "users/me/pairedDevices") {
    return Response.json({
      pairedDevices: [{ deviceVersion: "Fitbit Air", deviceType: "TRACKER", batteryLevel: 81, batteryStatus: "High", lastSyncTime: iso(Date.now() - 12 * 60000) }],
    });
  }

  const m = /^users\/me\/dataTypes\/([a-z0-9-]+)\/dataPoints(:\w+)?$/.exec(path);
  assert.ok(m, `unexpected path ${path}`);
  const [, type, op] = m!;
  if (method === "GET") {
    const filter = url.searchParams.get("filter") ?? "";
    const pageSize = Number(url.searchParams.get("pageSize"));
    if (type === "sleep" || type === "exercise") assert.ok(pageSize <= 25, "sleep/exercise pageSize max is 25");
    if (type === "daily-heart-rate-zones") assert.equal(op, ":reconcile");
    const [a, b] = filterDates(filter);
    if (type.startsWith("daily-")) {
      assert.ok(filter.startsWith(`${type.replace(/-/g, "_")}.date >= `), filter);
      return Response.json({ dataPoints: datesBetween(a, b).map((d) => dailyPoint(type, d)).filter(Boolean) });
    }
    if (type === "sleep") {
      assert.ok(filter.startsWith("sleep.interval.civil_end_time >= "), filter);
      return Response.json({ dataPoints: datesBetween(a, b).map(sleepFor).filter(Boolean) });
    }
    if (type === "exercise") {
      assert.ok(filter.startsWith("exercise.interval.civil_start_time >= "), filter);
      const pts = datesBetween(a, b).filter((d) => d >= FIRST_DATA_DAY && seed(d) % 3 === 0).map((d) => ({
        name: `users/me/dataTypes/exercise/dataPoints/e-${d}`,
        exercise: {
          interval: { startTime: iso(localMs(d, 18)), endTime: iso(localMs(d, 19)), startUtcOffset: "7200s", civilStartTime: { date: ymdParts(d) } },
          exerciseType: "RUNNING", displayName: "Run",
          metricsSummary: { caloriesKcal: 600, averageHeartRateBeatsPerMinute: "155", distanceMillimeters: 9000000 },
        },
      }));
      return Response.json({ dataPoints: pts });
    }
    // sample types: physical time filter
    assert.ok(filter.includes(".sample_time.physical_time >= "), filter);
    const sm = /"([^"]+)" AND .* < "([^"]+)"/.exec(filter)!;
    const s = Date.parse(sm[1]), e = Date.parse(sm[2]);
    const pts: Row[] = [];
    for (let t = s; t < e; t += 600_000) {
      const local = new Date(t + TZ_OFFSET_S * 1000);
      if (local.getUTCHours() >= 6 || local.toISOString().slice(0, 10) < FIRST_DATA_DAY) continue;
      const sampleTime = { physicalTime: iso(t), utcOffset: "7200s" };
      const x = t / 600_000;
      if (type === "heart-rate-variability") {
        pts.push({ heartRateVariability: { sampleTime, rootMeanSquareOfSuccessiveDifferencesMilliseconds: Math.round(46 + 9 * Math.sin(x / 5) + 4 * Math.sin(x / 1.7)) } });
      }
      if (type === "oxygen-saturation") pts.push({ oxygenSaturation: { sampleTime, percentage: Math.round((96 + 1.4 * Math.sin(x / 4) + 0.6 * Math.sin(x / 1.3)) * 10) / 10 } });
    }
    return Response.json({ dataPoints: pts });
  }

  const body = JSON.parse(String(init.body));
  if (op === ":dailyRollUp") {
    assert.equal(body.windowSizeDays, 1, "windowSizeDays must be explicit");
    const a = `${body.range.start.date.year}-${String(body.range.start.date.month).padStart(2, "0")}-${String(body.range.start.date.day).padStart(2, "0")}`;
    const b = `${body.range.end.date.year}-${String(body.range.end.date.month).padStart(2, "0")}-${String(body.range.end.date.day).padStart(2, "0")}`;
    const span = datesBetween(a, b).length;
    const short = ["heart-rate", "total-calories", "active-minutes", "calories-in-heart-rate-zone"].includes(type);
    assert.ok(span <= (short ? 14 : 90), `${type} range ${span} days exceeds cap`);
    return Response.json({
      rollupDataPoints: datesBetween(a, b).map((d) => ({
        civilStartTime: { date: ymdParts(d) },
        civilEndTime: { date: ymdParts(addDaysLocal(d, 1)) },
        ...(rollupValue(type, d) ?? {}),
      })),
    });
  }
  if (op === ":rollUp") {
    assert.equal(body.windowSize, "60s");
    const s = Date.parse(body.range.startTime), e = Date.parse(body.range.endTime);
    if (type === "heart-rate") assert.ok(e - s <= 14 * 86_400_000 + 3_600_000, "heart-rate rollUp range cap");
    const offset = body.pageToken ? Number(body.pageToken) : 0;
    const all: Row[] = [];
    for (let t = s; t < e; t += 60000) {
      const hr = minuteHr(t);
      if (hr === null) continue;
      if (type === "heart-rate") all.push({ startTime: iso(t), endTime: iso(t + 60000), heartRate: { beatsPerMinuteAvg: hr } });
      else all.push({ startTime: iso(t), endTime: iso(t + 60000), steps: { countSum: hr > 140 ? "160" : "0" } });
    }
    const page = all.slice(offset, offset + body.pageSize);
    return Response.json({ rollupDataPoints: page, ...(offset + body.pageSize < all.length ? { nextPageToken: String(offset + body.pageSize) } : {}) });
  }
  throw new Error(`unhandled ${method} ${path}`);
}

// ----------------------------------------------------------- fake Claude API

/** Request bodies sent to the Messages API, for assertions. */
export const claudeRequests: Row[] = [];
/** Set to an HTTP status to make the next Messages API call fail. */
export const claudeFailures: number[] = [];

function sseResponse(events: Row[]): Response {
  const bytes = new TextEncoder().encode(events.map((e) => `event: ${e.type}\ndata: ${JSON.stringify(e)}\n\n`).join(""));
  // Odd-sized chunks so events straddle reads, as they do over the network.
  const stream = new ReadableStream<Uint8Array>({
    start(c) {
      for (let i = 0; i < bytes.length; i += 37) c.enqueue(bytes.slice(i, i + 37));
      c.close();
    },
  });
  return new Response(stream, { status: 200, headers: { "content-type": "text/event-stream" } });
}

function textEvents(index: number, text: string): Row[] {
  const pieces = text.match(/.{1,24}/gs) ?? [];
  return [
    { type: "content_block_start", index, content_block: { type: "text", text: "" } },
    ...pieces.map((t) => ({ type: "content_block_delta", index, delta: { type: "text_delta", text: t } })),
    { type: "content_block_stop", index },
  ];
}

function message(model: string, usage: Row, blocks: Row[], stop: string, output: number): Row[] {
  return [
    { type: "message_start", message: { id: "msg_fake", type: "message", role: "assistant", content: [], model, stop_reason: null, usage: { ...usage, output_tokens: 1 } } },
    { type: "ping" },
    ...blocks,
    { type: "message_delta", delta: { stop_reason: stop, stop_sequence: null }, usage: { output_tokens: output } },
    { type: "message_stop" },
  ];
}

const avg = (xs: number[]) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : NaN);
const hm = (min: number) => `${Math.floor(min / 60)}h ${Math.round(min % 60)}m`;

/**
 * Chat: one tool round (thinking + a short text + get_daily_metrics), then an answer
 * computed from the tool result, so tests see real data flow through. Briefing: a
 * single answer built from the data summary in the system prompt.
 */
function claudeFetch(init: RequestInit): Response {
  const h = init.headers as Record<string, string>;
  assert.equal(h["x-api-key"], "sk-ant-test");
  assert.equal(h["anthropic-version"], "2023-06-01");
  const body = JSON.parse(String(init.body)) as Row;
  claudeRequests.push(body);
  const status = claudeFailures.shift();
  if (status) {
    return Response.json({ type: "error", error: { type: status === 401 ? "authentication_error" : "api_error", message: "fake failure" } }, { status });
  }
  assert.equal(body.stream, true);
  const model = String(body.model);
  const system = body.system as Row[];
  const summary = String(system[1].text);
  const messages = body.messages as Row[];
  const last = messages[messages.length - 1];
  const usage1 = { input_tokens: 40, cache_creation_input_tokens: 5200, cache_read_input_tokens: 0 };

  if (typeof last.content === "string" && last.content.startsWith("Write my briefing")) {
    const recovery = /\(today\): recovery (\d+)/.exec(summary)?.[1];
    const target = /Suggested strain for today: (\d+)–(\d+)/.exec(summary);
    const need = /sleep need (\d+h \d+m)/.exec(summary)?.[1] ?? "8h 0m";
    const text = `**Recovery** ${recovery ?? "not in yet"}${recovery ? " — HRV is below your baseline, resting heart rate is normal." : ""}\n` +
      `**Today** Aim for strain ${target ? `${target[1]}–${target[2]}` : "in the middle range"}: a steady 45-minute run or a gym session, nothing all-out.\n` +
      `**Tonight** Lights out by 22:45 to get your ${need} before your usual 06:50 wake-up.\n` +
      `**Trend** Steps are up 13% over the last week.`;
    return sseResponse(message(model, usage1, textEvents(0, text), "end_turn", 160));
  }

  const results = Array.isArray(last.content) ? (last.content as Row[]).filter((c) => c.type === "tool_result") : [];
  if (!results.length) {
    const today = /^Now: \w+ (\d{4}-\d{2}-\d{2})/m.exec(summary)![1];
    const from = new Date(Date.parse(`${today}T00:00:00Z`) - 6 * 86_400_000).toISOString().slice(0, 10);
    const input = JSON.stringify({ from, to: today, metrics: ["hrv_rmssd", "sleep_asleep_min"] });
    return sseResponse(message(model, usage1, [
      { type: "content_block_start", index: 0, content_block: { type: "thinking", thinking: "", signature: "" } },
      { type: "content_block_delta", index: 0, delta: { type: "thinking_delta", thinking: "" } },
      { type: "content_block_delta", index: 0, delta: { type: "signature_delta", signature: "sig-round-1" } },
      { type: "content_block_stop", index: 0 },
      ...textEvents(1, "Let me look at your last week."),
      { type: "content_block_start", index: 2, content_block: { type: "tool_use", id: "toolu_1", name: "get_daily_metrics", input: {} } },
      { type: "content_block_delta", index: 2, delta: { type: "input_json_delta", partial_json: input.slice(0, 20) } },
      { type: "content_block_delta", index: 2, delta: { type: "input_json_delta", partial_json: input.slice(20) } },
      { type: "content_block_stop", index: 2 },
    ], "tool_use", 210));
  }

  // Round 2: the assistant turn must come back unchanged, thinking block included.
  const assistant = messages[messages.length - 2];
  const blocks = assistant.content as Row[];
  assert.deepEqual(blocks[0], { type: "thinking", thinking: "", signature: "sig-round-1" });
  assert.equal(blocks[2].type, "tool_use");
  assert.equal(results[0].tool_use_id, "toolu_1");
  const data = JSON.parse(String(results[0].content)) as { days: Row[] };
  const hrv = avg(data.days.map((d) => d.hrv_rmssd).filter((v): v is number => typeof v === "number"));
  const sleep = avg(data.days.map((d) => d.sleep_asleep_min).filter((v): v is number => typeof v === "number"));
  const text = `Your HRV averaged **${Math.round(hrv)} ms** over the last 7 nights, and you slept **${hm(sleep)}** a night on average.\n\n` +
    `- Your two shortest nights were followed by your lowest HRV readings, so sleep looks like the lever here.\n` +
    `- Try to get to bed 30 minutes earlier for the next three nights and see if HRV moves back toward your baseline.`;
  return sseResponse(message(model, { input_tokens: 1400, cache_creation_input_tokens: 0, cache_read_input_tokens: 5200 }, textEvents(0, text), "end_turn", 140));
}

globalThis.fetch = (async (input: string | URL | Request, init: RequestInit = {}) => {
  const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url);
  if (url.origin === SUPABASE_URL) return postgrest(url, init);
  if (url.hostname === "api.anthropic.com") return claudeFetch(init);
  return googleFetch(url, init);
}) as typeof fetch;


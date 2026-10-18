// Fake Google Health API + in-memory PostgREST used by the sync test and the
// app screenshot fixtures. Importing this module installs a fake global fetch.
import assert from "node:assert/strict";

export type Row = Record<string, unknown>;

const SUPABASE_URL = "https://example.supabase.co";
const env: Record<string, string> = {
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY: "sb_secret_test",
  GOOGLE_CLIENT_ID: "cid",
  GOOGLE_CLIENT_SECRET: "csecret",
};
(globalThis as unknown as { Deno: unknown }).Deno = { env: { get: (k: string) => env[k] } };

// ------------------------------------------------------------ fake PostgREST

export const tables: Record<string, Row[]> = {
  fs_account: [{
    id: 1, token_status: "ok", refresh_token: "refresh-1", access_token: null, access_token_expires_at: null,
    time_zone: null, profile: null, google_settings: null, meta_fetched_at: null, google_sub: "sub", google_email: "me@example.com",
  }],
  fs_user_settings: [{ id: 1, sex: "unspecified", max_hr_override: null, sleep_need_min: 480, step_goal: 10000, backfill_days: 730 }],
  fs_sync_state: [{ id: 1, backfill_oldest: null, backfill_target: null, backfill_done: false, backfill_empty_chunks: 0, last_recent_sync_at: null, lock_until: null }],
  fs_days: [], fs_sleep: [], fs_exercise: [], fs_intraday: [], fs_samples: [], fs_cache: [],
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

function postgrest(url: URL, init: RequestInit): Response {
  const path = url.pathname.replace("/rest/v1/", "");
  const params = url.searchParams;
  const method = init.method ?? "GET";
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
    case "steps": return { steps: { countSum: String(5000 + k * 7) } };
    case "distance": return { distance: { millimetersSum: String((5000 + k * 7) * 750) } };
    case "floors": return { floors: { countSum: String(k % 15) } };
    case "active-zone-minutes": return { activeZoneMinutes: { sumInFatBurnHeartZone: "12", sumInCardioHeartZone: String(k % 30) } };
    case "active-energy-burned": return { activeEnergyBurned: { kcalSum: 400 + k / 2 } };
    case "total-calories": return { totalCalories: { kcalSum: 2200 + k } };
    case "sedentary-period": return { sedentaryPeriod: { durationSum: "30000s" } };
    case "time-in-heart-rate-zone": return { timeInHeartRateZone: { timeInHeartRateZones: [{ heartRateZone: "LIGHT", duration: "5400s" }] } };
    case "heart-rate": return { heartRate: { beatsPerMinuteMin: 50, beatsPerMinuteAvg: 70, beatsPerMinuteMax: 150 } };
    case "active-minutes": return { activeMinutes: { activeMinutesRollupByActivityLevel: [{ activityLevel: "LIGHT", activeMinutesSum: "180" }] } };
    default: return null; // weight / body-fat: no scale
  }
}

function sleepFor(date: string): Row | null {
  if (date < FIRST_DATA_DAY) return null;
  const start = localMs(addDaysLocal(date, -1), 23, seed(date) % 40);
  const end = localMs(date, 7, seed(date) % 30);
  const mid = start + (end - start) / 3;
  return {
    name: `users/me/dataTypes/sleep/dataPoints/s-${date}`,
    sleep: {
      interval: { startTime: iso(start), endTime: iso(end), startUtcOffset: `${TZ_OFFSET_S}s`, endUtcOffset: `${TZ_OFFSET_S}s`, civilEndTime: { date: ymdParts(date) } },
      type: "STAGES",
      metadata: { mainSleep: true, nap: false, processed: true },
      stages: [
        { type: "LIGHT", startTime: iso(start), endTime: iso(mid) },
        { type: "DEEP", startTime: iso(mid), endTime: iso(mid + 75 * 60000) },
        { type: "REM", startTime: iso(mid + 75 * 60000), endTime: iso(end) },
      ],
      summary: {
        minutesAsleep: String(Math.round((end - start) / 60000) - 15),
        minutesInSleepPeriod: String(Math.round((end - start) / 60000)),
        minutesAwake: "15",
        stagesSummary: [
          { type: "DEEP", minutes: "75", count: "2" },
          { type: "REM", minutes: "95", count: "3" },
          { type: "LIGHT", minutes: "250", count: "6" },
          { type: "AWAKE", minutes: "15", count: "3" },
        ],
      },
    },
  };
}

function minuteHr(ms: number): number | null {
  const local = new Date(ms + TZ_OFFSET_S * 1000);
  const date = local.toISOString().slice(0, 10);
  if (date < FIRST_DATA_DAY) return null;
  const h = local.getUTCHours();
  if (h < 7) return 52;
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
  if (path === "users/me/pairedDevices") return Response.json({ pairedDevices: [{ deviceVersion: "Fitbit Air", batteryLevel: 81 }] });

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
    for (let t = s; t < e; t += 3_600_000) {
      const local = new Date(t + TZ_OFFSET_S * 1000);
      if (local.getUTCHours() >= 7 || local.toISOString().slice(0, 10) < FIRST_DATA_DAY) continue;
      const sampleTime = { physicalTime: iso(t), utcOffset: "7200s" };
      if (type === "heart-rate-variability") pts.push({ heartRateVariability: { sampleTime, rootMeanSquareOfSuccessiveDifferencesMilliseconds: 45 } });
      if (type === "oxygen-saturation") pts.push({ oxygenSaturation: { sampleTime, percentage: 96 } });
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

globalThis.fetch = (async (input: string | URL | Request, init: RequestInit = {}) => {
  const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url);
  if (url.origin === SUPABASE_URL) return postgrest(url, init);
  return googleFetch(url, init);
}) as typeof fetch;


// Google OAuth + Google Health API v4 client (fetch only, no SDK).

import type { Json } from "./transform.ts";
import { googleDateFromYmd, type Ymd } from "./util.ts";

export const GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
export const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
export const HEALTH_BASE = "https://health.googleapis.com/v4";

const SCOPE_PREFIX = "https://www.googleapis.com/auth/googlehealth.";

export const HEALTH_SCOPES = [
  "activity_and_fitness.readonly",
  "health_metrics_and_measurements.readonly",
  "sleep.readonly",
  "profile.readonly",
  "settings.readonly",
].map((s) => SCOPE_PREFIX + s);

export const OAUTH_SCOPES = ["openid", "email", ...HEALTH_SCOPES];

export class GoogleApiError extends Error {
  status: number;
  reason: string;
  constructor(status: number, reason: string, message: string) {
    super(message);
    this.status = status;
    this.reason = reason;
  }
}

export interface TokenSet {
  access_token: string;
  expires_in: number;
  refresh_token?: string;
  scope?: string;
  id_token?: string;
}

async function tokenRequest(params: Record<string, string>): Promise<TokenSet> {
  const res = await fetch(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(params).toString(),
  });
  const text = await res.text();
  let body: Json = {};
  try {
    body = JSON.parse(text);
  } catch {
    // keep raw text for the error below
  }
  if (!res.ok) {
    const reason = typeof body.error === "string" ? body.error : `http_${res.status}`;
    const desc = typeof body.error_description === "string" ? body.error_description : text.slice(0, 300);
    throw new GoogleApiError(res.status, reason, `${reason}: ${desc}`);
  }
  return body as unknown as TokenSet;
}

export function exchangeCode(code: string, verifier: string, redirectUri: string, clientId: string, clientSecret: string) {
  return tokenRequest({
    grant_type: "authorization_code",
    code,
    code_verifier: verifier,
    redirect_uri: redirectUri,
    client_id: clientId,
    client_secret: clientSecret,
  });
}

export function refreshAccessToken(refreshToken: string, clientId: string, clientSecret: string) {
  return tokenRequest({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
    client_id: clientId,
    client_secret: clientSecret,
  });
}

/** Claims of an ID token received directly from Google's token endpoint over TLS. */
export function decodeIdToken(idToken: string | undefined): { sub?: string; email?: string } {
  if (!idToken) return {};
  try {
    const payload = idToken.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = payload + "===".slice((payload.length + 3) % 4);
    return JSON.parse(atob(padded));
  } catch {
    return {};
  }
}

export function rfc3339(ms: number): string {
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
}

export function filterName(type: string): string {
  return type.replace(/-/g, "_");
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export class HealthClient {
  private token: string;
  private refresh: () => Promise<string>;
  calls = 0;
  deadline: number;

  constructor(token: string, refresh: () => Promise<string>, deadline = Number.POSITIVE_INFINITY) {
    this.token = token;
    this.refresh = refresh;
    this.deadline = deadline;
  }

  async request(method: "GET" | "POST", path: string, query?: Record<string, string>, body?: unknown): Promise<Json> {
    const url = new URL(`${HEALTH_BASE}/${path}`);
    for (const [k, v] of Object.entries(query ?? {})) url.searchParams.set(k, v);
    let refreshed = false;
    for (let attempt = 0; ; attempt++) {
      this.calls++;
      const res = await fetch(url, {
        method,
        headers: {
          Authorization: `Bearer ${this.token}`,
          ...(body === undefined ? {} : { "Content-Type": "application/json" }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      if (res.ok) return (await res.json()) as Json;

      const text = await res.text();
      let reason = `http_${res.status}`;
      let message = text.slice(0, 500);
      try {
        const err = (JSON.parse(text) as Json).error as Json | undefined;
        if (err) {
          reason = String(err.status ?? reason);
          message = String(err.message ?? message);
        }
      } catch {
        // non-JSON error body
      }

      if (res.status === 401 && !refreshed) {
        refreshed = true;
        this.token = await this.refresh();
        continue;
      }
      const retryable = res.status === 429 || res.status >= 500;
      if (retryable && attempt < 3) {
        const retryAfter = Number(res.headers.get("retry-after"));
        const wait = Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : 1000 * 2 ** attempt;
        if (Date.now() + wait < this.deadline) {
          await sleep(Math.min(wait, 20_000));
          continue;
        }
      }
      throw new GoogleApiError(res.status, reason, `${method} ${path}: ${message}`);
    }
  }

  /** `list` (or `reconcile`) with pagination; returns all data points. */
  async listAll(
    type: string,
    filter: string,
    opts: { pageSize?: number; maxPages?: number; reconcile?: boolean; family?: string } = {},
  ) {
    const out: Json[] = [];
    let pageToken = "";
    const method = opts.reconcile ? "dataPoints:reconcile" : "dataPoints";
    for (let page = 0; page < (opts.maxPages ?? 20); page++) {
      const query: Record<string, string> = { filter, pageSize: String(opts.pageSize ?? 10000) };
      if (opts.family) query.dataSourceFamily = `users/me/dataSourceFamilies/${opts.family}`;
      if (pageToken) query.pageToken = pageToken;
      const res = await this.request("GET", `users/me/dataTypes/${type}/${method}`, query);
      const points = res.dataPoints;
      if (Array.isArray(points)) out.push(...(points as Json[]));
      pageToken = typeof res.nextPageToken === "string" ? res.nextPageToken : "";
      if (!pageToken) break;
    }
    return out;
  }

  /** Daily summary types filtered by `{type}.date`. */
  listDaily(type: string, start: Ymd, endExclusive: Ymd, reconcile = false) {
    const f = filterName(type);
    return this.listAll(type, `${f}.date >= "${start}" AND ${f}.date < "${endExclusive}"`, { pageSize: 1000, reconcile });
  }

  listSamples(type: string, startMs: number, endMs: number) {
    const f = `${filterName(type)}.sample_time.physical_time`;
    return this.listAll(type, `${f} >= "${rfc3339(startMs)}" AND ${f} < "${rfc3339(endMs)}"`, { pageSize: 10000, maxPages: 10 });
  }

  /** Sleep can only be filtered by its end time. */
  listSleep(start: Ymd, endExclusive: Ymd) {
    return this.listAll(
      "sleep",
      `sleep.interval.civil_end_time >= "${start}" AND sleep.interval.civil_end_time < "${endExclusive}"`,
      { pageSize: 25, maxPages: 40 },
    );
  }

  listExercise(start: Ymd, endExclusive: Ymd) {
    return this.listAll(
      "exercise",
      `exercise.interval.civil_start_time >= "${start}" AND exercise.interval.civil_start_time < "${endExclusive}"`,
      { pageSize: 25, maxPages: 40 },
    );
  }

  /** Interval types (steps, distance, …) by the civil date their intervals start on. */
  listIntervals(type: string, start: Ymd, endExclusive: Ymd, opts: { reconcile?: boolean; family?: string } = {}) {
    const f = `${filterName(type)}.interval.civil_start_time`;
    return this.listAll(type, `${f} >= "${start}" AND ${f} < "${endExclusive}"`, { pageSize: 10000, maxPages: 10, ...opts });
  }

  /** dailyRollUp in 1-day windows (windowSizeDays must be sent explicitly); `family` picks a data source family. */
  async dailyRollup(type: string, start: Ymd, endExclusive: Ymd, family?: string): Promise<Json[]> {
    const out: Json[] = [];
    let pageToken = "";
    for (let page = 0; page < 10; page++) {
      const body: Json = {
        range: { start: { date: googleDateFromYmd(start) }, end: { date: googleDateFromYmd(endExclusive) } },
        windowSizeDays: 1,
        pageSize: 1000,
      };
      if (family) body.dataSourceFamily = `users/me/dataSourceFamilies/${family}`;
      if (pageToken) body.pageToken = pageToken;
      const res = await this.request("POST", `users/me/dataTypes/${type}/dataPoints:dailyRollUp`, undefined, body);
      if (Array.isArray(res.rollupDataPoints)) out.push(...(res.rollupDataPoints as Json[]));
      pageToken = typeof res.nextPageToken === "string" ? res.nextPageToken : "";
      if (!pageToken) break;
    }
    return out;
  }

  /** rollUp over physical time, e.g. 60 s windows for minute heart rate. */
  async rollup(type: string, startMs: number, endMs: number, windowSize: string): Promise<Json[]> {
    const out: Json[] = [];
    let pageToken = "";
    for (let page = 0; page < 20; page++) {
      const body: Json = { range: { startTime: rfc3339(startMs), endTime: rfc3339(endMs) }, windowSize, pageSize: 10000 };
      if (pageToken) body.pageToken = pageToken;
      const res = await this.request("POST", `users/me/dataTypes/${type}/dataPoints:rollUp`, undefined, body);
      if (Array.isArray(res.rollupDataPoints)) out.push(...(res.rollupDataPoints as Json[]));
      pageToken = typeof res.nextPageToken === "string" ? res.nextPageToken : "";
      if (!pageToken) break;
    }
    return out;
  }

  getProfile() {
    return this.request("GET", "users/me/profile");
  }

  getSettings() {
    return this.request("GET", "users/me/settings");
  }

  getIdentity() {
    return this.request("GET", "users/me/identity");
  }

  listDevices() {
    return this.request("GET", "users/me/pairedDevices", { pageSize: "20" });
  }
}

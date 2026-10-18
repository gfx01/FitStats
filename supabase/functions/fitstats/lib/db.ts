// Minimal PostgREST client using the project's secret key (service role).

type Row = Record<string, unknown>;

const runtime = globalThis as unknown as { Deno?: { env: { get(name: string): string | undefined } } };

export function env(name: string): string {
  const v = runtime.Deno?.env.get(name);
  if (!v) throw new Error(`missing env ${name}`);
  return v;
}

export function optionalEnv(name: string): string | null {
  return runtime.Deno?.env.get(name) ?? null;
}

function headers(extra: Record<string, string> = {}): Record<string, string> {
  const key = env("SUPABASE_SERVICE_ROLE_KEY");
  const h: Record<string, string> = { apikey: key, "Content-Type": "application/json", ...extra };
  // Legacy service-role JWTs also go in Authorization; new sb_secret_ keys must not.
  if (key.startsWith("eyJ")) h.Authorization = `Bearer ${key}`;
  return h;
}

function rest(path: string): string {
  return `${env("SUPABASE_URL")}/rest/v1/${path}`;
}

async function check(res: Response, what: string): Promise<void> {
  if (!res.ok) throw new Error(`${what} failed: ${res.status} ${(await res.text()).slice(0, 400)}`);
}

/** GET rows; pages through results 1000 at a time. `query` is a PostgREST query string. */
export async function select<T = Row>(table: string, query = "select=*", maxRows = 20000): Promise<T[]> {
  const out: T[] = [];
  for (let offset = 0; offset < maxRows; offset += 1000) {
    const res = await fetch(rest(`${table}?${query}&limit=1000&offset=${offset}`), { headers: headers() });
    await check(res, `select ${table}`);
    const rows = (await res.json()) as T[];
    out.push(...rows);
    if (rows.length < 1000) break;
  }
  return out;
}

export async function selectOne<T = Row>(table: string, query: string): Promise<T | null> {
  const res = await fetch(rest(`${table}?${query}&limit=1`), { headers: headers() });
  await check(res, `select ${table}`);
  const rows = (await res.json()) as T[];
  return rows[0] ?? null;
}

/** Upsert in chunks. All rows in one call must share the same keys. */
export async function upsert(table: string, rows: Row[], onConflict: string, chunk = 200): Promise<void> {
  for (let i = 0; i < rows.length; i += chunk) {
    const part = rows.slice(i, i + chunk);
    const res = await fetch(rest(`${table}?on_conflict=${onConflict}`), {
      method: "POST",
      headers: headers({ Prefer: "resolution=merge-duplicates,return=minimal" }),
      body: JSON.stringify(part),
    });
    await check(res, `upsert ${table}`);
  }
}

export async function insert(table: string, rows: Row[]): Promise<void> {
  const res = await fetch(rest(table), {
    method: "POST",
    headers: headers({ Prefer: "return=minimal" }),
    body: JSON.stringify(rows),
  });
  await check(res, `insert ${table}`);
}

export async function update(table: string, filter: string, values: Row): Promise<void> {
  const res = await fetch(rest(`${table}?${filter}`), {
    method: "PATCH",
    headers: headers({ Prefer: "return=minimal" }),
    body: JSON.stringify(values),
  });
  await check(res, `update ${table}`);
}

export async function remove(table: string, filter: string): Promise<void> {
  const res = await fetch(rest(`${table}?${filter}`), {
    method: "DELETE",
    headers: headers({ Prefer: "return=minimal" }),
  });
  await check(res, `delete ${table}`);
}

export async function rpc<T = unknown>(fn: string, args: Row = {}): Promise<T> {
  const res = await fetch(rest(`rpc/${fn}`), { method: "POST", headers: headers(), body: JSON.stringify(args) });
  await check(res, `rpc ${fn}`);
  const text = await res.text();
  return (text ? JSON.parse(text) : null) as T;
}

/** Quotes a value for PostgREST `in.(...)` filters. */
export function inList(values: string[]): string {
  return `(${values.map((v) => `"${v.replace(/"/g, '\\"')}"`).join(",")})`;
}

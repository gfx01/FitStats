// Daily journal: tags for what you did on a day (alcohol, a late meal, …) and
// a short note. Statistics compare the following night and morning after
// tagged days with other logged days (journalImpacts in lib/stats.ts).

import * as db from "./db.ts";
import type { Ymd } from "./util.ts";

export interface JournalTag {
  id: string;
  label: string;
  /** SF Symbol shown by the app. */
  icon: string;
}

export const JOURNAL_TAGS: JournalTag[] = [
  { id: "alcohol", label: "Alcohol", icon: "wineglass.fill" },
  { id: "late_caffeine", label: "Caffeine after 2 pm", icon: "cup.and.saucer.fill" },
  { id: "late_meal", label: "Late meal", icon: "fork.knife" },
  { id: "screens_in_bed", label: "Screens in bed", icon: "iphone" },
  { id: "stressful_day", label: "Stressful day", icon: "brain.head.profile" },
  { id: "sick", label: "Sick", icon: "facemask.fill" },
  { id: "travel", label: "Travel", icon: "airplane" },
  { id: "meditation", label: "Meditation", icon: "figure.mind.and.body" },
  { id: "reading", label: "Read before bed", icon: "book.fill" },
  { id: "sleep_aid", label: "Sleep aid", icon: "pills.fill" },
];

const LABELS = new Map(JOURNAL_TAGS.map((t) => [t.id, t.label]));
const IDS_BY_NAME = new Map(JOURNAL_TAGS.flatMap((t) => [[t.id, t.id], [t.label.toLowerCase(), t.id]]));
const MAX_TAGS = 20;
const MAX_TAG_LENGTH = 30;
const MAX_NOTE_LENGTH = 500;
const YMD = /^\d{4}-\d{2}-\d{2}$/;

export interface JournalEntry {
  date: Ymd;
  tags: string[];
  note: string | null;
}

export class JournalInputError extends Error {}

/** Custom tags are kept as typed (trimmed, single spaces, at most 30 characters); a built-in tag's id or label picks that tag. */
export function normalizeTags(input: unknown): string[] | null {
  if (!Array.isArray(input)) return null;
  const out: string[] = [];
  const seen = new Set<string>();
  for (const raw of input) {
    if (typeof raw !== "string") return null;
    const typed = raw.trim().replace(/\s+/g, " ").slice(0, MAX_TAG_LENGTH);
    const tag = IDS_BY_NAME.get(typed.toLowerCase()) ?? typed;
    const key = tag.toLowerCase();
    if (!tag || seen.has(key)) continue;
    seen.add(key);
    out.push(tag);
  }
  return out.length > MAX_TAGS ? null : out;
}

export function tagLabel(tag: string): string {
  return LABELS.get(tag) ?? tag;
}

export async function journalEntries(from: Ymd, to?: Ymd): Promise<JournalEntry[]> {
  const until = to ? `&date=lte.${to}` : "";
  const rows = await db.select<JournalEntry>("fs_journal", `select=date,tags,note&date=gte.${from}${until}&order=date.asc`);
  return rows.map((r) => ({ date: r.date, tags: Array.isArray(r.tags) ? r.tags : [], note: r.note ?? null }));
}

/** Saves one day's entry, or deletes it when `clear` is true. An empty tag list means "nothing to note". */
export async function saveJournalEntry(body: Record<string, unknown>, today: Ymd): Promise<JournalEntry | null> {
  const date = String(body.date ?? "");
  if (!YMD.test(date) || date > today) throw new JournalInputError("date must be a YYYY-MM-DD day that is not in the future");
  if (body.clear === true) {
    await db.remove("fs_journal", `date=eq.${date}`);
    return null;
  }
  const tags = normalizeTags(body.tags ?? []);
  if (!tags) throw new JournalInputError(`tags must be a list of at most ${MAX_TAGS} strings`);
  const note = typeof body.note === "string" ? body.note.trim().slice(0, MAX_NOTE_LENGTH) || null : null;
  await db.upsert("fs_journal", [{ date, tags, note, updated_at: new Date().toISOString() }], "date");
  return { date, tags, note };
}

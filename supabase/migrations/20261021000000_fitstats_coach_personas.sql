-- Coach: which of the three coaches (lib/coach.ts COACH_PERSONAS) wrote a reply, and the
-- previews of screenshots attached to a question ([{media_type, thumb}], base64; the full
-- screenshots go to Claude with that question and are not stored).
alter table public.fs_coach_messages add column if not exists persona text;
alter table public.fs_coach_messages add column if not exists attachments jsonb;

// The exercise library: which muscles common exercises work, for the Training tab's body map
// and the coach. `primary` muscles do most of the work; `secondary` ones help. A set counts
// fully toward its primary muscles and half toward the secondary ones (muscleSets). The app
// gets this list with the training data, so it is the one source for both.

export type MuscleId =
  | "chest" | "shoulders" | "biceps" | "triceps" | "forearms" | "abs" | "obliques"
  | "upper_back" | "lats" | "lower_back" | "glutes" | "quads" | "hamstrings" | "adductors" | "calves";

export interface Muscle {
  id: MuscleId;
  label: string;
  /** Where the body map draws it. */
  side: "front" | "back" | "both";
}

export const MUSCLES: Muscle[] = [
  { id: "chest", label: "Chest", side: "front" },
  { id: "shoulders", label: "Shoulders", side: "both" },
  { id: "biceps", label: "Biceps", side: "front" },
  { id: "triceps", label: "Triceps", side: "back" },
  { id: "forearms", label: "Forearms", side: "both" },
  { id: "abs", label: "Abs", side: "front" },
  { id: "obliques", label: "Obliques", side: "front" },
  { id: "upper_back", label: "Upper back", side: "back" },
  { id: "lats", label: "Lats", side: "back" },
  { id: "lower_back", label: "Lower back", side: "back" },
  { id: "glutes", label: "Glutes", side: "back" },
  { id: "quads", label: "Quads", side: "front" },
  { id: "hamstrings", label: "Hamstrings", side: "back" },
  { id: "adductors", label: "Adductors", side: "front" },
  { id: "calves", label: "Calves", side: "both" },
];

export const MUSCLE_IDS = new Set<string>(MUSCLES.map((m) => m.id));

export interface LibraryExercise {
  name: string;
  /** Other names people write for it ("RDL", "Military press"). */
  aliases: string[];
  kind: "strength" | "cardio" | "mobility";
  equipment: string;
  primary: MuscleId[];
  secondary: MuscleId[];
}

function x(name: string, equipment: string, primary: MuscleId[], secondary: MuscleId[] = [], aliases: string[] = [], kind: LibraryExercise["kind"] = "strength"): LibraryExercise {
  return { name, aliases, kind, equipment, primary, secondary };
}

export const LIBRARY: LibraryExercise[] = [
  // Chest
  x("Bench press", "Barbell", ["chest"], ["triceps", "shoulders"], ["Barbell bench press", "Flat bench press", "Flat bench"]),
  x("Incline bench press", "Barbell", ["chest"], ["shoulders", "triceps"], ["Incline barbell bench press"]),
  x("Dumbbell bench press", "Dumbbells", ["chest"], ["triceps", "shoulders"], ["DB bench press", "Flat dumbbell press"]),
  x("Incline dumbbell press", "Dumbbells", ["chest"], ["shoulders", "triceps"], ["Incline DB press", "Incline dumbbell bench press"]),
  x("Machine chest press", "Machine", ["chest"], ["triceps", "shoulders"], ["Chest press"]),
  x("Chest fly", "Dumbbells or cable", ["chest"], ["shoulders"], ["Dumbbell fly", "Pec fly", "Flyes", "Cable fly"]),
  x("Pec deck", "Machine", ["chest"], ["shoulders"], ["Pec deck fly", "Machine fly"]),
  x("Cable crossover", "Cable", ["chest"], ["shoulders"]),
  x("Push-up", "Bodyweight", ["chest"], ["triceps", "shoulders", "abs"], ["Pushup", "Press-up"]),
  x("Dips", "Bodyweight", ["triceps", "chest"], ["shoulders"], ["Dip", "Chest dips", "Parallel bar dips"]),
  // Back
  x("Deadlift", "Barbell", ["hamstrings", "glutes", "lower_back"], ["quads", "upper_back", "lats", "forearms"], ["Conventional deadlift"]),
  x("Sumo deadlift", "Barbell", ["glutes", "hamstrings", "adductors"], ["quads", "lower_back", "upper_back", "forearms"]),
  x("Pull-up", "Bodyweight", ["lats"], ["biceps", "upper_back", "forearms"], ["Pullup", "Pull up", "Weighted pull-up"]),
  x("Chin-up", "Bodyweight", ["lats", "biceps"], ["upper_back", "forearms"], ["Chinup", "Chin up"]),
  x("Lat pulldown", "Cable", ["lats"], ["biceps", "upper_back"], ["Lat pull-down", "Pulldown", "Pull-down"]),
  x("Bent-over row", "Barbell", ["lats", "upper_back"], ["biceps", "lower_back", "shoulders"], ["Barbell row", "Bent over row", "Pendlay row"]),
  x("Dumbbell row", "Dumbbell", ["lats", "upper_back"], ["biceps", "shoulders"], ["One-arm dumbbell row", "Single-arm row", "DB row"]),
  x("Seated cable row", "Cable", ["upper_back", "lats"], ["biceps", "shoulders"], ["Cable row", "Seated row"]),
  x("T-bar row", "Barbell or machine", ["upper_back", "lats"], ["biceps", "lower_back"]),
  x("Face pull", "Cable", ["shoulders", "upper_back"], [], ["Face pulls"]),
  x("Shrug", "Barbell or dumbbells", ["upper_back"], ["forearms"], ["Shrugs", "Barbell shrug", "Dumbbell shrug"]),
  x("Back extension", "Bench", ["lower_back"], ["glutes", "hamstrings"], ["Hyperextension", "Back hyperextension"]),
  // Shoulders
  x("Overhead press", "Barbell", ["shoulders"], ["triceps", "upper_back"], ["OHP", "Military press", "Shoulder press", "Standing press"]),
  x("Dumbbell shoulder press", "Dumbbells", ["shoulders"], ["triceps"], ["Seated dumbbell press", "DB shoulder press"]),
  x("Arnold press", "Dumbbells", ["shoulders"], ["triceps"]),
  x("Lateral raise", "Dumbbells or cable", ["shoulders"], [], ["Side raise", "Lateral raises", "Side lateral raise"]),
  x("Front raise", "Dumbbells or plate", ["shoulders"], [], ["Front raises"]),
  x("Rear delt fly", "Dumbbells or machine", ["shoulders"], ["upper_back"], ["Reverse fly", "Rear delt raise", "Reverse pec deck"]),
  x("Upright row", "Barbell or cable", ["shoulders", "upper_back"], ["biceps"]),
  // Arms
  x("Barbell curl", "Barbell", ["biceps"], ["forearms"], ["Biceps curl", "Bicep curl", "EZ-bar curl"]),
  x("Dumbbell curl", "Dumbbells", ["biceps"], ["forearms"], ["DB curl", "Alternating curl"]),
  x("Hammer curl", "Dumbbells", ["biceps", "forearms"], [], ["Hammer curls"]),
  x("Preacher curl", "Barbell or machine", ["biceps"], []),
  x("Cable curl", "Cable", ["biceps"], ["forearms"]),
  x("Triceps pushdown", "Cable", ["triceps"], [], ["Tricep pushdown", "Rope pushdown", "Triceps pressdown"]),
  x("Overhead triceps extension", "Dumbbell or cable", ["triceps"], [], ["Overhead tricep extension", "Triceps extension"]),
  x("Skull crusher", "Barbell or dumbbells", ["triceps"], [], ["Skullcrusher", "Lying triceps extension"]),
  x("Close-grip bench press", "Barbell", ["triceps", "chest"], ["shoulders"], ["Close grip bench"]),
  x("Wrist curl", "Barbell or dumbbells", ["forearms"], [], ["Wrist curls"]),
  // Legs
  x("Squat", "Barbell", ["quads", "glutes"], ["adductors", "hamstrings", "lower_back"], ["Back squat", "Barbell squat"]),
  x("Front squat", "Barbell", ["quads"], ["glutes", "abs", "upper_back"]),
  x("Goblet squat", "Dumbbell or kettlebell", ["quads", "glutes"], ["abs", "adductors"]),
  x("Leg press", "Machine", ["quads", "glutes"], ["hamstrings", "adductors"]),
  x("Hack squat", "Machine", ["quads"], ["glutes"]),
  x("Walking lunge", "Dumbbells or bodyweight", ["quads", "glutes"], ["hamstrings", "adductors"], ["Lunge", "Lunges", "Walking lunges", "Reverse lunge"]),
  x("Bulgarian split squat", "Dumbbells", ["quads", "glutes"], ["hamstrings", "adductors"], ["Split squat", "BSS"]),
  x("Step-up", "Dumbbells or bodyweight", ["quads", "glutes"], ["hamstrings"], ["Step up", "Step-ups"]),
  x("Romanian deadlift", "Barbell or dumbbells", ["hamstrings", "glutes"], ["lower_back", "forearms"], ["RDL", "Stiff-leg deadlift"]),
  x("Good morning", "Barbell", ["hamstrings", "lower_back"], ["glutes"]),
  x("Leg curl", "Machine", ["hamstrings"], ["calves"], ["Hamstring curl", "Lying leg curl", "Seated leg curl"]),
  x("Leg extension", "Machine", ["quads"], [], ["Leg extensions"]),
  x("Hip thrust", "Barbell", ["glutes"], ["hamstrings"], ["Barbell hip thrust", "Hip thrusts"]),
  x("Glute bridge", "Bodyweight or barbell", ["glutes"], ["hamstrings"]),
  x("Kettlebell swing", "Kettlebell", ["glutes", "hamstrings"], ["lower_back", "abs"], ["KB swing"]),
  x("Calf raise", "Machine or dumbbells", ["calves"], [], ["Standing calf raise", "Calf raises"]),
  x("Seated calf raise", "Machine", ["calves"], []),
  x("Hip adduction", "Machine", ["adductors"], [], ["Adductor machine"]),
  x("Hip abduction", "Machine", ["glutes"], [], ["Abductor machine"]),
  // Core
  x("Plank", "Bodyweight", ["abs"], ["obliques", "shoulders"]),
  x("Side plank", "Bodyweight", ["obliques"], ["abs"]),
  x("Crunch", "Bodyweight", ["abs"], [], ["Crunches", "Sit-up", "Situp"]),
  x("Cable crunch", "Cable", ["abs"], []),
  x("Hanging leg raise", "Bar", ["abs"], ["obliques", "forearms"], ["Leg raise", "Hanging knee raise"]),
  x("Ab wheel rollout", "Ab wheel", ["abs"], ["lats", "shoulders"], ["Ab rollout", "Ab wheel"]),
  x("Russian twist", "Bodyweight or plate", ["obliques"], ["abs"]),
  x("Dead bug", "Bodyweight", ["abs"], []),
  x("Pallof press", "Cable or band", ["obliques", "abs"], []),
  // Cardio: muscles shown, but not counted as sets (a run isn't a set of an exercise).
  x("Run", "None", ["quads", "calves"], ["hamstrings", "glutes"], ["Running", "Jog", "Treadmill run"], "cardio"),
  x("Cycling", "Bike", ["quads"], ["glutes", "hamstrings", "calves"], ["Bike", "Indoor cycling", "Spin"], "cardio"),
  x("Rowing machine", "Rower", ["lats", "upper_back", "quads"], ["glutes", "hamstrings", "biceps"], ["Rowing", "Erg", "Indoor rowing"], "cardio"),
  x("Elliptical", "Machine", ["quads", "glutes"], ["hamstrings", "calves"], [], "cardio"),
  x("Stair climber", "Machine", ["quads", "glutes"], ["calves", "hamstrings"], ["Stairmaster", "Stairs"], "cardio"),
  x("Swim", "Pool", ["lats", "shoulders"], ["triceps", "upper_back"], ["Swimming"], "cardio"),
  x("Jump rope", "Rope", ["calves"], ["quads", "shoulders"], ["Skipping"], "cardio"),
  x("Walk", "None", [], ["quads", "glutes", "calves"], ["Walking", "Incline walk"], "cardio"),
];

/** "Pull-up", "pull up" and "Pullups" are the same exercise. */
export function normalizeExerciseName(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]/g, "");
}

const BY_NAME = new Map<string, LibraryExercise>();
for (const e of LIBRARY) {
  for (const n of [e.name, ...e.aliases]) BY_NAME.set(normalizeExerciseName(n), e);
}

/** The library entry for a name as written, also without a plural "s". */
export function findExercise(name: string): LibraryExercise | null {
  const n = normalizeExerciseName(name);
  return BY_NAME.get(n) ?? (n.endsWith("s") ? BY_NAME.get(n.slice(0, -1)) ?? null : null);
}

/** Muscles chosen for an exercise outside the library: known ids only, at most six. */
export function muscleList(v: unknown): MuscleId[] | null {
  if (!Array.isArray(v)) return null;
  const out = [...new Set(v.map(String).filter((m) => MUSCLE_IDS.has(m)))].slice(0, 6) as MuscleId[];
  return out.length ? out : null;
}

/** What an exercise works: the library's muscles, or the ones chosen for it (all primary). */
export function exerciseMuscles(name: string, chosen?: MuscleId[] | null): { primary: MuscleId[]; secondary: MuscleId[]; kind: string | null } {
  if (chosen?.length) return { primary: chosen, secondary: [], kind: null };
  const e = findExercise(name);
  return e ? { primary: e.primary, secondary: e.secondary, kind: e.kind } : { primary: [], secondary: [], kind: null };
}

/**
 * Sets per muscle over some logged workouts: each done set of a strength or mobility exercise
 * counts 1 for its primary muscles and 0.5 for its secondary ones. Cardio isn't counted.
 */
export function muscleSets(logs: { exercises: { name: string; kind?: string; muscles?: MuscleId[] | null; sets: { done?: boolean }[] }[] }[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const log of logs) {
    for (const ex of log.exercises) {
      if (ex.kind === "cardio") continue;
      const done = ex.sets.filter((s) => s.done !== false).length;
      if (!done) continue;
      const m = exerciseMuscles(ex.name, ex.muscles);
      if (m.kind === "cardio") continue;
      for (const id of m.primary) out[id] = (out[id] ?? 0) + done;
      for (const id of m.secondary) out[id] = (out[id] ?? 0) + done * 0.5;
    }
  }
  return out;
}

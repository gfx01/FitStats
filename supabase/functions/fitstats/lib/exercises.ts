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
  /** Where the app lists it: Chest, Back, Shoulders, Arms, Legs, Glutes, Core, Full body, Calisthenics, Cardio, Sports, Mobility. */
  category: string;
  equipment: string;
  primary: MuscleId[];
  secondary: MuscleId[];
}

type Entry = [name: string, equipment: string, primary: MuscleId[], secondary?: MuscleId[], aliases?: string[]];

function group(category: string, kind: LibraryExercise["kind"], entries: Entry[]): LibraryExercise[] {
  return entries.map(([name, equipment, primary, secondary = [], aliases = []]) => ({ name, aliases, kind, category, equipment, primary, secondary }));
}

export const LIBRARY: LibraryExercise[] = [
  ...group("Chest", "strength", [
    ["Bench press", "Barbell", ["chest"], ["triceps", "shoulders"], ["Barbell bench press", "Flat bench press", "Flat bench"]],
    ["Incline bench press", "Barbell", ["chest"], ["shoulders", "triceps"], ["Incline barbell bench press"]],
    ["Decline bench press", "Barbell", ["chest"], ["triceps", "shoulders"], ["Decline barbell bench press"]],
    ["Close-grip bench press", "Barbell", ["triceps", "chest"], ["shoulders"], ["Close grip bench", "CGBP"]],
    ["Reverse-grip bench press", "Barbell", ["chest"], ["triceps", "shoulders"], ["Reverse grip bench"]],
    ["Larsen press", "Barbell", ["chest"], ["triceps", "shoulders"]],
    ["Floor press", "Barbell or dumbbells", ["chest", "triceps"], ["shoulders"], ["Dumbbell floor press"]],
    ["Smith machine bench press", "Smith machine", ["chest"], ["triceps", "shoulders"], ["Smith bench press"]],
    ["Smith machine incline press", "Smith machine", ["chest"], ["shoulders", "triceps"], ["Smith incline press"]],
    ["Dumbbell bench press", "Dumbbells", ["chest"], ["triceps", "shoulders"], ["DB bench press", "Flat dumbbell press"]],
    ["Incline dumbbell press", "Dumbbells", ["chest"], ["shoulders", "triceps"], ["Incline DB press", "Incline dumbbell bench press"]],
    ["Decline dumbbell press", "Dumbbells", ["chest"], ["triceps", "shoulders"]],
    ["Squeeze press", "Dumbbells", ["chest"], ["triceps"], ["Dumbbell squeeze press", "Crush press"]],
    ["Machine chest press", "Machine", ["chest"], ["triceps", "shoulders"], ["Chest press", "Hammer Strength chest press"]],
    ["Incline machine press", "Machine", ["chest"], ["shoulders", "triceps"], ["Incline chest press"]],
    ["Cable chest press", "Cable", ["chest"], ["triceps", "shoulders"], ["Standing cable press"]],
    ["Chest fly", "Dumbbells", ["chest"], ["shoulders"], ["Dumbbell fly", "Pec fly", "Flyes", "Flat fly"]],
    ["Incline dumbbell fly", "Dumbbells", ["chest"], ["shoulders"], ["Incline fly"]],
    ["Pec deck", "Machine", ["chest"], ["shoulders"], ["Pec deck fly", "Machine fly", "Butterfly"]],
    ["Cable crossover", "Cable", ["chest"], ["shoulders"], ["Cable fly"]],
    ["Low-to-high cable fly", "Cable", ["chest"], ["shoulders"], ["Low cable fly"]],
    ["High-to-low cable fly", "Cable", ["chest"], ["shoulders"], ["High cable fly"]],
    ["Incline cable fly", "Cable", ["chest"], ["shoulders"]],
    ["Dumbbell pullover", "Dumbbell", ["chest", "lats"], ["triceps"], ["Pullover"]],
    ["Svend press", "Plate", ["chest"], ["shoulders"], ["Plate press"]],
    ["Push-up", "Bodyweight", ["chest"], ["triceps", "shoulders", "abs"], ["Pushup", "Press-up", "Weighted push-up"]],
    ["Incline push-up", "Bodyweight", ["chest"], ["triceps", "shoulders"]],
    ["Decline push-up", "Bodyweight", ["chest"], ["shoulders", "triceps"]],
    ["Wide push-up", "Bodyweight", ["chest"], ["shoulders", "triceps"], ["Wide-grip push-up"]],
    ["Diamond push-up", "Bodyweight", ["triceps", "chest"], ["shoulders"], ["Close-grip push-up", "Triangle push-up"]],
    ["Archer push-up", "Bodyweight", ["chest"], ["triceps", "shoulders"]],
    ["Dips", "Bodyweight", ["triceps", "chest"], ["shoulders"], ["Dip", "Chest dips", "Parallel bar dips", "Weighted dips"]],
  ]),
  ...group("Back", "strength", [
    ["Deadlift", "Barbell", ["hamstrings", "glutes", "lower_back"], ["quads", "upper_back", "lats", "forearms"], ["Conventional deadlift"]],
    ["Sumo deadlift", "Barbell", ["glutes", "hamstrings", "adductors"], ["quads", "lower_back", "upper_back", "forearms"]],
    ["Trap bar deadlift", "Trap bar", ["quads", "glutes", "hamstrings"], ["lower_back", "upper_back", "forearms"], ["Hex bar deadlift"]],
    ["Deficit deadlift", "Barbell", ["hamstrings", "glutes", "lower_back"], ["quads", "upper_back", "forearms"]],
    ["Snatch-grip deadlift", "Barbell", ["hamstrings", "glutes", "upper_back"], ["lower_back", "lats", "forearms"]],
    ["Rack pull", "Barbell", ["upper_back", "lower_back", "glutes"], ["hamstrings", "lats", "forearms"], ["Block pull"]],
    ["Pull-up", "Bodyweight", ["lats"], ["biceps", "upper_back", "forearms"], ["Pullup", "Pull up", "Weighted pull-up", "Wide-grip pull-up"]],
    ["Chin-up", "Bodyweight", ["lats", "biceps"], ["upper_back", "forearms"], ["Chinup", "Chin up", "Weighted chin-up"]],
    ["Neutral-grip pull-up", "Bodyweight", ["lats", "biceps"], ["upper_back", "forearms"], ["Hammer-grip pull-up"]],
    ["Assisted pull-up", "Machine or band", ["lats"], ["biceps", "upper_back"], ["Assisted pull-up machine", "Band-assisted pull-up"]],
    ["Scapular pull-up", "Bar", ["lats", "upper_back"], [], ["Scap pull-up"]],
    ["Lat pulldown", "Cable", ["lats"], ["biceps", "upper_back"], ["Lat pull-down", "Pulldown", "Pull-down", "Wide-grip lat pulldown"]],
    ["Close-grip lat pulldown", "Cable", ["lats"], ["biceps", "upper_back"], ["V-bar pulldown"]],
    ["Single-arm lat pulldown", "Cable", ["lats"], ["biceps"], ["One-arm pulldown"]],
    ["Straight-arm pulldown", "Cable", ["lats"], ["triceps"], ["Straight-arm lat pulldown", "Cable pullover"]],
    ["Machine pullover", "Machine", ["lats"], [], ["Lat pullover machine"]],
    ["Bent-over row", "Barbell", ["lats", "upper_back"], ["biceps", "lower_back", "shoulders"], ["Barbell row", "Bent over row", "Pendlay row"]],
    ["Yates row", "Barbell", ["lats", "upper_back"], ["biceps", "lower_back"], ["Underhand barbell row"]],
    ["Dumbbell row", "Dumbbell", ["lats", "upper_back"], ["biceps", "shoulders"], ["One-arm dumbbell row", "Single-arm row", "DB row"]],
    ["Kroc row", "Dumbbell", ["lats", "upper_back"], ["biceps", "forearms"]],
    ["Chest-supported row", "Dumbbells or machine", ["upper_back", "lats"], ["biceps", "shoulders"], ["Incline dumbbell row", "Chest supported row"]],
    ["Seal row", "Barbell or dumbbells", ["upper_back", "lats"], ["biceps", "shoulders"]],
    ["Seated cable row", "Cable", ["upper_back", "lats"], ["biceps", "shoulders"], ["Cable row", "Seated row"]],
    ["Machine row", "Machine", ["upper_back", "lats"], ["biceps"], ["Hammer Strength row", "Seated machine row"]],
    ["T-bar row", "Barbell or machine", ["upper_back", "lats"], ["biceps", "lower_back"]],
    ["Meadows row", "Barbell", ["lats", "upper_back"], ["biceps", "forearms"]],
    ["Renegade row", "Dumbbells", ["lats", "upper_back"], ["abs", "obliques", "biceps"]],
    ["Inverted row", "Bar or rings", ["upper_back", "lats"], ["biceps", "shoulders"], ["Bodyweight row", "Australian pull-up", "Ring row"]],
    ["Face pull", "Cable", ["shoulders", "upper_back"], [], ["Face pulls"]],
    ["Band pull-apart", "Band", ["shoulders", "upper_back"], [], ["Pull-apart"]],
    ["Prone Y-raise", "Dumbbells or bodyweight", ["shoulders", "upper_back"], [], ["Y raise", "Incline Y-raise"]],
    ["Shrug", "Barbell or dumbbells", ["upper_back"], ["forearms"], ["Shrugs", "Barbell shrug", "Dumbbell shrug", "Trap shrug"]],
    ["Back extension", "Bench", ["lower_back"], ["glutes", "hamstrings"], ["Hyperextension", "Back hyperextension", "45-degree back extension"]],
    ["Reverse hyperextension", "Machine or bench", ["glutes", "lower_back"], ["hamstrings"], ["Reverse hyper"]],
    ["Superman", "Bodyweight", ["lower_back"], ["glutes", "upper_back"], ["Superman hold"]],
    ["Bird dog", "Bodyweight", ["lower_back", "abs"], ["glutes", "shoulders"]],
    ["Good morning", "Barbell", ["hamstrings", "lower_back"], ["glutes"]],
  ]),
  ...group("Shoulders", "strength", [
    ["Overhead press", "Barbell", ["shoulders"], ["triceps", "upper_back"], ["OHP", "Military press", "Shoulder press", "Standing press", "Strict press"]],
    ["Push press", "Barbell", ["shoulders"], ["triceps", "quads", "glutes", "upper_back"]],
    ["Seated barbell press", "Barbell", ["shoulders"], ["triceps"], ["Behind-the-neck press", "Seated military press"]],
    ["Dumbbell shoulder press", "Dumbbells", ["shoulders"], ["triceps"], ["Seated dumbbell press", "DB shoulder press", "Dumbbell overhead press"]],
    ["Arnold press", "Dumbbells", ["shoulders"], ["triceps"]],
    ["Machine shoulder press", "Machine", ["shoulders"], ["triceps"], ["Shoulder press machine"]],
    ["Landmine press", "Barbell", ["shoulders", "chest"], ["triceps"], ["Single-arm landmine press"]],
    ["Z press", "Barbell or dumbbells", ["shoulders"], ["triceps", "abs"]],
    ["Lateral raise", "Dumbbells", ["shoulders"], [], ["Side raise", "Lateral raises", "Side lateral raise", "Dumbbell lateral raise", "Seated lateral raise"]],
    ["Cable lateral raise", "Cable", ["shoulders"], [], ["Single-arm cable lateral raise"]],
    ["Machine lateral raise", "Machine", ["shoulders"], []],
    ["Lean-away lateral raise", "Dumbbell", ["shoulders"], []],
    ["Front raise", "Dumbbells or plate", ["shoulders"], [], ["Front raises", "Plate front raise", "Cable front raise"]],
    ["Rear delt fly", "Dumbbells", ["shoulders"], ["upper_back"], ["Reverse fly", "Rear delt raise", "Bent-over lateral raise"]],
    ["Reverse pec deck", "Machine", ["shoulders"], ["upper_back"], ["Machine rear delt fly", "Rear delt machine"]],
    ["Cable rear delt fly", "Cable", ["shoulders"], ["upper_back"], ["Reverse cable fly", "Cable reverse fly"]],
    ["Upright row", "Barbell or cable", ["shoulders", "upper_back"], ["biceps"], ["Cable upright row"]],
    ["Cuban press", "Dumbbells", ["shoulders"], ["upper_back"]],
    ["External rotation", "Cable or band", ["shoulders"], [], ["Cable external rotation", "Band external rotation"]],
    ["Pike push-up", "Bodyweight", ["shoulders"], ["triceps", "upper_back"]],
    ["Handstand push-up", "Bodyweight", ["shoulders", "triceps"], ["upper_back"], ["HSPU", "Wall handstand push-up"]],
    ["Overhead carry", "Dumbbells or kettlebells", ["shoulders", "abs"], ["upper_back", "triceps"], ["Waiter carry"]],
  ]),
  ...group("Arms", "strength", [
    ["Barbell curl", "Barbell", ["biceps"], ["forearms"], ["Biceps curl", "Bicep curl", "EZ-bar curl", "Standing curl"]],
    ["Dumbbell curl", "Dumbbells", ["biceps"], ["forearms"], ["DB curl", "Alternating curl", "Alternating dumbbell curl"]],
    ["Hammer curl", "Dumbbells", ["biceps", "forearms"], [], ["Hammer curls", "Cross-body hammer curl"]],
    ["Rope hammer curl", "Cable", ["biceps", "forearms"], [], ["Cable hammer curl"]],
    ["Incline dumbbell curl", "Dumbbells", ["biceps"], ["forearms"], ["Incline curl"]],
    ["Preacher curl", "Barbell or machine", ["biceps"], [], ["EZ-bar preacher curl", "Machine preacher curl"]],
    ["Concentration curl", "Dumbbell", ["biceps"], []],
    ["Spider curl", "Dumbbells or barbell", ["biceps"], []],
    ["Cable curl", "Cable", ["biceps"], ["forearms"], ["Cable biceps curl"]],
    ["Bayesian curl", "Cable", ["biceps"], [], ["Behind-the-body cable curl"]],
    ["Drag curl", "Barbell", ["biceps"], ["forearms"]],
    ["21s", "Barbell", ["biceps"], ["forearms"], ["Bicep 21s", "Biceps 21s"]],
    ["Machine curl", "Machine", ["biceps"], [], ["Biceps machine"]],
    ["Reverse curl", "Barbell or EZ bar", ["forearms", "biceps"], [], ["Reverse-grip curl"]],
    ["Zottman curl", "Dumbbells", ["biceps", "forearms"], []],
    ["Wrist curl", "Barbell or dumbbells", ["forearms"], [], ["Wrist curls"]],
    ["Reverse wrist curl", "Barbell or dumbbells", ["forearms"], [], ["Wrist extension"]],
    ["Wrist roller", "Wrist roller", ["forearms"], []],
    ["Plate pinch", "Plates", ["forearms"], [], ["Pinch grip hold"]],
    ["Dead hang", "Bar", ["forearms"], ["lats", "shoulders"], ["Bar hang"]],
    ["Triceps pushdown", "Cable", ["triceps"], [], ["Tricep pushdown", "Rope pushdown", "Triceps pressdown", "Cable pushdown"]],
    ["Single-arm cable pushdown", "Cable", ["triceps"], [], ["One-arm pushdown"]],
    ["Overhead triceps extension", "Dumbbell or cable", ["triceps"], [], ["Overhead tricep extension", "Triceps extension", "Cable overhead extension", "French press"]],
    ["Skull crusher", "Barbell or dumbbells", ["triceps"], [], ["Skullcrusher", "Lying triceps extension", "EZ-bar skull crusher"]],
    ["JM press", "Barbell", ["triceps"], ["chest"]],
    ["Tate press", "Dumbbells", ["triceps"], []],
    ["Triceps kickback", "Dumbbell or cable", ["triceps"], [], ["Tricep kickback", "Kickback"]],
    ["Bench dip", "Bench", ["triceps"], ["chest", "shoulders"], ["Bench dips", "Tricep dips"]],
  ]),
  ...group("Legs", "strength", [
    ["Squat", "Barbell", ["quads", "glutes"], ["adductors", "hamstrings", "lower_back"], ["Back squat", "Barbell squat", "High-bar squat", "Low-bar squat"]],
    ["Front squat", "Barbell", ["quads"], ["glutes", "abs", "upper_back"]],
    ["Box squat", "Barbell", ["quads", "glutes"], ["hamstrings", "adductors", "lower_back"]],
    ["Pause squat", "Barbell", ["quads", "glutes"], ["adductors", "lower_back"], ["Paused squat"]],
    ["Safety bar squat", "Safety squat bar", ["quads", "glutes"], ["upper_back", "lower_back", "adductors"], ["SSB squat"]],
    ["Zercher squat", "Barbell", ["quads", "glutes"], ["abs", "upper_back", "biceps"]],
    ["Overhead squat", "Barbell", ["quads", "glutes", "shoulders"], ["abs", "upper_back", "adductors"]],
    ["Smith machine squat", "Smith machine", ["quads", "glutes"], ["adductors", "hamstrings"], ["Smith squat"]],
    ["Goblet squat", "Dumbbell or kettlebell", ["quads", "glutes"], ["abs", "adductors"], ["Heels-elevated goblet squat"]],
    ["Hack squat", "Machine", ["quads"], ["glutes"], ["Hack squat machine"]],
    ["Pendulum squat", "Machine", ["quads"], ["glutes"]],
    ["Belt squat", "Machine", ["quads", "glutes"], ["adductors"]],
    ["Leg press", "Machine", ["quads", "glutes"], ["hamstrings", "adductors"], ["Horizontal leg press", "45-degree leg press"]],
    ["Single-leg leg press", "Machine", ["quads", "glutes"], ["hamstrings"]],
    ["Pistol squat", "Bodyweight", ["quads", "glutes"], ["adductors", "calves", "abs"], ["Single-leg squat"]],
    ["Sissy squat", "Bodyweight", ["quads"], []],
    ["Spanish squat", "Band", ["quads"], []],
    ["Reverse Nordic", "Bodyweight", ["quads"], [], ["Reverse Nordic curl"]],
    ["Wall sit", "Bodyweight", ["quads"], ["glutes"]],
    ["Cossack squat", "Bodyweight or kettlebell", ["adductors", "quads", "glutes"], ["hamstrings"]],
    ["Walking lunge", "Dumbbells or bodyweight", ["quads", "glutes"], ["hamstrings", "adductors"], ["Lunge", "Lunges", "Walking lunges", "Forward lunge", "Dumbbell lunge"]],
    ["Reverse lunge", "Dumbbells or bodyweight", ["glutes", "quads"], ["hamstrings", "adductors"], ["Reverse lunges", "Deficit reverse lunge"]],
    ["Lateral lunge", "Dumbbells or bodyweight", ["adductors", "quads", "glutes"], ["hamstrings"], ["Side lunge"]],
    ["Curtsy lunge", "Dumbbells or bodyweight", ["glutes", "quads"], ["adductors"]],
    ["Bulgarian split squat", "Dumbbells", ["quads", "glutes"], ["hamstrings", "adductors"], ["BSS", "Rear-foot elevated split squat", "RFESS"]],
    ["Split squat", "Dumbbells or bodyweight", ["quads", "glutes"], ["hamstrings", "adductors"], ["Static lunge"]],
    ["Step-up", "Dumbbells or bodyweight", ["quads", "glutes"], ["hamstrings"], ["Step up", "Step-ups", "Box step-up"]],
    ["Leg extension", "Machine", ["quads"], [], ["Leg extensions", "Single-leg extension"]],
    ["Romanian deadlift", "Barbell or dumbbells", ["hamstrings", "glutes"], ["lower_back", "forearms"], ["RDL", "Dumbbell RDL"]],
    ["Stiff-leg deadlift", "Barbell or dumbbells", ["hamstrings", "lower_back"], ["glutes", "forearms"], ["Stiff-legged deadlift", "SLDL"]],
    ["Single-leg Romanian deadlift", "Dumbbell or kettlebell", ["hamstrings", "glutes"], ["lower_back"], ["Single-leg RDL", "Single-leg deadlift"]],
    ["Kettlebell deadlift", "Kettlebell", ["glutes", "hamstrings"], ["quads", "lower_back", "forearms"]],
    ["Leg curl", "Machine", ["hamstrings"], ["calves"], ["Hamstring curl", "Lying leg curl", "Seated leg curl", "Standing leg curl"]],
    ["Nordic hamstring curl", "Bodyweight", ["hamstrings"], ["glutes", "calves"], ["Nordic curl", "Nordics"]],
    ["Glute-ham raise", "GHD", ["hamstrings", "glutes"], ["calves", "lower_back"], ["GHR"]],
    ["Calf raise", "Machine or dumbbells", ["calves"], [], ["Standing calf raise", "Calf raises", "Smith machine calf raise"]],
    ["Seated calf raise", "Machine", ["calves"], []],
    ["Single-leg calf raise", "Dumbbell or bodyweight", ["calves"], []],
    ["Leg press calf raise", "Machine", ["calves"], [], ["Calf press"]],
    ["Donkey calf raise", "Machine", ["calves"], []],
    ["Hip adduction", "Machine", ["adductors"], [], ["Adductor machine", "Inner thigh machine"]],
    ["Copenhagen plank", "Bodyweight", ["adductors", "obliques"], ["abs"], ["Copenhagen adductor plank"]],
    ["Box jump", "Box", ["quads", "glutes"], ["calves", "hamstrings"], ["Box jumps"]],
    ["Jump squat", "Bodyweight", ["quads", "glutes"], ["calves"], ["Squat jump", "Squat jumps"]],
    ["Broad jump", "Bodyweight", ["glutes", "quads"], ["hamstrings", "calves"], ["Standing long jump"]],
    ["Sled push", "Sled", ["quads", "glutes"], ["calves", "hamstrings"], ["Prowler push", "Prowler"]],
    ["Sled drag", "Sled", ["quads", "glutes"], ["calves", "hamstrings"], ["Backward sled drag", "Sled pull"]],
  ]),
  ...group("Glutes", "strength", [
    ["Hip thrust", "Barbell", ["glutes"], ["hamstrings"], ["Barbell hip thrust", "Hip thrusts", "Hip thrust machine"]],
    ["Single-leg hip thrust", "Bodyweight or dumbbell", ["glutes"], ["hamstrings"]],
    ["Glute bridge", "Bodyweight or barbell", ["glutes"], ["hamstrings"], ["Barbell glute bridge"]],
    ["Single-leg glute bridge", "Bodyweight", ["glutes"], ["hamstrings"]],
    ["Frog pump", "Bodyweight or dumbbell", ["glutes"], [], ["Frog pumps"]],
    ["Cable kickback", "Cable", ["glutes"], ["hamstrings"], ["Glute kickback", "Cable glute kickback"]],
    ["Donkey kick", "Bodyweight", ["glutes"], ["hamstrings"], ["Donkey kicks"]],
    ["Cable pull-through", "Cable", ["glutes", "hamstrings"], ["lower_back"], ["Pull-through"]],
    ["Hip abduction", "Machine", ["glutes"], [], ["Abductor machine", "Seated hip abduction", "Standing cable hip abduction"]],
    ["Fire hydrant", "Bodyweight", ["glutes"], [], ["Fire hydrants"]],
    ["Clamshell", "Band", ["glutes"], [], ["Clamshells", "Clam"]],
    ["Banded side walk", "Band", ["glutes"], [], ["Monster walk", "Lateral band walk"]],
  ]),
  ...group("Core", "strength", [
    ["Plank", "Bodyweight", ["abs"], ["obliques", "shoulders"], ["Weighted plank", "Forearm plank"]],
    ["Side plank", "Bodyweight", ["obliques"], ["abs"]],
    ["Crunch", "Bodyweight", ["abs"], [], ["Crunches", "Sit-up", "Situp", "Sit-ups"]],
    ["Decline sit-up", "Bench", ["abs"], [], ["Decline crunch", "Weighted sit-up"]],
    ["Reverse crunch", "Bodyweight", ["abs"], []],
    ["Bicycle crunch", "Bodyweight", ["obliques", "abs"], [], ["Bicycle crunches", "Bicycles"]],
    ["Oblique crunch", "Bodyweight", ["obliques"], ["abs"]],
    ["Cable crunch", "Cable", ["abs"], [], ["Kneeling cable crunch"]],
    ["Ab crunch machine", "Machine", ["abs"], [], ["Machine crunch"]],
    ["V-up", "Bodyweight", ["abs"], ["obliques"], ["V-ups", "V sit-up"]],
    ["Hollow hold", "Bodyweight", ["abs"], [], ["Hollow body hold", "Hollow rock"]],
    ["Lying leg raise", "Bodyweight", ["abs"], [], ["Leg raises", "Lying leg raises"]],
    ["Hanging leg raise", "Bar", ["abs"], ["obliques", "forearms"], ["Leg raise", "Hanging knee raise", "Knee raise"]],
    ["Captain's chair leg raise", "Captain's chair", ["abs"], ["obliques"], ["Captain's chair", "Roman chair leg raise"]],
    ["Toes to bar", "Bar", ["abs"], ["obliques", "lats", "forearms"], ["Toes-to-bar", "T2B"]],
    ["Flutter kicks", "Bodyweight", ["abs"], [], ["Flutter kick"]],
    ["Dead bug", "Bodyweight", ["abs"], [], ["Dead bugs"]],
    ["Ab wheel rollout", "Ab wheel", ["abs"], ["lats", "shoulders"], ["Ab rollout", "Ab wheel", "Barbell rollout"]],
    ["Stir the pot", "Stability ball", ["abs"], ["obliques", "shoulders"]],
    ["Dragon flag", "Bench", ["abs"], ["obliques", "lats"]],
    ["L-sit", "Parallettes or bars", ["abs"], ["triceps", "quads"], ["L sit"]],
    ["Mountain climber", "Bodyweight", ["abs"], ["shoulders", "quads", "obliques"], ["Mountain climbers"]],
    ["Russian twist", "Bodyweight or plate", ["obliques"], ["abs"], ["Russian twists"]],
    ["Woodchopper", "Cable", ["obliques"], ["abs", "shoulders"], ["Cable woodchop", "Wood chop", "Woodchop"]],
    ["Landmine rotation", "Barbell", ["obliques"], ["abs", "shoulders"], ["Landmine twist"]],
    ["Pallof press", "Cable or band", ["obliques", "abs"], []],
    ["Side bend", "Dumbbell", ["obliques"], [], ["Dumbbell side bend"]],
    ["Suitcase carry", "Dumbbell or kettlebell", ["obliques", "forearms"], ["abs", "upper_back"], ["Single-arm farmer's carry"]],
  ]),
  ...group("Full body", "strength", [
    ["Power clean", "Barbell", ["glutes", "hamstrings", "quads", "upper_back"], ["calves", "shoulders", "forearms", "lower_back"], ["Clean"]],
    ["Hang clean", "Barbell", ["glutes", "hamstrings", "upper_back"], ["quads", "shoulders", "forearms", "calves"], ["Hang power clean"]],
    ["Clean and jerk", "Barbell", ["quads", "glutes", "shoulders", "upper_back"], ["hamstrings", "triceps", "calves", "lower_back"], ["Clean & jerk"]],
    ["Snatch", "Barbell", ["glutes", "hamstrings", "quads", "shoulders", "upper_back"], ["lower_back", "triceps", "calves"], ["Power snatch", "Hang snatch"]],
    ["High pull", "Barbell", ["upper_back", "shoulders", "glutes"], ["hamstrings", "biceps"], ["Clean high pull", "Snatch-grip high pull"]],
    ["Thruster", "Barbell or dumbbells", ["quads", "glutes", "shoulders"], ["triceps", "abs", "upper_back"], ["Thrusters"]],
    ["Kettlebell swing", "Kettlebell", ["glutes", "hamstrings"], ["lower_back", "abs"], ["KB swing", "Russian swing", "American swing"]],
    ["Kettlebell clean", "Kettlebell", ["glutes", "hamstrings"], ["upper_back", "forearms", "shoulders"], ["KB clean"]],
    ["Kettlebell snatch", "Kettlebell", ["glutes", "hamstrings", "shoulders"], ["upper_back", "lower_back", "forearms"], ["KB snatch"]],
    ["Turkish get-up", "Kettlebell", ["shoulders", "abs", "obliques"], ["glutes", "quads", "triceps"], ["Turkish getup", "TGU", "Get-up"]],
    ["Kettlebell windmill", "Kettlebell", ["obliques", "shoulders"], ["hamstrings", "glutes"], ["Windmill"]],
    ["Farmer's walk", "Dumbbells, kettlebells or handles", ["forearms", "upper_back"], ["abs", "obliques", "glutes", "calves"], ["Farmer's carry", "Farmers walk", "Farmer carry"]],
    ["Medicine ball slam", "Medicine ball", ["abs", "lats", "shoulders"], ["triceps", "glutes"], ["Ball slam", "Slam ball", "Med ball slam"]],
    ["Wall ball", "Medicine ball", ["quads", "glutes", "shoulders"], ["triceps", "abs"], ["Wall balls", "Wall ball shot"]],
    ["Burpee", "Bodyweight", ["quads", "chest", "shoulders"], ["triceps", "abs", "glutes", "calves"], ["Burpees"]],
    ["Bear crawl", "Bodyweight", ["shoulders", "abs"], ["quads"], ["Bear crawls"]],
    ["Tire flip", "Tire", ["glutes", "hamstrings", "quads", "upper_back"], ["lower_back", "shoulders", "triceps"], ["Tyre flip"]],
  ]),
  ...group("Calisthenics", "strength", [
    ["Muscle-up", "Bar or rings", ["lats", "chest", "triceps"], ["biceps", "shoulders", "upper_back"], ["Muscle up", "Bar muscle-up", "Ring muscle-up"]],
    ["Ring dip", "Rings", ["triceps", "chest"], ["shoulders"], ["Ring dips"]],
    ["Front lever", "Bar or rings", ["lats", "abs"], ["upper_back", "biceps"], ["Front lever hold", "Tuck front lever"]],
    ["Handstand hold", "Bodyweight", ["shoulders"], ["triceps", "upper_back", "abs"], ["Handstand", "Wall handstand"]],
  ]),
  // Cardio and sports: muscles shown, but not counted as sets (a run isn't a set of an exercise).
  ...group("Cardio", "cardio", [
    ["Run", "None", ["quads", "calves"], ["hamstrings", "glutes"], ["Running", "Jog", "Jogging", "Treadmill run", "Easy run", "Tempo run", "Long run"]],
    ["Sprint", "None", ["quads", "hamstrings", "glutes"], ["calves"], ["Sprints", "Interval sprints"]],
    ["Hill sprint", "None", ["glutes", "quads", "hamstrings"], ["calves"], ["Hill sprints", "Hill repeats"]],
    ["Trail run", "None", ["quads", "calves"], ["hamstrings", "glutes"], ["Trail running"]],
    ["Walk", "None", [], ["quads", "glutes", "calves"], ["Walking", "Incline walk", "Treadmill walk"]],
    ["Hike", "None", ["quads", "glutes"], ["hamstrings", "calves"], ["Hiking"]],
    ["Rucking", "Weighted backpack", ["quads", "glutes", "upper_back"], ["calves", "hamstrings", "lower_back"], ["Ruck", "Ruck march"]],
    ["Cycling", "Bike", ["quads"], ["glutes", "hamstrings", "calves"], ["Bike", "Indoor cycling", "Spin", "Spin class", "Road cycling", "Stationary bike"]],
    ["Mountain biking", "Bike", ["quads", "glutes"], ["hamstrings", "calves", "forearms"], ["MTB"]],
    ["Air bike", "Air bike", ["quads"], ["glutes", "hamstrings", "shoulders"], ["Assault bike", "Echo bike", "Airdyne"]],
    ["Rowing machine", "Rower", ["lats", "upper_back", "quads"], ["glutes", "hamstrings", "biceps"], ["Rowing", "Erg", "Indoor rowing", "Concept2"]],
    ["Ski erg", "Ski erg", ["lats", "triceps"], ["abs", "shoulders"], ["SkiErg"]],
    ["Elliptical", "Machine", ["quads", "glutes"], ["hamstrings", "calves"], ["Cross trainer"]],
    ["Stair climber", "Machine", ["quads", "glutes"], ["calves", "hamstrings"], ["Stairmaster", "Stairs", "Stair climbing", "Stepmill"]],
    ["Swim", "Pool", ["lats", "shoulders"], ["triceps", "upper_back"], ["Swimming", "Freestyle", "Laps"]],
    ["Jump rope", "Rope", ["calves"], ["quads", "shoulders"], ["Skipping", "Skipping rope", "Double unders"]],
    ["Jumping jacks", "Bodyweight", ["calves", "shoulders"], ["quads"], ["Star jumps"]],
    ["High knees", "Bodyweight", ["quads", "calves"], ["abs"]],
    ["Battle ropes", "Ropes", ["shoulders", "forearms"], ["abs", "upper_back", "biceps"], ["Battle rope"]],
    ["Boxing", "Gloves or bag", ["shoulders"], ["triceps", "abs", "obliques", "calves"], ["Shadow boxing", "Heavy bag", "Bag work"]],
    ["Kickboxing", "Bag", ["shoulders", "glutes"], ["quads", "abs", "obliques"], ["Muay Thai"]],
    ["HIIT", "Varies", [], [], ["Interval training", "Circuit training", "Circuit"]],
    ["Dance", "None", ["quads", "calves"], ["glutes"], ["Dancing", "Zumba"]],
  ]),
  ...group("Sports", "cardio", [
    ["Climbing", "Wall", ["forearms", "lats"], ["biceps", "upper_back", "shoulders"], ["Bouldering", "Rock climbing", "Indoor climbing"]],
    ["Soccer", "Ball", ["quads", "hamstrings", "calves"], ["glutes", "adductors"], ["Football", "Futsal"]],
    ["Basketball", "Ball", ["quads", "calves"], ["glutes", "hamstrings"]],
    ["Tennis", "Racket", ["shoulders", "forearms"], ["quads", "calves", "obliques"], ["Padel", "Squash", "Badminton"]],
    ["Volleyball", "Ball", ["quads", "calves", "shoulders"], ["glutes"]],
    ["Skiing", "Skis", ["quads", "glutes"], ["hamstrings", "abs"], ["Downhill skiing", "Snowboarding"]],
    ["Cross-country skiing", "Skis", ["quads", "lats"], ["glutes", "triceps", "shoulders"], ["Nordic skiing"]],
    ["Kayaking", "Kayak", ["lats", "shoulders"], ["obliques", "biceps", "abs"], ["Canoeing", "Paddling", "Stand-up paddle"]],
    ["Martial arts", "None", ["shoulders", "quads"], ["abs", "obliques", "glutes"], ["BJJ", "Judo", "Karate", "Wrestling", "MMA"]],
  ]),
  // Mobility: what each one stretches or moves; not counted as sets.
  ...group("Mobility", "mobility", [
    ["Hamstring stretch", "None", ["hamstrings"], []],
    ["Quad stretch", "None", ["quads"], [], ["Standing quad stretch"]],
    ["Calf stretch", "None", ["calves"], [], ["Wall calf stretch"]],
    ["Chest stretch", "Doorway", ["chest"], ["shoulders"], ["Doorway stretch", "Pec stretch"]],
    ["Child's pose", "Mat", ["lats", "lower_back"], []],
    ["Cat-cow", "Mat", ["lower_back"], ["abs"], ["Cat cow", "Cat-camel"]],
    ["Pigeon pose", "Mat", ["glutes"], [], ["Pigeon stretch"]],
    ["90/90 hip switch", "Mat", ["glutes"], ["adductors"], ["90/90", "90-90 stretch"]],
    ["Jefferson curl", "Light weight", ["lower_back", "hamstrings"], []],
    ["Thoracic rotation", "Mat", ["upper_back"], ["obliques"], ["Open book", "T-spine rotation"]],
    ["World's greatest stretch", "None", [], [], ["Worlds greatest stretch"]],
    ["Foam rolling", "Foam roller", [], [], ["Foam roll", "Foam roller"]],
    ["Stretching", "None", [], [], ["Stretch", "Static stretching", "Mobility work"]],
    ["Yoga", "Mat", [], [], ["Vinyasa", "Hatha yoga", "Yin yoga"]],
    ["Pilates", "Mat or reformer", ["abs"], ["obliques", "glutes"], ["Reformer pilates", "Mat pilates"]],
  ]),
];

/** "Pull-up", "pull up" and "Pullups" are the same exercise. */
export function normalizeExerciseName(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]/g, "");
}

const BY_NAME = new Map<string, LibraryExercise>();
for (const e of LIBRARY) {
  for (const n of [e.name, ...e.aliases]) BY_NAME.set(normalizeExerciseName(n), e);
}

/** The library entry for a name as written, also without a plural "s" or with its equipment in brackets. */
export function findExercise(name: string): LibraryExercise | null {
  const exact = (s: string) => {
    const n = normalizeExerciseName(s);
    return BY_NAME.get(n) ?? (n.endsWith("s") ? BY_NAME.get(n.slice(0, -1)) ?? null : null);
  };
  const found = exact(name);
  if (found) return found;
  // "Bench Press (Dumbbell)", as Strong and Hevy write them: the equipment in brackets.
  const m = name.match(/^(.+?)\s*\(([^)]*)\)\s*$/);
  return m ? exact(`${m[2]} ${m[1]}`) ?? exact(`${m[1]} ${m[2]}`) ?? exact(m[1]) : null;
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
 * Sets per muscle over some logged workouts: each done set counts 1 for its exercise's primary
 * muscles and 0.5 for its secondary ones. Cardio, sports and stretches aren't counted.
 */
export function muscleSets(logs: { exercises: { name: string; kind?: string; muscles?: MuscleId[] | null; sets: { done?: boolean }[] }[] }[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const log of logs) {
    for (const ex of log.exercises) {
      if (ex.kind === "cardio") continue;
      const done = ex.sets.filter((s) => s.done !== false).length;
      if (!done) continue;
      const m = exerciseMuscles(ex.name, ex.muscles);
      if (m.kind === "cardio" || m.kind === "mobility") continue;
      for (const id of m.primary) out[id] = (out[id] ?? 0) + done;
      for (const id of m.secondary) out[id] = (out[id] ?? 0) + done * 0.5;
    }
  }
  return out;
}

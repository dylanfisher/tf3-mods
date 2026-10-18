// Run colors of comparisons: run i (in data order) gets color i % RUN_COLORS, the theme's --c0..--c3. The class lists
// are literal so Tailwind sees them; use these instead of building "text-run-" + n.

const RUN_COLORS = 4;

type RunColor = 0 | 1 | 2 | 3;

export const runColor = (i: number): RunColor => (((i % RUN_COLORS) + RUN_COLORS) % RUN_COLORS) as RunColor;

/** Text in the run's color (run names, column heads). */
export const RUN_TEXT: Record<RunColor, string> = { 0: "text-run-0", 1: "text-run-1", 2: "text-run-2", 3: "text-run-3" };

/** Fill in the run's color (dots). */
const RUN_BG: Record<RunColor, string> = { 0: "bg-run-0", 1: "bg-run-1", 2: "bg-run-2", 3: "bg-run-3" };

/** A tone that is a run color or muted (verdict categories). */
type RunTone = `run-${RunColor}` | "muted";

export const TONE_BG: Record<RunTone, string> = {
  "run-0": RUN_BG[0], "run-1": RUN_BG[1], "run-2": RUN_BG[2], "run-3": RUN_BG[3], muted: "bg-muted-foreground",
};

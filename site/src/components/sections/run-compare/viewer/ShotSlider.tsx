// Two runs' shots of one unit over each other, split by a draggable line (the shared BeforeAfter slider).
import BeforeAfter from "@/components/site/BeforeAfter";
import type { ModelRun, ModelUnit } from "../types";
import { Picture, SHOT_SIZES } from "./parts";

export function ShotSlider({ unit, a, b }: { unit: ModelUnit; a: ModelRun; b: ModelRun }) {
  const ra = unit.runs[a.id], rb = unit.runs[b.id];
  return (
    <BeforeAfter
      className="max-w-shot"
      left={{ label: `A · ${a.label} · ${ra?.name ?? "-"}`, render: ra?.img && ((p) => <Picture img={ra.img!} alt={a.label} sizes={SHOT_SIZES} eager {...p} />) }}
      right={{ label: `B · ${b.label} · ${rb?.name ?? "-"}`, render: rb?.img && ((p) => <Picture img={rb.img!} alt={b.label} sizes={SHOT_SIZES} eager {...p} />) }}
    />
  );
}

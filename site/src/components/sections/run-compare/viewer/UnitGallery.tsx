// Single-run pages: a card per unit (its shot, facts and flags) that picks it in the viewer, then the units the run
// created (links to their shots).
import { cn } from "@/lib/utils";
import { lightboxAttrs } from "@/lib/lightbox";
import type { CompareModel, ModelRun, ModelUnit } from "../types";
import { Facts, H2, Hint, NoShot, Picture, Tag } from "./parts";

const CARD_SIZES = "(min-width: 640px) 33vw, 100vw";

export function UnitGallery({ hint, units, run, current, extras, onPick }: {
  hint: string;
  units: ModelUnit[];
  run: ModelRun;
  current: number;
  extras?: CompareModel["extras"];
  onPick: (index: number) => void;
}) {
  return (
    <section>
      <H2>Gallery</H2>
      <Hint className="mb-2.5">{hint}</Hint>
      <div className="card-grid gap-3">
        {units.map((u, i) => {
          const r = u.runs[run.id];
          if (!r) return null;
          return (
            <button
              key={u.nn}
              type="button"
              onClick={() => onPick(i)}
              className={cn("flex min-w-0 flex-col rounded-xl border bg-card p-2 text-left transition-colors hover:border-brand focus-visible:border-brand", i === current ? "border-brand" : "border-border")}
            >
              {r.img ? <Picture img={r.img} alt={r.name} sizes={CARD_SIZES} className="block aspect-video w-full rounded-md bg-chip object-cover" /> : <NoShot />}
              <h3 className="mx-0.5 mt-2 mb-0.5 text-subhead font-semibold">{u.nn} · {r.name}</h3>
              <Facts facts={r.facts} />
              {r.flags && <p className="mx-0.5 text-meta text-muted-foreground">{r.flags}</p>}
            </button>
          );
        })}
        {extras?.rows.filter((x) => x.run === run.id).map((x) => (
          <a key={x.name} href={x.img?.full ?? undefined} {...(x.img ? lightboxAttrs({ src: x.img.full, title: x.name }) : {})} className="flex min-w-0 flex-col rounded-xl border border-border bg-card p-2 transition-colors hover:border-brand">
            {x.img ? <Picture img={x.img} alt={x.name} sizes={CARD_SIZES} className="block aspect-video w-full rounded-md bg-chip object-cover" /> : <NoShot />}
            <h3 className="mx-0.5 mt-2 mb-0.5 text-subhead font-semibold">{x.name}{extras.tag && <Tag>{extras.tag}</Tag>}</h3>
            <Facts facts={x.facts} />
          </a>
        ))}
      </div>
    </section>
  );
}

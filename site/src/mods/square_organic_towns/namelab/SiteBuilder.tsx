// The site builder: presets, tag groups (toggle a tag, set its strength) and the ranked tags the scorer sees.
import { ChevronRight } from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { cn } from "@/lib/utils";
import { LabSlider, Muted, WeightPills } from "./bits.tsx";
import { tagGroups, type Lab } from "./engine.ts";
import type { LabState } from "./types.ts";

export function SiteBuilder({ lab, S, set }: { lab: Lab; S: LabState; set: (p: Partial<LabState>) => void }) {
  const D = lab.D;
  // groups the visitor opened or closed; the others follow "open when a tag is on" (as the old page)
  const [open, setOpen] = useState<Record<string, boolean>>({});
  const ranked = lab.ranked(lab.siteW(S));
  const setTag = (t: string, v: number | null) => {
    const site = { ...S.site };
    if (v == null) delete site[t];
    else site[t] = v;
    set({ site, preset: null });
  };
  return (
    <aside aria-label="Site builder" className="min-w-0 rounded-xl border border-border bg-card p-3 lg:sticky lg:top-chrome-pad lg:max-h-[calc(100dvh-var(--spacing-chrome-pad)-1rem)] lg:overflow-auto">
      <h2 className="text-base font-semibold">Site</h2>
      <Muted className="mt-0.5">Presets, or toggle tags and set their strength (the weights ot_placename.siteTags gives; 0.2 counts).</Muted>
      <div className="my-2 flex flex-wrap gap-1.5">
        {Object.keys(D.presets).map((p) => (
          <button
            key={p}
            type="button"
            aria-pressed={S.preset === p}
            onClick={() => {
              const site = { ...D.presets[p] };
              for (const k in site) if (site[k] < 0.2) delete site[k];
              set({ site, preset: p });
            }}
            className={cn(
              "rounded-full border px-2.5 py-0.5 text-hint transition-colors",
              S.preset === p ? "border-brand bg-card font-semibold" : "border-transparent bg-chip hover:border-border",
            )}
          >
            {p}
          </button>
        ))}
      </div>
      {tagGroups(D).map(([g, tags]) => {
        const on = tags.filter((t) => S.site[t] >= 0.2).length;
        return (
          <Collapsible key={g} open={open[g] ?? (!!on || g === "Rivers" || g === "Lakes")} onOpenChange={(o) => setOpen((m) => ({ ...m, [g]: o }))} className="border-t border-border py-1">
            <CollapsibleTrigger className="group flex w-full items-center gap-1 py-0.5 text-left text-dense font-semibold">
              <ChevronRight className="size-3.5 text-muted-foreground transition-transform group-data-[panel-open]:rotate-90" />
              {g}
              {on > 0 && <span className="ml-1 min-w-[18px] rounded-full bg-brand px-1.5 text-center text-tag text-on-brand">{on}</span>}
            </CollapsibleTrigger>
            <CollapsibleContent>
              <div className="flex flex-col gap-1 py-1">
                {tags.map((t) => {
                  const v = S.site[t];
                  const act = v >= 0.2;
                  return (
                    <div key={t} className={cn("grid grid-cols-[108px_1fr_34px] items-center gap-2 text-dense", act ? "text-foreground" : "text-muted-foreground")}>
                      <label className="flex cursor-pointer items-center gap-1.5 truncate">
                        <Checkbox checked={act} onCheckedChange={(c) => setTag(t, c ? 0.8 : null)} />
                        {t}
                      </label>
                      <LabSlider label={`${t} strength`} min={0.2} max={1} value={act ? v : 0.8} disabled={!act} onChange={(nv) => setTag(t, nv)} />
                      <span className="text-right text-tag tabular-nums">{act ? (+v).toFixed(2) : ""}</span>
                    </div>
                  );
                })}
              </div>
            </CollapsibleContent>
          </Collapsible>
        );
      })}
      <p className="mt-2.5 mb-1 text-hint">
        <b>Ranked</b> <span className="text-muted-foreground">(weight × specificity)</span>
      </p>
      <div className="text-hint">
        {ranked.length ? <WeightPills list={ranked} max={8} /> : <span className="text-muted-foreground">No tags: only the "any" parts fit.</span>}
      </div>
      <Button variant="outline" size="sm" className="mt-2.5" onClick={() => set({ site: {}, preset: null })}>
        Clear all tags
      </Button>
    </aside>
  );
}

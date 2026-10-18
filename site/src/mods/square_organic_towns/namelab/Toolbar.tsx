// The lab's controls: language, climate, generator, seed, dialect, affix gate, character town, word budget, map
// sharing, count; Generate, Export, Reset.
import { Dices } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { LabeledCheckbox, LabeledSelect } from "@/components/site/fields";
import { LabSlider } from "./bits.tsx";
import { baseLang, CLIMATES, LANG_NAMES, MODES, u, type Lab } from "./engine.ts";
import type { LabState } from "./types.ts";

type Set = (patch: Partial<LabState>) => void;

export function Toolbar({ lab, S, set, onGenerate, onExport, onReset }: {
  lab: Lab; S: LabState; set: Set; onGenerate: () => void; onExport: () => void; onReset: () => void;
}) {
  const D = lab.D;
  const L = lab.M.lang(S.lang);
  const dialects: string[] = (L?.groups || []).map((d: string) => u(d));
  const dialect = S.dialect !== "auto" && S.dialect !== "none" && !dialects.includes(S.dialect) ? "auto" : S.dialect;
  const modeValue = S.view === "all" ? "all" : S.mode;
  return (
    <div className="mb-3 flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-border pb-3">
      <LabeledSelect
        label="Language"
        value={S.lang}
        options={D.pn.LANGS.filter((l) => D.lang[baseLang(l)]).map((l) => ({ value: l, label: LANG_NAMES[l] || l }))}
        onChange={(v) => set({ lang: v })}
      />
      <LabeledSelect
        label="Climate"
        title="The map's climate (ot_climate): its own words (palms and reefs, mesas, fells) and the words it rules out"
        value={S.climate || "temperate"}
        options={CLIMATES}
        onChange={(v) => set({ climate: v })}
      />
      <LabeledSelect
        label="Rules"
        title="Naming rules: evocative (§61) adds whole names that plainly describe the site (Two Waters, Seven Oaks), every character town's kind and the industry near; descriptive (§60) names what is at the site, few quiet, opaque or dialect names; review (§53) the naming review's gazetteer mix (40 % quiet names, personal-name stems)"
        value={S.rules || "s61"}
        options={[{ value: "s61", label: "evocative (§61)" }, { value: "s60", label: "descriptive (§60)" }, { value: "s53", label: "review (§53)" }]}
        onChange={(v) => set({ rules: v === "s53" ? "s53" : (v === "s60" ? "s60" : "s61") })}
      />
      <ToggleGroup
        aria-label="Generator"
        variant="outline"
        size="sm"
        spacing={0}
        className="flex-wrap"
        value={[modeValue]}
        onValueChange={(v) => {
          const m = (v as string[])[0];
          if (!m) return;
          if (m === "all") set({ view: "all" });
          else set({ view: "grid", mode: m as LabState["mode"] });
        }}
      >
        {[...MODES.map((m) => ({ id: m.id as string, name: m.name })), { id: "all", name: "All side by side" }].map((m) => (
          <ToggleGroupItem key={m.id} value={m.id} className="aria-pressed:bg-primary aria-pressed:text-primary-foreground data-[pressed]:bg-primary data-[pressed]:text-primary-foreground">
            {m.name}
          </ToggleGroupItem>
        ))}
      </ToggleGroup>
      <label className="inline-flex items-center gap-1.5 text-sm text-muted-foreground">
        Seed
        <Input
          type="number"
          min={1}
          aria-label="Seed"
          className="w-24 bg-background text-foreground"
          key={`seed-${S.seed}`}
          defaultValue={S.seed}
          onBlur={(e) => set({ seed: Math.max(1, parseInt(e.currentTarget.value, 10) || 1) })}
          onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.blur(); }}
        />
      </label>
      <Button variant="outline" size="icon" title="Next seed" aria-label="Next seed" onClick={() => set({ seed: (S.seed % 99999) + 1 })}>
        <Dices />
      </Button>
      <LabeledSelect
        label="Dialect"
        value={dialect}
        disabled={dialects.length === 0}
        options={[{ value: "auto", label: "Dialect areas (as in game)" }, { value: "none", label: "None" }, ...dialects.map((d) => ({ value: d, label: d }))]}
        onChange={(v) => set({ dialect: v })}
      />
      <label className="inline-flex items-center gap-2 text-sm text-muted-foreground" title="Affix probability: a lab gate in front of the mod's affix rule (100% = the mod's behavior)">
        Affix
        <LabSlider label="Affix probability" className="w-28" value={S.affixP} onChange={(v) => set({ affixP: v })} />
        <span className="w-9 text-right text-foreground tabular-nums">{Math.round(S.affixP * 100)}%</span>
      </label>
      <LabeledCheckbox label="Character town" checked={!!S.character} onChange={(v) => set({ character: v })} />
      <LabeledCheckbox
        label="Word budget"
        title="The map's word budget: a generic word (Lake, Forest, -see ...) at most once per 8 towns of the run"
        checked={S.budget !== false}
        onChange={(v) => set({ budget: v })}
      />
      <LabeledSelect
        label="Towns"
        value={S.shared ? "1" : "0"}
        options={[{ value: "1", label: "on one map" }, { value: "0", label: "each on its own map" }]}
        onChange={(v) => set({ shared: v === "1" })}
      />
      <label className="inline-flex items-center gap-1.5 text-sm text-muted-foreground">
        Count
        <Input
          type="number"
          min={5}
          max={200}
          aria-label="Count"
          className="w-20 bg-background text-foreground"
          key={`count-${S.opt.count}`}
          defaultValue={S.opt.count}
          onBlur={(e) => set({ opt: { ...S.opt, count: Math.max(5, Math.min(200, parseInt(e.currentTarget.value, 10) || 50)) } })}
          onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.blur(); }}
        />
      </label>
      <Button onClick={onGenerate}>Generate</Button>
      <span className="hidden flex-1 sm:block" />
      <Button variant="outline" title="Copy and download your settings as JSON" onClick={onExport}>Export</Button>
      <Button variant="outline" title="Reset everything" onClick={onReset}>Reset</Button>
    </div>
  );
}

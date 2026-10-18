// The lab's lower tabs: this map, morpheme lists, constants, mode options, pinned and rated, stop names, port check,
// export.
import { ThumbsDown, ThumbsUp, X } from "lucide-react";
import { useState, type ComponentProps, type ReactNode } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { cn } from "@/lib/utils";
import { LabeledCheckbox, LabeledSelect } from "@/components/site/fields";
import { EntryLine, LabSlider, Muted, Pill, TableBox, td, th, WeightPills } from "./bits.tsx";
import { baseLang, f2, LANG_NAMES, MODE, u, withListText, type Lab, type ListKind } from "./engine.ts";
import type { PortResult } from "./port-check.ts";
import type { LabState } from "./types.ts";

type Set = (p: Partial<LabState>) => void;
interface P { lab: Lab; S: LabState; set: Set }

const H3 = ({ children }: { children: ReactNode }) => <h3 className="mb-1.5 text-subhead font-semibold">{children}</h3>;
const H4 = ({ children }: { children: ReactNode }) => <h4 className="mt-3.5 mb-1.5 text-dense font-semibold">{children}</h4>;
const CGrid = ({ children }: { children: ReactNode }) => <div className="mb-3 card-grid-fit gap-4">{children}</div>;
const chg = "bg-[color-mix(in_oklch,var(--warn)_14%,transparent)]";

/** Text field that commits on blur or Enter (like the old page's change events). */
function CommitInput({ value, onCommit, className, ...rest }: { value: string; onCommit: (v: string) => void; className?: string } & Omit<ComponentProps<typeof Input>, "value" | "defaultValue">) {
  return (
    <Input
      key={value}
      defaultValue={value}
      onBlur={(e) => { if (e.currentTarget.value !== value) onCommit(e.currentTarget.value); }}
      onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.blur(); }}
      className={className}
      {...rest}
    />
  );
}
function CommitTextarea({ value, onCommit, rows, placeholder }: { value: string; onCommit: (v: string) => void; rows: number; placeholder?: string }) {
  return (
    <Textarea
      key={value}
      defaultValue={value}
      rows={rows}
      spellCheck={false}
      placeholder={placeholder}
      onBlur={(e) => { if (e.currentTarget.value !== value) onCommit(e.currentTarget.value); }}
      className="font-mono text-hint"
    />
  );
}

// ---------------------------------------------------------------- This map
export function MapPanel({ lab, S, onLoadTown }: P & { onLoadTown: (i: number) => void }) {
  const mp = lab.D.map;
  if (!mp || !mp.towns || !mp.towns.length) {
    return (
      <Muted>
        No map in the lab data. Export one from a game log with NAME lines:{" "}
        <code>uv run plans/square_organic_towns/names/export_names.py --session live</code>
      </Muted>
    );
  }
  const sm = mp.summary || {};
  const labNames = lab.mapLabNames(S);
  return (
    <>
      <Muted className="mb-2">
        Seed text <b className="text-foreground">{mp.seedText || "-"}</b> · {mp.towns.length} towns · list {sm.list || "-"} · generator {sm.gen || "-"} · rivers{" "}
        {sm.rivers || "-"} · lakes {sm.lakes || "-"} · from <code>{mp.session || mp.log}</code>. Tags are the log's top six (weight × specificity);{" "}
        <b>Load site</b> turns them back into weights. <b>Lab now</b>: the same towns through the lab's generator with your edits (lab seed; the game's
        map seed is not in the log).
      </Muted>
      <TableBox>
        <table className="w-full border-collapse text-dense">
          <thead><tr>{["Game list → generated", "Parts", "Tags", "Water", "Dialect", "Score", "Lab now", ""].map((h) => <th key={h} className={th}>{h}</th>)}</tr></thead>
          <tbody>
            {mp.towns.map((t, i) => {
              const ln = labNames[t.id];
              return (
                <tr key={String(t.id)}>
                  <td className={cn(td, "min-w-[220px]")}>
                    <span className="text-muted-foreground">{t.old}</span> → <b>{t.new}</b>
                    {t.character && <Pill className="ml-1">character</Pill>}
                  </td>
                  <td className={td}>
                    {t.parts.filter(Boolean).join(" + ")}
                    <br /><span className="text-meta text-muted-foreground">feature {t.feature}</span>
                  </td>
                  <td className={td}><WeightPills list={t.tags} /></td>
                  <td className={td}>
                    {[t.river ? "river " + t.river : "", t.lake ? "lake " + t.lake : ""].filter(Boolean).join(", ") || "-"}
                    <br /><span className="text-meta text-muted-foreground">{t.read || ""}</span>
                  </td>
                  <td className={td}>{t.dialect || "-"}</td>
                  <td className={td}>{f2(t.score)}</td>
                  <td className={td}>
                    {ln ? <><b>{ln.name}</b><br /><span className="text-meta text-muted-foreground">{ln.parts.join(" + ")}</span></> : "-"}
                  </td>
                  <td className={td}><Button variant="outline" size="xs" onClick={() => onLoadTown(i)}>Load site</Button></td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </TableBox>
    </>
  );
}

// ---------------------------------------------------------------- Morpheme lists
const SYNTAX: Record<ListKind, string> = {
  spec: 'stem tag tag:weight @group * =class +p +c ~gender ("Ash ash", "Brad vale:.6 plain:.5 @saxon")',
  gen: '-suffix, _Word after, Word_ before, Pre^ joined prefix, Pre- hyphen prefix, then tags ("-ford ford river:.5 =cross")',
  affix: '%s the name, %l lower-case, %r river, %k lake, %p saint; "_" is a space ("%s-on-Sea coast sandy:.6")',
};
const KIND_NAME: Record<ListKind, string> = { spec: "Stems", gen: "Generics", affix: "Affixes" };
const EXAMPLE: Record<ListKind, string> = { spec: "Heron lake:.6 marsh:.5", gen: "-heron lake:.5", affix: "%s-by-the-Lake lake" };

export function ListsPanel({ lab, S, set }: P) {
  const [raw, setRaw] = useState(false);
  const [add, setAdd] = useState("");
  const lang = S.lang, kind = S.listKind;
  const setText = (txt: string) => set({ edits: withListText(lab, S, lang, kind, txt) });
  const lines = () => lab.curText(S, lang, kind).split("\n").filter((l) => l.trim() !== "");
  if (raw) {
    return <RawList lab={lab} S={S} onApply={(t) => { setText(t); setRaw(false); }} onCancel={() => setRaw(false)} />;
  }
  const rows = lab.listRows(S, kind);
  const flt = (S.listFilter || "").toLowerCase();
  let shown = rows.filter((r) => !flt || r.line.toLowerCase().includes(flt));
  if (S.listSort === "fit") shown = shown.slice().sort((a, c) => c.fit - a.fit || a.i - c.i);
  const edited = !!(S.edits[baseLang(lang)] || {})[kind];
  const L = lab.M.lang(lang);
  const doAdd = () => {
    const v = add.trim();
    if (!v) return;
    const ls = lines();
    ls.unshift(v);
    setText(ls.join("\n") + "\n");
    setAdd("");
  };
  return (
    <>
      <div className="mb-1.5 flex flex-wrap items-center gap-2">
        <ToggleGroup aria-label="List" variant="outline" size="sm" spacing={0} value={[kind]} onValueChange={(v) => { const k = (v as string[])[0]; if (k) set({ listKind: k as ListKind }); }}>
          {(["spec", "gen", "affix"] as ListKind[]).map((k) => (
            <ToggleGroupItem key={k} value={k} className="data-[pressed]:bg-primary data-[pressed]:text-primary-foreground">
              {KIND_NAME[k]} ({lab.curText(S, lang, k).split("\n").filter((l) => l.trim()).length})
            </ToggleGroupItem>
          ))}
        </ToggleGroup>
        <Input type="search" placeholder="Filter" aria-label="Filter lines" value={S.listFilter} onChange={(e) => set({ listFilter: e.currentTarget.value })} className="w-44 bg-background" />
        <LabeledSelect label="Sort" value={S.listSort} options={[{ value: "fit", label: "by fit to this site" }, { value: "file", label: "file order" }]} onChange={(v) => set({ listSort: v as LabState["listSort"] })} />
        <span className="flex-1" />
        {edited && (
          <>
            <Pill tone="warn">edited</Pill>
            <Button variant="outline" size="sm" onClick={() => setText(lab.origText(lang, kind))}>Revert this list</Button>
          </>
        )}
        <Button variant="outline" size="sm" onClick={() => setRaw(true)}>Edit as text</Button>
      </div>
      <Muted className="mb-2">
        {LANG_NAMES[lang]} · ot_placename_lang.lua <code>{kind}</code> · syntax: {SYNTAX[kind]}. Edit a line and press Enter (or leave the field); the names
        update. Lines you changed or added are marked.
      </Muted>
      <div className="mb-2 flex gap-1.5">
        <Input
          value={add}
          onChange={(e) => setAdd(e.currentTarget.value)}
          onKeyDown={(e) => { if (e.key === "Enter") doAdd(); }}
          placeholder={`New line, e.g. ${EXAMPLE[kind]}`}
          aria-label="New line"
          className="min-w-0 flex-1 bg-background"
        />
        <Button variant="outline" onClick={doAdd}>Add</Button>
      </div>
      <TableBox>
        <table className="w-full border-collapse text-dense">
          <thead><tr><th className={th}>Fit</th><th className={th}>Line</th><th className={th}>Parsed</th><th className={th} /></tr></thead>
          <tbody>
            {shown.map((r) => (
              <tr key={`${r.i}:${r.line}`} className={r.changed ? chg : undefined}>
                <td className={cn(td, "w-[1%] text-right whitespace-nowrap tabular-nums", r.fit > 0 ? "" : "text-muted-foreground")}>{f2(r.fit)}</td>
                <td className={td}>
                  <CommitInput
                    value={r.line}
                    aria-label={`Line ${r.i + 1}`}
                    className="h-7 min-w-[260px] border-transparent bg-transparent font-mono text-hint focus-visible:border-ring focus-visible:bg-background dark:bg-transparent"
                    onCommit={(v) => {
                      const ls = lines();
                      if (v.trim() === "") ls.splice(r.i, 1);
                      else ls[r.i] = v;
                      setText(ls.join("\n") + "\n");
                    }}
                  />
                </td>
                <td className={cn(td, "text-hint")}>{r.e ? <EntryLine e={r.e} /> : null}</td>
                <td className={td}>
                  <Button variant="ghost" size="icon-xs" title="Remove" aria-label="Remove line" onClick={() => { const ls = lines(); ls.splice(r.i, 1); setText(ls.join("\n") + "\n"); }}>
                    <X />
                  </Button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </TableBox>
      <Muted className="mt-2">
        Dialects ({LANG_NAMES[lang]}):{" "}
        {(L?.dialects || []).length
          ? (L.dialects as [string, number, Record<string, number>][]).map((d, i) => (
              <span key={i}>
                {i > 0 && " · "}
                <b className="text-foreground">{u(d[0])}</b> weight {d[1]} →{" "}
                {Object.entries(d[2] || {}).map(([k, v]) => u(k) + " ×" + v).join(", ") || "neutral"}
              </span>
            ))
          : "none"}
      </Muted>
    </>
  );
}

function RawList({ lab, S, onApply, onCancel }: { lab: Lab; S: LabState; onApply: (t: string) => void; onCancel: () => void }) {
  const [txt, setTxt] = useState(() => lab.curText(S, S.lang, S.listKind));
  return (
    <>
      <div className="mb-2 flex flex-wrap items-center gap-2">
        <Muted>{LANG_NAMES[S.lang]} · <code>{S.listKind}</code> as text (one entry per line).</Muted>
        <Button size="sm" onClick={() => onApply(txt)}>Apply</Button>
        <Button variant="outline" size="sm" onClick={onCancel}>Back to the table</Button>
      </div>
      <Textarea rows={28} spellCheck={false} value={txt} onChange={(e) => setTxt(e.currentTarget.value)} className="font-mono text-hint" aria-label="List as text" />
    </>
  );
}

// ---------------------------------------------------------------- Constants
const CONST_GROUPS: [string, string[]][] = [
  ["Scoring", ["SPEC_K", "PAIR_BONUS", "USE_GEN", "USE_SPEC", "JITTER", "ANY", "PERS_K", "RARE_ON", "RARE_OFF"]],
  ["Affixes", ["AFFIX_COST", "AFFIX_COST_CH", "USE_AFFIX"]],
  ["Search and length", ["TOP_SPEC", "TOP_GEN", "WIDE_SPEC", "WIDE_GEN", "MAX_BASE", "MAX_FULL", "MAX_KANJI"]],
  ["Map (not used by the lab's 50-name runs)", ["REGION_KM", "RIVER_LINK_M", "RIVER_DEG", "LAKE_LINK_M", "SAT_NEAR", "SAT_RATIO", "SAT_P"]],
];

export function ConstsPanel({ lab, S, set }: P) {
  const D = lab.D, C0 = D.pn.consts;
  const commit = (field: "consts" | "spec", base: Record<string, number>, k: string, txt: string) => {
    const v = parseFloat(txt);
    if (isNaN(v)) return;
    const next = { ...S[field] };
    if (v === base[k]) delete next[k];
    else next[k] = v;
    set({ [field]: next } as Partial<LabState>);
  };
  const Row = ({ k, v0, cur, field, base }: { k: string; v0: number; cur: number; field: "consts" | "spec"; base: Record<string, number> }) => (
    <tr className={cur !== v0 ? chg : undefined}>
      <th className="py-0.5 pr-2 text-left text-hint font-semibold">{k}</th>
      <td className="py-0.5 pr-1.5">
        <CommitInput type="number" step="any" aria-label={k} value={String(cur)} onCommit={(t) => commit(field, base, k, t)} className="h-7 w-24 bg-background text-hint" />
      </td>
      <td className="py-0.5 text-hint text-muted-foreground tabular-nums">{v0}</td>
    </tr>
  );
  const Head = () => <tr><th /><th className="text-left text-hint font-semibold">Value</th><th className="text-left text-hint font-semibold">Mod</th></tr>;
  return (
    <>
      <Muted className="mb-2">ot_placename constants (M.*) and tag specificity (M.SPEC). Changes apply to every mode at once and go into the export.</Muted>
      <CGrid>
        {CONST_GROUPS.map(([g, ks]) => (
          <section key={g} className="min-w-0">
            <H3>{g}</H3>
            <table><tbody><Head />{ks.filter((k) => k in C0).map((k) => <Row key={k} k={k} v0={C0[k]} cur={lab.M.C[k]} field="consts" base={C0} />)}</tbody></table>
          </section>
        ))}
        <section className="min-w-0">
          <H3>Tag specificity (SPEC)</H3>
          <table><tbody><Head />{D.pn.TAGS.filter((t) => t !== "any").map((t) => <Row key={t} k={t} v0={D.pn.SPEC[t]} cur={lab.M.SPEC[t]} field="spec" base={D.pn.SPEC} />)}</tbody></table>
        </section>
      </CGrid>
      <Button variant="outline" onClick={() => set({ consts: {}, spec: {} })}>Reset constants and specificity</Button>
    </>
  );
}

// ---------------------------------------------------------------- Mode options
export function OptsPanel({ lab, S, set }: P) {
  const id = lab.ideas(S, S.lang), bl = baseLang(S.lang);
  const tr = lab.trainingSet(S.lang);
  const setIdea = (k: "old" | "adj" | "oldGroups", v: string) => set({ ideas: { ...S.ideas, [bl]: { ...(S.ideas[bl] || {}), [k]: v } } });
  const opt = (p: Partial<LabState["opt"]>) => set({ opt: { ...S.opt, ...p } });
  const pct = (v: number) => <span className="w-9 text-right text-foreground tabular-nums">{Math.round(v * 100)}%</span>;
  return (
    <>
      <CGrid>
        <section className="flex min-w-0 flex-col gap-2">
          <H3>Real-name remix</H3>
          <label className="inline-flex items-center gap-2 text-sm text-muted-foreground">
            Chain order
            <CommitInput type="number" min={1} max={5} value={String(S.opt.order)} onCommit={(t) => opt({ order: Math.max(1, Math.min(5, parseInt(t, 10) || 3)) })} className="h-7 w-20 bg-background" />
          </label>
          <label className="inline-flex items-center gap-2 text-sm text-muted-foreground">
            Tag bias <LabSlider label="Tag bias" className="w-36" value={S.opt.bias} onChange={(v) => opt({ bias: v })} /> {pct(S.opt.bias)}
          </label>
          <Muted>Share of names that start with a fitting stem or end with a fitting generic (half each); the rest come from the chain alone.</Muted>
          <LabeledCheckbox label="Train on one-word names only" checked={S.opt.singleWords} onChange={(v) => opt({ singleWords: v })} />
          <Muted>Training set: {tr.n} names from {tr.sources.join(", ") || "-"}.</Muted>
        </section>
        <section className="flex min-w-0 flex-col gap-2">
          <H3>Old forms</H3>
          <label className="inline-flex items-center gap-2 text-sm text-muted-foreground">
            Old prefix / suffix share <LabSlider label="Old prefix / suffix share" className="w-32" value={S.opt.oldShare} onChange={(v) => opt({ oldShare: v })} /> {pct(S.opt.oldShare)}
          </label>
          <LabeledCheckbox label="Old spellings" checked={S.opt.spelling} onChange={(v) => opt({ spelling: v })} />
          <label className="inline-flex items-center gap-2 text-sm text-muted-foreground">
            Groups <CommitInput value={id.oldGroups} placeholder="celtic norse" onCommit={(v) => setIdea("oldGroups", v)} className="h-7 min-w-0 flex-1 bg-background" />
          </label>
          <Muted>Spelling rules ({LANG_NAMES[S.lang]}): <code>regex =&gt; replacement</code> per line.</Muted>
          <CommitTextarea rows={10} value={id.old} onCommit={(v) => setIdea("old", v)} />
        </section>
        <section className="flex min-w-0 flex-col gap-2">
          <H3>Descriptive</H3>
          <Muted>Extra terrain / color words ({LANG_NAMES[S.lang]}) in the stem syntax; joined with the inventory's terrain generics.</Muted>
          <CommitTextarea rows={12} value={id.adj} onCommit={(v) => setIdea("adj", v)} />
        </section>
      </CGrid>
      {S.ideas[bl] && (
        <Button variant="outline" onClick={() => { const ideas = { ...S.ideas }; delete ideas[bl]; set({ ideas }); }}>
          Revert the idea lists of this language
        </Button>
      )}
    </>
  );
}

// ---------------------------------------------------------------- Pinned and rated
export function RatedPanel({ S, set }: P) {
  const pins = Object.values(S.pinned), rated = Object.values(S.ratings).sort((a, c) => (c.r ?? 0) - (a.r ?? 0));
  const Item = ({ r, kind }: { r: (typeof pins)[number]; kind: "p" | "r" }) => (
    <li className="flex items-start gap-1.5 border-b border-border py-1">
      <span className="min-w-0 flex-1">
        <b>{r.name}</b>{" "}
        <span className="text-hint text-muted-foreground">
          {MODE[r.mode] ? MODE[r.mode].name : r.mode} · {r.lang} · {(r.parts || []).join(" + ")} · {(r.site || []).join(", ")}
        </span>
        {kind === "r" && (r.r! > 0 ? <ThumbsUp className="ml-1 inline size-3.5 text-up" aria-label="good" /> : <ThumbsDown className="ml-1 inline size-3.5 text-down" aria-label="bad" />)}
      </span>
      <Button
        variant="ghost"
        size="icon-xs"
        title="Remove"
        aria-label="Remove"
        onClick={() => {
          const field = kind === "p" ? "pinned" : "ratings";
          const next = { ...S[field] };
          delete next[r.key];
          set({ [field]: next } as Partial<LabState>);
        }}
      >
        <X />
      </Button>
    </li>
  );
  return (
    <CGrid>
      <section className="min-w-0">
        <H3>Pinned ({pins.length})</H3>
        <ul>{pins.length ? pins.map((r) => <Item key={r.key} r={r} kind="p" />) : <li className="py-1 text-muted-foreground">Pin names with the pin button.</li>}</ul>
      </section>
      <section className="min-w-0">
        <H3>Rated ({rated.length})</H3>
        <ul>{rated.length ? rated.map((r) => <Item key={r.key} r={r} kind="r" />) : <li className="py-1 text-muted-foreground">Rate names with the thumbs up / down buttons.</li>}</ul>
      </section>
      <section className="min-w-0">
        <H3>Notes</H3>
        <Textarea rows={10} value={S.notes} placeholder="What should change? (goes into the export)" onChange={(e) => set({ notes: e.currentTarget.value })} aria-label="Notes" />
      </section>
    </CGrid>
  );
}

// ---------------------------------------------------------------- Stop names
/* eslint-disable @typescript-eslint/no-explicit-any */
export function StopPanel({ lab, S }: P) {
  const SL = lab.D.stop?.LANG || {};
  const keys = Object.keys(SL);
  const k = SL[S.lang] ? S.lang : SL[baseLang(S.lang)] ? baseLang(S.lang) : keys[0];
  const L: Record<string, any> = SL[k] || {};
  const Block = ({ title, obj }: { title: string; obj: Record<string, any> | undefined }) =>
    obj ? (
      <>
        <H4>{title}</H4>
        <table className="w-full"><tbody>
          {Object.entries(obj).map(([name, v]) => (
            <tr key={name}>
              <th className="w-28 py-0.5 pr-2 text-left align-top text-hint font-semibold">{name}</th>
              <td className="py-0.5 leading-loose">
                {(Array.isArray(v) ? v : typeof v === "object" ? Object.values(v) : [v]).map((x: any, i: number) => (
                  <Pill key={i} className="mr-1">{Array.isArray(x) ? x.join(" ") : String(x)}</Pill>
                ))}
              </td>
            </tr>
          ))}
        </tbody></table>
      </>
    ) : null;
  return (
    <>
      <Muted>ot_stopname.LANG (read-only): the parts of the composed stop names per theme. Language: <b className="text-foreground">{k}</b> (lists: {keys.join(", ")}).</Muted>
      <Block title="Generics" obj={L.gens} />
      <Block title="Stand-alone names" obj={L.solos} />
      <Block title="Specific parts" obj={L.specs} />
      <Block title="Other parts" obj={Object.fromEntries(Object.entries(L).filter(([kk, v]) => !["gens", "solos", "specs", "join", "own"].includes(kk) && v && typeof v === "object"))} />
    </>
  );
}

// ---------------------------------------------------------------- Port check
export function PortPanel({ port }: { port: PortResult | null | string }) {
  if (port == null) return <Muted>Running the port check…</Muted>;
  if (typeof port === "string") return <Muted>Port check failed: {port}</Muted>;
  const ok = port.ok === port.n && !port.parse.length;
  return (
    <>
      <p className="mb-2">
        <Pill tone={ok ? "ok" : "warn"}>{ok ? "match" : "differs"}</Pill> The TypeScript port gives <b>{port.ok} / {port.n}</b> of Lua's names
        (ot_placename.assign on synthetic maps: every preset twice, character towns, river chains, lakes, twins, the map's name shapes (planShapes,
        NEXT_PHASE_BRIEF 53), towns with the map survey's cues, a kept town, the word budget and tag rarity on; export_names.py runs them in Lua).
        Parser: {port.parse.length ? port.parse.length + " entries differ" : "every inventory line parses the same"}. Unedited data and constants.
      </p>
      <TableBox>
        <table className="w-full border-collapse text-dense">
          <thead><tr><th className={th}>Language</th><th className={th}>Match</th><th className={th}>First difference</th></tr></thead>
          <tbody>
            {port.langs.map((l) => (
              <tr key={l.lang}>
                <td className={td}>{l.lang}</td>
                <td className={cn(td, "whitespace-nowrap tabular-nums")}>{l.ok} / {l.n}</td>
                <td className={cn(td, "text-meta wrap-anywhere")}>{l.bad.length ? JSON.stringify(l.bad[0]) : "-"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </TableBox>
      <H4>Where the lab differs from the game</H4>
      <ul className="list-disc space-y-1 pl-5 text-dense">
        <li>Sites come from the site builder (weights per tag); the mod measures them (ot_placename.read / siteTags, not ported).</li>
        <li>
          "Generate" names n towns of the same site on one imaginary map (or each alone): dialect areas over a 7-wide grid, one river / lake name per five
          towns; the game links rivers by distance and axis (riverSystems, ported and checked here) and orders towns by distinctiveness.
        </li>
        <li>
          The 50-name runs name each town without the map's shape plan (any shape, as before NEXT_PHASE_BRIEF 53) and without twins ("Little …"); assign
          has both (checked above). A map mode with the plan is NEXT_PHASE_BRIEF 53 Part B.
        </li>
        <li>Affix probability is a lab gate in front of the mod's affix rule (100% = the mod's behavior).</li>
        <li>Districts and Works (related / works) are not ported.</li>
      </ul>
    </>
  );
}

// ---------------------------------------------------------------- Export
export function ExportPanel({ json, onExport }: { json: string; onExport: () => void }) {
  return (
    <>
      <Muted className="mb-2">
        Everything you changed: settings, constants, list edits (added / removed lines per list), idea lists, ratings, pins, notes. <b>Copy and download</b>{" "}
        puts it on the clipboard and saves <code>name-lab-export.json</code>; paste it to Claude with "implement this".
      </Muted>
      <Button onClick={onExport}>Copy and download</Button>
      <pre className="mt-2 max-h-[480px] overflow-auto rounded-lg border border-border bg-background p-2.5 text-meta break-words whitespace-pre-wrap">{json}</pre>
    </>
  );
}

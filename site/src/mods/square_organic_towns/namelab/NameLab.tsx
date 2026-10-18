// Organic Towns Name lab (React island): build a site from tags, generate names with the mod's generator (the TS port
// in gen.ts) and four other ideas, compare them side by side, edit the morpheme lists and constants, rate and pin
// names, export the settings. Visitor edits persist in localStorage; the data (data.json) is fetched on load.
import { useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { setTheme } from "@/lib/theme";
import { cn } from "@/lib/utils";
import { Pill } from "./bits.tsx";
import { LANG_NAMES, Lab, MODE, MODES, type ModeId, type NameResult } from "./engine.ts";
import * as NG from "./gen.ts";
import { ConstsPanel, ExportPanel, ListsPanel, MapPanel, OptsPanel, PortPanel, RatedPanel, StopPanel } from "./Panels.tsx";
import { run as runPortCheck, type PortResult } from "./port-check.ts";
import { NameCard, rkey, WhyPanel, type CardActions } from "./Results.tsx";
import { SiteBuilder } from "./SiteBuilder.tsx";
import { buildExport, clearState, defaults, loadState, saveState } from "./state.ts";
import { Toolbar } from "./Toolbar.tsx";
import type { LabState, NameData, RatedName } from "./types.ts";

export default function NameLab({ dataUrl }: { dataUrl: string }) {
  const [D, setD] = useState<NameData | null>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    fetch(dataUrl)
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then((d) => { if (live) setD(d); })
      .catch((e) => { if (live) setErr(String(e?.message || e)); });
    return () => { live = false; };
  }, [dataUrl]);
  if (err) return <p className="text-muted-foreground">Could not load the name data ({err}).</p>;
  if (!D) return <p className="text-muted-foreground">Loading the name data…</p>;
  return <LabView D={D} />;
}

const TABS: [string, string][] = [
  ["map", "This map"], ["lists", "Morpheme lists"], ["consts", "Constants"], ["opts", "Mode options"],
  ["rated", "Pinned and rated"], ["stop", "Stop names"], ["port", "Port check"], ["export", "Export"],
];

function LabView({ D }: { D: NameData }) {
  const lab = useMemo(() => new Lab(D), [D]);
  const [S, setS] = useState<LabState>(() => loadState(D));
  const [lock, setLock] = useState<string | null>(null);
  const [hover, setHover] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  const [port, setPort] = useState<PortResult | string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const toastT = useRef<ReturnType<typeof setTimeout>>(undefined);
  const topRef = useRef<HTMLDivElement>(null);

  const set = (patch: Partial<LabState>) => setS((s) => ({ ...s, ...patch }));

  // link parameter #theme=dark|light (as the old page): a one-off through the site's theme switch, the visitor's
  // saved choice stays
  useEffect(() => {
    const t = new URLSearchParams(location.hash.slice(1)).get("theme");
    if (t === "dark" || t === "light") setTheme(t, { persist: false });
  }, []);

  // persist (debounced)
  useEffect(() => {
    const t = setTimeout(() => saveState(S), 250);
    return () => clearTimeout(t);
  }, [S]);

  // the engine follows the edited constants, specificity and lists
  const engineVer = useMemo(() => {
    lab.rebuild(S);
    return Symbol();
  }, [lab, S.consts, S.spec, S.edits]); // eslint-disable-line react-hooks/exhaustive-deps

  // the port check (unedited data), once, after the first paint
  useEffect(() => {
    const t = setTimeout(() => {
      try { setPort(runPortCheck(D, NG)); } catch (e) { setPort(String((e as Error)?.message || e)); }
    }, 30);
    return () => clearTimeout(t);
  }, [D]);

  // generation runs on a deferred copy of the state, so sliders stay responsive
  const G = useDeferredValue(S);
  const results = useMemo(() => {
    void engineVer; void tick;
    if (G.view === "all") {
      const n = Math.max(6, Math.min(20, Math.round(G.opt.count / 4)));
      return { n, groups: MODES.map((m) => ({ mode: m.id, results: lab.generate(G, m.id, n) })) };
    }
    const rs = lab.generate(G, G.mode, G.opt.count);
    return { n: rs.filter((r) => r.name).length, groups: [{ mode: G.mode as ModeId, results: rs }] };
  }, [lab, engineVer, tick, G.view, G.mode, G.opt, G.lang, G.climate, G.rules, G.seed, G.dialect, G.affixP, G.character, G.shared, G.budget, G.site, G.ideas]); // eslint-disable-line react-hooks/exhaustive-deps

  const byId = useMemo(() => {
    const m = new Map<string, NameResult>();
    for (const g of results.groups) g.results.forEach((r, i) => m.set(`${g.mode}:${i}`, r));
    return m;
  }, [results]);
  const firstId = useMemo(() => [...byId.entries()].find(([, r]) => r.name)?.[0] ?? null, [byId]);
  const lockOk = lock != null && byId.has(lock) ? lock : null;
  const whyId = lockOk ?? (hover != null && byId.has(hover) ? hover : firstId);
  const why = whyId ? byId.get(whyId) ?? null : null;

  const w = lab.siteW(S);
  const ranked = lab.ranked(w);
  const siteTxt = ranked.slice(0, 5).map((r) => r[0]).join(", ") || "no tags";

  const record = (r: NameResult): RatedName => ({
    key: rkey(S, r), name: r.name!, mode: r.mode, lang: S.lang, parts: r.parts || [],
    site: ranked.slice(0, 6).map((x) => x[0] + ":" + (S.site[x[0]] != null ? (+S.site[x[0]]).toFixed(2) : "1")), character: S.character,
  });
  const act: CardActions = {
    rate: (r, v) => {
      const k = rkey(S, r);
      const ratings = { ...S.ratings };
      if (ratings[k] && ratings[k].r === v) delete ratings[k];
      else ratings[k] = { ...record(r), r: v };
      set({ ratings });
    },
    pin: (r) => {
      const k = rkey(S, r);
      const pinned = { ...S.pinned };
      if (pinned[k]) delete pinned[k];
      else pinned[k] = record(r);
      set({ pinned });
    },
    hover: (id) => { if (lock == null) setHover(id); },
    toggleLock: (id) => setLock((l) => (l === id ? null : id)),
  };

  const showToast = (t: string) => {
    setToast(t);
    clearTimeout(toastT.current);
    toastT.current = setTimeout(() => setToast(null), 2600);
  };
  const exportJson = () => JSON.stringify(buildExport(D, S, w), null, 1);
  const doExport = () => {
    const j = exportJson();
    try {
      const a = document.createElement("a");
      a.href = URL.createObjectURL(new Blob([j], { type: "application/json" }));
      a.download = "name-lab-export.json";
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    } catch { /* ignore */ }
    const done = (copied: boolean) => showToast(copied ? "Copied to the clipboard and downloaded" : "Downloaded (clipboard blocked)");
    try {
      if (navigator.clipboard?.writeText) navigator.clipboard.writeText(j).then(() => done(true), () => done(false));
      else done(false);
    } catch { done(false); }
  };
  const doReset = () => {
    if (!confirm("Reset the lab: settings, edited lists, constants, ratings, pins and notes?")) return;
    clearState();
    setLock(null);
    setS(defaults(D));
  };
  const loadTown = (i: number) => {
    const t = D.map!.towns[i];
    const site: Record<string, number> = {};
    let ch = false;
    for (const [k, v] of t.tags) {
      if (k === "character") { ch = true; continue; }
      site[k] = Math.round(Math.min(1, v / (lab.M.SPEC[k] || 1)) * 100) / 100;
    }
    const g = D.map!.summary?.gen;
    set({
      site, character: ch || !!t.character, preset: null, view: "all",
      ...(g && D.lang[g === "ja_r" ? "ja" : g] ? { lang: g } : {}),
      ...(t.dialect ? { dialect: t.dialect } : {}),
    });
    topRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  const nPinned = Object.keys(S.pinned).length, nRated = Object.keys(S.ratings).length;
  const nEd = Object.keys(S.edits).length + Object.keys(S.consts).length + Object.keys(S.spec).length;
  const portOk = port && typeof port !== "string" ? port.ok === port.n && !port.parse.length : false;

  return (
    <div ref={topRef} className="scroll-mt-chrome-pad">
      <div className="mb-2 flex flex-wrap items-center justify-between gap-x-4 gap-y-1 text-hint text-muted-foreground">
        <span>
          Data {D.built} from <code>ot_placename.lua</code> {D.src["ot_placename.lua"]?.sha} · <code>ot_placename_lang.lua</code> {D.src["ot_placename_lang.lua"]?.sha}
        </span>
        <span className="flex flex-wrap items-center gap-2">
          {port && typeof port !== "string" && (
            <button type="button" title="Port check" onClick={() => set({ tab: "port" })}>
              <Pill tone={portOk ? "ok" : "warn"}>{portOk ? "TS port = Lua" : "port differs"} {port.ok}/{port.n}</Pill>
            </button>
          )}
          {typeof port === "string" && <span>port check failed: {port}</span>}
          <span>{nPinned} pinned · {nRated} rated{nEd ? " · edits active" : ""}</span>
        </span>
      </div>

      <Toolbar lab={lab} S={S} set={(p) => { if ("view" in p || "mode" in p) setLock(null); set(p); }} onGenerate={() => setTick((t) => t + 1)} onExport={doExport} onReset={doReset} />

      <div className="grid items-start gap-3.5 lg:grid-cols-[290px_minmax(0,1fr)]">
        <SiteBuilder lab={lab} S={S} set={set} />
        <section aria-label="Generated names" className="min-w-0">
          <div className="mb-1.5 flex flex-wrap items-baseline gap-x-3 gap-y-1">
            <h2 className="text-base font-semibold">
              {S.view === "all"
                ? `All modes · ${results.n} names each · ${LANG_NAMES[S.lang]} · ${siteTxt}${S.character ? " · character town" : ""}`
                : `${MODE[S.mode].name} · ${results.n} names · ${LANG_NAMES[S.lang]} · ${siteTxt}${S.character ? " · character town" : ""}`}
            </h2>
            {S.view !== "all" && <span className="text-hint text-muted-foreground">{MODE[S.mode].desc}</span>}
          </div>
          <WhyPanel r={why} locked={lockOk != null} onRelease={() => setLock(null)} specK={lab.M.C.SPEC_K} />
          <div className={cn(S !== G && "opacity-70 transition-opacity")}>
            {S.view === "all" ? (
              <div className="card-grid-fit items-start gap-2.5 card-min-170">
                {results.groups.map((g) => (
                  <section key={g.mode} className="min-w-0 rounded-xl border border-border bg-card p-2.5">
                    <h3 className="text-subhead font-semibold">{MODE[g.mode].name}</h3>
                    <p className="mb-1.5 min-h-[5.4em] text-hint text-muted-foreground">{MODE[g.mode].desc}</p>
                    <div className="flex flex-col gap-1.5">
                      {g.results.length ? (
                        g.results.map((r, i) => <NameCard key={i} r={r} id={`${g.mode}:${i}`} S={S} selected={lockOk === `${g.mode}:${i}`} inStack act={act} />)
                      ) : (
                        <p className="text-hint text-muted-foreground">No names for this site in this language.</p>
                      )}
                    </div>
                  </section>
                ))}
              </div>
            ) : results.groups[0].results.length ? (
              <div className="grid grid-cols-[repeat(auto-fill,minmax(150px,1fr))] gap-2 sm:grid-cols-[repeat(auto-fill,minmax(190px,1fr))]">
                {results.groups[0].results.map((r, i) => (
                  <NameCard key={i} r={r} id={`${results.groups[0].mode}:${i}`} S={S} selected={lockOk === `${results.groups[0].mode}:${i}`} act={act} />
                ))}
              </div>
            ) : (
              <p className="text-muted-foreground">No names for this site in this language (try another mode or more tags).</p>
            )}
          </div>
        </section>
      </div>

      <Tabs value={S.tab} onValueChange={(v) => set({ tab: v as string })} className="mt-7">
        <TabsList variant="line" className="w-full flex-wrap justify-start gap-y-2 group-data-horizontal/tabs:h-auto">
          {TABS.map(([id, name]) => <TabsTrigger key={id} value={id} className="flex-none px-2.5">{name}</TabsTrigger>)}
        </TabsList>
        <div className="min-h-[200px] rounded-xl border border-border bg-card p-3.5">
          <TabsContent value="map"><MapPanel lab={lab} S={S} set={set} onLoadTown={loadTown} /></TabsContent>
          <TabsContent value="lists"><ListsPanel lab={lab} S={S} set={set} /></TabsContent>
          <TabsContent value="consts"><ConstsPanel lab={lab} S={S} set={set} /></TabsContent>
          <TabsContent value="opts"><OptsPanel lab={lab} S={S} set={set} /></TabsContent>
          <TabsContent value="rated"><RatedPanel lab={lab} S={S} set={set} /></TabsContent>
          <TabsContent value="stop"><StopPanel lab={lab} S={S} set={set} /></TabsContent>
          <TabsContent value="port"><PortPanel port={port} /></TabsContent>
          <TabsContent value="export">{S.tab === "export" && <ExportPanel json={exportJson()} onExport={doExport} />}</TabsContent>
        </div>
      </Tabs>

      {toast && (
        <div role="status" className="fixed bottom-4 left-1/2 z-50 -translate-x-1/2 rounded-lg bg-foreground px-3.5 py-2 text-sm text-background shadow-md">
          {toast}
        </div>
      )}
    </div>
  );
}


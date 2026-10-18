// Generated names: the grid of one generator or the five side by side, each name with rate / pin actions, and the
// breakdown panel (what produced the hovered or kept name).
import { Pin, ThumbsDown, ThumbsUp } from "lucide-react";
import type { ReactNode } from "react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { EntryLine, Pill } from "./bits.tsx";
import { f2, MODE, u, type NameResult } from "./engine.ts";
import type { LabState } from "./types.ts";

export const rkey = (S: LabState, r: NameResult) => S.lang + "|" + r.mode + "|" + r.name;

export interface CardActions {
  rate: (r: NameResult, v: 1 | -1) => void;
  pin: (r: NameResult) => void;
  hover: (id: string) => void;
  toggleLock: (id: string) => void;
}

function IconToggle({ pressed, title, onClick, children }: { pressed: boolean; title: string; onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      title={title}
      aria-label={title}
      aria-pressed={pressed}
      onClick={(e) => { e.stopPropagation(); onClick(); }}
      className={cn(
        "inline-flex size-6 items-center justify-center rounded-md border border-transparent text-muted-foreground hover:border-border hover:text-foreground [&_svg]:size-3.5",
        pressed && "border-border bg-card text-brand-text",
      )}
    >
      {children}
    </button>
  );
}

export function NameCard({ r, id, S, selected, inStack, act }: { r: NameResult; id: string; S: LabState; selected: boolean; inStack?: boolean; act: CardActions }) {
  if (!r.name) {
    return <div className="rounded-lg border border-border px-2.5 py-1.5 text-hint text-muted-foreground">no name ({String(r.fail ?? "-")})</div>;
  }
  const k = rkey(S, r), rt = S.ratings[k]?.r ?? 0, pin = !!S.pinned[k];
  let sub = "";
  if (r.mode === "remix") sub = r.how || "";
  else if (r.mode === "old") sub = (r.applied && r.applied.length ? "from " + r.modern : "no spelling rule matched") + (r.how !== "spelling" ? " · " + r.how : "");
  else sub = (r.parts || []).join(" + ");
  return (
    <div
      role="button"
      tabIndex={0}
      aria-pressed={selected}
      onMouseEnter={() => act.hover(id)}
      onFocus={() => act.hover(id)}
      onClick={() => act.toggleLock(id)}
      onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); act.toggleLock(id); } }}
      className={cn(
        "group/name relative min-w-0 cursor-pointer rounded-lg border border-border px-2.5 pt-1.5 pb-1 outline-none hover:border-brand focus-visible:border-brand",
        inStack ? "bg-background" : "bg-card",
        rt > 0 && "border-l-4 border-l-up",
        rt < 0 && "border-l-4 border-l-down",
        pin && "bg-chip",
        selected && "ring-2 ring-brand",
      )}
    >
      <div className={cn("text-lead font-semibold wrap-anywhere", rt < 0 && "text-muted-foreground line-through decoration-down")}>{r.name}</div>
      <div className="text-meta text-muted-foreground wrap-anywhere">{sub}</div>
      <div className={cn("mt-0.5 flex gap-0.5 opacity-60 group-hover/name:opacity-100", (rt !== 0 || pin) && "opacity-100")}>
        <IconToggle pressed={rt > 0} title="Good" onClick={() => act.rate(r, 1)}><ThumbsUp /></IconToggle>
        <IconToggle pressed={rt < 0} title="Bad" onClick={() => act.rate(r, -1)}><ThumbsDown /></IconToggle>
        <IconToggle pressed={pin} title="Pin" onClick={() => act.pin(r)}><Pin /></IconToggle>
      </div>
    </div>
  );
}

function KV({ k, children }: { k: string; children: ReactNode }) {
  return (
    <tr>
      <th className="w-[1%] py-0.5 pr-2.5 text-left align-top font-semibold whitespace-nowrap text-muted-foreground">{k}</th>
      <td className="py-0.5">{children}</td>
    </tr>
  );
}

/* eslint-disable @typescript-eslint/no-explicit-any */
export function WhyPanel({ r, locked, onRelease, specK }: { r: NameResult | null; locked: boolean; onRelease: () => void; specK: number }) {
  let body: ReactNode;
  if (!r) body = <p className="text-muted-foreground">Hover a name for what produced it; click to keep it here.</p>;
  else {
    const head = (
      <div className="mb-1">
        <b className="text-lg">{r.name || "-"}</b>{" "}
        <span className="text-muted-foreground">
          {MODE[r.mode].name} ·{" "}
          {locked ? (
            <>kept (click the name again or <Button variant="outline" size="xs" onClick={onRelease}>release</Button>)</>
          ) : (
            "hover a name for its breakdown, click to keep it"
          )}
        </span>
      </div>
    );
    if (r.mode === "remix") {
      body = (
        <>
          {head}
          <table className="w-full border-collapse"><tbody>
            <KV k="How">{r.how}</KV>
            {r.stem && <KV k="Stem">{r.stem.text} · fit {f2(r.stem.f)} ({r.stem.bt || "-"})</KV>}
            {r.gen && <KV k="Generic">-{r.gen.text} · fit {f2(r.gen.f)} ({r.gen.bt || "-"})</KV>}
            <KV k="Chain">order {r.order} (shortest context used: {(r.minO ?? 9) > 8 ? "-" : r.minO}), trained on {r.trainN} game names, {(r.tries ?? 0) + 1} tries</KV>
          </tbody></table>
        </>
      );
    } else if (r.info) {
      const i = r.info as any, dbg = i.dbg || {};
      const xs = Object.keys(dbg.x || {}).sort((a, c) => dbg.x[c] - dbg.x[a]).slice(0, 10);
      body = (
        <>
          {head}
          <table className="w-full border-collapse"><tbody>
            {r.mode === "old" && (
              <KV k="Modern">
                {r.modern} · {r.how}
                {r.applied?.map((a) => <span key={a} className="block">{a}</span>)}
              </KV>
            )}
            <KV k="Base">{u(i.base)}</KV>
            <KV k="Stem"><b>{u(i.spec)}</b> · fit {f2(dbg.sF)} via <b>{i.specTag || "-"}</b> (× SPEC_K {specK})<br /><EntryLine e={i.sE} /></KV>
            <KV k="Generic"><b>{u(i.gen)}</b> · fit {f2(dbg.gF)} via <b>{i.genTag || "-"}</b><br /><EntryLine e={i.gE} /></KV>
            {dbg.pair ? <KV k="Pair bonus">+{f2(dbg.pair)} (stem and generic name two features)</KV> : null}
            <KV k="Affix">
              {i.affix ? <><b>{u(i.affix)}</b> · {f2(dbg.affixScore)} over the cost<br /><EntryLine e={i.aE} /></> : <span className="text-muted-foreground">none</span>}
            </KV>
            {(r.river || r.lake) && <KV k="Water">{[r.river ? "river " + r.river : "", r.lake ? "lake " + r.lake : ""].filter(Boolean).join(" · ")}</KV>}
            <KV k="Dialect">{i.dialect ? u(i.dialect) : "-"}</KV>
            <KV k="Score">{f2(i.score)}{dbg.wide ? " · from the wide search (no unique name in the top ones)" : ""}</KV>
            <KV k="Site">{xs.map((t) => <Pill key={t} className="mr-1">{t} {f2(dbg.x[t])}</Pill>)}</KV>
          </tbody></table>
          {dbg.alts && dbg.alts.length > 0 && (
            <>
              <p className="mt-1 text-hint text-muted-foreground">Top candidates before uniqueness and affixes:</p>
              <ol className="mt-0.5 list-decimal pl-6 text-hint sm:columns-2">
                {dbg.alts.map((a: any, j: number) => (
                  <li key={j}>{u(a.base)} <span className="text-muted-foreground">{u(a.s)}+{u(a.g)} {f2(a.sc)}</span></li>
                ))}
              </ol>
            </>
          )}
        </>
      );
    } else body = <p className="text-muted-foreground">{String(r.fail || "")}</p>;
  }
  return (
    <div aria-live="polite" className="mb-3 h-60 overflow-auto rounded-xl border border-border bg-card px-3.5 py-3 text-dense">
      {body}
    </div>
  );
}

# /// script
# requires-python = ">=3.11"
# ///
"""Report of the junction audit Smart Lanes writes to the game log (plans/square_smart_lanes/TESTING.md X).

Smart Lanes (mods/square_smart_lanes, sl_audit.lua) logs to <userdata>/crash_dump/stdout.txt:

  [SQRL] AUDIT node=128660 case=X shape=t_junction findings=shared:1 forced=squeeze:1 detail=shared:11:fs src=auto job=3
      one per junction with avoidable findings (src=auto: the automatic pass after a build, with the
      connections it planned; src=tool: the tool's Apply; src=pick: a tool pick, current connections)
  [SQRL] AUDIT_SUMMARY src=auto job=3 audited=54 flagged=9 findings=shared:12,weave:2 forced=shared:30,shared_lit:8 skips=ambiguous:2
      one per automatic job (every junction it handled, flagged or not; unlogged=N: flagged junctions over
      the job's AUDIT line cap, counted in the totals only)
  [SQRL] SKIP kind=slip node=.. reason=..   /   [SQRL] SUMMARY job=.. skips=reason:count,...
      nodes the rules left alone, and why

forced= holds what the lane counts force (squeeze, shared, weave: a movement that must change lanes before
the next junction because the lanes the other movements into its exit road take leave it no lane there
that reaches every exit; only misses a free lane next to its own would cover are avoidable) and what the
rule does on purpose (shared_lit: a straight movement sharing an exit lane with a turn at a crossroads with
traffic lights; turbo_gap: the ring-out outer lane after a turbo ring's exit-only junction, empty up to the
next entry); neither makes a junction flagged.

The report groups the AUDIT lines by finding (latest line per junction and source, so a junction picked
again or applied twice counts once), lists the worst junctions per finding with their case / shape /
detail, sums the AUDIT_SUMMARY lines, and tallies the skip reasons.

  uv run tools/sqrl_audit.py                    # the live stdout.txt (TF3_USERDATA / .hub.env / auto)
  uv run tools/sqrl_audit.py run1.txt           # saved copies
  ... --last                                    # per file, only the most recent load with [SQRL] lines
  ... --src auto                                # only this source (auto | tool | pick)
  ... --top 5                                   # junctions listed per finding (default 10)

After the Stress Test's Junction test and Crossing test (Smart Lanes enabled): `make audit`.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

SQRL = re.compile(r"\[SQRL\] (?P<kind>[A-Z_]+) (?P<rest>.*)$")
KV = re.compile(r"(\w+)=(\S*)")
# finding kinds in the order sl_audit.lua lists them (A.KINDS); unknown ones sort after
KINDS = ["squeeze", "shared", "shared_lit", "shared_open", "across", "ramp_ramp", "u_turn", "unfed", "turbo_gap", "dead",
         "bypassed_turn", "weave", "lights", "bad"]
# kinds sl_audit.lua logs only under forced= because the rule makes them on purpose (never avoidable)
BY_DESIGN = {
    "shared_lit": "an exit lane a straight movement shares with a turn from another approach at a crossroads "
                  "with traffic lights (the rule keeps its extra straight shares there: the movements run in "
                  "different phases; at unlit crossroads it drops them)",
    "shared_open": "an exit lane of an open exit road (a street stop or the next junction within 80 m) where "
                   "the far-side turns fan over the lanes and merge with the movements beside them",
    "turbo_gap": "the ring-out outer lane after a turbo ring's junction with exits and no entry (the outer lane "
                 "is exit-only there, so it stays empty up to the next entry, which joins without giving way)",
}


def default_log() -> Path:
    from hubconfig import userdata  # noqa: PLC0415

    return userdata() / "crash_dump" / "stdout.txt"


def counts(text: str | None) -> dict[str, int]:
    """'shared:2,weave:1' -> {'shared': 2, 'weave': 1}; '-' / None / '+N' tails -> skipped."""
    out: dict[str, int] = {}
    for part in (text or "").split(","):
        k, _, v = part.partition(":")
        if k and k != "-" and not k.startswith("+") and v.isdigit():
            out[k] = out.get(k, 0) + int(v)
    return out


def kind_order(k: str) -> tuple[int, str]:
    return (KINDS.index(k) if k in KINDS else len(KINDS), k)


@dataclass
class Audit:
    node: str
    case: str
    shape: str
    src: str
    findings: dict[str, int]
    forced: dict[str, int]
    detail: str
    where: str  # file:line

    @property
    def total(self) -> int:
        return sum(self.findings.values())


@dataclass
class Report:
    files: list[str] = field(default_factory=list)
    lines: int = 0  # AUDIT lines read
    audits: dict[tuple[str, str], Audit] = field(default_factory=dict)  # (src, node) -> latest line
    summaries: dict[str, Counter] = field(default_factory=lambda: defaultdict(Counter))  # src -> totals
    summary_findings: dict[str, Counter] = field(default_factory=lambda: defaultdict(Counter))
    summary_forced: dict[str, Counter] = field(default_factory=lambda: defaultdict(Counter))
    skip_lines: Counter = field(default_factory=Counter)  # (kind, reason) from SKIP lines
    summary_skips: Counter = field(default_factory=Counter)  # reason from SUMMARY skips=

    def by_kind(self) -> dict[str, list[Audit]]:
        out: dict[str, list[Audit]] = defaultdict(list)
        for a in self.audits.values():
            for k in a.findings:
                out[k].append(a)
        return out


def last_load(text: list[str]) -> list[str]:
    """The lines of the most recent load (a 'mod params:' dump starts one) with [SQRL] lines in it;
    the whole text when it has no load marker."""
    starts = [i for i, line in enumerate(text) if "mod params:" in line]
    if not starts:
        return text
    bounds = list(zip(starts, starts[1:] + [len(text)]))
    for a, b in reversed(bounds):
        if any("[SQRL] " in line for line in text[a:b]):
            return text[a:b]
    return text[bounds[-1][0]:]


def parse(paths: list[Path], only_src: str | None = None, last: bool = False) -> Report:
    rep = Report()
    for path in paths:
        rep.files.append(path.name)
        text = path.read_text(encoding="utf-8", errors="replace").splitlines()
        if last:
            text = last_load(text)
        for no, raw in enumerate(text, 1):
            m = SQRL.search(raw)
            if not m:
                continue
            kind, kv = m["kind"], dict(KV.findall(m["rest"]))
            src = kv.get("src", "auto")
            if kind == "AUDIT":
                if only_src and src != only_src:
                    continue
                rep.lines += 1
                a = Audit(kv.get("node", "?"), kv.get("case", "-"), kv.get("shape", "-"), src,
                          counts(kv.get("findings")), counts(kv.get("forced")), kv.get("detail", "-"),
                          f"{path.name}:{no}")
                rep.audits[(src, a.node)] = a
            elif kind == "AUDIT_SUMMARY":
                if only_src and src != only_src:
                    continue
                t = rep.summaries[src]
                t["jobs"] += 1
                for key in ("audited", "flagged", "failed", "unlogged"):
                    if kv.get(key, "").isdigit():
                        t[key] += int(kv[key])
                rep.summary_findings[src].update(counts(kv.get("findings")))
                rep.summary_forced[src].update(counts(kv.get("forced")))
            elif kind == "SKIP":
                reason = kv.get("reason", "?").split(":")[0]
                what = kv.get("kind") or ("ring" if "ring" in kv else kv.get("scope", "-"))
                if "src" in kv:
                    what = f"{what} ({kv['src']})"
                rep.skip_lines[(what, reason)] += 1
            elif kind == "SUMMARY":
                rep.summary_skips.update(counts(kv.get("skips")))
    return rep


def render(rep: Report, top: int = 10) -> str:
    out: list[str] = []
    junctions = len(rep.audits)
    out.append(f"# Smart Lanes junction audit ({', '.join(rep.files)})")
    out.append("")
    out.append(f"AUDIT lines: {rep.lines} ({junctions} junction(s) with avoidable findings, latest line per "
               "junction and source).")
    for src, t in sorted(rep.summaries.items()):
        fails = f", {t['failed']} audit(s) failed" if t["failed"] else ""
        unlogged = (f", {t['unlogged']} flagged without an AUDIT line (per-job line cap: see the totals below)"
                    if t["unlogged"] else "")
        out.append(f"AUDIT_SUMMARY src={src}: {t['jobs']} job(s), {t['audited']} junction(s) audited, "
                   f"{t['flagged']} flagged{fails}{unlogged}.")
    out.append("")
    by_kind = rep.by_kind()
    if by_kind:
        out.append("## Findings by type")
        out.append("")
        out.append("| finding | junctions | count | forced | cases | sources |")
        out.append("|---|---|---|---|---|---|")
        for k in sorted(by_kind, key=kind_order):
            lst = by_kind[k]
            n = sum(a.findings[k] for a in lst)
            forced = sum(a.forced.get(k, 0) for a in rep.audits.values())
            cases = Counter(a.case for a in lst)
            srcs = Counter(a.src for a in lst)
            out.append(f"| {k} | {len(lst)} | {n} | {forced or ''} | "
                       f"{', '.join(f'{c}:{v}' for c, v in cases.most_common())} | "
                       f"{', '.join(f'{c}:{v}' for c, v in srcs.most_common())} |")
        out.append("")
        out.append("## Worst junctions per finding")
        for k in sorted(by_kind, key=kind_order):
            lst = sorted(by_kind[k], key=lambda a: (-a.findings[k], -a.total, a.node))
            out.append("")
            out.append(f"### {k} ({len(lst)} junction(s), {sum(a.findings[k] for a in lst)})")
            out.append("")
            out.append("| node | count | case | shape | src | all findings | detail |")
            out.append("|---|---|---|---|---|---|---|")
            for a in lst[:top]:
                allf = ",".join(f"{x}:{a.findings[x]}" for x in sorted(a.findings, key=kind_order))
                out.append(f"| {a.node} | {a.findings[k]} | {a.case} | {a.shape} | {a.src} | {allf} | {a.detail} |")
            if len(lst) > top:
                out.append(f"| ... {len(lst) - top} more | | | | | | |")
        out.append("")
    else:
        out.append("No avoidable findings in the AUDIT lines.")
        out.append("")
    if rep.summary_findings or rep.summary_forced:
        out.append("## AUDIT_SUMMARY totals (every audited junction, per source)")
        out.append("")
        out.append("| source | finding | avoidable | forced |")
        out.append("|---|---|---|---|")
        for src in sorted(set(rep.summary_findings) | set(rep.summary_forced)):
            f, fo = rep.summary_findings[src], rep.summary_forced[src]
            for k in sorted(set(f) | set(fo), key=kind_order):
                avoidable = "by design" if k in BY_DESIGN and not f.get(k) else f.get(k, 0)
                out.append(f"| {src} | {k} | {avoidable} | {fo.get(k, 0)} |")
        out.append("")
        shown = {k for t in (*rep.summary_findings.values(), *rep.summary_forced.values()) for k in t}
        for k in sorted(shown & set(BY_DESIGN), key=kind_order):
            out.append(f"{k}: {BY_DESIGN[k]}.")
        if shown & set(BY_DESIGN):
            out.append("")
    if rep.skip_lines or rep.summary_skips:
        out.append("## Skip reasons")
        out.append("")
        out.append("| reason | SUMMARY skips (automatic pass) | SKIP lines (kind: count) |")
        out.append("|---|---|---|")
        reasons = set(rep.summary_skips) | {r for _, r in rep.skip_lines}
        total = Counter(rep.summary_skips)
        for (_, r), c in rep.skip_lines.items():
            total[r] += c
        for r in sorted(reasons, key=lambda x: (-total[x], x)):
            kinds = ", ".join(f"{w}: {c}" for (w, rr), c in sorted(rep.skip_lines.items()) if rr == r)
            out.append(f"| {r} | {rep.summary_skips.get(r, 0) or ''} | {kinds} |")
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("logs", nargs="*", type=Path, help="stdout.txt copies (default: the live one)")
    ap.add_argument("--last", action="store_true", help="per file, only the most recent load with [SQRL] lines")
    ap.add_argument("--src", choices=["auto", "tool", "pick"], help="only this source")
    ap.add_argument("--top", type=int, default=10, help="junctions listed per finding (default 10)")
    args = ap.parse_args()
    paths = args.logs or [default_log()]
    for p in paths:
        if not p.is_file():
            raise SystemExit(f"No such log: {p}")
    rep = parse(paths, args.src, args.last)
    if rep.lines == 0 and not rep.summaries and not rep.skip_lines and not rep.summary_skips:
        where = ", ".join(map(str, paths))
        print(f"No [SQRL] AUDIT / SUMMARY / SKIP lines in {where}.")
        print("Enable Smart Lanes (Apply automatically to new roads On), build junctions (e.g. the Stress Test's Junction test "
              "and Crossing test) or pick them with the Smart Lanes tool, then run this again.")
        return
    print(render(rep, args.top), end="")


if __name__ == "__main__":
    main()

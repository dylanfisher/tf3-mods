# /// script
# requires-python = ">=3.11"
# ///
"""Traffic flow A/B report from the Stress Test traffic log (plans/square_stress_test/FLOW.md, FLOW_PLAN.md step 6).

The Showcase builds every junction as twins with identical params, side by side (FLOW_PLAN.md "Revision
2026-10-12"): `ab=game` (Smart Lanes leaves it alone), `ab=sl` (Smart Lanes lanes) and, at lit plain crossings,
`ab=sl_phases` (Smart Lanes lanes + light phases); the Lights showcase adds a fourth twin: `ab=sl_lock` since
2026-10-13 (Smart Lanes lanes with the kerb turn never freed:
sl_lock vs game is the lane layout alone, sl vs sl_lock the free kerb turn alone; `ab=sl_fan`, Smart Lanes' full fan +
split phases, before, still compared with game and sl_phases). All twins run at the same time, so the report compares them
pairwise (same `pair=`) and pooled per kind / type. Lines read from <userdata>/crash_dump/stdout.txt:

  [SQST] showcase zone id=g3a pair=g3 ab=sl kind=roundabout type=Magic_Roundabout x=1200 y=-3400 r=167 ... match=yes
  [SQST] showcase zone_match id=g3a pair=g3 match=no reason=link   (after the links: updates that zone's match)
  [SQST] showcase zones sent n= run= by_ab= smart_lanes=yes|no / ack=yes|timeout|absent|unsent / cleared by=
  [SQST] FLOW_START / FLOW_ZONE / FLOW / FLOW_ALL / FLOW_TOWNS / FLOW_BUS / FLOW_SUMMARY   (the Traffic log)
  [SQST] FLOW_TARGET target= was= read= reason=skipped|recovered (v3: the sampler lowered / raised its per-sweep target)
  [SQST] lights_showcase entry <town> kind=roundabout|crossroads ...   (the Lights showcase's town entries)
  [SQRL] MODE phases= free_turn= / ZONES op= run= / TOGGLE state= phase= gt=               (Smart Lanes)

Values are parsed generically (key=value; unknown keys ignored, missing ones and `-` are empty). The log is split
into loads (each "mod params:" dump; a FLOW_START whose gt goes back starts one too), since `gt` is monotonic only
within one load. A FLOW_ZONE (and a FLOW / FLOW_BUS line) joins its showcase zone by `twin=`/`id=` or `pair=`+`ab=`
keys when present (a named twin the current Showcase lacks stays unjoined), else by position (nearest showcase zone
of the same kind within its `r`, one FLOW zone per twin, the closest). A new Showcase run (`showcase zones sent`, or a
zone id repeating) starts a new set of twins, `showcase zones cleared` ends it: zones are pooled across loads and
sampler runs by (Showcase run, twin id), else by label + rounded position within the Showcase run. Warm-up: per
zone and load, samples before the zone's first sample gt in that load + --warmup game seconds are dropped. Pairs with `match=no` or a missing `game` / `sl` twin are left out of the pairwise
comparisons (listed with the reason); pooled per-type numbers still use every twin. When `[SQRL] TOGGLE` lines
exist (the deferred global On/Off toggle), a toggle-block section follows the twins.

Units (FLOW.md, provisional until the probes 11a/11f): speeds m/s (shown as km/h), stand times s, gt game ms
(FLOW_START `gt_per_s=` when written, else --gt-per-s). "Worse" = car-weighted speed lower by more than --worse-pct % or % standing higher by more than
--worse-pct percentage points, with at least --min-samples samples on both sides.

  uv run tools/flow_report.py                   # the live stdout.txt (TF3_USERDATA / .hub.env / auto)
  uv run tools/flow_report.py run1.txt          # saved copies (in session order)
  ... --last                                    # only the most recent load with FLOW lines
  ... --warmup 180 --worse-pct 10 --min-samples 5 --gt-per-s 1000 --trend-rows 12 --towns 10
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

TAG = re.compile(r"\[(?P<mod>SQST|SQRL)\] (?P<rest>.*)$")
KV = re.compile(r"([A-Za-z_]\w*)=(\S*)")
LOAD_NAME = re.compile(r"Loading (?:config|game) from file (?P<name>.*)$")
LOG_PREFIX = re.compile(r"^\[[^\]]*\]\s*")
FLOW_KINDS = {"FLOW_START", "FLOW_ZONE", "FLOW", "FLOW_ALL", "FLOW_TOWNS", "FLOW_BUS", "FLOW_SUMMARY", "FLOW_TARGET"}
# "[SQST] lights_showcase entry Smart lanes 1 N kind=roundabout ..." (SHOWCASE.md "Town entries")
ENTRY = re.compile(r"^(?P<id>\w+) entry (?P<town>.+?) kind=(?P<kind>\w+)")
AB_ORDER = ["game", "sl", "sl_phases", "sl_fan", "sl_lock", "sl_exitfan", "sl_keeplights"]
# sl_fan: the Lights showcase's full fan + split phases (a measuring mode); sl_lock: Smart Lanes lanes with the kerb
# turn kept locked (game phases): vs game = the lane layout alone, sl vs sl_lock = the free kerb turn alone;
# sl_exitfan (twin e, 2026-10-13): Smart Lanes lanes with every turn fanned into the exit lanes (game phases): vs sl =
# the exit fan alone, vs game = lanes + fan
COMPARISONS = [("sl", "game"), ("sl_phases", "game"), ("sl_phases", "sl"), ("sl_fan", "game"), ("sl_fan", "sl_phases"),
               ("sl_lock", "game"), ("sl", "sl_lock"), ("sl_exitfan", "sl"), ("sl_exitfan", "game"), ("sl", "sl_keeplights")]
# sl_keeplights (the bench's lights twin, plans/square_stress_test/BENCH.md): Smart Lanes lanes with the game's lights left
# at rings and slip / ramp nodes: sl vs sl_keeplights = "No lights at roundabouts and ramps" alone
FLOW_KIND_NAMES = {"ix": "interchange", "rb": "roundabout", "x": "plain"}
TWIN_ID = re.compile(r"^((?:s\d+)?g\d+)([a-z])$")  # g3a, or a bench sheet's s2g3a
STANDING_MS = 0.5  # FLOW.md: standing = dyn.speed < 0.5 m/s (the sampler counts it; noted in the report)


def default_log() -> Path:
    from hubconfig import userdata  # noqa: PLC0415

    return userdata() / "crash_dump" / "stdout.txt"


def num(v: str | None) -> float | None:
    """'13.9' / '1.2e+03' / '7' -> float; '-' / '' / None / garbage -> None."""
    if v is None or v in ("", "-"):
        return None
    try:
        f = float(v)
    except ValueError:
        return None
    return f if math.isfinite(f) else None


def counts(text: str | None) -> dict[str, int]:
    """'a:2,b:1,+3' -> {'a': 2, 'b': 1}."""
    out: dict[str, int] = {}
    for part in (text or "").split(","):
        k, _, v = part.partition(":")
        if k and k != "-" and not k.startswith("+") and v.isdigit():
            out[k] = out.get(k, 0) + int(v)
    return out


def ints(text: str | None) -> list[int]:
    return [int(x) for x in (text or "").split(",") if x.strip().isdigit()]


# ---------------------------------------------------------------------------------------------- model


@dataclass
class ScZone:
    """One `[SQST] showcase zone` line."""

    gen: int  # showcase run in this report (a new `showcase zones sent` starts one)
    id: str
    pair: str
    ab: str
    kind: str
    type: str
    x: float | None
    y: float | None
    r: float | None
    match: bool
    reason: str
    towns: int | None

    @property
    def key(self) -> tuple:
        return ("sc", self.gen, self.id)


@dataclass
class Showcase:
    gen: int
    run: str = "-"
    sent: bool = False
    smart_lanes: str = "-"
    zones: dict[str, ScZone] = field(default_factory=dict)


@dataclass
class ZoneMeta:
    """One FLOW_ZONE line (per load + run)."""

    zone: str
    label: str
    kind: str
    src: str
    x: float | None
    y: float | None
    r: float | None
    sc: ScZone | None = None
    r_measure: float | None = None  # v3: the measured area reaches this far (r + 200 m along the arms)
    measure: str = "-"  # v3: corridor / circle
    arms: str = "-"  # v3: the arms' compass points, q_arm's order


@dataclass
class Sample:
    gt: float
    cars: float
    standing: float
    queue: float | None
    v_mean: float | None
    stand_mean: float | None
    cars_core: float | None = None  # v3: cars in the junction's circle r (the v2 zone)
    q_arm: dict[str, int] | None = None  # v3: queued cars per arm corridor
    q_in: dict[str, int] | None = None  # 2026-10-13: of them on the inbound side (towards the junction)
    q_out: dict[str, int] | None = None  # ... and on the outbound side
    thru: float | None = None  # 2026-10-13: cars through the junction since the previous sample
    thru_s: float | None = None  # that interval in game seconds


@dataclass
class Load:
    index: int
    file: str
    name: str = "(unnamed)"
    phases: str | None = None  # [SQRL] MODE phases=
    free_turn: str | None = None
    gt_reset: bool = False
    events: list[tuple[str, dict, int]] = field(default_factory=list)  # (kind, kv, stdout order) of FLOW_* lines
    toggles: list[dict] = field(default_factory=list)
    zones_runs: list[str] = field(default_factory=list)  # [SQRL] ZONES set/loaded run= in this load
    sent_runs: list[str] = field(default_factory=list)  # [SQST] showcase zones sent run=
    warnings: list[str] = field(default_factory=list)
    entries: Counter = field(default_factory=Counter)  # (showcase id, entry kind) -> towns
    entry_why: dict[str, str] = field(default_factory=dict)  # showcase id -> the first crossroads reason
    showcase: Showcase | None = None  # the showcase current at the end of the load
    max_gt: float | None = None
    first_gt: float | None = None
    gt_per_s: float | None = None  # --gt-per-s, else FLOW_START gt_per_s= (the sampler's unit), else 1000 (ms)
    dropped: int = 0  # FLOW samples in the warm-up

    def cut(self, warmup_s: float) -> float | None:
        return None if self.first_gt is None else self.first_gt + warmup_s * self.gps

    @property
    def gps(self) -> float:
        return self.gt_per_s or 1000.0

    def flow_lines(self) -> int:
        return sum(1 for k, _, _ in self.events if k in ("FLOW", "FLOW_ALL"))


@dataclass
class ZoneStat:
    key: tuple
    label: str
    kind: str
    type: str
    ab: str = "-"
    pair: str = "-"
    gen: int = 0
    match: bool = True
    reason: str = ""
    samples: list[Sample] = field(default_factory=list)
    dropped: int = 0  # warm-up
    measure: str = "-"  # v3 FLOW_ZONE measure= / r_measure= / arms=
    r: float | None = None
    r_measure: float | None = None
    arms: str = "-"

    @property
    def name(self) -> str:
        return self.key[2] if self.key[0] == "sc" else self.label

    # --- metrics
    def n(self) -> int:
        return len(self.samples)

    def cars_mean(self) -> float | None:
        return sum(s.cars for s in self.samples) / len(self.samples) if self.samples else None

    def speed_kmh(self) -> float | None:
        w = [(s.v_mean, s.cars) for s in self.samples if s.v_mean is not None and s.cars > 0]
        tot = sum(c for _, c in w)
        return sum(v * c for v, c in w) / tot * 3.6 if tot else None

    def standing_pct(self) -> float | None:
        cars = sum(s.cars for s in self.samples)
        return sum(s.standing for s in self.samples) / cars * 100 if cars else None

    def stand_times(self) -> list[float]:
        return [s.stand_mean for s in self.samples if s.stand_mean is not None and s.standing > 0]

    def stand_mean(self) -> float | None:
        w = [(s.stand_mean, s.standing) for s in self.samples if s.stand_mean is not None and s.standing > 0]
        tot = sum(c for _, c in w)
        return sum(v * c for v, c in w) / tot if tot else None

    def stand_p90(self) -> float | None:
        return pctl(self.stand_times(), 90)

    def stand_max(self) -> float | None:
        return max(self.stand_times(), default=None)

    def queue_mean(self) -> float | None:
        q = [s.queue for s in self.samples if s.queue is not None]
        return sum(q) / len(q) if q else None

    def core_mean(self) -> float | None:
        v = [s.cars_core for s in self.samples if s.cars_core is not None]
        return sum(v) / len(v) if v else None

    def thru_per_min(self) -> float | None:
        """Cars through the junction per game minute: every sample's thru over its thru_s (only samples with both)."""
        w = [(s.thru, s.thru_s) for s in self.samples if s.thru is not None and s.thru_s]
        secs = sum(t for _, t in w)
        return sum(c for c, _ in w) / secs * 60 if secs else None

    def q_arm_means(self, attr: str = "q_arm") -> dict[str, float]:
        """Mean queued cars per arm corridor over the samples that carry q_arm (v3; attr q_in / q_out: one side), in the
        arms' order."""
        rows = [getattr(s, attr) for s in self.samples if getattr(s, attr)]
        if not rows:
            return {}
        keys: list[str] = []
        for r in rows:
            keys.extend(k for k in r if k not in keys)
        return {k: sum(r.get(k, 0) for r in rows) / len(rows) for k in keys}

    def n_cars(self) -> int:
        return sum(1 for s in self.samples if s.cars > 0 and s.v_mean is not None)

    def usable(self, min_samples: int) -> bool:
        return self.n_cars() >= min_samples


def pctl(vals: list[float], p: float) -> float | None:
    """Nearest-rank percentile."""
    if not vals:
        return None
    s = sorted(vals)
    return s[max(0, min(len(s) - 1, math.ceil(p / 100 * len(s)) - 1))]


def sign_test(wins: int, losses: int) -> float | None:
    """Two-sided exact sign test p-value (ties dropped)."""
    n = wins + losses
    if n == 0:
        return None
    k = min(wins, losses)
    p = 2 * sum(math.comb(n, i) for i in range(k + 1)) / 2 ** n
    return min(1.0, p)


@dataclass
class PairCmp:
    pair: str
    gen: int
    kind: str
    type: str
    a: str
    b: str
    za: ZoneStat
    zb: ZoneStat

    def d_speed(self) -> float:
        return self.za.speed_kmh() - self.zb.speed_kmh()  # type: ignore[operator]

    def d_speed_pct(self) -> float | None:
        b = self.zb.speed_kmh()
        return (self.d_speed() / b * 100) if b else None

    def d_standing(self) -> float | None:
        a, b = self.za.standing_pct(), self.zb.standing_pct()
        return a - b if a is not None and b is not None else None

    def d_stand(self) -> float | None:
        a, b = self.za.stand_mean(), self.zb.stand_mean()
        return a - b if a is not None and b is not None else None

    def d_queue(self) -> float | None:
        a, b = self.za.queue_mean(), self.zb.queue_mean()
        return a - b if a is not None and b is not None else None

    def d_thru(self) -> float | None:
        a, b = self.za.thru_per_min(), self.zb.thru_per_min()
        return a - b if a is not None and b is not None else None

    def worse(self, pct: float) -> list[str]:
        why = []
        ds = self.d_speed_pct()
        if ds is not None and ds < -pct:
            why.append(f"speed {ds:+.0f}%")
        dst = self.d_standing()
        if dst is not None and dst > pct:
            why.append(f"standing {dst:+.0f} pp")
        return why


@dataclass
class Report:
    files: list[str] = field(default_factory=list)
    loads: list[Load] = field(default_factory=list)
    showcases: list[Showcase] = field(default_factory=list)
    zones: dict[tuple, ZoneStat] = field(default_factory=dict)
    pairs: list[PairCmp] = field(default_factory=list)
    excluded: list[tuple[str, str, str, str]] = field(default_factory=list)  # pair, kind, type, reason
    partial: int = 0  # cut-off last lines / FLOW lines without zone or gt
    warmup_s: float = 180.0
    gt_per_s: float | None = None
    min_samples: int = 5
    worse_pct: float = 10.0
    notes: list[str] = field(default_factory=list)
    bench: bool = False  # zone lines carry test= (a bench sheet): groups per test, no "all" row across tests

    def gen_label(self, gen: int) -> str:
        return "" if len(self.showcases) <= 1 else f"#{gen}"


# ---------------------------------------------------------------------------------------------- parse


def read_lines(path: Path) -> tuple[list[str], bool]:
    """(lines, last line cut off): a log the game is still writing may end mid-line."""
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    partial = bool(lines) and not text.endswith(("\n", "\r"))
    if partial:
        lines = lines[:-1]
    return lines, partial


def split_loads(rep: Report, paths: list[Path]) -> None:
    """Fill rep.loads / rep.showcases from the logs (stdout order)."""
    sc = Showcase(gen=0)
    order = 0
    for path in paths:
        rep.files.append(path.name)
        lines, partial = read_lines(path)
        rep.partial += partial
        load = Load(index=len(rep.loads) + 1, file=path.name, name="(before the first load)")
        rep.loads.append(load)
        pending_name: str | None = None
        for raw in lines:
            order += 1
            if "mod params:" in raw:
                load = Load(index=len(rep.loads) + 1, file=path.name, name=pending_name or "(unnamed)")
                rep.loads.append(load)
                pending_name = None
                continue
            m = TAG.search(raw)
            if not m:
                lm = LOAD_NAME.search(LOG_PREFIX.sub("", raw))
                if lm:
                    if load.name == "(unnamed)":
                        load.name = lm["name"].strip()
                    else:
                        pending_name = lm["name"].strip()
                continue
            mod, rest = m["mod"], m["rest"]
            kind, _, tail = rest.partition(" ")
            kv = dict(KV.findall(tail))
            if mod == "SQRL":
                if kind == "MODE":
                    load.phases, load.free_turn = kv.get("phases"), kv.get("free_turn")
                elif kind == "ZONES" and kv.get("op") in ("set", "loaded", "clear"):
                    load.zones_runs.append(kv.get("run", "-"))
                elif kind == "TOGGLE":
                    gt = num(kv.get("gt"))
                    if gt is not None and kv.get("phase") in ("start", "end", "load"):
                        load.toggles.append({**kv, "_gt": gt, "_order": order})
                continue
            # SQST
            em = ENTRY.match(rest)
            if em:
                # one count per town: a roundabout also writes "read ends=" and "joined=k/3" lines (and
                # "arms not read" / "joined=k/3 (broken)" when it broke): only its build line ("at x,y")
                # counts as built, the broken ones as "broken"
                detail = rest.split(f"kind={em['kind']}", 1)[1].strip()
                kind = em["kind"]
                if kind == "roundabout":
                    if detail.startswith("arms not read") or detail.endswith("(broken)"):
                        kind = "broken"
                    elif not detail.startswith("at "):
                        continue
                load.entries[(em["id"], kind)] += 1
                if kind == "crossroads" and em["id"] not in load.entry_why:
                    load.entry_why[em["id"]] = detail
                continue
            if rest.startswith("showcase zones sent"):
                sc = Showcase(gen=len(rep.showcases) + 1, run=kv.get("run", "-"), sent=True,
                              smart_lanes=kv.get("smart_lanes", "-"))
                rep.showcases.append(sc)
                load.sent_runs.append(sc.run)
                if kv.get("smart_lanes") == "no":
                    load.warnings.append(f"showcase run {sc.run}: zones sent without Smart Lanes (smart_lanes=no): "
                                         "every twin runs game lanes")
                if kv.get("failed") == "yes":
                    load.warnings.append(f"showcase run {sc.run}: sending the zones failed")
            elif rest.startswith("showcase zones ack="):
                ack = rest.split("ack=", 1)[1].split()[0]
                if ack != "yes":
                    load.warnings.append(f"showcase zones ack={ack} (run {kv.get('run', '-')}): `ab` cannot be "
                                         "trusted for the junctions built before the ack (FLOW.md)")
            elif rest.startswith("showcase zones cleared"):
                load.warnings.append(f"showcase zones cleared by={kv.get('by', '-')} (run {kv.get('run', '-')})")
                # the twins are gone (or no longer gated): later FLOW_ZONEs must not join them by position
                sc = Showcase(gen=0)
            elif rest.startswith("showcase zone_match ") and "id" in kv:
                # the late verdict after the links (an arm left unlinked: reason=link): applies to that zone of the
                # current run (and to its stats, should FLOW lines have joined it already)
                z = sc.zones.get(kv["id"])
                if z is not None:
                    z.match = kv.get("match", "yes") != "no"
                    z.reason = kv.get("reason", "") if not z.match else ""
                    st = rep.zones.get(z.key)
                    if st is not None:
                        st.match, st.reason = z.match, z.reason
            elif rest.startswith("showcase zone ") and "id" in kv:
                if sc.gen == 0 or kv["id"] in sc.zones:
                    # zone lines without a "zones sent" line before them (older log), or an id repeating: a new
                    # Showcase run
                    sc = Showcase(gen=len(rep.showcases) + 1)
                    rep.showcases.append(sc)
                tm = TWIN_ID.match(kv["id"])
                # a bench zone (test=): its test is its kind, so every table groups per test (BENCH.md)
                kind_ = kv.get("kind", "other")
                if kv.get("test"):
                    rep.bench = True
                    kind_ = "test:" + kv["test"]
                z = ScZone(sc.gen, kv["id"], kv.get("pair") or (tm[1] if tm else kv["id"]), kv.get("ab", "-"),
                           kind_, kv.get("type", "-"), num(kv.get("x")), num(kv.get("y")),
                           num(kv.get("r")), kv.get("match", "yes") != "no", kv.get("reason", ""),
                           int(kv["towns"]) if kv.get("towns", "").isdigit() else None)
                sc.zones[z.id] = z
            elif kind in FLOW_KINDS:
                gt = num(kv.get("gt"))
                if kind == "FLOW_START" and gt is not None and load.max_gt is not None and gt < load.max_gt:
                    # gt went back without a load marker: treat as a new load
                    load = Load(index=len(rep.loads) + 1, file=path.name, name=load.name, gt_reset=True,
                                phases=load.phases, free_turn=load.free_turn)
                    rep.loads.append(load)
                if kind == "FLOW_START" and num(kv.get("gt_per_s")):
                    load.gt_per_s = num(kv["gt_per_s"])  # type: ignore[assignment]
                if gt is not None:
                    load.max_gt = gt if load.max_gt is None else max(load.max_gt, gt)
                kv["_sc"] = sc  # type: ignore[assignment]  # the showcase current at this line
                load.events.append((kind, kv, order))
            load.showcase = sc
    rep.loads = [ld for ld in rep.loads if ld.events or ld.toggles]
    for i, ld in enumerate(rep.loads, 1):
        ld.index = i


TWIN_KEYS = ("twin", "id", "showcase")  # explicit showcase twin id on FLOW_ZONE / FLOW / FLOW_BUS lines


def explicit_twin(sc: Showcase, kv: dict) -> tuple[bool, ScZone | None]:
    """(the line names a twin, that twin in `sc`): `twin=`/`id=` g<set><letter>, or `pair=` + `ab=`."""
    named = False
    for k in TWIN_KEYS:
        v = kv.get(k)
        if v and v != "-":
            named = True
            if v in sc.zones:
                return True, sc.zones[v]
    pair, ab = kv.get("pair"), kv.get("ab")
    if pair and ab and pair != "-" and ab != "-":
        named = True
        for z in sc.zones.values():
            if z.pair == pair and z.ab == ab:
                return True, z
    return named, None


def join_showcase(sc: Showcase, meta: ZoneMeta, kv: dict) -> tuple[ScZone | None, float | None]:
    """(showcase twin, distance when joined by position). Explicit ids first; a line that names a twin the current
    Showcase does not have stays unjoined (never guessed by position). Position: nearest centre within max(r, 30) m,
    junction kinds only (rb / ix / x must equal the twin's kind; town / other never join)."""
    if not sc.zones:
        return None, None
    named, z = explicit_twin(sc, kv)
    if named:
        return z, None
    if kv.get("label") in sc.zones:
        return sc.zones[kv["label"]], None
    want = FLOW_KIND_NAMES.get(meta.kind)
    if meta.x is None or meta.y is None or want is None:
        return None, None
    best, best_d = None, None
    for z in sc.zones.values():
        if z.x is None or z.y is None or z.kind != want:
            continue
        d = math.hypot(z.x - meta.x, z.y - meta.y)
        if d <= max(z.r or 0, 30) and (best_d is None or d < best_d):
            best, best_d = z, d
    return best, best_d


def zone_stat(rep: Report, meta: ZoneMeta | None, load: Load, run: str, zone: str, sc_z: ScZone | None = None,
              gen: int = 0) -> ZoneStat:
    z = sc_z or (meta.sc if meta is not None else None)
    if z is not None:
        key: tuple = z.key
        st = rep.zones.get(key)
        if st is None:
            label = meta.label if meta is not None else z.type
            st = rep.zones[key] = ZoneStat(key, label, z.kind, z.type, z.ab, z.pair, z.gen, z.match, z.reason)
        return st
    if meta is not None:
        # pooled across loads / runs by label + position, within one Showcase run (ids and places repeat)
        key = ("raw", meta.label, round((meta.x or 0) / 10), round((meta.y or 0) / 10), gen)
        label = meta.label if meta.label not in ("", "-") else f"zone {zone}"
        kind = FLOW_KIND_NAMES.get(meta.kind, meta.kind)
    else:
        key = ("raw", f"load{load.index}", run, zone)
        label, kind = f"load {load.index} run {run} zone {zone}", "?"
    st = rep.zones.get(key)
    if st is None:
        st = rep.zones[key] = ZoneStat(key, label, kind, "-")
    return st


def first_gt(load: Load) -> None:
    gts = [num(kv.get("gt")) for k, kv, _ in load.events if k in ("FLOW", "FLOW_ALL")]
    gts = [g for g in gts if g is not None]
    load.first_gt = min(gts) if gts else None


def build(rep: Report) -> None:
    for load in rep.loads:
        first_gt(load)
        metas: dict[tuple[str, str], ZoneMeta] = {}
        claimed: dict[tuple, tuple[float, ZoneMeta]] = {}  # (run, twin key) -> position join (one zone per twin)
        rows: list[tuple[dict, float, float]] = []
        for kind, kv, _ in load.events:
            if kind == "FLOW_START" and kv.get("keep_cleared") == "1":
                load.warnings.append(f"run {kv.get('run', '-')}: Keep traffic cleared was on: not valid for A/B")
            elif kind == "FLOW_ZONE" and kv.get("zone"):
                run = kv.get("run", "-")
                meta = ZoneMeta(kv["zone"], kv.get("label", "-"), kv.get("kind", "other"), kv.get("src", "-"),
                                num(kv.get("x")), num(kv.get("y")), num(kv.get("r")), None, num(kv.get("r_measure")),
                                kv.get("measure", "-"), kv.get("arms", "-"))
                meta.sc, d = join_showcase(kv["_sc"], meta, kv)
                if meta.sc is not None and d is not None:
                    prev = claimed.get((run, meta.sc.key))
                    if prev is not None and prev[0] <= d:
                        meta.sc = None  # a closer FLOW zone already holds this twin
                    else:
                        if prev is not None:
                            prev[1].sc = None
                        claimed[(run, meta.sc.key)] = (d, meta)
                metas[(run, kv["zone"])] = meta
            elif kind == "FLOW_TARGET" and kv.get("reason") == "recovered":
                load.warnings.append(f"run {kv.get('run', '-')} sample {kv.get('s', '-')}: sweeps finish early again; target "
                                     f"{kv.get('was', '-')} -> {kv.get('target', '-')}"
                                     + (" (every driver: thru counts again)" if kv.get("target") == "all" else ""))
            elif kind == "FLOW_TARGET":
                load.warnings.append(f"run {kv.get('run', '-')} sample {kv.get('s', '-')}: the sampler could not read every "
                                     f"driver within its interval (read {kv.get('read', '-')} of ~{kv.get('drivers_prev', '-')}); "
                                     f"target {kv.get('was', '-')} -> {kv.get('target', '-')}: later samples read every k-th driver "
                                     "(thru=- until the target recovers)")
            elif kind == "FLOW":
                gt, cars = num(kv.get("gt")), num(kv.get("cars"))
                if not kv.get("zone") or gt is None or cars is None:
                    rep.partial += 1
                    continue
                rows.append((kv, gt, cars))
        # resolved after every FLOW_ZONE of the load (a later, closer zone may take a twin over)
        stats: list[tuple[ZoneStat, Sample]] = []
        for kv, gt, cars in rows:
            run, sc = kv.get("run", "-"), kv["_sc"]
            _, sc_z = explicit_twin(sc, kv)
            meta = metas.get((run, kv["zone"]))
            st = zone_stat(rep, meta, load, run, kv["zone"], sc_z, sc.gen)
            if meta is not None and meta.measure != "-":
                st.measure, st.r, st.r_measure, st.arms = meta.measure, meta.r, meta.r_measure, meta.arms
            def qv(key: str) -> dict[str, int] | None:
                return counts(kv.get(key)) if kv.get(key) not in (None, "", "-") else None
            stats.append((st, Sample(gt, cars, num(kv.get("standing")) or 0.0, num(kv.get("queue")),
                                     num(kv.get("v_mean")), num(kv.get("stand_mean")), num(kv.get("cars_core")), qv("q_arm"),
                                     qv("q_in"), qv("q_out"), num(kv.get("thru")), num(kv.get("thru_s")))))
        # warm-up per zone and load: from the zone's first sample in this load (a Showcase built mid-load warms up
        # from its own start, not the load's)
        first: dict[tuple, float] = {}
        for st, smp in stats:
            first[st.key] = min(first.get(st.key, smp.gt), smp.gt)
        for st, smp in stats:
            if smp.gt < first[st.key] + rep.warmup_s * load.gps:
                st.dropped += 1
                load.dropped += 1
            else:
                st.samples.append(smp)
        if load.sent_runs and load.zones_runs and load.zones_runs[-1] not in load.sent_runs:
            load.warnings.append(f"Smart Lanes holds zones of run {load.zones_runs[-1]}, the Showcase sent "
                                 f"{', '.join(load.sent_runs)}: `ab` may not match (FLOW.md)")
    build_pairs(rep)


def build_pairs(rep: Report) -> None:
    by_pair: dict[tuple[int, str], dict[str, ScZone]] = defaultdict(dict)
    used_gens = {st.gen for st in rep.zones.values() if st.key[0] == "sc"}
    for sc in rep.showcases:
        if sc.gen not in used_gens:
            continue
        for z in sc.zones.values():
            by_pair[(sc.gen, z.pair)][z.ab] = z
    for (gen, pair), twins in sorted(by_pair.items(), key=lambda kv: (kv[0][0], pair_sort(kv[0][1]))):
        any_z = next(iter(twins.values()))
        label = pair + rep.gen_label(gen)
        nomatch = [z for z in twins.values() if not z.match]
        if nomatch:
            reasons = sorted({r for z in nomatch for r in (z.reason or "?").split(",") if r})
            rep.excluded.append((label, any_z.kind, any_z.type, f"match=no ({','.join(reasons) or '?'})"))
            continue
        missing = [ab for ab in ("game", "sl") if ab not in twins]
        if missing:
            rep.excluded.append((label, any_z.kind, any_z.type,
                                 f"missing twin: {','.join(missing)} (no zone line: refused or not built)"))
            continue
        for a, b in COMPARISONS:
            if a not in twins or b not in twins:
                continue
            za, zb = rep.zones.get(twins[a].key), rep.zones.get(twins[b].key)
            if za is None or zb is None:
                miss = ",".join(ab for ab, zz in ((a, za), (b, zb)) if zz is None)
                rep.excluded.append((label, any_z.kind, any_z.type, f"{a} vs {b}: no FLOW samples for {miss} "
                                     "(not a FLOW_ZONE of the traffic log)"))
                continue
            if not (za.usable(rep.min_samples) and zb.usable(rep.min_samples)):
                rep.excluded.append((label, any_z.kind, any_z.type,
                                     f"{a} vs {b}: under {rep.min_samples} samples with cars "
                                     f"({a} {za.n_cars()}, {b} {zb.n_cars()})"))
                continue
            rep.pairs.append(PairCmp(label, gen, any_z.kind, any_z.type, a, b, za, zb))


def pair_sort(p: str) -> tuple:
    m = re.match(r"(?:s\d+)?g(\d+)", p)
    return (int(m[1]) if m else 1 << 30, p)


def ignore_reasons(rep: Report, ignore: list[str]) -> None:
    """Treat every zone whose match=no reasons all lie in `ignore` as matched (noted in the report)."""
    want = {r.strip() for r in ignore if r.strip()}
    if not want:
        return
    def ok(match: bool, reason: str) -> bool:
        reasons = {r for r in (reason or "").split(",") if r}
        return not match and bool(reasons) and reasons <= want

    n = 0
    for sc in rep.showcases:
        for z in sc.zones.values():
            if ok(z.match, z.reason):
                z.match, z.reason = True, ""
                n += 1
    # zone stats already made while reading (FLOW lines before a late zone_match)
    for st in rep.zones.values():
        if ok(st.match, st.reason):
            st.match, st.reason = True, ""
    rep.notes.append(f"--ignore-reason {','.join(sorted(want))}: {n} zone{'' if n == 1 else 's'} with only those match=no "
                     "reasons counted as matched (their twins may differ there: check the log)")


def parse(paths: list[Path], last: bool = False, warmup: float = 180.0, gt_per_s: float | None = None,
          min_samples: int = 5, worse_pct: float = 10.0, ignore: list[str] | None = None) -> Report:
    rep = Report(warmup_s=warmup, gt_per_s=gt_per_s, min_samples=min_samples, worse_pct=worse_pct)
    split_loads(rep, paths)
    ignore_reasons(rep, ignore or [])
    for ld in rep.loads:
        ld.gt_per_s = gt_per_s or ld.gt_per_s
    if last:
        with_flow = [ld for ld in rep.loads if ld.flow_lines()]
        if with_flow:
            rep.notes.append(f"--last: load {with_flow[-1].index} of {len(rep.loads)} ({with_flow[-1].file}, "
                             f"{with_flow[-1].name})")
            rep.loads = [with_flow[-1]]
    build(rep)
    return rep


# ---------------------------------------------------------------------------------------------- render


def f(v: float | None, d: int = 1, sign: bool = False) -> str:
    if v is None:
        return "-"
    return f"{v:+.{d}f}" if sign else f"{v:.{d}f}"


def pv(p: float | None) -> str:
    return "-" if p is None else (f"{p:.3f}" if p >= 0.001 else "<0.001")


def zone_row(st: ZoneStat, label: str) -> str:
    return (f"| {label} | {st.kind} | {st.type} | {st.ab} | {st.n()} | {f(st.cars_mean())} | {f(st.speed_kmh())} | "
            f"{f(st.standing_pct(), 0)} | {f(st.stand_mean())} / {f(st.stand_p90())} / {f(st.stand_max())} | "
            f"{f(st.queue_mean())} |")


ZONE_HEAD = ["| zone | kind | type | ab | samples | cars | km/h | standing % | stand s mean / p90 / max | queue |",
             "|---|---|---|---|---|---|---|---|---|---|"]


def render_loads(rep: Report, out: list[str]) -> None:
    out.append("## Loads")
    out.append("")
    out.append("| load | file | save | Smart Lanes phases | runs | FLOW samples | warm-up dropped | game min |")
    out.append("|---|---|---|---|---|---|---|---|")
    for ld in rep.loads:
        runs = sorted({kv.get("run", "-") for _, kv, _ in ld.events})
        flows = [num(kv.get("gt")) for k, kv, _ in ld.events if k == "FLOW" and num(kv.get("cars")) is not None]
        flows = [g for g in flows if g is not None]
        span = (ld.max_gt - ld.first_gt) / ld.gps / 60 if ld.first_gt is not None and ld.max_gt else None
        name = ld.name + (" (gt reset)" if ld.gt_reset else "")
        out.append(f"| {ld.index} | {ld.file} | {name} | {ld.phases or 'game (no MODE line)'} | {','.join(runs) or '-'} "
                   f"| {len(flows)} | {ld.dropped} | {f(span)} |")
    out.append("")
    entries: list[str] = []
    for ld in rep.loads:
        for sid in dict.fromkeys(k[0] for k in ld.entries):
            kinds = ", ".join(f"{n} {kd}" for (i, kd), n in sorted(ld.entries.items()) if i == sid)
            why = f" (first crossroads: {ld.entry_why[sid]})" if sid in ld.entry_why else ""
            entries.append(f"Load {ld.index}: {sid} town entries: {kinds}{why}.")
    warns = [(ld.index, w) for ld in rep.loads for w in dict.fromkeys(ld.warnings)]
    for i, w in warns:
        out.append(f"- Warning (load {i}): {w}")
    for n in rep.notes + entries:
        out.append(f"- {n}")
    if rep.partial:
        out.append(f"- {rep.partial} incomplete line(s) skipped (cut off, or a FLOW line without zone / gt / cars).")
    if warns or rep.notes or entries or rep.partial:
        out.append("")


def render_twins(rep: Report, out: list[str]) -> None:
    sc_zones = [st for st in rep.zones.values() if st.key[0] == "sc"]
    out.append("## Twins: per zone")
    out.append("")
    if not sc_zones:
        out.append("No FLOW zone matched a `[SQST] showcase zone` line (no Showcase in these logs, or the zones were "
                   "registered elsewhere). Per-zone numbers are under \"Other zones\".")
        out.append("")
        return
    out.append(f"After the warm-up ({rep.warmup_s:g} game s per zone and load). cars = mean per sample; km/h = car-weighted "
               f"mean speed; standing = cars under {STANDING_MS} m/s; stand s = the samples' mean time standing "
               "(mean weighted by standing cars, p90 / max over samples); queue = cars standing >= 5 s.")
    out.append("")
    out.extend(ZONE_HEAD)
    for st in sorted(sc_zones, key=lambda s: (s.gen, pair_sort(s.pair), AB_ORDER.index(s.ab) if s.ab in AB_ORDER else 9)):
        label = st.name + rep.gen_label(st.gen) + ("" if st.match else " (match=no)")
        out.append(zone_row(st, label))
    out.append("")
    out.append("## Twins: per pair")
    out.append("")
    if rep.pairs:
        out.append("delta = first mode minus second (km/h higher is better; standing, stand time and queue lower "
                   "is better).")
        out.append("")
        out.append("| pair | kind | type | compare | samples | km/h | delta km/h | delta % | standing pp | stand s | queue | "
                   "thru/min | delta thru/min |")
        out.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        for p in rep.pairs:
            out.append(f"| {p.pair} | {p.kind} | {p.type} | {p.a} vs {p.b} | {p.za.n()} / {p.zb.n()} | "
                       f"{f(p.za.speed_kmh())} / {f(p.zb.speed_kmh())} | {f(p.d_speed(), 1, True)} | "
                       f"{f(p.d_speed_pct(), 0, True)} | {f(p.d_standing(), 0, True)} | {f(p.d_stand(), 1, True)} | "
                       f"{f(p.d_queue(), 1, True)} | {f(p.za.thru_per_min())} / {f(p.zb.thru_per_min())} | "
                       f"{f(p.d_thru(), 1, True)} |")
    else:
        out.append("No pair with both twins measured (see Excluded pairs).")
    out.append("")
    if rep.pairs:
        out.append("## Twins: paired comparison across pairs")
        out.append("")
        out.append("Per group, the pairs' differences (first mode minus second): mean, wins / losses / ties (speed "
                   "higher, standing lower, thru higher = win for the first mode) and the two-sided sign test p. "
                   "Group `all` pools every pair of every kind / type (all shapes).")
        out.append("")
        out.append("| group | compare | pairs | mean delta km/h | speed W/L/T | p | mean standing pp | standing W/L/T | p | "
                   "mean delta thru/min | thru W/L/T | p |")
        out.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
        groups: dict[tuple[str, str], list[PairCmp]] = defaultdict(list)
        for p in rep.pairs:
            groups[(f"{p.kind}/{p.type}", f"{p.a} vs {p.b}")].append(p)
            groups[(p.kind, f"{p.a} vs {p.b}")].append(p)
            groups[("all", f"{p.a} vs {p.b}")].append(p)
        def gkey(k: tuple[str, str]) -> tuple:
            g, c = k
            return ([f"{a} vs {b}" for a, b in COMPARISONS].index(c), g == "all", "/" not in g, g)
        for (g, c) in sorted(groups, key=gkey):
            ps = groups[(g, c)]
            if g != "all" and "/" not in g and len({p.type for p in ps}) == 1:
                continue  # the kind row equals its only type row
            if g != "all" and "/" not in g and len(ps) == len(groups[("all", c)]):
                continue  # the kind row pools the same pairs as the all row (one kind: e.g. the Lights showcase's plain)
            if g == "all" and len({(p.kind, p.type) for p in ps}) == 1:
                continue  # the all row equals the only type row
            if g == "all" and rep.bench:
                continue  # a bench sheet: every test is its own question, never pooled across tests
            ds = [p.d_speed() for p in ps]
            sw, sl_, st_ = sum(d > 0 for d in ds), sum(d < 0 for d in ds), sum(d == 0 for d in ds)
            dst = [p.d_standing() for p in ps if p.d_standing() is not None]
            tw, tl, tt = sum(d < 0 for d in dst), sum(d > 0 for d in dst), sum(d == 0 for d in dst)
            dth = [p.d_thru() for p in ps if p.d_thru() is not None]
            hw, hl, ht = sum(d > 0 for d in dth), sum(d < 0 for d in dth), sum(d == 0 for d in dth)
            out.append(f"| {g} | {c} | {len(ps)} | {f(sum(ds) / len(ds), 1, True)} | {sw}/{sl_}/{st_} | "
                       f"{pv(sign_test(sw, sl_))} | {f(sum(dst) / len(dst) if dst else None, 1, True)} | "
                       f"{tw}/{tl}/{tt} | {pv(sign_test(tw, tl))} | {f(sum(dth) / len(dth) if dth else None, 1, True)} | "
                       f"{hw}/{hl}/{ht} | {pv(sign_test(hw, hl))} |")
        out.append("")
    if rep.excluded:
        out.append("## Excluded pairs")
        out.append("")
        out.append("| pair | kind | type | reason |")
        out.append("|---|---|---|---|")
        for pair, kind, typ, why in rep.excluded:
            out.append(f"| {pair} | {kind} | {typ} | {why} |")
        out.append("")


def render_approaches(rep: Report, out: list[str]) -> None:
    """v3 zones (FLOW_ZONE measure=corridor): the junction box and each arm's approach (out to r_measure)."""
    zs = [st for st in rep.zones.values() if st.key[0] == "sc" and st.q_arm_means()]
    if not zs:
        return
    out.append("## Approaches (v3 measured area)")
    out.append("")
    out.append("Each zone counts its junction's circle r plus a 30 m corridor along every arm out to r_measure (FLOW.md "
               "\"Measured area\"). box cars = mean cars inside r; queued per arm = mean cars standing >= 5 s per arm "
               "corridor (both directions); in / out = of them on the side towards / away from the junction (q_in / q_out, "
               "2026-10-13; `-` in older logs); thru/min = cars through the junction per game minute.")
    out.append("")
    out.append("| zone | ab | r / r_measure m | cars | box cars | queued per arm | in | out | thru/min |")
    out.append("|---|---|---|---|---|---|---|---|---|")
    for st in sorted(zs, key=lambda s: (s.gen, pair_sort(s.pair), AB_ORDER.index(s.ab) if s.ab in AB_ORDER else 9)):
        def qt(attr: str) -> str:
            return ", ".join(f"{k} {v:.1f}" for k, v in st.q_arm_means(attr).items()) or "-"
        out.append(f"| {st.name}{rep.gen_label(st.gen)} | {st.ab} | {f(st.r, 0)} / {f(st.r_measure, 0)} | {f(st.cars_mean())} | "
                   f"{f(st.core_mean())} | {qt('q_arm')} | {qt('q_in')} | {qt('q_out')} | {f(st.thru_per_min())} |")
    out.append("")


def pooled(stats: list[ZoneStat]) -> ZoneStat:
    z = ZoneStat(("pool",), "", stats[0].kind, stats[0].type, stats[0].ab)
    for s in stats:
        z.samples.extend(s.samples)
    return z


def render_pooled(rep: Report, out: list[str]) -> None:
    sc_zones = [st for st in rep.zones.values() if st.key[0] == "sc" and st.samples]
    if not sc_zones:
        return
    out.append("## Pooled per kind / type")
    out.append("")
    out.append("Every twin with samples (unmatched and incomplete sets too), all samples pooled.")
    out.append("")
    out.append("| kind | type | ab | zones | samples | cars | km/h | standing % | stand s mean / p90 / max | queue |")
    out.append("|---|---|---|---|---|---|---|---|---|---|")
    groups: dict[tuple[str, str, str], list[ZoneStat]] = defaultdict(list)
    for st in sc_zones:
        groups[(st.kind, st.type, st.ab)].append(st)
        groups[(st.kind, "(all)", st.ab)].append(st)
    for k in sorted(groups, key=lambda k: (k[0], k[1] == "(all)", k[1], AB_ORDER.index(k[2]) if k[2] in AB_ORDER else 9)):
        if k[1] == "(all)" and len({s.type for s in groups[k]}) == 1 and \
                len({s.type for kk, v in groups.items() if kk[0] == k[0] and kk[1] != "(all)" for s in v}) == 1:
            continue
        z = pooled(groups[k])
        out.append(f"| {k[0]} | {k[1]} | {k[2]} | {len(groups[k])} | {z.n()} | {f(z.cars_mean())} | "
                   f"{f(z.speed_kmh())} | {f(z.standing_pct(), 0)} | {f(z.stand_mean())} / {f(z.stand_p90())} / "
                   f"{f(z.stand_max())} | {f(z.queue_mean())} |")
    out.append("")


def render_worse(rep: Report, out: list[str]) -> None:
    if not rep.pairs:
        return
    worse = [(p, p.worse(rep.worse_pct)) for p in rep.pairs if p.b == "game"]
    worse = [(p, w) for p, w in worse if w]
    out.append(f"## Worse than game (speed down > {rep.worse_pct:g} % or standing up > {rep.worse_pct:g} pp, "
               f">= {rep.min_samples} samples each)")
    out.append("")
    if not worse:
        out.append("None.")
    else:
        out.append("| pair | kind | type | mode | zone | km/h (game) | standing % (game) | why |")
        out.append("|---|---|---|---|---|---|---|---|")
        for p, w in sorted(worse, key=lambda x: x[0].d_speed_pct() or 0):
            out.append(f"| {p.pair} | {p.kind} | {p.type} | {p.a} | {p.za.name} | {f(p.za.speed_kmh())} "
                       f"({f(p.zb.speed_kmh())}) | {f(p.za.standing_pct(), 0)} ({f(p.zb.standing_pct(), 0)}) | "
                       f"{', '.join(w)} |")
    out.append("")


def render_other_zones(rep: Report, out: list[str]) -> None:
    raw = [st for st in rep.zones.values() if st.key[0] == "raw" and (st.samples or st.dropped)]
    if not raw:
        return
    out.append("## Other zones (no showcase twin)")
    out.append("")
    out.extend(ZONE_HEAD)
    for st in sorted(raw, key=lambda s: (s.kind, s.label)):
        out.append(zone_row(st, st.label))
    out.append("")


def render_trend(rep: Report, out: list[str], rows: int) -> None:
    any_all = False
    for ld in rep.loads:
        alls = [kv for k, kv, _ in ld.events if k == "FLOW_ALL" and num(kv.get("gt")) is not None]
        if not alls:
            continue
        if not any_all:
            out.append("## Map-wide trend (FLOW_ALL)")
            out.append("")
            out.append("Per load, the samples in up to --trend-rows equal chunks. game min from the load's first "
                       "sample; km/h weighted by sampled cars.")
            out.append("")
            any_all = True
        alls.sort(key=lambda kv: num(kv["gt"]))  # type: ignore[arg-type,return-value]
        cut = ld.cut(rep.warmup_s)
        out.append(f"Load {ld.index} ({ld.name}):")
        out.append("")
        out.append("| game min | samples | drivers | in zones | standing % | km/h | stand s | sweep ms | frames | capped | target |")
        out.append("|---|---|---|---|---|---|---|---|---|---|---|")
        size = max(1, math.ceil(len(alls) / max(1, rows)))
        for i in range(0, len(alls), size):
            ch = alls[i:i + size]
            g0, g1 = num(ch[0]["gt"]), num(ch[-1]["gt"])
            t0 = (g0 - ld.first_gt) / ld.gps / 60 if ld.first_gt is not None else 0
            t1 = (g1 - ld.first_gt) / ld.gps / 60 if ld.first_gt is not None else 0
            warm = " (warm-up)" if cut is not None and g1 < cut else ""

            def mean(key: str, rows_: list[dict] = ch) -> float | None:
                v = [num(r.get(key)) for r in rows_]
                v = [x for x in v if x is not None]
                return sum(v) / len(v) if v else None
            sampled = sum(num(r.get("sampled")) or 0 for r in ch)
            standing = sum(num(r.get("standing")) or 0 for r in ch)
            w = [(num(r.get("v_mean")), num(r.get("sampled")) or 0) for r in ch]
            w = [(v, c) for v, c in w if v is not None and c > 0]
            spd = sum(v * c for v, c in w) / sum(c for _, c in w) * 3.6 if w else None
            capped = sum(1 for r in ch if r.get("capped") == "1")
            when = f"{t0:.1f}" if len(ch) == 1 else f"{t0:.1f}-{t1:.1f}"
            # v3: the last sample's target ("all": every driver read); v2 lines have none
            target = ch[-1].get("target", "-")
            out.append(f"| {when}{warm} | {len(ch)} | {f(mean('drivers'), 0)} | {f(mean('in_zones'), 0)} | "
                       f"{f(standing / sampled * 100 if sampled else None, 0)} | {f(spd)} | {f(mean('stand_mean'))} | "
                       f"{f(mean('sweep_ms'), 0)} | {f(mean('frames'), 0)} | {capped or ''} | {target} |")
        out.append("")


def render_buses(rep: Report, out: list[str]) -> None:
    lines: dict[tuple[int, str], dict] = {}  # (Showcase run, line name): a new Showcase reuses the names
    for ld in rep.loads:
        cut = ld.cut(rep.warmup_s)
        for k, kv, _ in ld.events:
            if k != "FLOW_BUS":
                continue
            gt = num(kv.get("gt"))
            name = kv.get("name") or f"line {kv.get('line', '?')}"
            sc_gen = kv["_sc"].gen if kv.get("_sc") is not None else 0
            b = lines.setdefault((sc_gen, name), {"n": 0, "rt_sum": 0.0, "rt_n": 0, "rt_min": None, "rt_max": None,
                                        "age": None, "veh": [], "kv": kv, "dropped": 0})
            if cut is not None and gt is not None and gt < cut:
                b["dropped"] += 1
                continue
            b["n"] += 1
            b["kv"] = kv
            rn, rm = num(kv.get("rt_n")), num(kv.get("rt_mean"))
            if rn and rm is not None:
                b["rt_sum"] += rm * rn
                b["rt_n"] += rn
            for key, fn in (("rt_min", min), ("rt_max", max)):
                v = num(kv.get(key))
                if v is not None:
                    b[key] = v if b[key] is None else fn(b[key], v)
            age = num(kv.get("dep_age_max"))
            if age is not None:
                b["age"] = age if b["age"] is None else max(b["age"], age)
            v = num(kv.get("vehicles"))
            if v is not None:
                b["veh"].append(v)
    if not lines:
        return
    out.append("## Bus lines (FLOW_BUS)")
    out.append("")
    out.append("Round trip in game s (FLOW.md (P) 11f), weighted by the vehicles with a full round trip; "
               "dep age max = the longest wait since a stop departure (a stuck bus grows it).")
    out.append("")
    out.append("| line | twin | samples | vehicles | rt mean | rt min | rt max | dep age max |")
    out.append("|---|---|---|---|---|---|---|---|")

    def twin_of(b: dict) -> tuple[str, str] | None:
        kv = b["kv"]
        if kv.get("pair") and kv.get("ab") and "-" not in (kv["pair"], kv["ab"]):
            return kv["pair"], kv["ab"]
        sc: Showcase | None = kv.get("_sc")
        _, z = explicit_twin(sc, kv) if sc is not None else (False, None)
        return (z.pair, z.ab) if z is not None else None
    for key in sorted(lines, key=lambda k: (k[0], pair_sort((twin_of(lines[k]) or ("~", ""))[0]), k[1])):
        b = lines[key]
        name = key[1] + rep.gen_label(key[0])
        tw = twin_of(b)
        rt = b["rt_sum"] / b["rt_n"] if b["rt_n"] else None
        veh = sum(b["veh"]) / len(b["veh"]) if b["veh"] else None
        out.append(f"| {name} | {f'{tw[0]} {tw[1]}' if tw else '-'} | {b['n']} | {f(veh)} | {f(rt, 0)} | "
                   f"{f(b['rt_min'], 0)} | {f(b['rt_max'], 0)} | {f(b['age'], 0)} |")
    paired: dict[tuple[int, str], dict[str, float]] = defaultdict(dict)
    for (gen, _), b in lines.items():
        tw = twin_of(b)
        if tw and b["rt_n"]:
            paired[(gen, tw[0])][tw[1]] = b["rt_sum"] / b["rt_n"]
    rows = []
    for (gen, pair), abs_ in sorted(paired.items(), key=lambda kv: (kv[0][0], pair_sort(kv[0][1]))):
        pair += rep.gen_label(gen)
        for a, bb in COMPARISONS:
            if a in abs_ and bb in abs_:
                rows.append(f"| {pair} | {a} vs {bb} | {abs_[a]:.0f} / {abs_[bb]:.0f} | {abs_[a] - abs_[bb]:+.0f} |")
    if rows:
        out.append("")
        out.append("| pair | compare | rt mean | delta s (lower is better) |")
        out.append("|---|---|---|---|")
        out.extend(rows)
    elif not any(twin_of(b) for b in lines.values()):
        out.append("")
        out.append("The FLOW_BUS lines name no twin (no pair= / ab= keys): bus lines are listed, not paired.")
    out.append("")


def render_towns(rep: Report, out: list[str], top: int) -> None:
    alls: list[tuple[int, dict]] = []
    towns: dict[str, list[float]] = defaultdict(list)
    for ld in rep.loads:
        for k, kv, _ in ld.events:
            if k != "FLOW_TOWNS":
                continue
            if kv.get("scope") == "all":
                alls.append((ld.index, kv))
            elif kv.get("scope") == "town":
                sp = num(kv.get("speed"))
                if sp is not None:
                    towns[kv.get("name") or kv.get("town", "?")].append(sp)
    if not alls and not towns:
        return
    out.append("## Towns (FLOW_TOWNS)")
    out.append("")
    if alls:
        out.append("| load | game min | towns | speed mean | speed min | levels (streets per congestion level) |")
        out.append("|---|---|---|---|---|---|")
        shown = alls if len(alls) <= 6 else alls[:3] + alls[-3:]
        for i, kv in shown:
            ld = next(x for x in rep.loads if x.index == i)
            gt = num(kv.get("gt"))
            t = (gt - ld.first_gt) / ld.gps / 60 if gt is not None and ld.first_gt is not None else None
            out.append(f"| {i} | {f(t, 0)} | {kv.get('towns', '-')} | {kv.get('speed_mean', '-')} | "
                       f"{kv.get('speed_min', '-')} | {kv.get('levels', '-')} |")
        if len(alls) > 6:
            out.append(f"| ... | {len(alls) - 6} more | | | | |")
        out.append("")
    if towns:
        out.append(f"Slowest towns (mean `speed` rating over the samples, lowest {top}):")
        out.append("")
        out.append("| town | samples | speed mean | first | last |")
        out.append("|---|---|---|---|---|")
        for name in sorted(towns, key=lambda n: sum(towns[n]) / len(towns[n]))[:top]:
            v = towns[name]
            out.append(f"| {name} | {len(v)} | {sum(v) / len(v):.2f} | {v[0]:.2f} | {v[-1]:.2f} |")
        out.append("")


def render_runs(rep: Report, out: list[str]) -> None:
    rows = []
    for ld in rep.loads:
        starts = {kv.get("run", "-"): kv for k, kv, _ in ld.events if k == "FLOW_START"}
        sums = {kv.get("run", "-"): kv for k, kv, _ in ld.events if k == "FLOW_SUMMARY"}
        for run in sorted(set(starts) | set(sums)):
            st, sm = starts.get(run, {}), sums.get(run, {})
            warn = sm.get("warn", "-")
            if st.get("keep_cleared") == "1":
                warn = "keep_cleared" if warn in ("-", "") else warn
            rows.append(f"| {ld.index} | {run} | {st.get('interval', '-')} | {st.get('speed', '-')} | "
                        f"{st.get('zones', '-')} | {sm.get('samples', '(no summary)')} | {sm.get('standing_frac', '-')} | "
                        f"{f(num(sm.get('v_mean')) * 3.6 if num(sm.get('v_mean')) is not None else None)} | "
                        f"{sm.get('capped', '-')} | {sm.get('skipped', '-')} | {warn} |")
    if not rows:
        return
    out.append("## Sampler runs (FLOW_START / FLOW_SUMMARY)")
    out.append("")
    out.append("| load | run | interval s | game speed | zones | samples | standing frac | km/h | capped | skipped | warn |")
    out.append("|---|---|---|---|---|---|---|---|---|---|---|")
    out.extend(rows)
    out.append("")


# ---------------------------------------------------------------------------------------------- toggle blocks


@dataclass
class Block:
    load: int
    seq: int
    state: str
    gt0: float
    gt1: float | None = None
    zones: list[Sample] = field(default_factory=list)
    alls: list[dict] = field(default_factory=list)
    dropped: int = 0
    gps: float = 1000.0

    def speed(self) -> float | None:
        z = ZoneStat(("b",), "", "", "", samples=self.zones)
        return z.speed_kmh()

    def standing(self) -> float | None:
        return ZoneStat(("b",), "", "", "", samples=self.zones).standing_pct()

    def map_speed(self) -> float | None:
        w = [(num(r.get("v_mean")), num(r.get("sampled")) or 0) for r in self.alls]
        w = [(v, c) for v, c in w if v is not None and c > 0]
        return sum(v * c for v, c in w) / sum(c for _, c in w) * 3.6 if w else None

    def map_standing(self) -> float | None:
        s = sum(num(r.get("sampled")) or 0 for r in self.alls)
        return sum(num(r.get("standing")) or 0 for r in self.alls) / s * 100 if s else None


def toggle_blocks(rep: Report) -> tuple[list[Block], int]:
    """FLOW.md "[SQRL] TOGGLE" report rule: a block runs from a phase=end / phase=load line to the next
    phase=start; samples while toggling are dropped; warm-up after each block start."""
    blocks: list[Block] = []
    toggling = 0
    for ld in rep.loads:
        if not ld.toggles:
            continue
        tg = sorted(ld.toggles, key=lambda t: (t["_gt"], t["_order"]))
        lb: list[Block] = []
        for t in tg:
            if lb and lb[-1].gt1 is None and t["phase"] in ("start", "end", "load"):
                lb[-1].gt1 = t["_gt"]
            if t["phase"] in ("end", "load"):
                lb.append(Block(ld.index, int(num(t.get("seq")) or 0), t.get("state", "?"), t["_gt"], gps=ld.gps))
        starts = [t["_gt"] for t in tg if t["phase"] == "start"]
        for k, kv, _ in ld.events:
            if k not in ("FLOW", "FLOW_ALL"):
                continue
            gt = num(kv.get("gt"))
            if gt is None:
                continue
            blk = next((b for b in reversed(lb) if b.gt0 <= gt and (b.gt1 is None or gt < b.gt1)), None)
            if blk is None:
                if any(s <= gt for s in starts):
                    toggling += 1
                continue
            if gt < blk.gt0 + rep.warmup_s * ld.gps:
                blk.dropped += 1
                continue
            if k == "FLOW_ALL":
                blk.alls.append(kv)
            elif num(kv.get("cars")) is not None:
                blk.zones.append(Sample(gt, num(kv["cars"]) or 0, num(kv.get("standing")) or 0,  # type: ignore[arg-type]
                                        num(kv.get("queue")), num(kv.get("v_mean")), num(kv.get("stand_mean"))))
        blocks.extend(lb)
    return blocks, toggling


def render_toggle(rep: Report, out: list[str]) -> None:
    blocks, toggling = toggle_blocks(rep)
    if not blocks:
        return
    out.append("## Toggle blocks ([SQRL] TOGGLE fallback)")
    out.append("")
    out.append(f"Blocks from each TOGGLE phase=end / load to the next phase=start; {toggling} sample line(s) while "
               f"toggling dropped; warm-up {rep.warmup_s:g} game s after each block start.")
    out.append("")
    out.append("| block | load | seq | state | game min | FLOW_ALL samples | map km/h | map standing % | zone km/h | zone standing % |")
    out.append("|---|---|---|---|---|---|---|---|---|---|")
    counter: Counter = Counter()
    names = []
    for b in blocks:
        counter[b.state] += 1
        name = f"{b.state.capitalize()}#{counter[b.state]}"
        names.append(name)
        dur = (b.gt1 - b.gt0) / b.gps / 60 if b.gt1 is not None else None
        out.append(f"| {name} | {b.load} | {b.seq} | {b.state} | {f(dur)} | {len(b.alls)} | {f(b.map_speed())} | "
                   f"{f(b.map_standing(), 0)} | {f(b.speed())} | {f(b.standing(), 0)} |")
    out.append("")
    pairs = []
    for i, b in enumerate(blocks):
        if b.state != "on" or b.map_speed() is None:
            continue
        nb = [blocks[j] for j in (i - 1, i + 1) if 0 <= j < len(blocks) and blocks[j].state == "off"
              and blocks[j].map_speed() is not None]
        if nb:
            off = sum(x.map_speed() for x in nb) / len(nb)  # type: ignore[misc]
            pairs.append((names[i], b.map_speed() - off))  # type: ignore[operator]
    if pairs:
        out.append("On block vs its neighbouring Off block(s), map-wide km/h: " +
                   ", ".join(f"{n} {d:+.1f}" for n, d in pairs) + ".")
    if counter["on"] < 2 or counter["off"] < 2:
        out.append("Fewer than two On and two Off blocks: run Off / On / Off / On (ABAB) so a time trend does not "
                   "pass for an effect.")
    out.append("")


def render(rep: Report, trend_rows: int = 12, towns: int = 10) -> str:
    out: list[str] = [f"# Traffic flow report ({', '.join(rep.files)})", ""]
    render_loads(rep, out)
    render_twins(rep, out)
    render_approaches(rep, out)
    render_worse(rep, out)
    render_pooled(rep, out)
    render_other_zones(rep, out)
    render_trend(rep, out, trend_rows)
    render_buses(rep, out)
    render_towns(rep, out, towns)
    render_runs(rep, out)
    render_toggle(rep, out)
    return "\n".join(out).rstrip() + "\n"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("logs", nargs="*", type=Path, help="stdout.txt copies, in session order (default: the live one)")
    ap.add_argument("--last", action="store_true", help="only the most recent load with FLOW lines")
    ap.add_argument("--warmup", type=float, default=180.0, help="game seconds dropped per zone and load (default 180)")
    ap.add_argument("--worse-pct", type=float, default=10.0, help="'worse than game' threshold (default 10)")
    ap.add_argument("--min-samples", type=int, default=5, help="samples per twin for a comparison (default 5)")
    ap.add_argument("--gt-per-s", type=float, default=None,
                    help="gt units per game second (default: FLOW_START gt_per_s=, else 1000: ms)")
    ap.add_argument("--trend-rows", type=int, default=12, help="FLOW_ALL rows per load (default 12)")
    ap.add_argument("--towns", type=int, default=10, help="slowest towns listed (default 10)")
    ap.add_argument("--ignore-reason", action="append", default=[], metavar="REASON[,REASON]",
                    help="count zones whose match=no reasons are all among these as matched (repeatable or a comma "
                         "list, e.g. entry: a false entry alarm); the report notes it")
    args = ap.parse_args()
    paths = args.logs or [default_log()]
    for p in paths:
        if not p.is_file():
            raise SystemExit(f"No such log: {p}")
    ignore = [r for a in args.ignore_reason for r in a.split(",")]
    rep = parse(paths, args.last, args.warmup, args.gt_per_s, args.min_samples, args.worse_pct, ignore)
    if not rep.loads:
        print(f"No [SQST] FLOW_* or [SQRL] TOGGLE lines in {', '.join(map(str, paths))}.")
        print("Build a Showcase (Stress Test), turn the Traffic tab's Traffic log On, let the game run for a while "
              "(at least --warmup plus a few samples), then run this again.")
        return
    print(render(rep, args.trend_rows, args.towns), end="")


if __name__ == "__main__":
    main()

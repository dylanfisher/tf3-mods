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
  [SQST] RINGMIX / RINGLANE run= s= zone= twin= ...  (bench Sheet 5: a ring twin's turning mix / lane use, cumulative per run)
  [SQST] lights_showcase entry <town> kind=roundabout|crossroads ...   (the Lights showcase's town entries)
  [SQRL] MODE phases= free_turn= / ZONES op= run= / TOGGLE state= phase= gt=               (Smart Lanes)
  [SQRL] RETIME op=write node= sent= [zid=] / op=probe at=cb success=                      (Smart Lanes' Re-time)
  [SQRL] AUTORETIME op=write node= sent=1 zid= / op=enroll_all phase=done run= / op=enroll src=all node= pos= [zid=]
  [SQST] AUTO_ALL op=all|clear run=                                   (the Stress Test's whole-map button)
  [SQRL] LIGHTS / APPLY / PHASES ... node= ... zid=<twin id>          (which twin a node belongs to)

Light plans A/B (SHOWCASE.md "Light plans A/B"): sets with twins game / sl_phases (the axis plan) / sl_auto (the axis
plan with Smart Lanes' automatic re-timing; sl_classic, the classic patterns, in the earlier build) get their own
section per shape and demand (the zone lines' `demand=balanced|unbalanced`): game vs axis vs auto (thru/min, queue per
arm, standing %, km/h) and a one-line verdict. Auto timing (`[SQRL] AUTORETIME op=write sent=1 ... zid=`): a set whose
sl_auto twin wrote is split like a Re-time: before its first write (the plans as built) in the tables, the samples from
its "settled from" time (the first write + --auto-settle game s) on as set `<pair>+as` (the auto twin's mode
`sl_auto+as`); the light plans section compares the plans in that settled window, an "Auto timing" section shows
before / settled per set. Whole-map auto re-time (Stress Test "Auto re-time > All lit junctions": `AUTORETIME
op=enroll_all phase=done`): the enrolled zones (and the map) before the request and from --auto-settle s after it. The
bench's city run (BENCH.md "City lights at scale": `[SQST] CITY` / `CITY_ENROLL`, city zones ab=city_auto|city_control):
section "Auto lights at scale": Smart Lanes' frame cost (`[SQPERF] ... ctx=bg` windows, slow lines, `AUTORETIME
op=snapshot` person-list spikes), writes per game minute, junctions written, first fits, every city before the enroll vs
from --auto-settle after it, the controls, the pass criteria; v2 (the City lights options): one part per run, each pair's
baseline gap (a warning over 10 %), the funnel layout's crossings and gap streets (`CITY_GAPS`), and with runs of both roles
(`CITY_ENROLL role_swap=0|1`) their swapped-roles mean; snapshot spikes by `fetch_ms` (Smart Lanes with `op=config
clock=wall`; an older one's os.clock `max_frame_ms` is shown as inflated, never a spike). Ring twins (zone lines with mix=, bench Sheets 5 / 6) get a
gridlock check per twin (GRID_* below). Re-time: a twin whose node got a Re-time write (`RETIME op=write sent>=1`, joined to its twin
by the write's own `zid=` or any Smart Lanes line naming that node with a `zid=`) splits its whole set at the write:
the twin tables keep the samples before it (the plans as built), the samples from --retime-settle game s after it
form the set `<pair>+rt` (the written twin's mode `<ab>+rt`, compared with its set's other twins in that same window),
and the Re-time section shows before / after with the change relative to the game twin.

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

Ring lane use (bench Sheet 5, BENCH.md "Sheet 5"): zone lines with `mix=even|straight|adjacent` get a section per ring and
mix (every mode's thru/min, km/h, standing, queue per arm, lane use from RINGLANE and the measured turning mix from RINGMIX
over the recorded window), a RINGMIX table per twin and a verdict line per ring and mix (each mode vs game and vs sl_rturbo).

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
import bisect
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
FLOW_KINDS = {"FLOW_START", "FLOW_ZONE", "FLOW", "FLOW_ALL", "FLOW_TOWNS", "FLOW_BUS", "FLOW_SUMMARY", "FLOW_TARGET", "RINGMIX", "RINGLANE"}
RING_KINDS = ("RINGMIX", "RINGLANE")  # bench Sheet 5: cumulative per traffic log run (BENCH.md "Sheet 5", FLOW.md "RINGMIX")
# "[SQST] lights_showcase entry Smart lanes 1 N kind=roundabout ..." (SHOWCASE.md "Town entries")
ENTRY = re.compile(r"^(?P<id>\w+) entry (?P<town>.+?) kind=(?P<kind>\w+)")
# the ring layouts (Smart Lanes PLAN.md "Ring layout variants (bench)"): the micro bench's six, then sl_rsplit (Sheet 4 v3:
# the spiral with its lane change at the ring's mid nodes) and sl_rmid (Sheet 4 v4: every lane change at the mid nodes)
# and the ring lane use modes (Smart Lanes PLAN.md "Ring lane use", bench Sheet 5): sl_rmid2 (sl_rmid with wide exits fed by
# the first circulating lane; Smart Lanes adds the mid nodes) and sl_rturbo_in (turbo with the inner lanes fed)
RING_MODES = ["sl_rturbo", "sl_rmatch", "sl_rout1", "sl_r2exit", "sl_rspiral", "sl_rspread", "sl_rsplit", "sl_rmid", "sl_rmid2",
              "sl_rturbo_in"]
AB_ORDER = ["game", "sl", "sl_phases", "sl_fan", "sl_lock", "sl_exitfan", "sl_keeplights"] + RING_MODES + ["sl_classic", "sl_auto"]
# sl_fan: the Lights showcase's full fan + split phases (a measuring mode); sl_lock: Smart Lanes lanes with the kerb
# turn kept locked (game phases): vs game = the lane layout alone, sl vs sl_lock = the free kerb turn alone;
# sl_exitfan (twin e, 2026-10-13): Smart Lanes lanes with every turn fanned into the exit lanes (game phases): vs sl =
# the exit fan alone, vs game = lanes + fan
COMPARISONS = [("sl", "game"), ("sl_phases", "game"), ("sl_phases", "sl"), ("sl_fan", "game"), ("sl_fan", "sl_phases"),
               ("sl_lock", "game"), ("sl", "sl_lock"), ("sl_exitfan", "sl"), ("sl_exitfan", "game"), ("sl", "sl_keeplights")]
COMPARISONS += [(m, "sl") for m in RING_MODES] + [(m, "game") for m in RING_MODES]
# Light plans A/B (2026-10-14, SHOWCASE.md "Light plans A/B"): sl_classic = Smart Lanes lanes with its classic light
# patterns (protected / split / lead-lag), sl_phases = the same lanes with the axis plan (Smart Lanes rev 8)
COMPARISONS += [("sl_classic", "game"), ("sl_phases", "sl_classic")]
# Keep timing adjusted (Smart Lanes rev 8 step B, its PLAN.md "Stress Test interface: Keep timing adjusted"): sl_auto = the
# axis plan with Smart Lanes' automatic re-timing: vs sl_phases = the re-timing alone, vs game = lanes + plan + timing
COMPARISONS += [("sl_auto", "sl_phases"), ("sl_auto", "game")]
COMPARISONS += [("sl_rsplit", "sl_rspiral")]  # Sheet 4 v3: the mid-node lane change alone
# Sheet 5 (ring lane use): every layout also against sl_rturbo, what Smart Lanes wrote on these rings when Sheet 5 ran (its 2-lane default with wide exits is matched since 2026-10-15)
LU_VS_TURBO = ["sl_rmid2", "sl_rturbo_in", "sl_rmatch", "sl_rspread"]
COMPARISONS += [(m, "sl_rturbo") for m in LU_VS_TURBO]
COMPARISONS += [("sl_rmid", "sl_rsplit"), ("sl_rmid", "sl_rspiral")]  # Sheet 4 v4: the outward move off the junction too
# Sheet 6 (the mid-node default under heavy traffic): the shipped default against the old matched one; there
# sl_rmatch vs sl_rturbo (above, Sheet 5) compares identical twins: on one-lane exits both write matched lanes (A/A)
COMPARISONS += [("sl", "sl_rmatch")]
# Sheet 4 v5: twins of one set on two ring geometries (BENCH.md "Sheet 4" v5): a bench zone line's geom= makes its mode
# "<ab>@<geom>" (plain: the ring as players have it, mid: with nodes between the arms)
COMPARISONS += [("sl_rsplit@mid", "game@plain"), ("sl_rsplit@mid", "sl@plain"), ("game@mid", "game@plain"),
                ("sl@plain", "game@plain"), ("sl_rmid@mid", "game@plain"), ("sl_rmid@mid", "sl_rsplit@mid")]
# sl_keeplights (the bench's lights twin, plans/square_stress_test/BENCH.md): Smart Lanes lanes with the game's lights left
# at rings and slip / ramp nodes: sl vs sl_keeplights = "No lights at roundabouts and ramps" alone
FLOW_KIND_NAMES = {"ix": "interchange", "rb": "roundabout", "x": "plain"}
TWIN_ID = re.compile(r"^((?:[a-z]+\d*)?g\d+)([a-z])$")  # g3a, or a bench sheet's s2g3a / microg3a
STANDING_MS = 0.5  # FLOW.md: standing = dyn.speed < 0.5 m/s (the sampler counts it; noted in the report)
RT = "+rt"  # the after-Re-time window: pair "<pair>+rt", zone "<id>+rt", the written twin's mode "<ab>+rt"
AS = "+as"  # the auto twin's settled window: pair "<pair>+as", zone "<id>+as", the auto twin's mode "sl_auto+as"
SUFFIXES = (RT, AS)
# the light plans A/B's plans, as the report names them
PLAN_NAMES = {"game": "game", "sl_phases": "axis", "sl_classic": "classic", "sl_auto": "auto"}
PLAN_ABS = ["game", "sl_phases", "sl_classic", "sl_auto"]
AUTO_AB = "sl_auto"
DEMANDS = ("balanced", "unbalanced")
TOWN_WORDS = {"busy": 600, "small": 150, "tiny": 40}  # the unbalanced sets' town name suffixes and their targets
MIXES = ("even", "straight", "adjacent")  # bench Sheet 5's traffic mixes (zone lines' mix=), in set order
LANE_GAP_M = 1.25  # RINGLANE: distances further apart than this (between non-empty 0.5 m bins) are two lanes
LANE_MIN_SHARE = 0.02  # bins with less than this share of a ring's car samples are left out of the clustering
# Gridlock (bench Sheet 6, BENCH.md "Sheet 6"): per twin, windows of GRID_WIN_S game s over its recorded samples; a window is
# locked at >= GRID_STANDING % standing with thru/min <= GRID_THRU_FRAC of the best window any twin of its set reached; a
# twin is in gridlock when its last GRID_LAST windows are all locked (the lock lasted to the end of the record)
GRID_WIN_S = 120.0
GRID_STANDING = 80.0
GRID_THRU_FRAC = 0.25
GRID_LAST = 3
# The city run (BENCH.md "City lights at scale"): its zones' modes (never sent to Smart Lanes) and the pass criteria
CITY_ABS = ("city_auto", "city_control")
CITY_FRAME_MS = 5.0     # no Smart Lanes frame over this (SQPERF ctx=bg window max, slow lines)
CITY_MEAN_MS = 1.5      # mean Smart Lanes background cost per frame at 4x
CITY_WORSE_PCT = 10.0   # no city's km/h more than this % below its baseline
CITY_FIT_SHARES = (0.5, 0.8)  # "time until most report fits": the first fits of this share of the enrolled junctions
CITY_PAIR_GAP_PCT = 10.0  # a pair whose auto and control cities' baseline km/h differ by more: "pairs too unequal at baseline"
SQPERF_SL = re.compile(r"\[SQPERF\] mod=square_smart_lanes ctx=(?P<ctx>\S+) vm=\S+ (?P<rest>.*)$")
SQPERF_SLOW = re.compile(r"slow=(\w+) max=([\d.]+) over=(\d+)/(\d+)")
SQPERF_SECTION = re.compile(r"\| (\w+) n=(\d+) ms=([\d.]+) max=([\d.]+)")


def suffix_of(v: str) -> str:
    """The split window suffix of a pair / zone / mode ("+rt", "+as"), "" for none."""
    return next((x for x in SUFFIXES if v.endswith(x)), "")


def base_of(v: str) -> str:
    """A pair / zone / mode without its split window suffix."""
    sx = suffix_of(v)
    return v[: -len(sx)] if sx else v


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
    demand: str = "-"  # the light plans A/B's set demand (balanced / unbalanced; "-": none)
    mix: str = "-"  # bench Sheet 5: the set's traffic mix (even / straight / adjacent; "-": none)

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
    order: int = 0  # stdout order of its FLOW line (the Re-time split)
    load: int = 0  # its load's index


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
    demand: str = "-"  # the light plans A/B's set demand
    mix: str = "-"  # bench Sheet 5: the set's traffic mix
    ringmix: Counter = field(default_factory=Counter)  # RINGMIX over the recorded window: n, exit1.., uturn, none
    ringlanes: Counter = field(default_factory=Counter)  # RINGLANE over the recorded window: distance (m) -> car samples
    ring_arms: int = 0  # RINGMIX arms=
    x: float | None = None  # its centre (the whole-map split joins Smart Lanes' enroll lines by position)
    y: float | None = None

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
    retime_settle_s: float = 60.0  # game s after a Re-time write before the after window starts
    retimes: list[dict] = field(default_factory=list)  # [SQRL] RETIME op=write sent>=1: node, zid, gen, order, refused
    node_zid: dict[tuple[int, str], str] = field(default_factory=dict)  # (showcase gen, node) -> zid of Smart Lanes lines
    rt_sets: list[dict] = field(default_factory=list)  # the split sets (render_retime)
    auto_settle_s: float = 2700.0  # game s after an auto twin's first write before its settled window starts
    auto_writes: list[dict] = field(default_factory=list)  # [SQRL] AUTORETIME op=write sent=1: node, zid, gen, order, load
    as_sets: list[dict] = field(default_factory=list)  # the auto-split sets (render_auto)
    enroll_all: list[dict] = field(default_factory=list)  # AUTORETIME op=enroll_all phase=done: run, order, load, gen
    enrolled: list[dict] = field(default_factory=list)  # AUTORETIME op=enroll src=all: node, zid, x, y, gen, order
    auto_all: list[dict] = field(default_factory=list)  # [SQST] AUTO_ALL op= run=
    wm: dict | None = None  # the whole-map before / after (render_whole_map)
    # the bench's city run (BENCH.md "City lights at scale"): CITY / CITY_ENROLL lines, every AUTORETIME enroll / plan line,
    # Smart Lanes' SQPERF lines, the record's game speed (BENCH_PHASE speed=)
    cities: list[dict] = field(default_factory=list)
    city_enroll: list[dict] = field(default_factory=list)
    auto_enrolls: list[dict] = field(default_factory=list)  # AUTORETIME op=enroll (any src): node, pos, src, order, load
    auto_plans: list[dict] = field(default_factory=list)  # AUTORETIME op=plan: node, result, order, load
    auto_snaps: list[dict] = field(default_factory=list)  # AUTORETIME op=snapshot (v4): src, max (frame ms), busy, frames, n, fetch, finish
    auto_clocks: list[dict] = field(default_factory=list)  # AUTORETIME op=config clock=wall|os: clock, order, load
    city_gaps: list[dict] = field(default_factory=list)  # [SQST] CITY_GAPS (funnel layouts): kv + order, load
    sqperf: list[dict] = field(default_factory=list)  # [SQPERF] mod=square_smart_lanes: ctx, kind window|slow, order, load
    bench_speeds: list[tuple[int, int]] = field(default_factory=list)  # (order, speed) of BENCH_PHASE lines with speed=

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
            pm = SQPERF_SL.search(raw) if "[SQPERF]" in raw else None
            if pm:
                rest_p = pm["rest"]
                sm = SQPERF_SLOW.search(rest_p)
                if sm:
                    rep.sqperf.append({"ctx": pm["ctx"], "kind": "slow", "section": sm[1], "max": float(sm[2]),
                                       "over": int(sm[3]), "n": int(sm[4]), "order": order, "load": load})
                elif "win_ms=" in rest_p:
                    secs = {s[0]: (int(s[1]), float(s[2]), float(s[3])) for s in SQPERF_SECTION.findall(rest_p)}
                    rep.sqperf.append({"ctx": pm["ctx"], "kind": "window", "sections": secs, "order": order, "load": load})
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
                elif kind == "RETIME" and kv.get("op") == "write" and (num(kv.get("sent")) or 0) > 0 and kv.get("node"):
                    rep.retimes.append({"node": kv["node"], "zid": kv.get("zid"), "gen": sc.gen, "order": order,
                                        "load": load, "refused": False})
                elif kind == "AUTORETIME" and kv.get("op") == "write" and kv.get("at") != "cb" and \
                        (num(kv.get("sent")) or 0) > 0 and kv.get("node"):
                    rep.auto_writes.append({"node": kv["node"], "zid": kv.get("zid"), "gen": sc.gen, "order": order,
                                            "load": load, "refused": False, "pos": kv.get("pos")})
                elif kind == "AUTORETIME" and kv.get("op") == "snapshot":
                    # Smart Lanes step B v4: one queue snapshot of every watched junction every 120 game s; src=scan reads
                    # the whole person list in one engine call (its one long frame: max_frame_ms)
                    # fetch_ms (the person-list call alone) / finish_ms: Smart Lanes with the wall clock (op=config clock=)
                    rep.auto_snaps.append({"src": kv.get("src", "-"), "max": num(kv.get("max_frame_ms")), "busy": num(kv.get("busy_ms")),
                                           "frames": num(kv.get("frames")), "n": num(kv.get("n")), "order": order, "load": load,
                                           "fetch": num(kv.get("fetch_ms")), "finish": num(kv.get("finish_ms"))})
                elif kind == "AUTORETIME" and kv.get("op") == "config" and kv.get("clock"):
                    rep.auto_clocks.append({"clock": kv["clock"], "order": order, "load": load})
                elif kind == "AUTORETIME" and kv.get("op") == "plan" and kv.get("node"):
                    rep.auto_plans.append({"node": kv["node"], "result": kv.get("result", "-"), "order": order, "load": load})
                elif kind == "AUTORETIME" and kv.get("op") == "write" and kv.get("at") == "cb" and \
                        kv.get("success") in ("false", "0", "no", "nil"):
                    for w in reversed(rep.auto_writes):
                        if w["node"] == kv.get("node") and not w["refused"]:
                            w["refused"] = True
                            break
                elif kind == "AUTORETIME" and kv.get("op") == "enroll_all" and kv.get("phase") == "done":
                    rep.enroll_all.append({"run": kv.get("run", "-"), "order": order, "load": load, "gen": sc.gen,
                                           "lit": kv.get("lit", "-"), "sent": kv.get("sent", "-"),
                                           "capped": kv.get("capped", "-")})
                elif kind == "AUTORETIME" and kv.get("op") == "enroll":
                    px, _, py = (kv.get("pos") or "").partition(",")
                    rep.auto_enrolls.append({"node": kv.get("node"), "src": kv.get("src", "-"), "x": num(px), "y": num(py),
                                             "order": order, "load": load})
                    if kv.get("src") == "all":
                        zid = kv.get("zid")
                        rep.enrolled.append({"node": kv.get("node"), "zid": zid.split(",")[0] if zid and zid != "-" else None,
                                             "x": num(px), "y": num(py), "gen": sc.gen, "order": order})
                elif kind == "RETIME" and kv.get("op") == "probe" and kv.get("at") == "cb" and \
                        kv.get("success") in ("false", "0", "no", "nil"):
                    # the game refused the written phases: that write changed nothing
                    for w in reversed(rep.retimes):
                        if w["node"] == kv.get("node") and not w["refused"]:
                            w["refused"] = True
                            break
                if kv.get("node") and kv.get("zid") and kv["zid"] != "-":
                    rep.node_zid[(sc.gen, kv["node"])] = kv["zid"].split(",")[0]
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
            if kind == "AUTO_ALL":
                rep.auto_all.append({"op": kv.get("op", "-"), "run": kv.get("run", "-"), "order": order})
                continue
            if kind == "CITY":
                rep.cities.append({**kv, "_order": order, "_load": load})
                continue
            if kind == "CITY_ENROLL":
                # its run's city zones are the showcase current now (their zone lines come before the enroll)
                rep.city_enroll.append({**kv, "_order": order, "_load": load, "_gen": sc.gen})
                continue
            if kind == "CITY_GAPS":
                rep.city_gaps.append({**kv, "_order": order, "_load": load})
                continue
            if kind == "BENCH_PHASE" and num(kv.get("speed")):
                rep.bench_speeds.append((order, int(num(kv["speed"]))))  # type: ignore[arg-type]
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
                # a bench twin on a named ring geometry (geom=): its mode is "<ab>@<geom>" (Sheet 4 v5)
                ab_ = kv.get("ab", "-") + ("@" + kv["geom"] if kv.get("geom") else "")
                z = ScZone(sc.gen, kv["id"], kv.get("pair") or (tm[1] if tm else kv["id"]), ab_,
                           kind_, kv.get("type", "-"), num(kv.get("x")), num(kv.get("y")),
                           num(kv.get("r")), kv.get("match", "yes") != "no", kv.get("reason", ""),
                           int(kv["towns"]) if kv.get("towns", "").isdigit() else None, kv.get("demand") or "-",
                           kv.get("mix") or "-")
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
            if z.pair == pair and z.ab.split("@")[0] == ab:
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
            st = rep.zones[key] = ZoneStat(key, label, z.kind, z.type, z.ab, z.pair, z.gen, z.match, z.reason,
                                           demand=z.demand, mix=z.mix, x=z.x, y=z.y)
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
        st = rep.zones[key] = ZoneStat(key, label, kind, "-", x=meta.x if meta else None, y=meta.y if meta else None)
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
        rows: list[tuple[dict, float, float, int]] = []
        ring_rows: list[tuple[str, dict, int]] = []
        run_start: dict[str, float] = {}
        for kind, kv, order in load.events:
            if kind == "FLOW_START" and num(kv.get("gt")) is not None:
                run_start[kv.get("run", "-")] = num(kv.get("gt"))  # type: ignore[assignment]
            if kind in RING_KINDS:
                ring_rows.append((kind, kv, order))
                continue
            if kind == "FLOW_START" and kv.get("keep_cleared") == "1":
                load.warnings.append(f"run {kv.get('run', '-')}: Keep traffic cleared was on: not valid for A/B")
            elif kind == "FLOW_ZONE" and kv.get("zone"):
                run = kv.get("run", "-")
                meta = ZoneMeta(kv["zone"], kv.get("label", "-"), kv.get("kind", "other"), kv.get("src", "-"),
                                num(kv.get("x")), num(kv.get("y")), num(kv.get("r")), None, num(kv.get("r_measure")),
                                kv.get("measure", "-"), kv.get("arms", "-"))
                meta.sc, d = join_showcase(kv["_sc"], meta, kv)
                if meta.sc is not None and meta.sc.demand == "-" and kv.get("demand") not in (None, "", "-"):
                    meta.sc.demand = kv["demand"]  # an older zone line without demand=: the FLOW_ZONE's
                if meta.sc is not None and meta.sc.mix == "-" and kv.get("mix") not in (None, "", "-"):
                    meta.sc.mix = kv["mix"]
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
                rows.append((kv, gt, cars, order))
        # resolved after every FLOW_ZONE of the load (a later, closer zone may take a twin over)
        stats: list[tuple[ZoneStat, Sample]] = []
        for kv, gt, cars, order in rows:
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
                                     qv("q_in"), qv("q_out"), num(kv.get("thru")), num(kv.get("thru_s")), order,
                                     load.index)))
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
        ring_windows(rep, load, ring_rows, metas, first, run_start)
        if load.sent_runs and load.zones_runs and load.zones_runs[-1] not in load.sent_runs:
            load.warnings.append(f"Smart Lanes holds zones of run {load.zones_runs[-1]}, the Showcase sent "
                                 f"{', '.join(load.sent_runs)}: `ab` may not match (FLOW.md)")
    whole_map(rep)
    split_retimes(rep)
    split_auto(rep)
    build_pairs(rep)


def ring_values(kind: str, kv: dict) -> Counter:
    """A RINGMIX line's counts (n, exit1.., uturn, none) or a RINGLANE line's car samples per distance (m)."""
    out: Counter = Counter()
    if kind == "RINGMIX":
        for k, v in kv.items():
            if (k in ("n", "uturn", "none") or re.fullmatch(r"exit\d+", k)) and str(v).isdigit():
                out[k] = int(v)
        return out
    for part in (kv.get("radii") or "").split(","):
        r, _, c = part.partition(":")
        if num(r) is not None and c.isdigit():
            out[num(r)] = int(c)
    return out


def ring_windows(rep: Report, load: Load, ring_rows: list[tuple[str, dict, int]], metas: dict, first: dict,
                 run_start: dict[str, float]) -> None:
    """RINGMIX / RINGLANE (bench Sheet 5): cumulative per sampler run, so a twin's recorded window is its run's last line
    minus its first line at or after the warm-up cut (the zone's first sample in this load + --warmup); a run that started
    after the cut counts whole; without a line after the cut the last one before it (some warm-up included). Summed over
    runs into the twin's ringmix / ringlanes."""
    groups: dict[tuple, list[tuple[float, int, dict, ZoneStat]]] = defaultdict(list)
    for kind, kv, order in ring_rows:
        gt = num(kv.get("gt"))
        if gt is None or not kv.get("zone"):
            continue
        run, sc = kv.get("run", "-"), kv["_sc"]
        _, sc_z = explicit_twin(sc, kv)
        meta = metas.get((run, kv["zone"]))
        if sc_z is None and meta is None:
            continue
        st = zone_stat(rep, meta, load, run, kv["zone"], sc_z, sc.gen)
        groups[(st.key, kind, run)].append((gt, order, kv, st))
    for (key, kind, run), snaps in groups.items():
        snaps.sort(key=lambda t: (t[0], t[1]))
        st = snaps[0][3]
        if key not in first:
            continue  # no FLOW sample of this twin in the load: no window
        cut = first[key] + rep.warmup_s * load.gps
        last = snaps[-1]
        if last[0] < cut:
            continue  # the whole run in the warm-up
        start = run_start.get(run)
        base = None
        if start is None or start < cut:
            after = [sn for sn in snaps[:-1] if sn[0] >= cut]
            before = [sn for sn in snaps[:-1] if sn[0] < cut]
            base = after[0] if after else (before[-1] if before else None)
        vals = ring_values(kind, last[2])
        if base is not None:
            vals.subtract(ring_values(kind, base[2]))
        vals = Counter({k: v for k, v in vals.items() if v > 0})
        if kind == "RINGMIX":
            st.ringmix.update(vals)
            st.ring_arms = int(last[2]["arms"]) if str(last[2].get("arms", "")).isdigit() else st.ring_arms
        else:
            st.ringlanes.update(vals)


def ring_lanes(bins: Counter) -> list[tuple[float, int]]:
    """RINGLANE car samples per distance clustered into lanes, outer first: (mean distance, car samples). Bins under
    LANE_MIN_SHARE of the total are left out (lane changes between); a gap over LANE_GAP_M starts the next lane."""
    total = sum(bins.values())
    if not total:
        return []
    keep = sorted(((r, c) for r, c in bins.items() if c >= LANE_MIN_SHARE * total), reverse=True)
    lanes: list[list[tuple[float, int]]] = []
    for r, c in keep:
        if lanes and lanes[-1][-1][0] - r <= LANE_GAP_M:
            lanes[-1].append((r, c))
        else:
            lanes.append([(r, c)])
    return [(sum(r * c for r, c in ln) / sum(c for _, c in ln), sum(c for _, c in ln)) for ln in lanes]


def split_retimes(rep: Report) -> None:
    """Re-time (Smart Lanes' tool, `[SQRL] RETIME op=write`): every set with a written twin is split at the write. Its
    twins keep the samples before the first write (the plans as built); the samples from --retime-settle game s after
    the last write (in the same load; any later load counts whole) go to a new set `<pair>+rt` of zones `<id>+rt`, the
    written twin's mode `<ab>+rt`. Samples in between are dropped."""
    by_set: dict[tuple[int, str], list[dict]] = defaultdict(list)
    for w in rep.retimes:
        if w["refused"]:
            rep.notes.append(f"Re-time at node {w['node']}: the game refused the write (probe at=cb success=false): "
                             "not split")
            continue
        zid = w["zid"] or rep.node_zid.get((w["gen"], w["node"]))
        sc = next((x for x in rep.showcases if x.gen == w["gen"]), None)
        z = sc.zones.get(zid) if sc is not None and zid else None
        if z is None:
            rep.notes.append(f"Re-time at node {w['node']}: its twin is unknown (no zid= for that node on a Smart Lanes "
                             "line of the current Showcase run): not split")
            continue
        w["zid"] = zid
        by_set[(z.gen, z.pair)].append(w)
    for (gen, pair), ws in by_set.items():
        sc = next(x for x in rep.showcases if x.gen == gen)
        twins = [z for z in sc.zones.values() if z.pair == pair]
        first, last = min(w["order"] for w in ws), max(w["order"] for w in ws)
        written = {w["zid"] for w in ws}
        # the write's game time: the first FLOW sample of any zone after it in its load
        wl = max(ws, key=lambda w: w["order"])["load"]
        load_ix = wl.index if any(wl is ld for ld in rep.loads) else None
        after = [num(kv.get("gt")) for k, kv, o in wl.events if k == "FLOW" and o > last]
        after = [g for g in after if g is not None]
        after_gt = min(after) if after else None
        gps = wl.gps
        info = {"gen": gen, "pair": pair, "written": sorted(written), "nodes": sorted({w["node"] for w in ws}),
                "writes": len(ws), "gt": after_gt, "load": load_ix, "twins": {}, "between": 0}
        for z in twins:
            st = rep.zones.get(z.key)
            if st is None:
                continue
            before = [s_ for s_ in st.samples if s_.order < first]
            aft: list[Sample] = []
            for s_ in st.samples:
                if s_.order <= last:
                    continue
                if s_.load == load_ix and after_gt is not None and s_.gt < after_gt + rep.retime_settle_s * gps:
                    info["between"] += 1
                    continue
                aft.append(s_)
            info["between"] += sum(1 for s_ in st.samples if first <= s_.order <= last)
            ab_after = z.ab + RT if z.id in written else z.ab
            nz = ScZone(gen, z.id + RT, pair + RT, ab_after, z.kind, z.type, z.x, z.y, z.r, z.match, z.reason, z.towns,
                        z.demand)
            sc.zones[nz.id] = nz
            ns = ZoneStat(nz.key, st.label, st.kind, st.type, ab_after, nz.pair, gen, st.match, st.reason, aft,
                          measure=st.measure, r=st.r, r_measure=st.r_measure, arms=st.arms, demand=st.demand, x=st.x,
                          y=st.y)
            rep.zones[nz.key] = ns
            st.samples = before
            info["twins"][z.ab] = (st, ns, z.id in written)
        rep.rt_sets.append(info)


def gt_after(load: Load, order: int) -> float | None:
    """The game time of a log line: the first FLOW sample of any zone after it in its load (None: none after)."""
    after = [num(kv.get("gt")) for k, kv, o in load.events if k == "FLOW" and o > order]
    after = [g for g in after if g is not None]
    return min(after) if after else None


def split_auto(rep: Report) -> None:
    """Auto timing (`[SQRL] AUTORETIME op=write sent=1`, twin by the write's `zid=` or any Smart Lanes line naming that
    node with one): every set whose sl_auto twin wrote is split. Its twins keep the samples before the first write (the
    plans as built: the auto twin is still the axis plan); the samples from its settled-from time (the first write's game
    time + --auto-settle s, in that load; any later load counts whole) go to a new set `<pair>+as` of zones `<id>+as`,
    the auto twin's mode `sl_auto+as`. Samples in between are dropped. Writes after the settled-from time are counted
    (the timing still moving)."""
    by_set: dict[tuple[int, str], list[dict]] = defaultdict(list)
    unknown = 0
    for w in rep.auto_writes:
        if w["refused"]:
            continue
        zid = w["zid"] or rep.node_zid.get((w["gen"], w["node"]))
        sc = next((x for x in rep.showcases if x.gen == w["gen"]), None)
        z = sc.zones.get(zid) if sc is not None and zid else None
        if z is None or z.ab != AUTO_AB:
            unknown += z is None
            continue
        w["zid"] = zid
        by_set[(z.gen, z.pair)].append(w)
    if unknown and not rep.city_enroll:  # the city run's writes are no twin's (its own section)
        rep.notes.append(f"Auto timing: {unknown} write(s) at nodes no twin of the current Showcase run could be joined to "
                         "(no zid=): not used")
    for (gen, pair), ws in by_set.items():
        sc = next(x for x in rep.showcases if x.gen == gen)
        twins = [z for z in sc.zones.values() if z.pair == pair and not suffix_of(z.id)]
        first = min(ws, key=lambda w: w["order"])
        wl = first["load"]
        load_ix = wl.index if any(wl is ld for ld in rep.loads) else None
        if load_ix is None:
            continue  # its load was left out (--last)
        g0 = gt_after(wl, first["order"])
        settled = g0 + rep.auto_settle_s * wl.gps if g0 is not None else None
        late = 0
        for w in ws:
            if w["load"] is wl:
                gw = gt_after(wl, w["order"])
                late += gw is not None and settled is not None and gw > settled
        info = {"gen": gen, "pair": pair, "zid": first["zid"], "nodes": sorted({w["node"] for w in ws}), "writes": len(ws),
                "late": late, "gt": g0, "settled": settled, "load": wl, "twins": {}, "between": 0,
                "demand": next((z.demand for z in twins), "-")}
        for z in twins:
            st = rep.zones.get(z.key)
            if st is None:
                continue
            before = [s_ for s_ in st.samples if s_.order < first["order"]]
            aft: list[Sample] = []
            for s_ in st.samples:
                if s_.order < first["order"]:
                    continue
                if s_.load == load_ix and (settled is None or s_.gt < settled):
                    info["between"] += 1
                    continue
                aft.append(s_)
            ab_after = z.ab + AS if z.ab == AUTO_AB else z.ab
            nz = ScZone(gen, z.id + AS, pair + AS, ab_after, z.kind, z.type, z.x, z.y, z.r, z.match, z.reason, z.towns,
                        z.demand)
            sc.zones[nz.id] = nz
            ns = ZoneStat(nz.key, st.label, st.kind, st.type, ab_after, nz.pair, gen, st.match, st.reason, aft,
                          measure=st.measure, r=st.r, r_measure=st.r_measure, arms=st.arms, demand=st.demand, x=st.x,
                          y=st.y)
            rep.zones[nz.key] = ns
            st.samples = before
            info["twins"][z.ab] = (st, ns)
        rep.as_sets.append(info)


def whole_map(rep: Report) -> None:
    """Whole-map auto re-time (`AUTORETIME op=enroll_all phase=done`, the last one in the report's loads): every
    enrolled zone (a twin named by an enroll line's `zid=`, else a zone whose centre lies within max(r, 60) m of an
    enroll line's `pos=`; without enroll lines every plain zone) and the map (FLOW_ALL) before the request vs from
    --auto-settle game s after it. Computed before the set splits (whole samples)."""
    done = [e for e in rep.enroll_all if any(e["load"] is ld for ld in rep.loads)]
    if not done:
        return
    e = done[-1]
    ld = e["load"]
    g0 = gt_after(ld, e["order"])
    settled = g0 + rep.auto_settle_s * ld.gps if g0 is not None else None
    ids = {(x["gen"], x["zid"]) for x in rep.enrolled if x["zid"]}
    pts = [(x["x"], x["y"]) for x in rep.enrolled if x["x"] is not None and x["y"] is not None]
    zones: list[tuple[ZoneStat, list[Sample], list[Sample]]] = []
    by_enroll = bool(rep.enrolled)
    for st in rep.zones.values():
        if not st.samples:
            continue
        if by_enroll:
            hit = st.key[0] == "sc" and (st.gen, st.key[2]) in ids
            if not hit and st.x is not None and st.y is not None:
                hit = any(math.hypot(px - st.x, py - st.y) <= max(st.r or 0, 60) for px, py in pts)
        else:
            hit = st.kind in ("plain", "x")
        if not hit:
            continue
        before = [s_ for s_ in st.samples if s_.load == ld.index and s_.order < e["order"]]
        after = [s_ for s_ in st.samples if s_.load > ld.index or (s_.load == ld.index and settled is not None
                                                                     and s_.gt >= settled)]
        zones.append((st, before, after))
    alls_b, alls_a = [], []
    for k, kv, o in ld.events:
        if k != "FLOW_ALL" or num(kv.get("gt")) is None:
            continue
        if o < e["order"]:
            alls_b.append(kv)
        elif settled is not None and num(kv["gt"]) >= settled:
            alls_a.append(kv)
    rep.wm = {"run": e["run"], "lit": e["lit"], "sent": e["sent"], "capped": e["capped"], "gt": g0, "settled": settled,
              "load": ld, "zones": zones, "by_enroll": by_enroll, "all_before": alls_b, "all_after": alls_a,
              "enrolled": len(rep.enrolled)}


def build_pairs(rep: Report) -> None:
    by_pair: dict[tuple[int, str], dict[str, ScZone]] = defaultdict(dict)
    used_gens = {st.gen for st in rep.zones.values() if st.key[0] == "sc"}
    for sc in rep.showcases:
        if sc.gen not in used_gens:
            continue
        for z in sc.zones.values():
            by_pair[(sc.gen, z.pair)][z.ab] = z
    for (gen, pair), twins in sorted(by_pair.items(), key=lambda kv: (kv[0][0], pair_sort(kv[0][1]))):
        if all(base_of(ab) in CITY_ABS for ab in twins):
            continue  # the city run's pairs: its own section (render_city), no game twin
        any_z = next(iter(twins.values()))
        label = pair + rep.gen_label(gen)
        nomatch = [z for z in twins.values() if not z.match]
        if nomatch:
            reasons = sorted({r for z in nomatch for r in (z.reason or "?").split(",") if r})
            rep.excluded.append((label, any_z.kind, any_z.type, f"match=no ({','.join(reasons) or '?'})"))
            continue
        bases = {base_of(k.split("@")[0]) for k in twins}
        # every set needs its game twin; sl only where the run builds sl twins (the light plans A/B builds none)
        run_bases = {base_of(z.ab.split("@")[0]) for sc in rep.showcases if sc.gen == gen for z in sc.zones.values()}
        missing = [ab for ab in ("game", "sl") if ab not in bases and (ab == "game" or ab in run_bases)]
        if missing:
            rep.excluded.append((label, any_z.kind, any_z.type,
                                 f"missing twin: {','.join(missing)} (no zone line: refused or not built)"))
            continue
        for a, b in comparisons_for(twins):
            if a not in twins or b not in twins:
                continue
            if suffix_of(pair) and not (suffix_of(a) or suffix_of(b)):
                continue  # the after window only for the written / auto twin: its siblings are in the set already
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


def comparisons_for(twins: dict) -> list[tuple[str, str]]:
    """COMPARISONS, plus for a re-timed / settled mode `<ab>+rt` / `<ab>+as` every comparison of <ab> with it in <ab>'s
    place."""
    out = list(COMPARISONS)
    for ab in twins:
        if suffix_of(ab):
            base = base_of(ab)
            for a, b in COMPARISONS:
                if a == base:
                    out.append((ab, b))
                elif b == base:
                    out.append((a, ab))
    return out


def comp_rank(c: str) -> tuple:
    """Sort key of a compare text: COMPARISONS order, a re-timed one right after its base."""
    names = [f"{a} vs {b}" for a, b in COMPARISONS]
    base = c
    for sx in SUFFIXES:
        base = base.replace(sx, "")
    return (names.index(base) if base in names else len(names), any(sx in c for sx in SUFFIXES), c)


def pair_sort(p: str) -> tuple:
    m = re.match(r"(?:[a-z]+\d*?)?g(\d+)", p)
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
          min_samples: int = 5, worse_pct: float = 10.0, ignore: list[str] | None = None,
          retime_settle: float = 60.0, auto_settle: float = 2700.0) -> Report:
    rep = Report(warmup_s=warmup, gt_per_s=gt_per_s, min_samples=min_samples, worse_pct=worse_pct,
                 retime_settle_s=retime_settle, auto_settle_s=auto_settle)
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
            return (comp_rank(c), g == "all", "/" not in g, g)
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
    # an after-Re-time window's untouched twins are their set's twins again (counted once, before the write)
    sc_zones = [st for st in rep.zones.values() if st.key[0] == "sc" and st.samples
                and not (suffix_of(st.pair) and not suffix_of(st.ab))]
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


def plan_name(ab: str) -> str:
    base = base_of(ab)
    return PLAN_NAMES.get(base, base) + {RT: " re-timed", AS: " settled", "": ""}[suffix_of(ab)]


def arm_text(stats: list[ZoneStat]) -> str:
    """Mean inbound queue per arm over the twins (q_in; q_arm in logs without it), 'N 3.1, E 0.4, ...'."""
    attr = "q_in" if any(st.q_arm_means("q_in") for st in stats) else "q_arm"
    sums: dict[str, list[float]] = defaultdict(list)
    for st in stats:
        for k, v in st.q_arm_means(attr).items():
            sums[k].append(v)
    return ", ".join(f"{k} {sum(v) / len(v):.1f}" for k, v in sums.items()) or "-"


def plan_verdict(label: str, rows: dict[str, ZoneStat], sets: list[dict[str, ZoneStat]], min_samples: int = 1) -> str:
    """One line: the best plan of a shape (and demand) by thru/min (by km/h when thru is missing), its margin over the
    others, and its per-set wins against each (sets where both twins have >= min_samples samples with cars)."""
    use_thru = all(z.thru_per_min() for z in rows.values())
    def key(z: ZoneStat) -> float:
        return (z.thru_per_min() if use_thru else z.speed_kmh()) or 0.0
    ranked = sorted(rows.items(), key=lambda kv: key(kv[1]), reverse=True)
    best_ab, best = ranked[0]
    metric = "thru/min" if use_thru else "km/h"
    parts = []
    for ab, z in ranked[1:]:
        b, o = key(best), key(z)
        pct = (b - o) / o * 100 if o else None
        dst = (best.standing_pct() or 0) - (z.standing_pct() or 0)
        wins = losses = 0
        for one in sets:
            za, zb = one.get(best_ab), one.get(ab)
            if za is None or zb is None or not (za.usable(min_samples) and zb.usable(min_samples)):
                continue
            va = za.thru_per_min() if use_thru else za.speed_kmh()
            vb = zb.thru_per_min() if use_thru else zb.speed_kmh()
            if va is None or vb is None:
                continue
            wins, losses = wins + (va > vb), losses + (va < vb)
        sets_t = f", {wins}/{wins + losses} sets" if wins + losses else ""
        parts.append(f"{f(pct, 0, True)} % {metric} vs {plan_name(ab)} (standing {f(dst, 0, True)} pp{sets_t})")
    if len(ranked) > 1 and key(best) == key(ranked[1][1]):
        return f"**{label}**: no clear best ({metric} tied)."
    return f"**{label}**: {plan_name(best_ab)} best: " + "; ".join(parts) + "."


def plan_sets(rep: Report) -> tuple[dict[tuple[str, str], list[dict[str, ZoneStat]]], int]:
    """The light plans A/B's matched sets per (kind/type, demand): each set's plans (base mode -> its twin) in the
    window they are compared in: a set whose auto twin settled (split_auto) in its settled window (`<pair>+as`, every
    twin), any other set whole (a re-timed set before its write). Only runs with a plan beyond game / axis (auto or
    classic). Second result: the sets compared in their settled window."""
    excluded = {e[0] for e in rep.excluded}
    out: dict[tuple[str, str], list[dict[str, ZoneStat]]] = defaultdict(list)
    settled = 0
    for sc in rep.showcases:
        pairs: dict[str, dict[str, ZoneStat]] = defaultdict(dict)
        for z in sc.zones.values():
            st = rep.zones.get(z.key)
            if st is None or suffix_of(z.pair) == RT:
                continue
            if base_of(st.ab) in PLAN_ABS and st.match:
                pairs[z.pair][st.ab] = st
        for pair, twins in pairs.items():
            if suffix_of(pair) or pair + rep.gen_label(sc.gen) in excluded:
                continue
            win = pairs.get(pair + AS)
            use = {base_of(ab): st for ab, st in (win or twins).items()}
            use = {ab: st for ab, st in use.items() if st.samples}
            if len(use) < 2 or not ({"sl_classic", AUTO_AB} & set(twins)):
                continue
            settled += win is not None
            any_st = next(iter(use.values()))
            out[(f"{any_st.kind}/{any_st.type}", any_st.demand)].append(use)
    return out, settled


def render_light_plans(rep: Report, out: list[str]) -> None:
    """Light plans A/B: per shape and demand, the game's plan vs Smart Lanes' axis plan vs its auto-timed axis plan (or
    the classic patterns), pooled over the matched sets (sets left out of the pairwise tables are left out here too)."""
    groups, n_settled = plan_sets(rep)
    if not groups:
        return
    present = [ab for ab in PLAN_ABS if any(ab in one for sets in groups.values() for one in sets)]
    out.append("## Light plans: " + " vs ".join(plan_name(ab) for ab in present))
    out.append("")
    words = {"sl_phases": "axis = Smart Lanes' axis plan (`sl_phases`)",
             "sl_auto": "auto = the axis plan with its timing kept adjusted (`sl_auto`)",
             "sl_classic": "classic = its classic patterns (`sl_classic`)"}
    settled_t = (f" A set whose auto twin wrote is compared in its settled window (from its first write + "
                 f"{rep.auto_settle_s:g} game s on, every twin; {n_settled} set{'' if n_settled == 1 else 's'}), any "
                 "other set whole." if AUTO_AB in present else "")
    out.append("Per shape and demand (`demand=` of the zone lines: balanced = every town busy, unbalanced = a small north "
               "and a tiny south town; `-`: none), every matched set's twins pooled (after the warm-up; a re-timed set "
               "only before its write). " + ", ".join(words[ab] for ab in present if ab in words) + "." + settled_t +
               " thru/min = cars through the junction per game minute (higher is better); queue = cars standing >= 5 s "
               "in the measured area; queue per arm = inbound side (`q_in`). Verdict: the best plan by thru/min (km/h "
               "without thru), its margin and its wins per set.")
    out.append("")
    out.append("| shape | demand | plan | sets | samples | thru/min | km/h | standing % | queue | queue per arm (inbound) |")
    out.append("|---|---|---|---|---|---|---|---|---|---|")
    verdicts = []
    def gkey(k: tuple[str, str]) -> tuple:
        return (k[0], DEMANDS.index(k[1]) if k[1] in DEMANDS else 9, k[1])
    for shape, demand in sorted(groups, key=gkey):
        sets = groups[(shape, demand)]
        rows: dict[str, ZoneStat] = {}
        for ab in PLAN_ABS:
            sts = [one[ab] for one in sets if ab in one]
            if not sts:
                continue
            z = pooled(sts)
            rows[ab] = z
            out.append(f"| {shape.split('/', 1)[-1]} | {demand} | {plan_name(ab)} | {len(sts)} | {z.n()} | "
                       f"{f(z.thru_per_min())} | {f(z.speed_kmh())} | {f(z.standing_pct(), 0)} | {f(z.queue_mean())} | "
                       f"{arm_text(sts)} |")
        label = shape.split("/", 1)[-1] + ("" if demand == "-" else f" {demand}")
        verdicts.append(plan_verdict(label, rows, sets, rep.min_samples))
    out.append("")
    for v in verdicts:
        out.append(f"- {v}")
    out.append("")


def ordinal(k: int) -> str:
    return {1: "1st", 2: "2nd", 3: "3rd"}.get(k, f"{k}th")


def mix_text(c: Counter, arms: int) -> str:
    """'1st 31 %, 2nd 40 %, 3rd 22 %, U 7 % (n 1234, none 2 %)': the measured turning mix (shares of the drivers with an
    entry and an exit)."""
    known = sum(v for k, v in c.items() if k.startswith("exit") or k == "uturn")
    if not c.get("n"):
        return "-"
    ks = sorted(int(k[4:]) for k in c if k.startswith("exit"))
    top = max(ks + [arms - 1, 0])
    parts = [f"{ordinal(k)} {c.get(f'exit{k}', 0) / known * 100:.0f} %" for k in range(1, top + 1)] if known else []
    if known:
        parts.append(f"U {c.get('uturn', 0) / known * 100:.0f} %")
    return ", ".join(parts) + f" (n {c['n']}, none {c.get('none', 0) / c['n'] * 100:.0f} %)"


def lane_text(bins: Counter) -> str:
    """'o1 22 % (32.1 m), o2 78 % (28.0 m)': ring lane occupancy, outer lane first (RINGLANE clustered)."""
    lanes = ring_lanes(bins)
    tot = sum(c for _, c in lanes)
    if not tot:
        return "-"
    return ", ".join(f"o{i} {c / tot * 100:.0f} % ({r:.1f} m)" for i, (r, c) in enumerate(lanes, 1))


def mix_check(mix: str, c: Counter) -> str:
    """Whether the measured mix bears out the label: straight = the 2nd exit the most taken, adjacent = 1st + 3rd exits
    more than the 2nd; even: nothing to check. '' when it does (or can't tell)."""
    e1, e2, e3 = c.get("exit1", 0), c.get("exit2", 0), c.get("exit3", 0)
    if not (e1 + e2 + e3):
        return ""
    if mix == "straight" and e2 < max(e1, e3):
        return " (label not borne out: the 2nd exit is not the most taken)"
    if mix == "adjacent" and e1 + e3 <= e2:
        return " (label not borne out: 1st + 3rd exits not above the 2nd)"
    return ""


def ring_groups(rep: Report, gen: int | None = None) -> dict[tuple[str, str], dict[str, list[ZoneStat]]]:
    """Bench Sheet 5's ring twins (zone lines with mix=) per (test kind, mix): mode -> its matched twins (sets left out of
    the pairwise tables are left out here too)."""
    excluded = {e[0] for e in rep.excluded}
    out: dict[tuple[str, str], dict[str, list[ZoneStat]]] = defaultdict(lambda: defaultdict(list))
    for st in rep.zones.values():
        if st.key[0] != "sc" or st.mix == "-" or suffix_of(st.pair) or (gen is not None and st.gen != gen):
            continue
        if not st.match or st.pair + rep.gen_label(st.gen) in excluded:
            continue
        out[(st.kind, st.mix)][st.ab].append(st)
    return out


def ring_verdict(label: str, rows: dict[str, ZoneStat]) -> str:
    """One line per ring and mix: the best mode by thru/min (km/h without thru), then every Smart Lanes mode against game
    and against sl_rturbo (thru/min %, km/h, standing pp)."""
    use_thru = all(z.thru_per_min() for z in rows.values())
    def key(z: ZoneStat) -> float:
        return (z.thru_per_min() if use_thru else z.speed_kmh()) or 0.0
    metric = "thru/min" if use_thru else "km/h"
    ranked = sorted(rows.items(), key=lambda kv: key(kv[1]), reverse=True)
    if not ranked:
        return f"**{label}**: no samples."
    tie = len(ranked) > 1 and key(ranked[0][1]) == key(ranked[1][1])
    head = f"**{label}**: " + ("no clear best" if tie else f"{ranked[0][0]} best") + f" by {metric} ({f(key(ranked[0][1]))})"
    parts = []
    for ab, z in ranked:
        if ab == "game":
            continue
        vs = []
        for base in ("game", "sl_rturbo"):
            b = rows.get(base)
            if b is None or base == ab:
                continue
            o = key(b)
            pct = (key(z) - o) / o * 100 if o else None
            dk = (z.speed_kmh() - b.speed_kmh()) if z.speed_kmh() is not None and b.speed_kmh() is not None else None
            ds = (z.standing_pct() - b.standing_pct()) if z.standing_pct() is not None and b.standing_pct() is not None else None
            vs.append(f"{f(pct, 0, True)} % {metric}, {f(dk, 1, True)} km/h, standing {f(ds, 0, True)} pp vs {base}")
        if vs:
            parts.append(f"{ab}: " + "; ".join(vs))
    return head + (". " + ". ".join(parts) if parts else "") + "."


def grid_windows(rep: Report, st: ZoneStat) -> list[dict]:
    """A twin's recorded samples in GRID_WIN_S game s windows (per load, from its first sample there), in log order:
    {start_min, standing (% of its cars), thru (cars through per game minute; None without thru), samples}."""
    gps = {ld.index: ld.gps for ld in rep.loads}
    first: dict[int, float] = {}
    for s_ in st.samples:
        first[s_.load] = min(first.get(s_.load, s_.gt), s_.gt)
    wins: dict[tuple[int, int], dict] = {}
    for s_ in sorted(st.samples, key=lambda x: x.order):
        g = gps.get(s_.load, 1000.0)
        k = int((s_.gt - first[s_.load]) / g // GRID_WIN_S)
        w = wins.setdefault((s_.load, k), {"start_min": k * GRID_WIN_S / 60, "cars": 0.0, "standing": 0.0, "thru": 0.0,
                                           "thru_s": 0.0, "samples": 0, "order": s_.order})
        w["cars"] += s_.cars
        w["standing"] += s_.standing
        w["samples"] += 1
        if s_.thru is not None and s_.thru_s:
            w["thru"] += s_.thru
            w["thru_s"] += s_.thru_s
    out = []
    for w in sorted(wins.values(), key=lambda x: x["order"]):
        out.append({"start_min": w["start_min"], "samples": w["samples"],
                    "standing": w["standing"] / w["cars"] * 100 if w["cars"] else None,
                    "thru": w["thru"] / w["thru_s"] * 60 if w["thru_s"] else None})
    return out


def gridlock(rep: Report, st: ZoneStat, best: float | None) -> dict:
    """Gridlock of one twin against its set's best window thru/min: the locked windows (standing >= GRID_STANDING % and
    thru/min <= GRID_THRU_FRAC x best), whether the last GRID_LAST windows are all locked (gridlock: the lock lasted to
    the end of the record) and from which window that last locked run started."""
    wins = grid_windows(rep, st)
    lim = best * GRID_THRU_FRAC if best else None

    def locked(w: dict) -> bool:
        return (w["standing"] is not None and w["standing"] >= GRID_STANDING and lim is not None and w["thru"] is not None
                and w["thru"] <= lim)
    flags = [locked(w) for w in wins]
    final = len(flags) >= GRID_LAST and all(flags[-GRID_LAST:])
    onset = None
    if final:
        k = len(flags) - 1
        while k > 0 and flags[k - 1]:
            k -= 1
        onset = wins[k]["start_min"]
    last = wins[-1] if wins else None
    return {"windows": len(wins), "locked": sum(flags), "final": final, "onset": onset,
            "last_standing": last["standing"] if last else None, "last_thru": last["thru"] if last else None, "best": best}


def set_best_thru(rep: Report, st: ZoneStat) -> float | None:
    """The best GRID_WIN_S window thru/min any twin of st's set (same Showcase run and pair) reached."""
    best = None
    for z in rep.zones.values():
        if z.key[0] != "sc" or z.gen != st.gen or z.pair != st.pair:
            continue
        for w in grid_windows(rep, z):
            if w["thru"] is not None and (best is None or w["thru"] > best):
                best = w["thru"]
    return best


def gridlock_text(g: dict) -> str:
    if g["final"]:
        return f"GRIDLOCK from game min {g['onset']:.0f}"
    if g["locked"]:
        return f"no (locked {g['locked']} of {g['windows']} windows, not at the end)"
    return "no"


def ring_use_lines(rep: Report, gen: int | None = None) -> list[str]:
    """Ring lane use (bench Sheet 5): per ring and traffic mix every mode's thru/min, km/h, standing, queue per arm
    (inbound), its ring lane occupancy (RINGLANE, outer lane first) and its measured turning mix (RINGMIX); the RINGMIX
    counts per twin; a verdict line per ring and mix."""
    groups = ring_groups(rep, gen)
    if not groups:
        return []
    out = ["## Ring lane use", ""]
    out.append("Bench sheets 5 and 6 (BENCH.md \"Sheet 5\", \"Sheet 6\"): per ring (test) and traffic mix (`mix=` of the zone lines: even = four "
               "equal towns, straight = the N and S towns large, adjacent = the N and E towns large), every mode's matched "
               "twins pooled over the recorded window (after the warm-up). thru/min = cars through per game minute; queue per "
               "arm = queued cars on the inbound side (`q_in`); lane use = car samples on the ring's edges by lane, outer lane "
               "(o1) first (`RINGLANE`, clustered by distance from the centre); turning mix = arms passed from entry to exit "
               "per driver, each once (`RINGMIX`: 1st exit .. U-turn; none = no entry and exit read).")
    out.append("")
    out.append("| ring | mix | mode | sets | samples | thru/min | km/h | standing % | queue | queue per arm (inbound) | lane use | turning mix |")
    out.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
    order = {ab: i for i, ab in enumerate(AB_ORDER)}
    def gkey(k: tuple[str, str]) -> tuple:
        return (k[0], MIXES.index(k[1]) if k[1] in MIXES else 9, k[1])
    verdicts = []
    grid_rows: list[tuple[str, str, ZoneStat, dict]] = []
    for kind, mix in sorted(groups, key=gkey):
        modes = groups[(kind, mix)]
        rows: dict[str, ZoneStat] = {}
        ring = kind.split(":", 1)[-1]
        for ab in sorted(modes, key=lambda a: (order.get(a, 99), a)):
            sts = modes[ab]
            z = pooled(sts)
            rows[ab] = z
            mixc: Counter = Counter()
            lanes: Counter = Counter()
            for one in sts:
                mixc.update(one.ringmix)
                lanes.update(one.ringlanes)
            arms = max((one.ring_arms for one in sts), default=0)
            out.append(f"| {ring} | {mix} | {ab} | {len(sts)} | {z.n()} | {f(z.thru_per_min())} | {f(z.speed_kmh())} | "
                       f"{f(z.standing_pct(), 0)} | {f(z.queue_mean())} | {arm_text(sts)} | {lane_text(lanes)} | {mix_text(mixc, arms)} |")
        allmix: Counter = Counter()
        for sts in modes.values():
            for one in sts:
                allmix.update(one.ringmix)
        locks = []
        for ab in sorted(modes, key=lambda a: (order.get(a, 99), a)):
            for one in sorted(modes[ab], key=lambda z: pair_sort(z.pair)):
                g = gridlock(rep, one, set_best_thru(rep, one))
                grid_rows.append((ring, mix, one, g))
                if g["final"]:
                    locks.append(f"{ab} ({one.name}) from game min {g['onset']:.0f}")
        lock_text = (" Gridlock: " + "; ".join(locks) + ".") if locks else ""
        verdicts.append(ring_verdict(f"{ring} {mix}", rows) + mix_check(mix, allmix) + lock_text)
    out.append("")
    # gridlock per twin (bench Sheet 6: heavy traffic)
    if grid_rows:
        out.append(f"Gridlock per twin ({GRID_WIN_S / 60:g} game min windows of the recorded samples; locked = standing >= "
                   f"{GRID_STANDING:g} % and thru/min <= {GRID_THRU_FRAC * 100:g} % of the best window of any twin of its set; "
                   f"gridlock = the last {GRID_LAST} windows locked):")
        out.append("")
        out.append("| ring | mix | twin | mode | windows | locked | last window standing % | last window thru/min | set best thru/min | gridlock |")
        out.append("|---|---|---|---|---|---|---|---|---|---|")
        for ring, mix, one, g in grid_rows:
            out.append(f"| {ring} | {mix} | {one.name} | {one.ab} | {g['windows']} | {g['locked']} | {f(g['last_standing'], 0)} | "
                       f"{f(g['last_thru'])} | {f(g['best'])} | {gridlock_text(g)} |")
        out.append("")
    # RINGMIX per twin
    twins = [st for g in groups.values() for sts in g.values() for st in sts if st.ringmix]
    if twins:
        top = max([st.ring_arms - 1 for st in twins] + [3])
        out.append("Turning mix per twin (`RINGMIX`, recorded window; drivers counted once):")
        out.append("")
        out.append("| ring | mix | twin | mode | n | " + " | ".join(ordinal(k) for k in range(1, top + 1)) + " | U-turn | none |")
        out.append("|---|---|---|---|---|" + "---|" * top + "---|---|")
        for st in sorted(twins, key=lambda z: (z.kind, MIXES.index(z.mix) if z.mix in MIXES else 9, pair_sort(z.pair), z.name)):
            c = st.ringmix
            cells = " | ".join(str(c.get(f"exit{k}", 0)) for k in range(1, top + 1))
            out.append(f"| {st.kind.split(':', 1)[-1]} | {st.mix} | {st.name} | {st.ab} | {c.get('n', 0)} | {cells} | "
                       f"{c.get('uturn', 0)} | {c.get('none', 0)} |")
        out.append("")
    for v in verdicts:
        out.append(f"- {v}")
    out.append("")
    return out


def render_ring_use(rep: Report, out: list[str]) -> None:
    out.extend(ring_use_lines(rep))


def game_min(load: Load, gt: float | None) -> float | None:
    return (gt - load.first_gt) / load.gps / 60 if gt is not None and load.first_gt is not None else None


def render_auto(rep: Report) -> list[str]:
    """Auto timing: each split set's twins before the auto twin's first write (as built) and from its settled-from time
    on, the auto twin relative to its set's game and axis twins in the same window."""
    out: list[str] = []
    if not rep.as_sets:
        return out
    out.append("## Auto timing: as built / settled")
    out.append("")
    out.append("Each set whose auto twin (`sl_auto`) wrote (`[SQRL] AUTORETIME op=write sent=1`, twin by `zid=`), split at "
               f"its first write: before = as built (also in every table above), settled = from the first write + "
               f"{rep.auto_settle_s:g} game s (--auto-settle) on (set `<pair>+as`). settled from = game min since the "
               "load's first sample; writes = its writes (after = written after the settled-from time: the timing was "
               "still moving). vs game / vs axis = the auto twin minus that twin in the same window.")
    out.append("")
    out.append("| set | demand | auto twin | settled from (game min) | writes (after) | samples before / settled | "
               "thru/min before / settled | km/h before / settled | standing % before / settled | "
               "vs game thru/min before / settled | vs axis thru/min before / settled |")
    out.append("|---|---|---|---|---|---|---|---|---|---|---|")
    lines = []
    def d(a: ZoneStat | None, b: ZoneStat | None, attr: str) -> float | None:
        if a is None or b is None:
            return None
        x, y = getattr(a, attr)(), getattr(b, attr)()
        return x - y if x is not None and y is not None else None
    for info in sorted(rep.as_sets, key=lambda i: (i["gen"], pair_sort(i["pair"]))):
        label = info["pair"] + rep.gen_label(info["gen"])
        tw = info["twins"]
        if AUTO_AB not in tw:
            continue
        ab_, aa = tw[AUTO_AB]
        gb, ga = tw.get("game", (None, None))
        xb, xa = tw.get("sl_phases", (None, None))
        sf = game_min(info["load"], info["settled"])
        out.append(f"| {label} | {info['demand']} | {ab_.name} | {f(sf, 1)} | {info['writes']} ({info['late']}) | "
                   f"{ab_.n()} / {aa.n()} | {f(ab_.thru_per_min())} / {f(aa.thru_per_min())} | "
                   f"{f(ab_.speed_kmh())} / {f(aa.speed_kmh())} | {f(ab_.standing_pct(), 0)} / {f(aa.standing_pct(), 0)} | "
                   f"{f(d(ab_, gb, 'thru_per_min'), 1, True)} / {f(d(aa, ga, 'thru_per_min'), 1, True)} | "
                   f"{f(d(ab_, xb, 'thru_per_min'), 1, True)} / {f(d(aa, xa, 'thru_per_min'), 1, True)} |")
        b0, a0 = d(ab_, xb, "thru_per_min"), d(aa, xa, "thru_per_min")
        if b0 is not None and a0 is not None:
            ch = a0 - b0
            word = "gained" if ch > 0 else ("lost" if ch < 0 else "unchanged")
            lines.append(f"**{label} {ab_.name}** ({info['demand']}, {ab_.type}): auto vs axis {word} {f(ch, 1, True)} "
                         f"thru/min from as built to settled ({f(b0, 1, True)} -> {f(a0, 1, True)}; {ab_.n()} / {aa.n()} "
                         "samples)" + (" (too few settled samples)" if aa.n() < rep.min_samples else "")
                         + (f"; {info['late']} write(s) after the settled-from time" if info["late"] else "") + ".")
        if info["settled"] is None:
            lines.append(f"{label}: no FLOW sample after the first write: nothing settled.")
    out.append("")
    for info in rep.as_sets:
        if info["between"]:
            lines.append(f"{info['pair']}{rep.gen_label(info['gen'])}: {info['between']} sample(s) between the first write "
                         f"and the settled-from time dropped; node(s) {', '.join(info['nodes'])}.")
    for ln in lines:
        out.append(f"- {ln}")
    if lines:
        out.append("")
    return out


def render_whole_map(rep: Report) -> list[str]:
    """Whole-map auto re-time: the enrolled zones pooled per kind / type and mode, and the map (FLOW_ALL), before the
    enroll_all request vs from --auto-settle game s after it."""
    out: list[str] = []
    wm = rep.wm
    if wm is None:
        return out
    ld = wm["load"]
    out.append("## Whole-map auto re-time: before / after")
    out.append("")
    which = (f"{wm['enrolled']} junction(s) named by `AUTORETIME op=enroll src=all` lines (twin by `zid=`, else the zone "
             "within max(r, 60) m of its `pos=`)" if wm["by_enroll"] else
             "no enroll lines in the log: every plain zone counted as lit")
    out.append(f"Run {wm['run']} (`AUTORETIME op=enroll_all phase=done`: lit={wm['lit']} sent={wm['sent']} "
               f"capped={wm['capped']}) at game min {f(game_min(ld, wm['gt']), 1)} of load {ld.index}; {which}. Before = "
               f"every sample before the request (after the warm-up), after = from {rep.auto_settle_s:g} game s after it "
               f"(game min {f(game_min(ld, wm['settled']), 1)}; --auto-settle) on. The traffic itself may drift between "
               "the windows: compare with the game twins where there are any.")
    out.append("")
    if not wm["zones"]:
        out.append("No measured zone is enrolled.")
        out.append("")
    else:
        out.append("| kind | type | ab | zones | samples before / after | thru/min before / after | km/h before / after | "
                   "standing % before / after | queue before / after |")
        out.append("|---|---|---|---|---|---|---|---|---|")
        groups: dict[tuple[str, str, str], list[tuple[ZoneStat, list[Sample], list[Sample]]]] = defaultdict(list)
        for st, b, a in wm["zones"]:
            groups[(st.kind, st.type, st.ab)].append((st, b, a))
        for k in sorted(groups, key=lambda k: (k[0], k[1], AB_ORDER.index(k[2]) if k[2] in AB_ORDER else 99, k[2])):
            rows = groups[k]
            zb = ZoneStat(("pool",), "", k[0], k[1], k[2], samples=[s_ for _, b, _ in rows for s_ in b])
            za = ZoneStat(("pool",), "", k[0], k[1], k[2], samples=[s_ for _, _, a in rows for s_ in a])
            out.append(f"| {k[0]} | {k[1]} | {k[2]} | {len(rows)} | {zb.n()} / {za.n()} | {f(zb.thru_per_min())} / "
                       f"{f(za.thru_per_min())} | {f(zb.speed_kmh())} / {f(za.speed_kmh())} | {f(zb.standing_pct(), 0)} / "
                       f"{f(za.standing_pct(), 0)} | {f(zb.queue_mean())} / {f(za.queue_mean())} |")
        out.append("")
    def mapwide(rows: list[dict]) -> tuple[float | None, float | None]:
        w = [(num(kv.get("v_mean")), num(kv.get("sampled")) or 0) for kv in rows]
        w = [(v, c) for v, c in w if v is not None and c > 0]
        cars = sum(num(kv.get("sampled")) or 0 for kv in rows)
        st = sum(num(kv.get("standing")) or 0 for kv in rows)
        spd = sum(v * c for v, c in w) / sum(c for _, c in w) * 3.6 if w else None
        return spd, (st / cars * 100 if cars else None)
    if wm["all_before"] or wm["all_after"]:
        kb, sb = mapwide(wm["all_before"])
        ka, sa = mapwide(wm["all_after"])
        out.append(f"Map-wide (FLOW_ALL): {len(wm['all_before'])} / {len(wm['all_after'])} samples, km/h {f(kb)} / {f(ka)}, "
                   f"standing % {f(sb, 0)} / {f(sa, 0)} (before / after).")
        out.append("")
    return out


def gt_of(load: Load, order: int, cache: dict) -> float | None:
    """The game time of a log line: the first FLOW / FLOW_ALL sample after it in its load (bisect over a cached list)."""
    lst = cache.get(load.index)
    if lst is None:
        lst = sorted((o, num(kv.get("gt"))) for k, kv, o in load.events if k in ("FLOW", "FLOW_ALL") and num(kv.get("gt")) is not None)
        cache[load.index] = lst
    i = bisect.bisect_right(lst, (order, math.inf))
    return lst[i][1] if i < len(lst) else None


def city_of(cities: list[dict], x: float | None, y: float | None) -> dict | None:
    """The city whose grid (half + 50 m) holds (x, y)."""
    if x is None or y is None:
        return None
    for c in cities:
        cx, cy, h = num(c.get("x")), num(c.get("y")), (num(c.get("half")) or 400) + 50
        if cx is not None and cy is not None and abs(x - cx) <= h and abs(y - cy) <= h:
            return c
    return None


def render_city(rep: Report) -> list[str]:
    """The city runs (BENCH.md "City lights at scale"): one part per run (`CITY_ENROLL`; render_city_run), then, when runs
    with both roles (role_swap=0 and 1) are given, the swapped-roles summary (render_city_swap)."""
    runs = [e for e in rep.city_enroll if any(e["_load"] is x for x in rep.loads)]
    if not runs:
        return []
    out = ["## Auto lights at scale", ""]
    results = []
    for i, e in enumerate(runs):
        prev = runs[i - 1] if i else None
        nxt = runs[i + 1] if i + 1 < len(runs) else None
        lines, res = render_city_run(rep, e, prev, nxt, len(runs) > 1)
        out += lines
        results.append(res)
    out += render_city_swap(results)
    return out


def city_run_label(e: dict) -> str:
    """'layout hourglass, Busy, baseline 30 game min, roles swapped' from a CITY_ENROLL line (v1 lines: plain, as usual)."""
    parts = [f"layout {e.get('layout', 'plain')}"]
    if e.get("busy") == "1":
        parts.append("Busy")
    parts.append(f"baseline {f((num(e.get('baseline_s')) or 0) / 60, 0)} game min")
    parts.append("roles swapped" if e.get("role_swap") == "1" else "roles as usual")
    return ", ".join(parts)


def render_city_run(rep: Report, e: dict, prev: dict | None, nxt: dict | None, several: bool) -> tuple[list[str], dict]:
    """One city run: Smart Lanes' cost (SQPERF ctx=bg), its snapshots, writes and fits, every city's km/h / standing / queue
    before the enroll vs from --auto-settle after it, each pair's baseline gap, the controls, the pass criteria. A run spans
    its CITY lines (after the previous run's enroll) to the next run's first CITY line."""
    ld: Load = e["_load"]
    eo = e["_order"]
    prev_o = prev["_order"] if prev is not None and prev["_load"] is ld else 0
    later = [c["_order"] for c in rep.cities if c["_load"] is ld and c["_order"] > eo]
    end_o = min(later) if later else (nxt["_order"] if nxt is not None and nxt["_load"] is ld else math.inf)
    cache: dict = {}
    g0 = gt_of(ld, eo, cache)
    gps = ld.gps
    settled = g0 + rep.auto_settle_s * gps if g0 is not None else None
    cities = [c for c in rep.cities if c["_load"] is ld and prev_o < c["_order"] < eo]
    start_o = min((c["_order"] for c in cities), default=prev_o)
    by_id = {c.get("id"): c for c in cities}
    gts = [num(kv.get("gt")) for k, kv, o in ld.events if k in ("FLOW", "FLOW_ALL") and o < end_o and num(kv.get("gt")) is not None]
    end_gt = max(gts) if gts else None
    after_min = (end_gt - g0) / gps / 60 if end_gt is not None and g0 is not None else None

    def within(o: int) -> bool:
        return eo < o < end_o
    out: list[str] = []
    if several:
        out += [f"### City run {e.get('run', '-')} ({city_run_label(e)})", ""]
    out.append(f"City run {e.get('run', '-')} (`[SQST] CITY_ENROLL op={e.get('op', '-')}`: {e.get('cities', '?')} auto cities, "
               f"{e.get('nodes', '?')} junctions asked for in {e.get('events', '?')} event(s)) at game min {f(game_min(ld, g0), 1)} "
               f"of load {ld.index}; {f(after_min, 1)} game min recorded after it. Before = every sample before the enroll (after "
               f"the warm-up), after = from {rep.auto_settle_s:g} game s after it (--auto-settle) on.")
    out.append("")
    out.append(f"Options: {city_run_label(e)} (`CITY_ENROLL layout= busy= role_swap= baseline_s=`; a v1 line has none: plain).")
    gaps = [g for g in rep.city_gaps if g["_load"] is ld and start_o <= g["_order"] < end_o]
    if gaps or e.get("layout", "plain") != "plain":
        kinds = Counter()
        for c in cities:
            kinds["found4"] += int(num(c.get("found4")) or 0)
            kinds["found3"] += int(num(c.get("found3")) or 0)
            kinds["lit4"] += int(num(c.get("lit4")) or 0)
            kinds["lit3"] += int(num(c.get("lit3")) or 0)
        g_build = sum(int(num(g.get("gap_streets")) or 0) for g in gaps if g.get("at") == "build")
        g_removed = sum(int(num(g.get("removed")) or 0) for g in gaps if g.get("at") == "build")
        g_end = [g for g in gaps if g.get("at") == "end"]
        end_txt = (f"{sum(int(num(g.get('gap_streets')) or 0) for g in g_end)} at the end ({len(g_end)} cities checked)"
                   if g_end else "not checked at the end")
        pops = [num(c.get("pop")) for c in cities if num(c.get("pop")) is not None]
        out.append(f"Layout: {kinds['found4']} 4-way and {kinds['found3']} T crossings found, {kinds['lit4']} / {kinds['lit3']} lit; "
                   f"streets in the gaps: {g_build} after the lock ({g_removed} removed), {end_txt}"
                   + (f"; people per city {min(pops):.0f}-{max(pops):.0f}" if pops else "") + ".")
    out.append("")
    # --- Smart Lanes' cost: SQPERF ctx=bg (the background runtime that measures and re-times the enrolled junctions)
    perf = [p for p in rep.sqperf if p["load"] is ld and p["ctx"] == "bg"]
    speed = None
    for o, sp in rep.bench_speeds:
        if o < eo:
            speed = sp

    def cost(lines: list[dict]) -> tuple[float | None, float | None, int, int]:
        """(mean ms per frame, max ms, windows, windows with a frame over CITY_FRAME_MS) over SQPERF window lines."""
        ms, frames, mx, over = 0.0, 0, None, 0
        for p in lines:
            secs = p["sections"]
            if not secs:
                continue
            ms += sum(v[1] for v in secs.values())
            frames += max(v[0] for v in secs.values())
            m = max(v[2] for v in secs.values())
            mx = m if mx is None else max(mx, m)
            over += m > CITY_FRAME_MS
        return (ms / frames if frames else None), mx, len([p for p in lines if p["sections"]]), over
    win_b = [p for p in perf if p["kind"] == "window" and start_o < p["order"] < eo]
    win_a = [p for p in perf if p["kind"] == "window" and within(p["order"])]
    slow_a = [p for p in perf if p["kind"] == "slow" and within(p["order"])]
    mb, xb, nb, _ = cost(win_b)
    ma, xa, na, over_a = cost(win_a)
    slow_max = max((p["max"] for p in slow_a), default=None)
    sections = sorted({s for p in win_a for s in p["sections"]})
    out.append(f"Smart Lanes' cost (`[SQPERF] mod=square_smart_lanes ctx=bg`, sections {', '.join(sections) or '-'}; mean = "
               f"the sections' ms over the frames (the most calls of one section) per 30 s window): before {nb} window(s), mean "
               f"{f(mb, 3)} ms/frame, max {f(xb, 1)} ms; after {na} window(s), mean {f(ma, 3)} ms/frame, max {f(xa, 1)} ms, "
               f"{over_a} window(s) with a frame over {CITY_FRAME_MS:g} ms; {len(slow_a)} slow line(s) after the enroll"
               f"{f' (max {slow_max:.1f} ms)' if slow_max is not None else ''}; recorded at {speed or '?'}x.")
    # the snapshots (step B v4: every 120 game s): a src=scan snapshot reads the whole person list in one engine call. Smart
    # Lanes with the wall clock (`AUTORETIME op=config clock=wall`) logs that call's own time (fetch_ms): a person-list spike
    # is a scan snapshot whose fetch_ms is over the limit. Before (no clock=wall), max_frame_ms was os.clock: CPU time over
    # all threads on macOS, 3-6x the frame's wall time, so it is shown but never counted as a spike; the SQPERF windows (wall
    # clock) stay the frame criterion
    clocks = [c for c in rep.auto_clocks if c["load"] is ld and c["order"] < end_o]
    wall = bool(clocks) and clocks[-1]["clock"] == "wall"
    snaps = [s for s in rep.auto_snaps if s["load"] is ld and within(s["order"])]

    def spike(s: dict) -> bool:
        if s["src"] != "scan":
            return False
        if s.get("fetch") is not None:
            return s["fetch"] > CITY_FRAME_MS
        return wall and (s["max"] or 0) > CITY_FRAME_MS
    scan_spikes = [s for s in snaps if spike(s)]
    spike_wins, other_wins, other_max = 0, 0, None
    prev_w = eo
    for p in win_a:
        m = max((v[2] for v in p["sections"].values()), default=None)
        if m is not None and m > CITY_FRAME_MS:
            if any(prev_w < s["order"] < p["order"] for s in scan_spikes):
                spike_wins += 1
            else:
                other_wins += 1
                other_max = m if other_max is None else max(other_max, m)
        elif m is not None:
            other_max = m if other_max is None else max(other_max, m)
        prev_w = p["order"]
    if snaps:
        srcs = Counter(s["src"] for s in snaps)
        smax = max((s["max"] for s in snaps if s["max"] is not None), default=None)
        spike_val = [s["fetch"] if s.get("fetch") is not None else s["max"] for s in scan_spikes]
        spike_max = max((v for v in spike_val if v is not None), default=None)
        fetches = [s["fetch"] for s in snaps if s.get("fetch") is not None]
        clock_txt = "" if wall else " (os.clock: CPU time over all threads, inflated 3-6x on macOS; not counted as frame spikes)"
        fetch_txt = (f"person-list fetch (fetch_ms) mean {sum(fetches) / len(fetches):.2f} ms, max {max(fetches):.2f} ms over "
                     f"{len(fetches)} snapshot(s)" if fetches else "fetch_ms not logged (an older Smart Lanes)")
        rule = "fetch_ms" if fetches else "a frame"
        out.append("")
        out.append(f"Snapshots (`AUTORETIME op=snapshot`) after the enroll: {len(snaps)} ("
                   + ", ".join(f"src={k} {v}" for k, v in sorted(srcs.items())) + f"), watched up to "
                   f"{max((int(s['n'] or 0) for s in snaps), default=0)}, busy {f(sum(s['busy'] or 0 for s in snaps) / len(snaps), 1)} ms "
                   f"each on average, longest frame {f(smax, 2)} ms{clock_txt}; {fetch_txt}; person-list spikes (src=scan, "
                   f"{rule} over {CITY_FRAME_MS:g} ms, once per snapshot): {len(scan_spikes)}"
                   f"{f' (max {spike_max:.1f} ms)' if spike_max is not None else ''}.")
    out.append("")
    # --- enrolled, writes, fits
    enrolled = {x["node"]: x for x in rep.auto_enrolls if x["load"] is ld and within(x["order"])}
    n_enr = len(enrolled) or int(num(e.get("nodes")) or 0)
    writes = [w for w in rep.auto_writes if w["load"] is ld and within(w["order"]) and not w["refused"]]
    refused = sum(1 for w in rep.auto_writes if w["load"] is ld and within(w["order"]) and w["refused"])
    written = {w["node"] for w in writes}
    per_min = len(writes) / after_min if after_min else None
    out.append(f"Writes: {len(writes)} (refused {refused}) after the enroll, {f(per_min, 2)} per game minute; {len(written)} of "
               f"{n_enr} enrolled junctions written at least once ({len(enrolled)} `AUTORETIME op=enroll` lines).")
    bins: Counter = Counter()
    for w in writes:
        gw = gt_of(ld, w["order"], cache)
        if gw is not None and g0 is not None:
            bins[int((gw - g0) / gps // 600)] += 1
    if bins:
        out.append("")
        out.append("| game min after the enroll | " + " | ".join(f"{k * 10}-{k * 10 + 10}" for k in range(max(bins) + 1)) + " |")
        out.append("|---|" + "---|" * (max(bins) + 1))
        out.append("| writes | " + " | ".join(str(bins.get(k, 0)) for k in range(max(bins) + 1)) + " |")
    plans = [p for p in rep.auto_plans if p["load"] is ld and within(p["order"])]
    results = Counter(p["result"] for p in plans)
    first_fit: dict[str, float] = {}
    for p in plans:
        if p["result"] == "fits" and p["node"] not in first_fit:
            gp = gt_of(ld, p["order"], cache)
            if gp is not None and g0 is not None:
                first_fit[p["node"]] = (gp - g0) / gps / 60
    fit_txt = []
    times = sorted(first_fit.values())
    for share in CITY_FIT_SHARES:
        need = math.ceil(share * n_enr) if n_enr else 0
        fit_txt.append(f"{share * 100:.0f} %: " + (f"game min {times[need - 1]:.1f}" if need and len(times) >= need else "not reached"))
    out.append("")
    out.append(f"Checks (`AUTORETIME op=plan`): {len(plans)} after the enroll ("
               + (", ".join(f"{k} {v}" for k, v in sorted(results.items())) or "none") + f"); {len(first_fit)} of {n_enr} junctions "
               f"reported fits at least once; first fits reached by {'; '.join(fit_txt)} (game min after the enroll).")
    out.append("")
    # --- per city (this run's zones: the showcase current at its enroll)
    gen = e.get("_gen")
    zs = {st.key[2]: st for st in rep.zones.values()
          if st.key[0] == "sc" and st.ab in CITY_ABS and (gen is None or st.gen == gen)}
    if zs:
        out.append("| city | role | crossings found / lit before / forced | enrolled | written | samples before / after | "
                   "km/h before / after | change | standing % before / after | queue before / after |")
        out.append("|---|---|---|---|---|---|---|---|---|---|")
    rows: dict[str, dict] = {}
    for zid in sorted(zs, key=lambda z: (pair_sort(zs[z].pair), zs[z].ab)):
        st = zs[zid]
        before = [s_ for s_ in st.samples if s_.load == ld.index and start_o < s_.order < eo]
        after = [s_ for s_ in st.samples
                 if (s_.load > ld.index and end_o == math.inf)
                 or (s_.load == ld.index and settled is not None and s_.gt >= settled and eo < s_.order < end_o)]
        zb = ZoneStat(("pool",), "", st.kind, st.type, st.ab, samples=before)
        za = ZoneStat(("pool",), "", st.kind, st.type, st.ab, samples=after)
        c = by_id.get(zid, {})
        n_e = sum(1 for x in enrolled.values() if city_of([c], x["x"], x["y"]) is not None) if c else 0
        n_w = 0
        for node in written:
            w = next(w for w in writes if w["node"] == node)
            px, _, py = (w.get("pos") or "").partition(",")
            if c and city_of([c], num(px), num(py)) is not None:
                n_w += 1
        kb, ka = zb.speed_kmh(), za.speed_kmh()
        ch = (ka - kb) / kb * 100 if kb and ka is not None else None
        rows[zid] = {"st": st, "role": "auto" if st.ab == "city_auto" else "control", "change": ch, "kb": kb, "ka": ka,
                     "sb": zb.standing_pct(), "sa": za.standing_pct(), "n_after": za.n(), "qb": zb.queue_mean(),
                     "x": num(c.get("x")) if c else st.x, "y": num(c.get("y")) if c else st.y}
        out.append(f"| {zid} | {rows[zid]['role']} | {c.get('found', '?')} / {c.get('lit_before', '?')} / {c.get('forced', '?')} | "
                   f"{n_e} | {n_w} | {zb.n()} / {za.n()} | {f(kb)} / {f(ka)} | {f(ch, 0, True)} % | {f(zb.standing_pct(), 0)} / "
                   f"{f(za.standing_pct(), 0)} | {f(zb.queue_mean())} / {f(za.queue_mean())} |")
    if zs:
        out.append("")
    # map-wide
    alls_b = [kv for k, kv, o in ld.events if k == "FLOW_ALL" and start_o < o < eo and num(kv.get("gt")) is not None]
    alls_a = [kv for k, kv, o in ld.events if k == "FLOW_ALL" and within(o) and settled is not None and num(kv.get("gt")) >= settled]

    def mapwide(rows_: list[dict]) -> tuple[float | None, float | None]:
        w = [(num(kv.get("v_mean")), num(kv.get("sampled")) or 0) for kv in rows_]
        w = [(v, c_) for v, c_ in w if v is not None and c_ > 0]
        cars = sum(num(kv.get("sampled")) or 0 for kv in rows_)
        stn = sum(num(kv.get("standing")) or 0 for kv in rows_)
        return (sum(v * c_ for v, c_ in w) / sum(c_ for _, c_ in w) * 3.6 if w else None), (stn / cars * 100 if cars else None)
    kb_, sb_ = mapwide(alls_b)
    ka_, sa_ = mapwide(alls_a)
    out.append(f"Map-wide (FLOW_ALL): {len(alls_b)} / {len(alls_a)} samples, km/h {f(kb_)} / {f(ka_)}, standing % {f(sb_, 0)} / "
               f"{f(sa_, 0)} (before / after).")
    # each pair at baseline (the same layout, so any gap is the pair's own noise) and its auto minus control change
    pairs: dict[str, dict] = {}
    for zid, r in rows.items():
        if r["role"] != "auto":
            continue
        ctl_id, ctl = next(((z2, r2) for z2, r2 in rows.items() if r2["role"] == "control" and r2["st"].pair == r["st"].pair),
                           (None, None))
        if ctl is None:
            continue
        gap = (r["kb"] - ctl["kb"]) / ctl["kb"] * 100 if r["kb"] is not None and ctl["kb"] else None
        did = r["change"] - ctl["change"] if r["change"] is not None and ctl["change"] is not None else None
        pairs[r["st"].pair] = {"auto": zid, "control": ctl_id, "gap": gap, "did": did, "kb": (r["kb"], ctl["kb"]),
                               "qb": (r["qb"], ctl["qb"]), "auto_at": (r["x"], r["y"])}
    if pairs:
        out.append("")
        out.append("Pairs at baseline (before the enroll; the same layout, so a gap is the pair's own noise):")
        out.append("")
        out.append("| pair | auto / control | km/h before auto / control | gap | queue before auto / control | auto minus control (pp) |")
        out.append("|---|---|---|---|---|---|")
        for pair in sorted(pairs, key=pair_sort):
            pr = pairs[pair]
            out.append(f"| {pair} | {pr['auto']} / {pr['control']} | {f(pr['kb'][0])} / {f(pr['kb'][1])} | {f(pr['gap'], 0, True)} % | "
                       f"{f(pr['qb'][0])} / {f(pr['qb'][1])} | {f(pr['did'], 1, True)} |")
        unequal = [f"{p_} ({pairs[p_]['gap']:+.0f} %)" for p_ in sorted(pairs, key=pair_sort)
                   if pairs[p_]["gap"] is not None and abs(pairs[p_]["gap"]) > CITY_PAIR_GAP_PCT]
        if unequal:
            out.append("")
            out.append(f"WARNING: pairs too unequal at baseline (km/h differs by more than {CITY_PAIR_GAP_PCT:g} %): "
                       + ", ".join(unequal) + ". A run with Swap roles (same seed) cancels it: give both logs (make flow LOG='<session 1> <session 2>').")
    did = [f"{pr['auto']} {pr['did']:+.1f} pp vs {pr['control']}" for pair, pr in sorted(pairs.items(), key=lambda x: pair_sort(x[0]))
           if pr["did"] is not None]
    if did:
        out.append("")
        out.append("Auto city change minus its control's (km/h %, the drift cancels): " + "; ".join(did) + ".")
    out.append("")
    # --- pass criteria
    out.append("Pass criteria:")
    if ma is None and slow_max is None:
        out.append(f"- No Smart Lanes frame over {CITY_FRAME_MS:g} ms: UNKNOWN (no SQPERF ctx=bg window lines after the enroll: turn "
                   "Smart Lanes' Debug: performance log On, or enable DEV SQPERF: all mods).")
    else:
        worst = max(x for x in (xa, slow_max) if x is not None)
        ok_f = worst <= CITY_FRAME_MS
        out.append(f"- No Smart Lanes frame over {CITY_FRAME_MS:g} ms: {'PASS' if ok_f else 'FAIL'} (worst {worst:.1f} ms; {over_a} "
                   f"window(s) over: {spike_wins} with a person-list snapshot spike, {other_wins} other; {len(slow_a)} slow "
                   f"line(s)).")
        if spike_wins:
            ok_o = other_wins == 0 and (other_max is None or other_max <= CITY_FRAME_MS)
            out.append(f"  - Without the person-list spikes (once per snapshot, every 120 game s): {'PASS' if ok_o else 'FAIL'} "
                       f"(worst other window {f(other_max, 1)} ms).")
    if ma is None:
        out.append(f"- Mean cost under {CITY_MEAN_MS:g} ms/frame at 4x: UNKNOWN (no window lines).")
    else:
        note = "" if speed in (None, 4) else f" (recorded at {speed}x, not 4x: the frames carry less simulation each)"
        out.append(f"- Mean cost under {CITY_MEAN_MS:g} ms/frame at 4x: {'PASS' if ma < CITY_MEAN_MS else 'FAIL'} ({ma:.3f} ms/frame){note}.")
    autos = {z: r for z, r in rows.items() if r["role"] == "auto"}
    changes = sorted((r["change"], z) for z, r in autos.items() if r["change"] is not None)
    worse = [f"{z} {c:+.0f} %" for c, z in changes if c < -CITY_WORSE_PCT]
    unknown = [z for z, r in autos.items() if r["change"] is None or r["n_after"] < rep.min_samples]
    if not autos:
        out.append(f"- No city worse than its baseline by more than {CITY_WORSE_PCT:g} %: UNKNOWN (no city zones in the traffic log).")
    else:
        detail = "; ".join(worse) if worse else (f"worst {changes[0][1]} {changes[0][0]:+.0f} %" if changes else "-")
        out.append(f"- No city worse than its baseline by more than {CITY_WORSE_PCT:g} % (km/h): {'FAIL' if worse else 'PASS'} "
                   f"({detail}){'; too few samples after: ' + ', '.join(unknown) if unknown else ''}.")
    out.append("")
    return out, {"run": e.get("run", "-"), "swap": e.get("role_swap", "0"), "label": city_run_label(e),
                 "layout": e.get("layout", "plain"), "busy": e.get("busy", "0"), "pairs": pairs}


def render_city_swap(results: list[dict]) -> list[str]:
    """Runs with swapped roles (role_swap=0 and 1, same layout): per pair, auto minus control in each run and their mean. A
    pair's own difference (one city of it simply faster) enters the two runs with opposite signs and cancels in the mean;
    what stays is the automatic timing's effect. The last run of each role is used."""
    plain = [r for r in results if r["swap"] != "1"]
    swapped = [r for r in results if r["swap"] == "1"]
    if not plain or not swapped:
        return []
    a, b = plain[-1], swapped[-1]
    out = [f"### Swapped roles: runs {a['run']} and {b['run']}", ""]
    if (a["layout"], a["busy"]) != (b["layout"], b["busy"]):
        out.append(f"WARNING: the two runs differ in more than the roles ({a['label']} vs {b['label']}): the mean mixes them.")
        out.append("")
    out.append("Each pair's auto minus control change (km/h, percentage points) in both runs; the mean cancels the pair's own "
               "difference (the cities swap roles), the baseline gaps show how large that difference was.")
    out.append("")
    out.append(f"| pair | {a['run']} auto minus control | {b['run']} auto minus control | mean | baseline gap {a['run']} / {b['run']} |")
    out.append("|---|---|---|---|---|")
    means = []
    for pair in sorted(set(a["pairs"]) | set(b["pairs"]), key=pair_sort):
        pa, pb = a["pairs"].get(pair, {}), b["pairs"].get(pair, {})
        da, db = pa.get("did"), pb.get("did")
        m = (da + db) / 2 if da is not None and db is not None else None
        if m is not None:
            means.append(m)
        out.append(f"| {pair} | {f(da, 1, True)} | {f(db, 1, True)} | {f(m, 1, True)} | {f(pa.get('gap'), 0, True)} % / "
                   f"{f(pb.get('gap'), 0, True)} % |")
    out.append("")
    if means:
        out.append(f"Swapped-roles effect of the automatic timing (km/h, auto minus control, mean over {len(means)} pair(s)): "
                   f"{sum(means) / len(means):+.1f} pp (spread {min(means):+.1f} to {max(means):+.1f}).")
        out.append("")
    return out


def render_retime(rep: Report, out: list[str]) -> None:
    """Re-time: each split set's twins before the write and from --retime-settle s after it, and the written twin's
    change relative to its game twin (the difference of differences: the traffic's own drift cancels)."""
    if not rep.rt_sets and not any("Re-time" in n for n in rep.notes):
        return
    out.append("## Re-time: before / after")
    out.append("")
    if not rep.rt_sets:
        out.append("No Re-time write could be joined to a twin (see the notes under Loads).")
        out.append("")
        return
    out.append(f"Each set with a Re-time write (`[SQRL] RETIME op=write sent>=1`), split at the write: before = its "
               f"samples up to the first write (also in every table above), after = from {rep.retime_settle_s:g} game s "
               "after the last write (set `<pair>+rt` in the tables above). vs game = the twin minus its set's game twin "
               "in the same window, so a change of the traffic itself cancels out.")
    out.append("")
    out.append("| set | twin | plan | samples before / after | thru/min before / after | km/h before / after | "
               "standing % before / after | queue before / after | vs game km/h before / after | vs game thru/min before / after |")
    out.append("|---|---|---|---|---|---|---|---|---|---|")
    lines = []
    for info in rep.rt_sets:
        label = info["pair"] + rep.gen_label(info["gen"])
        tw = info["twins"]
        game = tw.get("game")
        def vs(st: ZoneStat, g: ZoneStat | None, attr: str) -> float | None:
            if g is None:
                return None
            a, b = getattr(st, attr)(), getattr(g, attr)()
            return a - b if a is not None and b is not None else None
        for ab in sorted(tw, key=lambda a: AB_ORDER.index(a) if a in AB_ORDER else 99):
            bst, ast, written = tw[ab]
            g_b, g_a = (game[0], game[1]) if game else (None, None)
            name = bst.name + (" (re-timed)" if written else "")
            vg = (f"{f(vs(bst, g_b, 'speed_kmh'), 1, True)} / {f(vs(ast, g_a, 'speed_kmh'), 1, True)}"
                  if ab != "game" and game else "-")
            vt = (f"{f(vs(bst, g_b, 'thru_per_min'), 1, True)} / {f(vs(ast, g_a, 'thru_per_min'), 1, True)}"
                  if ab != "game" and game else "-")
            out.append(f"| {label} | {name} | {plan_name(ab)} | {bst.n()} / {ast.n()} | {f(bst.thru_per_min())} / "
                       f"{f(ast.thru_per_min())} | {f(bst.speed_kmh())} / {f(ast.speed_kmh())} | "
                       f"{f(bst.standing_pct(), 0)} / {f(ast.standing_pct(), 0)} | {f(bst.queue_mean())} / "
                       f"{f(ast.queue_mean())} | {vg} | {vt} |")
            if written and game:
                use_thru = all(x is not None for x in (vs(bst, g_b, "thru_per_min"), vs(ast, g_a, "thru_per_min")))
                attr, unit = ("thru_per_min", "thru/min") if use_thru else ("speed_kmh", "km/h")
                b0, a0 = vs(bst, g_b, attr), vs(ast, g_a, attr)
                if b0 is not None and a0 is not None:
                    d = a0 - b0
                    word = "better" if d > 0 else ("worse" if d < 0 else "unchanged")
                    lines.append(f"**{label} {bst.name}** ({plan_name(ab)}, {bst.type}): re-timed {word} by "
                                 f"{f(d, 1, True)} {unit} relative to game ({f(b0, 1, True)} before, {f(a0, 1, True)} after; "
                                 f"{bst.n()} / {ast.n()} samples)" + (" (too few samples after)"
                                                                      if ast.n() < rep.min_samples else "") + ".")
    out.append("")
    for info in rep.rt_sets:
        if info["between"]:
            lines.append(f"{info['pair']}{rep.gen_label(info['gen'])}: {info['between']} sample(s) between the writes / in "
                         f"the {rep.retime_settle_s:g} s settle dropped; node(s) {', '.join(info['nodes'])}, "
                         f"{info['writes']} write(s).")
    for ln in lines:
        out.append(f"- {ln}")
    if lines:
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
    pops: dict[str, list[float]] = defaultdict(list)  # 2026-10-14: pop= per town line (people, in sample order)
    for ld in rep.loads:
        for k, kv, _ in ld.events:
            if k != "FLOW_TOWNS":
                continue
            if kv.get("scope") == "all":
                alls.append((ld.index, kv))
            elif kv.get("scope") == "town":
                sp = num(kv.get("speed"))
                name = kv.get("name") or kv.get("town", "?")
                if sp is not None:
                    towns[name].append(sp)
                pp = num(kv.get("pop"))
                if pp is not None:
                    pops[name].append(pp)
    if not alls and not towns:
        return
    out.append("## Towns (FLOW_TOWNS)")
    out.append("")
    if pops:
        # the light plans A/B's unbalanced towns end in busy / small / tiny ("Auto_timing_2_S_tiny"); the rest balanced
        classes: dict[str, list[list[float]]] = defaultdict(list)
        for name, v in pops.items():
            word = name.rsplit("_", 1)[-1]
            classes[word if word in TOWN_WORDS else "other"].append(v)
        out.append("Town populations (`pop=`, people = residential capacity) per class (the light plans A/B's unbalanced "
                   "sets: busy / small / tiny; other = every other town), first and last sample:")
        out.append("")
        out.append("| class | towns | first mean | last mean | last min / max |")
        out.append("|---|---|---|---|---|")
        for c in sorted(classes, key=lambda c: (list(TOWN_WORDS) + ["other"]).index(c)):
            vs = classes[c]
            first = [v[0] for v in vs]
            last = [v[-1] for v in vs]
            out.append(f"| {c} | {len(vs)} | {sum(first) / len(first):.0f} | {sum(last) / len(last):.0f} | "
                       f"{min(last):.0f} / {max(last):.0f} |")
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
    render_light_plans(rep, out)
    render_ring_use(rep, out)
    out.extend(render_auto(rep))
    out.extend(render_whole_map(rep))
    out.extend(render_city(rep))
    render_retime(rep, out)
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
    ap.add_argument("--retime-settle", type=float, default=60.0,
                    help="game seconds after a Re-time write before its set's after window starts (default 60)")
    ap.add_argument("--auto-settle", type=float, default=2700.0,
                    help="game seconds after an auto twin's first write (or a whole-map enroll_all) before its settled "
                         "window starts (default 2700: Smart Lanes step B v4 decides a junction first after 8 snapshots, "
                         "~16 game min, then every 10-60 min; a saturated junction settles ~45 game min after enrolling; "
                         "900 before v4)")
    args = ap.parse_args()
    paths = args.logs or [default_log()]
    for p in paths:
        if not p.is_file():
            raise SystemExit(f"No such log: {p}")
    ignore = [r for a in args.ignore_reason for r in a.split(",")]
    rep = parse(paths, args.last, args.warmup, args.gt_per_s, args.min_samples, args.worse_pct, ignore,
                args.retime_settle, args.auto_settle)
    if not rep.loads:
        print(f"No [SQST] FLOW_* or [SQRL] TOGGLE lines in {', '.join(map(str, paths))}.")
        print("Build a Showcase (Stress Test), turn the Traffic tab's Traffic log On, let the game run for a while "
              "(at least --warmup plus a few samples), then run this again.")
        return
    print(render(rep, args.trend_rows, args.towns), end="")


if __name__ == "__main__":
    main()

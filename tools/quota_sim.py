# /// script
# requires-python = ">=3.11"
# dependencies = ["lupa"]
# ///
"""Offline simulator for the Quota Run mod (square_quota_run).

Drives the REAL quota_logic.tl (transpiled with the game's Teal compiler via
tools/tealrt.py) through a whole run in a synthetic world, for balancing and
for testing the loop. Only the stable logic entry points are used: activate,
tick, delivered, pickCard, continueSandbox (plus the pure helper factsNeeded). Rules and bosses
(v2.1) are injected like in the game. See plans/square_quota_run/SIMULATOR.md.

World model (all per default game month, "m" = months since run start):
  deliveries/month = (RATE + RATE_GROWTH*m) * speed * prod * noise
      speed = 1 + SPEED_ELASTICITY * (fx.vehicleMods.TopSpeed - 1)
      prod  = 1 - CARGO_SHARE + CARGO_SHARE * cargoProd, where every industryMods intent
              multiplies cargoProd by 1 + PROD_ELASTICITY*(mult-1)*share
              (share = 1 for "all", else min(count, INDUSTRIES)/INDUSTRIES)
      noise = uniform(1-NOISE, 1+NOISE) per step (seeded), 1 when NOISE = 0
  balance += (INCOME + INCOME_GROWTH*m) per month (prorated per step) + cash intents
Card picks happen instantly at the deadline (the game pauses for the picker).

Examples:
  uv run tools/quota_sim.py --rate 150 --rate-growth 0
  uv run tools/quota_sim.py --runs 200 --strategy random --set GROWTH=1.4
  uv run tools/quota_sim.py --income -500000 --balance 0 --verbose
  uv run tools/quota_sim.py --selftest
"""

from __future__ import annotations

import argparse
import json
import random
import statistics
import sys
import time
from collections import Counter
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hubconfig import MODS_DIR  # noqa: E402
from tealrt import Teal, def_modules  # noqa: E402

MOD_ID = "square_quota_run"
MOD_DIR = MODS_DIR / MOD_ID
CONTENT = MOD_DIR / "content"
MODULES = {
    "config": "quota/quota_config.tl",
    "cards": "quota/quota_cards.tl",
    "rules": "quota/quota_rules.tl",
    "bosses": "quota/quota_bosses.tl",
    "logic": "quota/quota_logic.tl",
}
FACTS_CAP = 500  # larger batches use the units path (exact for kind-only facts, much faster)
MONTH = 1200  # synthetic game-time units per default month (divisible by 2,3,4,5,6,8,10,12)
STRATEGIES = ("first", "random", "greedy")

# Loads a transpiled module in a sandbox whose ug_require only knows the quota modules.
LOADER = r"""
local code, name, mods = ...
local env = setmetatable({}, { __index = _G })
env.ug_require = function(path)
  local key = path:gsub("^[%w_]+::", ""):gsub("^/", "")
  local m = mods[key]
  if m == nil then error("quota_sim: ug_require '" .. path .. "' not available offline", 2) end
  return m
end
local chunk, err = load(code, "@" .. name, "t", env)
if not chunk then error(err) end
return chunk()
"""

# n kind-only delivery facts, built on the Lua side (the sim knows nothing but the kind).
MAKE_FACTS = r"""
return function(kind, n)
  local facts = {}
  for i = 1, n do facts[i] = { kind = kind } end
  return facts
end
"""


# --------------------------------------------------------------------------- loading


class Logic:
    """The real logic module, compiled once; config overrides applied before new()."""

    def __init__(self, overrides: dict[str, Any]):
        t0 = time.perf_counter()
        search = [d for d in (CONTENT, MOD_DIR / "tealdef") if d.is_dir()]
        teal = Teal(search)
        env, _ = teal.new_env(def_modules(CONTENT))
        self.lua = teal.lua
        loader = self.lua.eval("load")(LOADER, "=quota_sim")
        mods = self.lua.table()
        loaded: dict[str, Any] = {}
        for key, rel in MODULES.items():
            path = CONTENT / rel
            code, diags = teal.gen(env, path.read_text(encoding="utf-8-sig"), str(path.relative_to(MOD_DIR.parent.parent)))
            if code is None:
                msg = "\n".join(map(str, diags))
                raise SystemExit(f"quota_sim: {rel} does not compile (mid-edit? retry in a minute):\n{msg}")
            loaded[key] = loader(code, rel, mods)
            mods["/" + rel] = loaded[key]
            mods[rel] = loaded[key]
        self.config = loaded["config"]
        self.cards = loaded["cards"]
        self.rules = loaded["rules"]
        self.bosses = loaded["bosses"]
        self.make_facts = self.lua.execute(MAKE_FACTS)
        for k, v in overrides.items():
            if self.config[k] is None:
                known = sorted(str(x) for x in self.config.keys())
                raise SystemExit(f"--set {k}: no such config field (known: {', '.join(known)})")
            self.config[k] = v
        self.logic = loaded["logic"].new(self.config, self.cards, self.rules, self.bosses)
        self.compile_seconds = time.perf_counter() - t0
        # Card effects as plain Python, for the greedy strategy.
        self.card_effects: dict[str, list[dict[str, Any]]] = {}
        for card in self.cards.list.values():
            effs = []
            for e in card.effects.values():
                d = {k: e[k] for k in ("kind", "amount", "mult", "months", "count", "rule") if e[k] is not None}
                if e.mods is not None:
                    d["mods"] = dict(e.mods.items())
                effs.append(d)
            self.card_effects[str(card.id)] = effs

    def cfg(self, key: str) -> Any:
        return self.config[key]

    def rule_kind_factor(self, rule_id: Any, cargo_share: float) -> tuple[float, float]:
        """(weight per unit for this world's kind mix, quotaMult) of a rule; kind parts only."""
        rule = self.rules.get(rule_id) if rule_id is not None else None
        if rule is None:
            return 1.0, 1.0
        cw = 1.0 if rule.cargoWeight is None else float(rule.cargoWeight)
        pw = 0.0 if rule.cargoOnly else (1.0 if rule.passengerWeight is None else float(rule.passengerWeight))
        qm = 1.0 if rule.quotaMult is None else float(rule.quotaMult)
        return cargo_share * cw + (1 - cargo_share) * pw, qm


def parse_value(text: str) -> Any:
    low = text.lower()
    if low in ("true", "false"):
        return low == "true"
    for conv in (int, float):
        try:
            return conv(text, 0) if conv is int else conv(text)
        except ValueError:
            pass
    return text


# --------------------------------------------------------------------------- world


@dataclass
class World:
    rate: float = 100.0
    rate_growth: float = 4.0
    balance: float | None = 5_000_000
    income: float = 300_000
    income_growth: float = 5_000
    speed_elasticity: float = 0.7
    prod_elasticity: float = 0.7
    cargo_share: float = 0.5
    industries: int = 20
    noise: float = 0.0
    step: float = 0.25  # months
    max_months: float = 1200
    strategy: str = "greedy"
    picks: list[str] = field(default_factory=list)


@dataclass
class Row:
    round: int
    months: float = 0.0
    quota: int = 0
    delivered: int = 0
    result: str = ""
    reward: int = 0
    balance: int | None = None
    offer: str = ""
    pick: str = ""
    boss: str = ""  # boss of the round (at round start)
    rule: str = ""  # scoring rule of the round (after the pick)


class Run:
    def __init__(self, L: Logic, world: World, seed: int, verbose: bool = False):
        self.L, self.w, self.seed, self.verbose = L, world, seed, verbose
        self.rng = random.Random(seed)
        self.balance = world.balance
        self.cargo_prod = 1.0
        self.carry = {"cargo": 0.0, "passenger": 0.0}
        self.rows: list[Row] = []
        self.log: list[str] = []
        self.pick_no = 0
        self.row_starts: list[int] = []
        self.t = 0  # game time

    def T(self, **kw: Any) -> Any:
        return self.L.lua.table_from(kw)

    # -- world model
    def months(self, t: float | None = None) -> float:
        return (self.t if t is None else t) / MONTH

    def factors(self, top_speed: float, cargo_prod: float) -> float:
        speed = 1 + self.w.speed_elasticity * (top_speed - 1)
        prod = 1 - self.w.cargo_share + self.w.cargo_share * cargo_prod
        return speed * prod

    def top_speed(self) -> float:
        v = self.s.fx.vehicleMods["TopSpeed"]
        return 1.0 if v is None else float(v)

    def base_integral(self, m0: float, m1: float) -> float:
        return self.w.rate * (m1 - m0) + self.w.rate_growth * (m1 * m1 - m0 * m0) / 2

    # -- logic plumbing
    def handle(self, intents: Any, where: str) -> list[Any]:
        out = list(intents.values()) if intents is not None else []
        for it in out:
            kind = str(it.kind)
            if kind == "cash" and self.balance is not None:
                self.balance += int(it.amount)
            elif kind == "industryMods":
                share = 1.0 if it.industryCount is None else min(int(it.industryCount), self.w.industries) / self.w.industries
                self.cargo_prod *= 1 + self.w.prod_elasticity * (float(it.mult) - 1) * share
            elif kind == "clearEffects":
                self.cargo_prod = 1.0
            if self.verbose:
                if kind == "log":
                    text = f"log[{it.level}] {it.message}"
                elif kind == "notify":
                    params = self.L.logic.dump(it.params) if it.params is not None else ""
                    text = f"notify {it.key} {params}"
                elif kind == "cash":
                    text = f"cash {int(it.amount):+,}"
                elif kind == "industryMods":
                    text = f"industryMods count={it.industryCount} mult={it.mult}"
                else:
                    text = kind
                self.log.append(f"[m{self.months():7.2f}] {where}: {text}")
        return out

    def bal_int(self) -> int | None:
        return None if self.balance is None else int(round(self.balance))

    def new_row(self) -> Row:
        s = self.s
        row = Row(round=int(s.round), quota=int(s.quota), boss="" if s.boss is None else str(s.boss),
                  rule="" if s.rule is None else str(s.rule))
        self.rows.append(row)
        self.row_starts.append(int(self.s.roundStartTime))
        return row

    def close_row(self, result: str) -> None:
        row = self.rows[-1]
        s = self.s
        row.result = result
        row.months = round((min(self.t, int(s.roundEndTime)) - self.row_starts[-1]) / MONTH, 2)
        row.balance = self.bal_int()

    # -- picking
    def choose(self, offer: list[str]) -> tuple[int, str]:
        """Returns (1-based index, note)."""
        if self.pick_no < len(self.w.picks):
            want = self.w.picks[self.pick_no]
            self.pick_no += 1
            if want in offer:
                return offer.index(want) + 1, ""
            note = "*"  # wanted card not offered; fall back to the strategy
        else:
            note = ""
        if self.w.strategy == "first":
            return 1, note
        if self.w.strategy == "random":
            return self.rng.randrange(len(offer)) + 1, note
        return self.greedy(offer) + 1, note

    def greedy(self, offer: list[str]) -> int:
        """Score each card by projected deliveries/quota for the round that just started.

        Behind (projected ratio < 1.15 without a card): maximise the ratio. Ahead: take value
        (reward multipliers, permanent quota cuts, cash), but never drop the ratio below 1.15
        and never pay cash we don't have.
        """
        s, cfg = self.s, self.L.cfg
        r = int(s.round)
        m0 = self.months(int(s.roundStartTime))
        m_end = self.months(int(s.roundEndTime))
        now = self.months()
        # this round's quota without the card multipliers (keeps the rule/boss quotaMult)
        base_q = float(s.quota) / max(1e-9, float(s.quotaMultAll) * float(s.quotaMultRound))
        cur_w, cur_qm = self.L.rule_kind_factor(s.rule, self.w.cargo_share)

        def project(card: str | None) -> tuple[float, float]:
            qa, qr, end, ts, cp, cash, rew = float(s.quotaMultAll), float(s.quotaMultRound), m_end, self.top_speed(), self.cargo_prod, 0.0, 0.0
            rw, rq = 1.0, 1.0  # rule card: weight and quota relative to the current rule
            for e in self.L.card_effects.get(card, []) if card else []:
                k = e["kind"]
                if k == "quotaMultAll":
                    qa *= e["mult"]
                elif k == "quotaMultRound":
                    qr *= e["mult"]
                elif k == "roundMonths":
                    end = max(end + e["months"], min(end, now + cfg("MIN_MONTHS_LEFT"))) if e["months"] < 0 else end + e["months"]
                elif k == "vehicleMod":
                    ts = min(cfg("VEHICLE_MOD_CAP"), ts + e.get("mods", {}).get("TopSpeed", 1.0) - 1)
                elif k == "industryProd":
                    share = 1.0 if e.get("count") is None else min(e["count"], self.w.industries) / self.w.industries
                    cp *= 1 + self.w.prod_elasticity * (e["mult"] - 1) * share
                elif k == "cash":
                    cash += e["amount"] * r
                elif k == "rewardMult":
                    rew += e["mult"] - 1
                elif k == "rewardMultRound":
                    rew += (e["mult"] - 1) / 3  # one round only
                elif k == "rule":
                    w_new, qm_new = self.L.rule_kind_factor(e["rule"], self.w.cargo_share)
                    rw, rq = w_new / max(1e-9, cur_w), qm_new / cur_qm
            delivered = int(s.progress) + self.base_integral(now, end) * self.factors(ts, cp) * cur_w * rw
            quota = max(1.0, base_q * qa * qr * rq)
            # value: permanent multipliers matter for every later round
            value = rew * 2 + (1 - qa / float(s.quotaMultAll)) * 6 + (ts - self.top_speed()) * 4 + (cp - self.cargo_prod) * 2
            value += cash / max(1.0, cfg("REWARD_BASE") * r)
            if cash < 0 and self.balance is not None and self.balance + cash < 0:
                value -= 10
            return delivered / quota, value

        baseline, _ = project(None)
        best, best_score = 0, float("-inf")
        for i, card in enumerate(offer):
            ratio, value = project(card)
            if baseline < 1.15:
                score = ratio * 100 + value
            else:
                score = value - (100 if ratio < 1.15 else 0)
            if score > best_score:
                best, best_score = i, score
        return best

    # -- main loop
    def play(self) -> dict[str, Any]:
        lg, w = self.L.logic, self.w
        self.s, intents = lg.activate(None, self.T(gameTime=0, seed=self.seed, monthDuration=MONTH, statsTotal=0))
        self.handle(intents, "activate")
        self.new_row()
        step = max(1, int(round(w.step * MONTH)))
        limit = int(w.max_months * MONTH)
        end_reason = "limit"
        while True:
            s = self.s
            phase = str(s.phase)
            if phase == "ended":
                end_reason = str(s.endReason)
                break
            if phase == "choosing":
                offer = [str(x) for x in s.offer.values()]
                idx, note = self.choose(offer)
                self.s, intents = lg.pickCard(s, self.T(index=idx, gameTime=self.t))
                self.handle(intents, "pickCard")
                row = self.rows[-1]
                row.offer, row.pick, row.quota = ",".join(offer), offer[idx - 1] + note, int(self.s.quota)
                row.rule = "" if self.s.rule is None else str(self.s.rule)
                continue
            if self.t >= limit:
                break
            # advance to the next step, never past a deadline or month tick
            t1 = min(self.t + step, int(s.roundEndTime), int(s.nextMonthTick), limit)
            if t1 <= self.t:
                t1 = self.t + 1
            m0, m1 = self.months(), self.months(t1)
            units = self.base_integral(m0, m1) * self.factors(self.top_speed(), self.cargo_prod)
            if w.noise > 0:
                units *= self.rng.uniform(1 - w.noise, 1 + w.noise)
            for kind, share in (("cargo", w.cargo_share), ("passenger", 1 - w.cargo_share)):
                self.carry[kind] += max(0.0, units * share)
                n = int(self.carry[kind])
                if n > 0:
                    self.carry[kind] -= n
                    if n <= FACTS_CAP and lg.factsNeeded(self.s) is not None:
                        # the adapter would resolve cargoType/toTown/...; the sim only knows the kind
                        inp = self.T(units=n, kind=kind, facts=self.L.make_facts(kind, n))
                    else:
                        inp = self.T(units=n, kind=kind)
                    self.s, intents = lg.delivered(self.s, inp)
                    self.handle(intents, "delivered")
            if self.balance is not None:
                self.balance += w.income * (m1 - m0) + w.income_growth * (m1 * m1 - m0 * m0) / 2
            self.t = t1
            self.s, intents = lg.tick(self.s, self.T(gameTime=self.t, balance=self.bal_int()))
            items = self.handle(intents, "tick")
            for it in items:
                if str(it.kind) == "notify" and str(it.key) == "roundCleared":
                    row = self.rows[-1]
                    row.delivered, row.reward = int(it.params.progress), int(it.params.reward)
                    row.result = "pass"
                    row.balance = self.bal_int()
                    row.months = round((int(self.s.roundStartTime) - self.row_starts[-1]) / MONTH, 2)
                    self.new_row()
            if str(self.s.phase) == "ended":
                row = self.rows[-1]
                row.delivered = int(self.s.progress)
                self.close_row("FAIL" if str(self.s.endReason) == "quota" else str(self.s.endReason))
        # the stable "after the run" entry point; must flip to sandbox
        sandbox = None
        if str(self.s.phase) == "ended":
            self.s, intents = lg.continueSandbox(self.s, self.T())
            self.handle(intents, "continueSandbox")
            sandbox = str(self.s.phase)
        if end_reason == "limit":
            self.rows[-1].result = "limit"
            self.rows[-1].delivered = int(self.s.progress)
            self.rows[-1].balance = self.bal_int()
        return {
            "seed": self.seed,
            "roundsCleared": int(self.s.roundsCleared),
            "endReason": end_reason,
            "endRound": int(self.s.round),
            "months": round(self.months(), 2),
            "total": int(self.s.totalTransported or 0),
            "balance": self.bal_int(),
            "picked": [str(x) for x in self.s.picked.values()],
            "afterContinue": sandbox,
        }


# --------------------------------------------------------------------------- output


def fmt_money(v: int | None) -> str:
    if v is None:
        return "inf"
    return f"{v / 1e6:,.1f}M"


def print_table(rows: list[Row]) -> None:
    hdr = ("rnd", "boss/rule", "months", "quota", "delivered", "result", "reward", "balance", "offer", "pick")
    lines = [hdr]
    for r in rows:
        lines.append((str(r.round), "/".join(x for x in (r.boss, r.rule) if x) or "-", f"{r.months:g}", f"{r.quota:,}", f"{r.delivered:,}", r.result,
                      fmt_money(r.reward) if r.reward else "-", fmt_money(r.balance), r.offer or "-", r.pick or "-"))
    widths = [max(len(l[i]) for l in lines) for i in range(len(hdr))]
    right = {0, 2, 3, 4, 6, 7}
    for n, l in enumerate(lines):
        print("  ".join(c.rjust(widths[i]) if i in right else c.ljust(widths[i]) for i, c in enumerate(l)).rstrip())
        if n == 0:
            print("  ".join("-" * x for x in widths))


def aggregate(results: list[dict[str, Any]]) -> dict[str, Any]:
    rc = [r["roundsCleared"] for r in results]
    qs = statistics.quantiles(rc, n=10) if len(rc) >= 2 else [rc[0]] * 9
    return {
        "runs": len(results),
        "roundsCleared": {
            "mean": round(statistics.fmean(rc), 3),
            "median": statistics.median(rc),
            "min": min(rc),
            "p10": qs[0],
            "p90": qs[-1],
            "max": max(rc),
            "histogram": dict(sorted(Counter(rc).items())),
        },
        "endReasons": dict(Counter(r["endReason"] for r in results)),
        "meanMonths": round(statistics.fmean(r["months"] for r in results), 1),
        "meanTotal": round(statistics.fmean(r["total"] for r in results)),
        "pickCounts": dict(Counter(p for r in results for p in r["picked"]).most_common()),
    }


def print_aggregate(a: dict[str, Any]) -> None:
    rc = a["roundsCleared"]
    print(f"{a['runs']} runs: rounds cleared mean {rc['mean']}, median {rc['median']}, "
          f"min {rc['min']}, p10 {rc['p10']:g}, p90 {rc['p90']:g}, max {rc['max']}")
    top = max(rc["histogram"].values())
    for k, v in rc["histogram"].items():
        print(f"  {k:>3} rounds  {v:>5}  {'#' * max(1, round(40 * v / top))}")
    print(f"end reasons: {a['endReasons']}  mean months: {a['meanMonths']}  mean total delivered: {a['meanTotal']:,}")
    print("picks: " + ", ".join(f"{k} {v}" for k, v in a["pickCounts"].items()))


# --------------------------------------------------------------------------- selftest


def selftest(L: Logic) -> None:
    fails = []

    def check(cond: bool, what: str) -> None:
        print(("  ok    " if cond else "  FAIL  ") + what)
        if not cond:
            fails.append(what)

    def run(seed: int = 1, **kw: Any) -> tuple[Run, dict[str, Any]]:
        r = Run(L, World(**kw), seed)
        return r, r.play()

    base_q = L.cfg("BASE_QUOTA")
    first = L.cfg("FIRST_ROUND_MONTHS")
    _, res = run(rate=0, rate_growth=0, income=0)
    check(res["endReason"] == "quota" and res["roundsCleared"] == 0 and abs(res["months"] - first) < 1e-6,
          f"no deliveries: round 1 fails at month {first}")
    check(res["afterContinue"] == "sandbox", "continueSandbox after ENDED -> sandbox")
    need = base_q / first
    _, res = run(rate=need * 1.05, rate_growth=0, income=0, strategy="first")
    check(res["roundsCleared"] >= 1, f"steady {need * 1.05:.0f}/month clears round 1")
    _, res = run(rate=need * 0.95, rate_growth=0, income=0)
    check(res["roundsCleared"] == 0, f"steady {need * 0.95:.0f}/month fails round 1")
    _, res = run(rate=1e6, rate_growth=0, balance=0, income=-1000, income_growth=0, strategy="first")
    bm = L.cfg("BANKRUPT_MONTHS")
    check(res["endReason"] == "bankrupt" and abs(res["months"] - bm) < 1e-6, f"negative income: bankrupt at month {bm}")
    _, res = run(rate=1e6, rate_growth=0, balance=None, income=-1000)
    check(res["endReason"] == "quota" and res["roundsCleared"] > 1, "infinite money (balance nil) never goes bankrupt")
    a = json.dumps(run(seed=7, strategy="random", noise=0.3)[1], sort_keys=True)
    b = json.dumps(run(seed=7, strategy="random", noise=0.3)[1], sort_keys=True)
    check(a == b, "deterministic for a given seed")
    r, res = run(seed=3, rate=400, rate_growth=10, picks=["extension", "venture"], strategy="first")
    check(len(res["picked"]) >= 1, "fixed --picks list is consumed")
    t0 = time.perf_counter()
    r, res = run(seed=5, rate=1e9, rate_growth=0, max_months=first + 20 * L.cfg("ROUND_MONTHS"))
    dt = time.perf_counter() - t0
    check(res["roundsCleared"] >= 20 and dt < 1.0, f"20-round run in {dt * 1000:.0f} ms (< 1 s)")
    every = L.cfg("BOSS_EVERY")
    if every and every > 0:
        boss_rounds = [row.round for row in r.rows if row.boss]
        want = [n for n in range(1, 21) if n % every == 0]
        check(all(n in boss_rounds for n in want) and all(n % every == 0 for n in boss_rounds),
              f"bosses exactly on rounds {want[:3]}... (every {every})")
    if fails:
        raise SystemExit(f"selftest: {len(fails)} failed")
    print("selftest passed")


# --------------------------------------------------------------------------- main


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    d = World()
    p.add_argument("--set", action="append", default=[], metavar="KEY=VALUE", help="override a quota_config field")
    p.add_argument("--rate", type=float, default=d.rate, help="deliveries per month at run start (%(default)s)")
    p.add_argument("--rate-growth", type=float, default=d.rate_growth, help="added deliveries/month per month (%(default)s)")
    p.add_argument("--balance", type=float, default=d.balance, help="starting balance (%(default)s)")
    p.add_argument("--infinite-money", action="store_true", help="balance nil: bankruptcy check skipped")
    p.add_argument("--income", type=float, default=d.income, help="net income per month at run start (%(default)s)")
    p.add_argument("--income-growth", type=float, default=d.income_growth, help="added income/month per month (%(default)s)")
    p.add_argument("--speed-elasticity", type=float, default=d.speed_elasticity, help="deliveries gain per TopSpeed gain (%(default)s)")
    p.add_argument("--prod-elasticity", type=float, default=d.prod_elasticity, help="cargo gain per industry productivity gain (%(default)s)")
    p.add_argument("--cargo-share", type=float, default=d.cargo_share, help="share of deliveries that are cargo (%(default)s)")
    p.add_argument("--industries", type=int, default=d.industries, help="industries on the map, for N-random cards (%(default)s)")
    p.add_argument("--noise", type=float, default=d.noise, help="per-step uniform noise on deliveries, e.g. 0.2 (%(default)s)")
    p.add_argument("--step", type=float, default=d.step, help="tick step in months (%(default)s = weekly)")
    p.add_argument("--max-months", type=float, default=d.max_months, help="stop a run after this many months (%(default)s)")
    p.add_argument("--strategy", choices=STRATEGIES, default=d.strategy, help="card pick strategy (%(default)s)")
    p.add_argument("--picks", default="", help="comma list of card ids to pick in order (falls back to --strategy if not offered)")
    p.add_argument("--seed", type=int, default=1, help="seed: activation seed (card offers) and sim RNG (%(default)s)")
    p.add_argument("--runs", type=int, default=1, help="run seeds seed..seed+N-1 and print aggregate stats")
    p.add_argument("--json", action="store_true", help="machine-readable output")
    p.add_argument("--verbose", action="store_true", help="print every intent/log (single run)")
    p.add_argument("--selftest", action="store_true", help="run built-in checks against the real logic")
    a = p.parse_args()

    overrides = {}
    for item in a.set:
        if "=" not in item:
            p.error(f"--set {item}: expected KEY=VALUE")
        k, v = item.split("=", 1)
        overrides[k.strip()] = parse_value(v.strip())
    L = Logic(overrides)
    if a.selftest:
        print(f"compiled quota logic in {L.compile_seconds:.2f} s")
        selftest(L)
        return

    world = World(
        rate=a.rate, rate_growth=a.rate_growth, balance=None if a.infinite_money else a.balance,
        income=a.income, income_growth=a.income_growth, speed_elasticity=a.speed_elasticity,
        prod_elasticity=a.prod_elasticity, cargo_share=a.cargo_share, industries=a.industries,
        noise=a.noise, step=a.step, max_months=a.max_months, strategy=a.strategy,
        picks=[x.strip() for x in a.picks.split(",") if x.strip()],
    )
    unknown = [x for x in world.picks if x not in L.card_effects]
    if unknown:
        p.error(f"--picks: unknown card ids {unknown}; known: {', '.join(L.card_effects)}")
    meta = {"overrides": overrides, "world": asdict(world)}

    t0 = time.perf_counter()
    if a.runs <= 1:
        run = Run(L, world, a.seed, verbose=a.verbose)
        summary = run.play()
        dt = time.perf_counter() - t0
        if a.json:
            out = {**meta, "rows": [asdict(r) for r in run.rows], "summary": summary}
            if a.verbose:
                out["log"] = run.log
            print(json.dumps(out, indent=2))
            return
        if a.verbose:
            print("\n".join(run.log))
            print()
        print_table(run.rows)
        print(f"\nseed {a.seed}: {summary['roundsCleared']} rounds cleared, ended by {summary['endReason']} "
              f"in round {summary['endRound']} at month {summary['months']:g}, total delivered {summary['total']:,}, "
              f"balance {fmt_money(summary['balance'])}")
        print(f"(compile {L.compile_seconds:.2f} s, run {dt * 1000:.0f} ms)")
        return

    results = [Run(L, world, a.seed + i).play() for i in range(a.runs)]
    dt = time.perf_counter() - t0
    agg = aggregate(results)
    if a.json:
        print(json.dumps({**meta, "aggregate": agg, "runs": results}, indent=2))
        return
    print_aggregate(agg)
    print(f"(compile {L.compile_seconds:.2f} s, {a.runs} runs in {dt:.2f} s)")


if __name__ == "__main__":
    main()

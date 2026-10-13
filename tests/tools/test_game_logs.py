"""Unit tests for tools/game_logs.py (game log archive + index: make logs / logs-list / logs-grep).

Run: make test-tools   (uv run --with lupa python -m unittest discover -s tests/tools)
Input: small synthetic stdout.txt sessions and crash_dump reports written to a temp dir.
"""

from __future__ import annotations

import gzip
import io
import json
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import game_logs as gl  # noqa: E402


def line(ts: str, msg: str, level: str = "MESSAGE") -> str:
    return f"[2026-10-12 {ts}Z - {level:<8} - Main Thread      - Main           ]  {msg}\n"


def session(sid: str, start: str = "06:00:00", extra: str = "") -> str:
    return (line(start, "Application startup. Hello!")
            + line(start, f"Startup session with id {sid}")
            + line(start, "Starting up build version: 40420, build name \"Build\"")
            + line("06:00:05", "+ Active mods:").replace("]  +", "]+")
            + "    |   square_smart_lanes (rev. 4) (Smart Lanes)\n"
            + "    |   square_stress_test (rev. 9) (Stress Test)\n"
            + "    | Config dict:\n"
            + line("06:00:06", "Loading game from file Empty 2")
            + line("06:00:07", "[SQRL] AUDIT node=12 case=X findings=shared:1 src=auto")
            + line("06:00:08", "[SQRL] AUDIT node=13 case=X findings=weave:1 src=auto")
            + line("06:00:09", "[SQST] showcase: seed=747943 map=4096")
            + line("06:00:10", "[SQST] action=showcase count=3 ms=10")
            + line("06:00:11", "[SQST] showcase summary seed=747943 placements=3")
            + line("06:00:12", "[Minimap] ready [SQPERF] mod=x")
            + line("06:00:13", "[SQST] cell A1 refused by the check: Construction Not Possible", "WARNING")
            + extra)


ASSERT_TAIL = (line("06:05:00", "+ Exception type: Fatal error", "ERROR").replace("]  +", "]+")
               + "    | Assertion Failure: Assertion `it != components.end()' failed.\n"
               + "    | In file: train_fever/src/Lib/ecs/Engine.h:323\n"
               + "    + In function: GetComponentDataIndex\n"
               + line("06:05:00", "+ Ungraceful exit", "ERROR").replace("]  +", "]+"))

LUA_ERR = (line("06:01:00", "+ Exception type: Lua error", "VERBOSE").replace("]  +", "]+")
           + "    | Error message: attempt to call global 'rawget' (a nil value)\n")


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.logs = root / "logs"
        self.crash = root / "crash_dump"
        self.crash.mkdir()
        self.live = self.crash / "stdout.txt"

    def tearDown(self):
        self.tmp.cleanup()

    def store(self) -> gl.Store:
        return gl.Store(self.logs, self.crash, self.live)

    def save(self, text: str, tags=()) -> tuple[str, str]:
        self.live.write_text(text)
        st = self.store()
        res = st.save(self.live, list(tags))
        st.index_crashes()
        st.write()
        return res


class AnalyzeTest(unittest.TestCase):
    def test_tags_mods_markers(self):
        a = gl.analyze_bytes((session("aaaa-1") + LUA_ERR).encode())
        self.assertEqual(a["session_id"], "aaaa-1")
        self.assertEqual(a["build"], "40420")
        self.assertEqual(a["start"], "2026-10-12 06:00:00")
        self.assertEqual(a["end"], "2026-10-12 06:01:00")
        self.assertEqual(a["mods"], {"square_smart_lanes": "4", "square_stress_test": "9"})
        self.assertEqual(a["n_loads"], 1)
        self.assertEqual(a["loads"], ["Empty 2"])
        self.assertEqual(a["tags"]["SQRL"], 2)
        self.assertEqual(a["tags"]["SQST"], 4)
        self.assertEqual(a["tags"]["Minimap"], 1)
        self.assertEqual(a["tags"]["SQPERF"], 1)  # two tags on one line: each counted
        self.assertNotIn("C", a["tags"])
        self.assertEqual(a["actions"], {"showcase": 1})
        self.assertEqual(a["seeds"], ["747943"])
        self.assertEqual(a["audit"], 2)
        self.assertEqual(a["errors"]["construction_not_possible"], 1)
        self.assertEqual(a["errors"]["lua"], 1)
        self.assertFalse(a["crashed"])

    def test_crash_reason(self):
        a = gl.analyze_bytes((session("aaaa-1") + ASSERT_TAIL).encode())
        self.assertTrue(a["crashed"])
        self.assertEqual(a["errors"]["asserts"], 1)
        self.assertIn("it != components.end()", a["reason"])
        self.assertIn("Engine.h:323", a["reason"])

    def test_mod_text_is_no_crash_marker(self):
        a = gl.analyze_bytes((session("aaaa-1") + line("06:01:00", "[SQRL] retry after Ungraceful exit / ShowErrorBox")
                              + "Minidump callback called\n").encode())
        self.assertFalse(a["crashed"])

    def test_bad_utf8(self):
        a = gl.analyze_bytes(session("x").encode() + b"\xff\xfe broken [SQRL] AUDIT x\n")
        self.assertEqual(a["tags"]["SQRL"], 3)


class SaveTest(Base):
    def test_name_and_dedupe(self):
        status, name = self.save(session("aaaa-1"), ["showcase"])
        self.assertEqual(status, "new")
        self.assertEqual(name, "2026-10-12_0600_showcase-747943")
        self.assertTrue((self.logs / f"{name}.log.gz").is_file())
        with gzip.open(self.logs / f"{name}.log.gz", "rt") as f:
            self.assertEqual(f.read(), session("aaaa-1"))
        status2, name2 = self.save(session("aaaa-1"))
        self.assertEqual((status2, name2), ("unchanged", name))
        self.assertEqual(len(self.store().idx["sessions"]), 1)
        md = (self.logs / "INDEX.md").read_text()
        self.assertIn(name, md)
        self.assertIn("SQST:4", md)

    def test_action_slug(self):
        _, name = self.save(session("aaaa-1"))
        self.assertEqual(name, "2026-10-12_0600_showcase-747943")

    def test_auto_slug(self):
        text = line("07:00:00", "Startup session with id bbbb-2") + line("07:00:01", "[SQOT_DEV] x") * 3 \
            + line("07:00:02", "[SQOT] y") + line("07:00:03", "[SQPERF] z")
        _, name = self.save(text)
        self.assertEqual(name, "2026-10-12_0700_sqot-dev")

    def test_grown_session_replaces(self):
        _, n1 = self.save(session("aaaa-1"), ["t1"])
        status, n2 = self.save(session("aaaa-1", extra=LUA_ERR), ["t2"])
        self.assertEqual(status, "replaced")
        sessions = self.store().idx["sessions"]
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0]["user_tags"], ["t1", "t2"])
        self.assertEqual(sessions[0]["errors"]["lua"], 1)
        self.assertFalse((self.logs / f"{n1}.log.gz").exists())
        self.assertTrue((self.logs / f"{n2}.log.gz").exists())
        _, n3 = self.save(session("aaaa-1", extra=LUA_ERR + line("06:09:00", "[ZZZ] a") * 30))
        self.assertEqual(n3, n2)  # grown without new tags: same name although its top tags changed
        # the older, shorter copy saved again: kept out
        self.assertEqual(self.save(session("aaaa-1"))[0], "unchanged")

    def test_shorter_copy_of_archived_session_is_skipped(self):
        self.save(session("aaaa-1", extra=LUA_ERR))
        self.assertEqual(self.save(session("aaaa-1"))[0], "older")
        self.assertEqual(len(self.store().idx["sessions"]), 1)

    def test_no_session_id_never_replaces(self):
        text = line("07:00:00", "[SQRL] a") + line("07:00:01", "[SQRL] b")
        _, n1 = self.save(text)
        status, n2 = self.save(line("07:00:00", "[SQRL] a") + line("07:00:01", "[SQRL] c") * 2)
        self.assertEqual(status, "new")
        self.assertNotEqual(n1, n2)
        self.assertTrue((self.logs / f"{n1}.log.gz").exists())

    def test_same_id_not_a_prefix_is_kept(self):
        _, n1 = self.save(session("aaaa-1"))
        status, _ = self.save(session("aaaa-1").replace("node=12", "node=99") + LUA_ERR)
        self.assertEqual(status, "new")
        self.assertTrue((self.logs / f"{n1}.log.gz").exists())

    def test_two_sessions(self):
        self.save(session("aaaa-1"))
        self.save(session("bbbb-2", start="06:00:00"))
        names = [s["name"] for s in self.store().idx["sessions"]]
        self.assertEqual(len(set(names)), 2)


class CrashTest(Base):
    UID = "0123abcd-0000-1111-2222-333344445555"

    def write_crash(self, kind="assert", message="Fatal error: it != components.end()"):
        (self.crash / f"{self.UID}_1.txt").write_text(session(self.UID, start="05:00:00") + ASSERT_TAIL)
        (self.crash / f"{self.UID}_0.dmp").write_bytes(b"\0" * 64)
        (self.crash / f"{self.UID}_3.json").write_text(json.dumps({
            "buildInfo": {"version": 40420},
            "errorInfo": {"type": kind, "message": message, "file": "train_fever/src/Lib/ecs/Engine.h",
                          "line": 323, "function": "GetComponentDataIndex", "logFile": f"{self.UID}_1.txt",
                          "dumpFile": f"{self.UID}_0.dmp", "timestamp": "2026-10-12 05:41:14Z"},
            "sessionInfo": {"started": "2026-10-12 05:00:00Z", "uid": self.UID},
            "gameInfo": {"mods": [{"name": "square_smart_lanes"}], "savegameName": "Empty 2"}}))
        (self.crash / "error.json").write_text(json.dumps({"errorInfo": {"type": "ping"}}))

    def test_index_crash_dump(self):
        self.write_crash()
        st = self.store()
        st.index_crashes()
        ents = st.entries()
        self.assertEqual(len(ents), 1)
        e = ents[0]
        self.assertEqual(e["name"], "2026-10-12_0500_crash-0123abcd")
        self.assertTrue(e["crashed"] and e["fatal"])
        self.assertIn("assert: Fatal error: it != components.end() (Engine.h:323", e["reason"])
        self.assertEqual(e["mods"], {"square_smart_lanes": ""})
        self.assertEqual(e["tags"]["SQRL"], 2)
        self.assertFalse(any(f["path"].endswith(".dmp") for f in e["files"]))

    def test_native_crash_without_message(self):
        self.write_crash(kind="crash", message="")
        (self.crash / f"{self.UID}_1.txt").write_text(session(self.UID) + line("06:02:00", "Minidump callback called"))
        st = self.store()
        st.index_crashes()
        e = st.entries()[0]
        self.assertTrue(e["fatal"])
        self.assertIn("native crash", e["reason"])

    def test_missing_after_delete(self):
        self.write_crash()
        st = self.store()
        st.index_crashes()
        st.write()
        for p in self.crash.glob(f"{self.UID}_*"):
            p.unlink()
        st = self.store()
        st.index_crashes()
        e = st.entries()[0]
        self.assertTrue(e["missing"])
        self.assertTrue(all(not f["exists"] for f in e["files"]))
        self.assertIn("MISSING", gl.summary(e))

    def test_archive_links_crash_report(self):
        self.write_crash()
        self.save(session(self.UID, start="05:00:00") + ASSERT_TAIL)
        ents = self.store().entries()
        arch = next(e for e in ents if e["kind"] == "archive")
        crash = next(e for e in ents if e["kind"] == "crash_dump")
        self.assertTrue(arch["fatal"])
        self.assertEqual(crash["archived_as"], arch["name"])
        st = self.store()
        self.assertEqual(gl.resolve(st, "last-crash")["name"], arch["name"])  # not the crash_dump tail copy
        self.assertEqual(gl.resolve(st, crash["name"])["kind"], "crash_dump")  # still reachable by name


    def test_crash_logs_archived_by_cli(self):
        self.write_crash()
        st = self.store()
        st.index_crashes(archive=True)
        st.write()
        self.assertEqual(st.new, ["2026-10-12_0500_showcase-747943-crash"])
        ents = st.entries()
        arch = next(e for e in ents if e["kind"] == "archive")
        crash = next(e for e in ents if e["kind"] == "crash_dump")
        self.assertEqual(crash["archived_as"], arch["name"])
        self.assertIn("Engine.h:323", arch["reason"])
        md = (self.logs / "INDEX.md").read_text()
        self.assertIn(arch["name"], md)
        self.assertNotIn(crash["name"], md)  # shown once, as its archive
        # archived once: a second run reads nothing new, and the archive outlives crash_dump
        st = self.store()
        st.index_crashes(archive=True)
        self.assertEqual(st.new, [])
        for p in self.crash.glob(f"{self.UID}_*"):
            p.unlink()
        st = self.store()
        st.index_crashes(archive=True)
        st.write()
        self.assertEqual(gl.resolve(st, "last-crash")["name"], arch["name"])
        self.assertIn(arch["name"], (self.logs / "INDEX.md").read_text())

    def test_brief_save_prints_only_new(self):
        self.live.write_text(session("aaaa-1"))
        out = io.StringIO()
        with unittest.mock.patch.object(gl, "default_store", self.store), \
                unittest.mock.patch("sys.stdout", out):
            gl.main(["save", "--brief"])
            first = out.getvalue()
            out.truncate(0)
            out.seek(0)
            gl.main(["save", "--brief"])
        self.assertIn("2026-10-12_0600_showcase-747943", first)
        self.assertEqual(out.getvalue(), "")


class ResolveGrepTest(Base):
    def setUp(self):
        super().setUp()
        self.n1 = self.save(session("aaaa-1", start="06:00:00"))[1]
        plain = line("08:00:00", "Startup session with id cccc-3") + line("08:00:01", "[SQRL] AUDIT node=99")
        self.n2 = self.save(plain)[1]
        self.n3 = self.save(line("07:00:00", "Startup session with id bbbb-2") + ASSERT_TAIL)[1]

    def test_aliases(self):
        st = self.store()
        self.assertEqual(gl.resolve(st, "last")["name"], self.n2)
        self.assertEqual(gl.resolve(st, "last-crash")["name"], self.n3)
        self.assertEqual(gl.resolve(st, "last-showcase")["name"], self.n1)  # a Stress Test action
        self.assertEqual(gl.resolve(st, "last-sqrl")["name"], self.n2)
        self.assertEqual(gl.resolve(st, "747943")["name"], self.n1)
        self.assertEqual(gl.resolve(st, "bbbb")["name"], self.n3)  # session-id prefix
        self.assertEqual(gl.resolve(st, self.n1[:15])["name"], self.n1)  # unique name prefix
        with self.assertRaises(SystemExit):
            gl.resolve(st, "2026-10-12")  # ambiguous
        with self.assertRaises(SystemExit):
            gl.resolve(st, "nothing-like-it")
        p = gl.readable_path(st, gl.resolve(st, "last"))
        self.assertTrue(p.read_text().endswith("[SQRL] AUDIT node=99\n"))
        self.assertEqual(gl.resolve(st, str(p)), p)  # existing files pass through
        spaced = Path(self.tmp.name) / "with space" / "stdout.txt"
        spaced.parent.mkdir()
        spaced.write_text("x\n")
        q = gl.resolve(st, str(spaced))
        self.assertNotIn(" ", str(q))
        self.assertEqual(q.read_text(), "x\n")

    def test_crash_grep_dedupes_across_files_only(self):
        uid = "0123abcd-0000-1111-2222-333344445555"
        same = line("05:00:01", "[SQRL] AUDIT dup")
        (self.crash / f"{uid}_1.txt").write_text(line("05:00:00", "Startup") + same * 2)
        (self.crash / f"{uid}_3.txt").write_text(same + line("05:00:02", "[SQRL] AUDIT new"))
        st = self.store()
        st.index_crashes()
        out = io.StringIO()
        # both identical lines of _1.txt are shown; _3.txt's overlap with _1.txt is not repeated
        self.assertEqual(gl.grep(st, "AUDIT (dup|new)", out=out), 3)
        self.assertEqual(out.getvalue().count("AUDIT dup"), 2)

    def test_grep(self):
        st = self.store()
        out = io.StringIO()
        n = gl.grep(st, r"AUDIT node=\d+", out=out)
        self.assertEqual(n, 3)
        lines = out.getvalue().splitlines()
        self.assertTrue(lines[0].startswith(f"{self.n1}:9: "))
        self.assertTrue(lines[-1].startswith(f"{self.n2}:2: "))
        out = io.StringIO()
        gl.grep(st, "node=13", session="747943", context=1, out=out)
        self.assertEqual([x.split(" ")[0] for x in out.getvalue().splitlines()],
                         [f"{self.n1}-9-", f"{self.n1}:10:", f"{self.n1}-11-"])
        out = io.StringIO()
        self.assertEqual(gl.grep(st, "AUDIT", tag="showcase", out=out), 2)
        out = io.StringIO()
        self.assertEqual(gl.grep(st, "audit", ignore_case=True, max_hits=1, out=out), 1)
        out = io.StringIO()
        self.assertEqual(gl.grep(st, "AUDIT", since="2026-10-12 07:30", out=out), 1)

    def test_list_filters(self):
        st = self.store()
        ents = st.entries()
        self.assertEqual([e["name"] for e in ents if gl.tag_match(e, "crash")], [self.n3])
        self.assertEqual([e["name"] for e in ents if gl.tag_match(e, "[SQST]")], [self.n1])


if __name__ == "__main__":
    unittest.main()

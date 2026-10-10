"""Unit tests for tools/i18n.py (strings.json translation report).

Run: make test-tools   (uv run --with lupa python -m unittest discover -s tests/tools)
Input: the fake mod tests/tools/data/i18n/square_fixture/ (one extraction case per source line, a strings.json
with a stale key, an empty value and placeholder mismatches, a modinfo.json with bad localization).
"""

from __future__ import annotations

import contextlib
import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import i18n  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "data" / "i18n" / "square_fixture"


def scan(src: str, resource: bool = False) -> i18n.Scan:
    out = i18n.Scan()
    i18n.scan_source(src, "x.lua", out, resource=resource)
    return out


def run(*argv: str) -> tuple[int, str]:
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(io.StringIO()):
        code = i18n.main(list(argv))
    return code, buf.getvalue()


class ExtractTest(unittest.TestCase):
    def test_escapes(self):
        keys = list(
            scan(r"""local a = _("Tab\tq\" b\\ n\n end") local b = _("caf\u{E9} \65\x42\z
              tail")""").keys
        )
        self.assertEqual(keys, ['Tab\tq" b\\ n\n end', "café ABtail"])

    def test_backslash_newline(self):
        self.assertEqual(list(scan('x = _("a\\\nb")').keys), ["a\nb"])

    def test_long_strings(self):
        keys = list(scan("a = _([[\nLong\nstring]]) b = _ [==[two ]] in]==]").keys)
        self.assertEqual(keys, ["Long\nstring", "two ]] in"])

    def test_single_quotes_and_call_without_parens(self):
        keys = list(scan("a = _('It\\'s \"q\"') b = _ \"No parens\" c = _'Q'").keys)
        self.assertEqual(keys, ['It\'s "q"', "No parens", "Q"])

    def test_not_tr_calls(self):
        s = scan('foo_("a") obj._("b") obj:_("c") local function _(s) return s end for _, v in ipairs(t) do end')
        self.assertEqual(s.keys, {})
        self.assertEqual(s.nonliteral, [])

    def test_comments_ignored(self):
        self.assertEqual(scan('-- _("x")\n--[[ _("y") ]] z = _("z")').keys, {"z": "x.lua:2"})

    def test_nonliteral(self):
        s = scan('a = _(name)\nb = _("P " .. n)\nc = _(string.format("%d", n))\nd = _(x) -- i18n: ignore\ne = _()')
        self.assertEqual([(h.line, h.text) for h in s.nonliteral], [
            (1, "_(name)"), (2, '_("P " .. n)'), (3, '_(string.format("%d", n))'), (5, "_()"),
        ])  # fmt: skip
        self.assertEqual(s.keys, {})

    def test_concatenation(self):
        s = scan(
            'a = _("Total:") .. " " .. n .. " " .. _("items")\n'
            'b = _("Speed") .. " km/h"\n'
            'c = _("Name") .. ": " .. name\n'
            'd = "Undo: " .. _(x)\n'
            'e = f(_("A")) .. g\n'
            'f = _("B") .. _("C") -- i18n: ignore\n'
        )
        self.assertEqual([h.line for h in s.concat], [1, 2, 4])

    def test_untranslated_sinks(self):
        s = scan(
            'v = { text = "Shown text", title = "font-scale-body", label = _("Ok") }\n'
            't = text("Raw call", cls)\n'
            'w = api.gui.comp.TextView.new("Raw ctor")\n'
            'x = { tooltip = "Skipped" } -- i18n: ignore\n'
            'y = { label = "gs20", text = "x", name = "Not a resource" }\n'
        )
        self.assertEqual([(h.line, h.text) for h in s.untranslated], [
            (1, 'text = "Shown text"'), (2, 'text("Raw call", ...)'), (3, 'TextView.new("Raw ctor")'),
        ])  # fmt: skip
        res = scan('return { name = "Menu name", description = "icon_path.tga", n2 = "x" }', resource=True)
        self.assertEqual([h.text for h in res.untranslated], ['name = "Menu name"'])

    def test_keys_marker(self):
        s = scan(
            'A = { s = "Small", ["k"] = "Large" } -- i18n: keys\n'
            'B = { key = "a", label = "Row" } -- i18n: keys label\n'
            "-- i18n: keys begin\n"
            'C = { "One",\n "Two" }\n'
            "-- i18n: keys end\n"
        )
        self.assertEqual(list(s.keys), ["Small", "Large", "Row", "One", "Two"])

    def test_looks_like_text(self):
        for s in ("Debug", "off", "Hide all", "A4"):
            self.assertTrue(i18n.looks_like_text(s), s)
        for s in ("", "x", "gs20", "font-scale-body, radar-hint", "path/to.tga", "my_id", "12", "#"):
            self.assertFalse(i18n.looks_like_text(s), s)


class ModTest(unittest.TestCase):
    def setUp(self):
        self.rep = i18n.analyze(FIXTURE, lint_info=True)

    def test_keys_and_params(self):
        keys = self.rep.keys
        self.assertEqual(keys[:4], ["Small", "Large", "Alpha row", "Beta row"])
        self.assertEqual(keys.count("Filter"), 1)
        self.assertEqual(keys[-4:], ["Display mode", "How %s is shown", "Off", "On"])
        self.assertEqual(self.rep.param_keys, 4)
        self.assertIn("A construction", keys)
        self.assertNotIn("Skipped: sqperf copy", keys)
        self.assertNotIn("size_param", keys)  # literals in a resource's params are not _() keys

    def test_language_report(self):
        langs = self.rep.langs
        self.assertEqual(list(langs)[:3], ["en", "ru", "de"])
        self.assertEqual(langs["en"].unused, ["SQ_ID_KEY"])
        self.assertEqual(langs["en"].redundant, ["Filter"])
        self.assertEqual(langs["en"].missing, [])
        self.assertEqual(langs["de"].unused, ["Stale key"])
        self.assertEqual(langs["de"].empty, ["On"])
        self.assertNotIn("On", langs["de"].missing)
        self.assertEqual(len(langs["fr"].missing), len(self.rep.keys))
        self.assertEqual([k for k, _ in langs["de"].placeholder], ["%d of %s"])  # order of printf tokens
        self.assertEqual([k for k, _ in langs["ru"].placeholder], ["{n} vehicles"])  # renamed named token
        self.assertTrue(self.rep.failed)

    def test_placeholders(self):
        self.assertIsNone(i18n.placeholder_problem("{a} and {b}", "{b} und {a}"))  # named: any order
        self.assertIsNone(i18n.placeholder_problem("%1% of %2%", "%2% von %1%"))
        self.assertIsNone(i18n.placeholder_problem("100%% at %.1f", "%.1f: 100%%"))
        self.assertIsNotNone(i18n.placeholder_problem("%d items", "items"))
        self.assertIsNone(i18n.placeholder_problem("50% sure", "zu 50% sicher"))  # a lone % is no token

    def test_en_needed_for_id_keys(self):
        rep = i18n.compare(["SQ_NAME", "Plain text"], {"en": {}, "de": {"SQ_NAME": "x", "Plain text": "y"}})
        self.assertEqual(rep["en"].missing, ["SQ_NAME"])
        self.assertEqual(rep["de"].missing, [])

    def test_modinfo_lint(self):
        problems = "\n".join(self.rep.modinfo)
        self.assertIn("lacks 10 languages", problems)
        self.assertIn("fr: name must be <= 32", problems)
        self.assertIn("fr: summary must be <= 100 chars, single line", problems)
        self.assertNotIn("de:", problems)

    def test_summary_line(self):
        line = i18n.summary_line(FIXTURE)
        self.assertTrue(line.startswith("translations: keys missing in ru (21), de (19), fr (23)"), line)
        self.assertIn("2 placeholder mismatches", line)
        with tempfile.TemporaryDirectory() as tmp:  # DEV/probe mods are never warned about
            probe = Path(tmp) / "square_x_probe"
            shutil.copytree(FIXTURE, probe)
            self.assertIsNone(i18n.summary_line(probe))


class CliTest(unittest.TestCase):
    def test_check_exit_code(self):
        code, out = run("--check", str(FIXTURE))
        self.assertEqual(code, 1)
        self.assertIn("[FAIL] square_fixture", out)
        self.assertEqual(run(str(FIXTURE))[0], 0)

    def test_missing(self):
        code, out = run("--missing", "de", str(FIXTURE))
        miss = json.loads(out)
        self.assertEqual(code, 0)
        self.assertEqual(miss["Small"], "Small")
        self.assertNotIn("Filter", miss)
        self.assertNotIn("On", miss)  # present, if empty
        self.assertEqual(next(iter(miss)), "Small")  # extraction order

    def test_json(self):
        data = json.loads(run("--json", str(FIXTURE))[1])
        self.assertEqual(data[0]["mod"], "square_fixture")
        self.assertEqual(len(data[0]["nonliteral"]), 3)
        self.assertEqual(data[0]["langs"]["de"]["unused"], ["Stale key"])

    def test_fix_format_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            mod = Path(tmp) / "square_fixture"
            shutil.copytree(FIXTURE, mod)
            before = json.loads((mod / "strings.json").read_text(encoding="utf-8"))
            run("--fix-format", str(mod))
            raw = (mod / "strings.json").read_bytes()
            self.assertFalse(raw.startswith(b"\xef\xbb\xbf"))
            self.assertTrue(raw.endswith(b"}\n"))
            text = raw.decode("utf-8")
            self.assertIn('    "en": {\n        "Filter"', text)
            self.assertIn("Фильтр", text)  # ensure_ascii=False
            after = json.loads(text)
            self.assertEqual(after, before)
            self.assertEqual(list(after), ["en", "ru", "de"])
            self.assertEqual(list(after["de"]), ["Filter", "{n} vehicles", "%d of %s", "On", "Stale key"])
            run("--fix-format", str(mod))
            self.assertEqual((mod / "strings.json").read_bytes(), raw)  # stable


if __name__ == "__main__":
    unittest.main()

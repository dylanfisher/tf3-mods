"""Unit tests for tools/more_from.py (no network: the profile page is a string, names a dict).

Run: make test-tools
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import more_from as mf  # noqa: E402

ENTRIES = [
    {"slug": "b", "modioId": 2, "logo": "0.3.png", "modId": "square_b"},
    {"slug": "a", "modioId": 1, "logo": "0.png", "modId": "square_a"},
    {"slug": "tx", "modioId": 4, "logo": "0.png", "modId": "square_names_us_texas"},
    {"slug": "c", "modioId": 3, "logo": "0.png", "modId": "square_c"},
    {"slug": "ak", "modioId": 5, "logo": "0.png", "modId": "square_names_us_alaska"},
]
NAMES = {"square_a": "A & Co", "square_b": "B", "square_c": "C",
         "square_names_us_texas": "Texas Towns & Streets", "square_names_us_alaska": "Alaska Towns & Streets"}
CONFIG = {
    "heading": "More from square",
    "groups": [
        {"title": "Top", "style": "tiles", "fixedOrder": True, "mods": ["square_a", "square_b"]},
        {"title": "Rest", "style": "tiles", "mods": ["square_c"]},
        {"title": "Towns & Streets", "style": "line", "labelStrip": " Towns & Streets", "mods": ["square_names_us_*"]},
    ],
}
DESC = "<p>Intro</p>\n<hr>\n<h2>Changelog</h2>\n<h4>Revision 1</h4>\n"


class MoreFromTest(unittest.TestCase):
    def render(self, host="square_x"):
        return mf.render_section(CONFIG, mf.resolve_groups(CONFIG, ENTRIES), host, NAMES.__getitem__)

    def test_parse_profile_takes_page_order_and_logo(self):
        dom = ('<a href="/g/transportfever3/m/b"><img src="https://thumb.modcdn.io/mods/c81e/2/crop_320x180/0.3.png"></a>'
               '<a href="/g/transportfever3/m/a"><img src="https://thumb.modcdn.io/mods/c4ca/1/crop_320x180/0.png"></a>'
               '<a href="/g/transportfever3/m/b">again</a>')
        self.assertEqual(mf.parse_profile(dom), [{"slug": "b", "modioId": 2, "logo": "0.3.png"},
                                                 {"slug": "a", "modioId": 1, "logo": "0.png"}])

    def test_fixed_order_group_and_profile_order_line(self):
        s = self.render()
        self.assertLess(s.index('alt="A &amp; Co"'), s.index('alt="B"'))  # fixed order, not profile order
        self.assertIn("thumb.modcdn.io/mods/c4ca/1/crop_640x360/0.png", s)  # md5("1")[:4]
        self.assertIn('width="200"', s)
        self.assertNotIn("style=", s)
        styled = mf.render_section({**CONFIG, "tileStyle": "margin-bottom:8px"}, mf.resolve_groups(CONFIG, ENTRIES),
                                   "square_x", NAMES.__getitem__)
        self.assertIn('width="200" style="margin-bottom:8px"', styled)
        self.assertLess(s.index(">Texas<"), s.index(">Alaska<"))  # profile order, label stripped
        self.assertIn("<strong>Towns &amp; Streets</strong>:", s)

    def test_host_left_out_and_empty_group_dropped(self):
        s = self.render("square_c")
        self.assertNotIn('alt="C"', s)
        self.assertNotIn("<strong>Rest</strong>", s)

    def test_unplaced_mod_is_an_error(self):
        with self.assertRaises(SystemExit):
            mf.resolve_groups(CONFIG, ENTRIES + [{"slug": "d", "modioId": 6, "logo": "0.png", "modId": "square_d"}])

    def test_apply_inserts_once_then_replaces(self):
        once = mf.apply_section(DESC, self.render())
        self.assertTrue(once.startswith("<p>Intro</p>\n<hr>\n<h4>More from square</h4>"))
        self.assertTrue(once.endswith(mf.CHANGELOG + "\n<h4>Revision 1</h4>\n"))
        self.assertEqual(mf.apply_section(once, self.render()), once)
        self.assertEqual(once.count("<h4>More from"), 1)


if __name__ == "__main__":
    unittest.main()

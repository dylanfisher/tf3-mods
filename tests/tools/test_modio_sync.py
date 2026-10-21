"""Unit tests for tools/modio_sync.py planning (no network: remote mods are dicts, downloads a fake).

Run: make test-tools
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import modio_sync as ms  # noqa: E402

ALL = set(ms.PARTS)


class PlanTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        mod = Path(self.tmp.name) / "square_x"
        meta = mod / "_metadata"
        meta.mkdir(parents=True)
        (meta / "mod.io_fileid.txt").write_text("123\n")
        (meta / "modinfo.json").write_text(json.dumps(
            {"name": "X", "summary": "Sum", "description": "plain", "tags": ["Script Mod"]}))
        (meta / "description.html").write_text("<p>Hi</p>")
        for name in ("0.png", "1.png", "2.png", "10.png"):
            (meta / name).write_bytes(name.encode())
        self.local = ms.load_local(mod)
        self.urls = {"L": b"0.png", "A": b"1.png", "B": b"2.png", "C": b"10.png"}
        self.fetched = []

    def tearDown(self):
        self.tmp.cleanup()

    def fetch(self, url):
        self.fetched.append(url)
        return self.urls[url]

    def remote(self, **over):
        r = {
            "name": "X", "summary": "Sum", "description": "<p>Hi</p>",
            "tags": [{"name": "Script Mod"}],
            "logo": {"filename": "0.png", "original": "L"},
            "media": {"images": [{"filename": n, "original": u} for n, u in
                                 (("1.png", "A"), ("2.png", "B"), ("10.png", "C"))]},
        }
        r.update(over)
        return r

    def plan(self, remote, state=None, parts=ALL, force=False):
        return ms.make_plan(self.local, remote, state or {}, parts, force, self.fetch)

    def test_load_local(self):
        self.assertEqual(self.local.modio_id, 123)
        self.assertEqual(self.local.text["description"], "<p>Hi</p>")
        self.assertEqual([p.name for p in self.local.images], ["1.png", "2.png", "10.png"])

    def test_in_sync_by_download_then_by_record(self):
        remote = self.remote()
        self.assertTrue(self.plan(remote).empty(False))
        self.assertEqual(len(self.fetched), 4)
        state = ms.record_state(self.local, remote, ALL, {})
        self.fetched.clear()
        self.assertTrue(self.plan(remote, state).empty(False))
        self.assertEqual(self.fetched, [])

    def test_text_rewritten_by_modio_counts_as_synced(self):
        remote = self.remote(description="<p class=\"x\">Hi</p>")
        self.assertEqual(self.plan(remote).text, {"description": "<p>Hi</p>"})
        state = ms.record_state(self.local, remote, {"text"}, {})
        self.assertEqual(self.plan(remote, state, {"text"}).text, {})

    def test_base_name(self):
        self.assertEqual(ms.base_name("1.1.png"), "1.png")
        self.assertEqual(ms.base_name("10.23.png"), "10.png")
        self.assertEqual(ms.base_name("3.png"), "3.png")
        self.assertEqual(ms.base_name("cover.1.png"), "cover.1.png")
        self.assertEqual(ms.base_name("4-a78c3aa9.png"), "4.png")
        self.assertEqual(ms.base_name("4-a78c3aa9.2.png"), "4.png")
        up = ms.upload_name(self.local.images[0])
        self.assertRegex(up, r"^1-[0-9a-f]{8}\.png$")
        self.assertEqual(ms.base_name(up), "1.png")

    def test_gallery_renamed_by_modio_in_sync(self):
        images = [{"filename": n, "original": u} for n, u in (("1.1.png", "A"), ("2.3.png", "B"), ("10.1.png", "C"))]
        remote = self.remote(media={"images": images})
        self.assertFalse(self.plan(remote, parts={"gallery"}).gallery)
        state = ms.record_state(self.local, remote, {"gallery"}, {})
        self.assertEqual([i["remote"] for i in state["images"]], ["1.1.png", "2.3.png", "10.1.png"])
        self.fetched.clear()
        self.assertFalse(self.plan(remote, state, {"gallery"}).gallery)
        self.assertEqual(self.fetched, [])

    def test_gallery_out_of_order(self):
        images = [{"filename": n, "original": u} for n, u in (("2.1.png", "B"), ("1.1.png", "A"), ("10.1.png", "C"))]
        self.assertTrue(self.plan(self.remote(media={"images": images}), parts={"gallery"}).gallery)

    def test_whitespace_only_difference(self):
        self.local.text["description"] = "<p>Hi</p>  \r\n<p>B</p>\n"
        self.assertEqual(self.plan(self.remote(description="<p>Hi</p>\n<p>B</p>"), parts={"text"}).text, {})

    def test_escaped_name(self):
        self.local.text["name"] = "Towns & Streets"
        self.assertEqual(self.plan(self.remote(name="Towns &amp; Streets"), parts={"text"}).text, {})

    def test_text_diff(self):
        lines = ms.text_diff(self.local, self.remote(description="<p>Old</p>"), "description")
        self.assertIn("-<p>Old</p>", lines)
        self.assertIn("+<p>Hi</p>", lines)

    def test_release_zip_and_compare(self):
        mod = self.local.path
        (mod / "mod.json").write_text('{"revision": 3}')
        (mod / "content").mkdir()
        (mod / "content" / "a.lua").write_text("a")
        (mod / "content" / "b.lua").write_text("b-new")
        (mod / "content" / "c.lua").write_text("c")
        zpath = Path(self.tmp.name) / "live.zip"
        import zipfile
        with zipfile.ZipFile(zpath, "w") as z:
            z.writestr("square_x/mod.json", '{\n  "revision": 2\n}')
            z.writestr("square_x/content/a.lua", "a")
            z.writestr("square_x/content/b.lua", "b-old")
            z.writestr("square_x/strings.json", "{}")
            z.writestr("square_x/_metadata/1.png", "old slide")
        live, mod_json = ms.zip_files(zpath)
        self.assertEqual(mod_json["revision"], 2)
        self.assertIn("content/a.lua", live)
        rel = ms.compare_release(ms.local_files(mod), live, 2, 3)
        self.assertEqual(rel.changed, ["content/b.lua", "mod.json"])
        self.assertEqual(rel.added, ["content/c.lua"])
        self.assertIn("strings.json", rel.removed)
        self.assertIn("_metadata/1.png", rel.profile)
        self.assertNotIn("_metadata/mod.io_fileid.txt", ms.local_files(mod))
        self.assertEqual(ms.ReleaseRow("m", rel=rel).status, "update")
        self.assertEqual(ms.ReleaseRow("m", rel=ms.compare_release({"x": "1"}, {"x": "2"}, 2, 2)).status, "bump")
        same = ms.compare_release({"x": "1"}, {"x": "1", "strings.json": "s"}, 2, 2)
        self.assertEqual(ms.ReleaseRow("m", rel=same).status, "ok")

    def test_render_release(self):
        rows = [
            ms.ReleaseRow("square_a", "2026-10-09", ms.compare_release({"x": "1", "y": "1"}, {"x": "2"}, 2, 3)),
            ms.ReleaseRow("square_b", "2026-10-08", ms.compare_release({"x": "1"}, {"x": "2"}, 2, 2)),
            ms.ReleaseRow("square_c", "2026-10-08", ms.compare_release({"x": "1"}, {"x": "1"}, 1, 1)),
            ms.ReleaseRow("square_d", error="HTTP 500"),
            ms.ReleaseRow("square_e", "2026-10-10", ms.compare_release({"x": "1"}, {"x": "2"}, 1, 2), pending=True),
        ]
        out = "\n".join(ms.render_release(rows, verbose=False, color=False))
        self.assertIn("Needs a Hub update (1)", out)
        self.assertIn("square_a  2 -> 3", out)
        self.assertIn("1 changed, 1 new", out)
        self.assertIn("Changed, revision not bumped (1)", out)
        self.assertIn("Up to date (1)\n  square_c", out)
        self.assertIn("square_d  HTTP 500", out)
        self.assertIn("Uploaded, waiting for mod.io (1)", out)
        self.assertEqual(rows[4].status, "pending")
        self.assertIn("2 of 5 mod(s) need a Hub update.", out)
        self.assertNotIn("\033[", out)

    def test_render_release_newer_upload_not_live(self):
        row = ms.ReleaseRow("square_f", "2026-10-18", ms.compare_release({"x": "1"}, {"x": "2"}, 9, 11),
                            newer="rev 11 (2026-10-20) rejected by mod.io review")
        out = "\n".join(ms.render_release([row], verbose=False, color=False))
        self.assertIn("square_f  9 -> 11", out)
        self.assertIn("newer upload not live: rev 11 (2026-10-20) rejected by mod.io review; live is still rev 9", out)

    def test_newer_note_same_revision_is_another_platform_copy(self):
        self.assertEqual(ms.newer_note(8, 8, "2026-10-18", {"platforms": [{"platform": "ps5", "status": 1}]}), "")
        self.assertEqual(ms.newer_note(9, 11, "2026-10-20", {"platforms": [{"platform": "windows", "status": 2}]}),
                         "rev 11 (2026-10-20) rejected by mod.io review")

    def test_modfile_state(self):
        self.assertEqual(ms.modfile_state({"platforms": [{"platform": "ps5", "status": 0},
                                                         {"platform": "windows", "status": 2}]}),
                         "rejected by mod.io review")
        self.assertEqual(ms.modfile_state({"platforms": [{"platform": "mac", "status": 0}]}), "waiting for mod.io review")
        self.assertEqual(ms.modfile_state({}), "not live")

    def test_live_modfile_id(self):
        self.assertEqual(ms.live_modfile_id({"modfile": None, "platforms": [
            {"platform": "ps5", "modfile_live": 7}, {"platform": "windows", "modfile_live": 8},
            {"platform": "mac", "modfile_live": 0}]}), (8, "windows"))
        self.assertEqual(ms.live_modfile_id({"platforms": [{"platform": "ps5", "modfile_live": 7}]}), (7, "ps5"))
        self.assertEqual(ms.live_modfile_id({"modfile": {"id": 5}, "platforms": []}), (5, None))
        self.assertEqual(ms.live_modfile_id({"modfile": None}), (None, None))

    def test_mod_json_formatting_ignored(self):
        self.assertEqual(ms.file_key("mod.json", b'{"a":1,"b":2}'), ms.file_key("mod.json", b'{\n "b": 2,\n "a": 1\n}'))

    def test_tags(self):
        p = self.plan(self.remote(tags=[{"name": "Misc"}]), parts={"tags"})
        self.assertEqual((p.tags_add, p.tags_extra), (["Script Mod"], ["Misc"]))
        self.assertFalse(p.empty(False))
        p = self.plan(self.remote(tags=[{"name": "Script Mod"}, {"name": "Misc"}]), parts={"tags"})
        self.assertTrue(p.empty(False))
        self.assertFalse(p.empty(True))

    def test_gallery_extra_remote_image(self):
        images = self.remote()["media"]["images"] + [{"filename": "3.png", "original": "A"}]
        p = self.plan(self.remote(media={"images": images}), parts={"gallery"})
        self.assertTrue(p.gallery)
        self.assertEqual(self.fetched, [])

    def test_no_slides_cover_copy_is_in_sync(self):
        for p in self.local.images:
            p.unlink()
        self.local.images = []
        cover = self.remote(media={"images": [{"filename": "0.3.png", "original": "L"}]})
        self.assertFalse(self.plan(cover, parts={"gallery"}).gallery)
        other = self.remote(media={"images": [{"filename": "5.1.png", "original": "A"}]})
        self.assertTrue(self.plan(other, parts={"gallery"}).gallery)

    def test_gallery_changed_slide(self):
        self.urls["B"] = b"old"
        self.assertTrue(self.plan(self.remote(), parts={"gallery"}).gallery)

    def test_changed_slide_after_record(self):
        remote = self.remote()
        state = ms.record_state(self.local, remote, ALL, {})
        (self.local.images[0]).write_bytes(b"new")
        self.urls["A"] = b"stale"
        self.assertTrue(self.plan(remote, state, {"gallery"}).gallery)

    def test_logo(self):
        self.urls["L"] = b"old"
        self.assertTrue(self.plan(self.remote(), parts={"logo"}).logo)
        self.assertTrue(self.plan(self.remote(logo=None), parts={"logo"}).logo)

    def test_force(self):
        p = self.plan(self.remote(), parts={"logo", "gallery"}, force=True)
        self.assertTrue(p.logo and p.gallery)

    def test_synced_date_only_on_change(self):
        remote = self.remote()
        first = ms.record_state(self.local, remote, ALL, {})
        self.assertIn("synced", first)
        first["synced"] = "2000-01-01"
        self.assertEqual(ms.record_state(self.local, remote, ALL, first)["synced"], "2000-01-01")

    def test_rate_limit_info(self):
        raw = b'{"error": {"code": 429, "error_ref": 11009, "message": "Too many requests to this endpoint."}}'
        wait, lines = ms.rate_limit_info("POST", "/games/10640/mods/6433435/media", {"retry-after": "0", "X-RateLimit-Remaining": "0"}, raw)
        self.assertEqual(wait, 60)
        self.assertEqual(ms.rate_limit_info("POST", "/x", {"retry-after": "0"}, raw, attempt=2)[0], 240)
        self.assertEqual(ms.rate_limit_info("POST", "/x", {}, raw, attempt=9)[0], 600)
        self.assertIn("endpoint: POST /media", lines)
        self.assertIn("error_ref 11009: this endpoint only: other requests still work", lines)
        self.assertIn("message: Too many requests to this endpoint.", lines)
        self.assertIn("X-RateLimit-Remaining: 0", lines)
        wait, lines = ms.rate_limit_info("GET", "/games/10640/mods/1", {"retry-after": "17"}, b"")
        self.assertEqual(wait, 17)
        self.assertIn("retry-after: 17 s", lines)

    def test_multipart(self):
        body, ctype = ms._multipart([("sync", "true")], [("image1", "1.png", b"\x89PNG")])
        boundary = ctype.split("boundary=")[1]
        self.assertIn(b'name="sync"\r\n\r\ntrue\r\n', body)
        self.assertIn(b'filename="1.png"', body)
        self.assertTrue(body.endswith(f"--{boundary}--\r\n".encode()))


if __name__ == "__main__":
    unittest.main()

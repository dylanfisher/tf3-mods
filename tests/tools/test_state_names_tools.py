"""Unit tests for the US State Names generator tools (tools/state_towns.py, tools/gen_state_mod.py).

Run: make test-tools   (uv run --with lupa python -m unittest discover -s tests/tools)
Synthetic Census files in a temp dir; nothing is downloaded.
"""

from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import gen_state_mod as gen  # noqa: E402
import state_towns as st  # noqa: E402


class LsadTest(unittest.TestCase):
    def test_suffixes(self):
        cases = {
            "Seattle city": ("Seattle", "city"),
            "Juneau city and borough": ("Juneau", "city and borough"),
            "Anchorage municipality": ("Anchorage", "municipality"),
            "Kodiak Station CDP": ("Kodiak Station", "CDP"),
            "Bloomsburg town": ("Bloomsburg", "town"),
            "State College borough": ("State College", "borough"),
            "Charles Town city": ("Charles Town", "city"),
            "Indianapolis city (balance)": ("Indianapolis", "city"),
            "Athens-Clarke County unified government (balance)": ("Athens-Clarke County", "unified government"),
            "Augusta-Richmond County consolidated government (balance)":
                ("Augusta-Richmond County", "consolidated government"),
            "Nashville-Davidson metropolitan government (balance)": ("Nashville-Davidson", "metropolitan government"),
            "Louisville/Jefferson County metro government (balance)":
                ("Louisville/Jefferson County", "metro government"),
            "Lexington-Fayette urban county": ("Lexington-Fayette", "urban county"),
            "Butte-Silver Bow (balance)": ("Butte-Silver Bow", "balance"),
            "Anaconda-Deer Lodge County": ("Anaconda-Deer Lodge County", "?"),
        }
        for full, want in cases.items():
            self.assertEqual(st.strip_lsad(full), want, full)

    def test_longest_first(self):
        lens = [len(s) for s in st.LSAD_SUFFIXES]
        self.assertEqual(lens, sorted(lens, reverse=True))


class GeometryTest(unittest.TestCase):
    SQUARE = [[30, -100], [30, -90], [20, -90], [20, -100]]

    def test_point_in_polygon(self):
        self.assertTrue(st.point_in_polygon(25, -95, self.SQUARE))
        self.assertFalse(st.point_in_polygon(35, -95, self.SQUARE))
        self.assertFalse(st.point_in_polygon(25, -85, self.SQUARE))
        closed = self.SQUARE + [self.SQUARE[0]]
        self.assertTrue(st.point_in_polygon(25, -95, closed))
        # concave: an L shape without its top-right quarter
        ell = [[0, 0], [0, 10], [5, 10], [5, 5], [10, 5], [10, 0]]
        self.assertTrue(st.point_in_polygon(2, 8, ell))
        self.assertFalse(st.point_in_polygon(8, 8, ell))

    def test_region_first_match_and_default(self):
        regions = [{"tag": "a", "polygon": self.SQUARE}, {"tag": "b", "polygon": [[40, -110], [40, -80], [10, -80], [10, -110]]}]
        self.assertEqual(st.region_of(25, -95, regions, "z"), "a")
        self.assertEqual(st.region_of(35, -95, regions, "z"), "b")
        self.assertEqual(st.region_of(50, -95, regions, "z"), "z")
        self.assertIsNone(st.region_of(50, -95, regions, None))

    def test_rules(self):
        self.assertTrue(st.rule_matches({"tag": "t", "latLt": 29.0, "lonGe": -83.6}, "x", 28.0, -80.0))
        self.assertFalse(st.rule_matches({"tag": "t", "latLt": 29.0}, "x", 29.0, -80.0))
        self.assertFalse(st.rule_matches({"tag": "t", "lonGe": -83.6}, "x", 28.0, -84.0))
        self.assertTrue(st.rule_matches({"tag": "t", "lonLt": -83.6, "latGe": 29.6}, "x", 30.0, -85.0))
        self.assertFalse(st.rule_matches({"tag": "t", "side": "east"}, "west", 30.0, -85.0))


class CountyTest(unittest.TestCase):
    def test_county_key(self):
        self.assertEqual(st.county_key("Monroe County"), "monroe")
        self.assertEqual(st.county_key("Monroe"), "monroe")
        self.assertEqual(st.county_key("Juneau City and Borough"), "juneau")
        self.assertEqual(st.county_key("Kodiak Island Borough"), "kodiak island")
        self.assertEqual(st.county_key("Bethel Census Area"), "bethel")
        self.assertEqual(st.county_key("Orleans Parish"), "orleans")

    def test_largest_part(self):
        rows = [
            {"COUNTYFP": "001", "COUNTYNAME": "Alpha County", "PLACEFP": "11111"},
            {"COUNTYFP": "003", "COUNTYNAME": "Beta County", "PLACEFP": "11111"},
            {"COUNTYFP": "003", "COUNTYNAME": "Beta County", "PLACEFP": "22222"},
            {"COUNTYFP": "005", "COUNTYNAME": "Gamma County", "PLACEFP": "33333"},
        ]
        baf = ["BLOCKID|PLACEFP", "120019501001000|11111", "120039501001001|11111", "120039501001002|11111",
               "120039501001003|22222", "120019501001004|"]
        got = st.place_counties(rows, baf)
        self.assertEqual(got["11111"], "Beta County", "two of three blocks in Beta")
        self.assertEqual(got["22222"], "Beta County")
        self.assertEqual(got["33333"], "Gamma County", "missing from the block file: first listed county")


def write_census(root: Path, fips: str, postal: str) -> None:
    """Minimal Gazetteer 2023, popest 2023, Gazetteer 2010 and county files for draft_rows."""
    gaz = ["USPS\tGEOID\tANSICODE\tNAME\tLSAD\tFUNCSTAT\tALAND\tAWATER\tALAND_SQMI\tAWATER_SQMI\tINTPTLAT\tINTPTLONG"]
    places = [
        ("00100", "Big city", "25", 25.0, -95.0), ("00200", "Juneau city and borough", "25", 35.0, -95.0),
        ("00300", "Keyport CDP", "57", 24.6, -81.5), ("00400", "Urban Honolulu CDP", "57", 21.3, -157.8),
        ("00500", "Oddplace", "00", 25.1, -95.1), ("00600", "Kept city (balance)", "25", 25.2, -95.2),
    ]
    for code, name, lsad, lat, lon in places:
        gaz.append(f"{postal}\t{fips}{code}\t0\t{name}\t{lsad}\tA\t0\t0\t0\t0\t{lat}\t{lon}")
    d = root / f"gaz2023_place_{fips}"
    d.mkdir(parents=True)
    (d / "gaz.txt").write_text("\n".join(gaz) + "\n", encoding="utf-8")
    pop = ["SUMLEV,STATE,COUNTY,PLACE,NAME,POPESTIMATE2023",
           f"162,{int(fips)},0,100,Big city,90000", f"162,{int(fips)},0,200,Juneau city and borough,30000",
           f"162,{int(fips)},0,500,Oddplace,10", f"162,{int(fips)},0,600,Kept city (balance),500"]
    d = root / f"popest2023_{fips}"
    d.mkdir(parents=True)
    (d / f"sub-est2023_{fips}.csv").write_text("\n".join(pop) + "\n", encoding="latin-1")
    g10 = ["USPS\tGEOID\tANSICODE\tNAME\tPOP10", f"{postal}\t{fips}00300\t0\tKeyport CDP\t900",
           f"{postal}\t{fips}00400\t0\tUrban Honolulu CDP\t300000"]
    d = root / "gaz2010_places_extracted"
    d.mkdir(parents=True)
    (d / f"gaz2010_{postal.lower()}.txt").write_text("\n".join(g10) + "\n", encoding="utf-8")
    d = root / f"placecou2020_{fips}"
    d.mkdir(parents=True)
    (d / "place_by_county.txt").write_text(
        "STATE|STATEFP|COUNTYFP|COUNTYNAME|PLACEFP|PLACENS|PLACENAME|TYPE|CLASSFP|FUNCSTAT\n"
        f"{postal}|{fips}|087|Monroe County|00300|0|Keyport CDP|CDP|U1|S\n"
        f"{postal}|{fips}|001|Alpha County|00100|0|Big city|INCORPORATED PLACE|C1|A\n", encoding="utf-8")
    d = root / f"baf2020_{fips}"
    d.mkdir(parents=True)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr(f"BlockAssign_ST{fips}_{postal}_INCPLACE_CDP.txt",
                   f"BLOCKID|PLACEFP\n{fips}0879501001000|00300\n{fips}0019501001000|00100\n")
    (d / f"BlockAssign_ST{fips}_{postal}.zip").write_bytes(buf.getvalue())


class DraftTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.old = st.CENSUS
        st.CENSUS = Path(self.tmp.name)
        write_census(st.CENSUS, "12", "FL")
        self.cfg = {
            "fips": "12", "postal": "FL", "gazetteerYear": 2023, "popestYear": 2023, "bigCount": 2, "cdpMinPop": 300,
            "regions": [{"tag": "north", "polygon": [[40, -100], [40, -90], [30, -90], [30, -100]]}],
            "defaultTag": "south",
            "rules": [{"tag": "low", "latLt": 25.05, "side": "south"}],
            "countyTags": {"keys": ["Monroe"]},
            "rename": {"Urban Honolulu": "Honolulu"},
        }

    def tearDown(self):
        st.CENSUS = self.old
        self.tmp.cleanup()

    def rows(self, **over):
        rows, warnings = st.draft_rows("zz", {**self.cfg, **over})
        return {r["name"]: r for r in rows}, warnings

    def test_regions_counties_lsad(self):
        rows, warnings = self.rows()
        self.assertEqual(rows["Juneau"]["tags"], ["north", "big"])
        self.assertEqual(rows["Big"]["tags"], ["south", "low", "big"])
        self.assertEqual(rows["Keyport"]["tags"], ["south", "low", "keys"])
        self.assertIn("Kept", rows)
        self.assertIn("Honolulu", rows)
        self.assertTrue(any("unknown LSAD suffix" in w and "Oddplace" in w for w in warnings), warnings)
        self.assertFalse(any("Kept" in w and "LSAD" in w for w in warnings), "a balance name is a known form")

    def test_unknown_suffix_accepted_by_rename(self):
        _, warnings = self.rows(rename={"Urban Honolulu": "Honolulu", "Oddplace": "Oddplace"})
        self.assertFalse(any("unknown LSAD" in w for w in warnings), warnings)

    def test_big_includes_cdp(self):
        rows, _ = self.rows()
        self.assertNotIn("big", rows["Honolulu"]["tags"])
        rows, _ = self.rows(bigIncludesCdp=True)
        self.assertIn("big", rows["Honolulu"]["tags"])
        self.assertNotIn("big", rows["Juneau"]["tags"], "bigCount 2: Honolulu and Big")

    def test_inc_min_pop(self):
        rows, warnings = self.rows(incMinPop=1000)
        self.assertNotIn("Kept", rows, "500 < 1000")
        self.assertNotIn("Oddplace", rows)
        self.assertIn("Big", rows)
        self.assertIn("Keyport", rows, "CDPs follow cdpMinPop, not incMinPop")
        rows, _ = self.rows(incMinPop={"south": 1000}, keepTown=["Oddplace"])
        self.assertNotIn("Kept", rows, "Kept is south")
        self.assertIn("Oddplace", rows, "keepTown is exempt")
        rows, _ = self.rows(incMinPop={"north": 1000})
        self.assertIn("Kept", rows, "no floor for an unlisted tag")
        _, warnings = self.rows(keepTown=["Nowhere"])
        self.assertTrue(any("Nowhere" in w for w in warnings), warnings)

    def test_cdp_min_pop_per_region(self):
        rows, _ = self.rows(cdpMinPop={"south": 10**9})
        self.assertNotIn("Keyport", rows, "Keyport is a south CDP")
        rows, _ = self.rows(cdpMinPop={"north": 10**9})
        self.assertIn("Keyport", rows, "no floor for an unlisted tag")

    def test_rename_geoid(self):
        rows, warnings = self.rows(renameGeoid={"1200300": "Keyport-Kona", "1299999": "Ghost"},
                                   keepCdp=["Keyport-Kona"])
        self.assertIn("Keyport-Kona", rows)
        self.assertNotIn("Keyport", rows)
        rows, _ = self.rows(renameGeoid={"1200300": "Keyport-Kona"})
        self.assertNotIn("Keyport-Kona", rows, "the hyphen filter still applies (keepCdp the new name)")
        self.assertTrue(any("1299999" in w for w in warnings), warnings)
        rows, _ = self.rows(renameGeoid={"1200300": "Ike"}, rename={"Ike": "Mike", "Urban Honolulu": "Honolulu"})
        self.assertIn("Mike", rows, "rename applies after renameGeoid")

    def test_crest_plus_regions(self):
        rows, _ = self.rows(crest=[[20, -96], [40, -96]])
        self.assertEqual(rows["Juneau"]["tags"][:2], ["east", "north"])
        self.assertEqual(rows["Keyport"]["tags"][:2], ["east", "south"])

    def test_geojson(self):
        rows, _ = st.draft_rows("zz", self.cfg)
        gj = json.loads(st.geojson(self.cfg, rows))
        polys = [f for f in gj["features"] if f["geometry"]["type"] == "Polygon"]
        pts = [f for f in gj["features"] if f["geometry"]["type"] == "Point"]
        self.assertEqual(len(polys), 1)
        ring = polys[0]["geometry"]["coordinates"][0]
        self.assertEqual(ring[0], ring[-1])
        self.assertEqual(ring[0], [-100, 40], "GeoJSON is [lon, lat]")
        self.assertEqual(len(pts), len(rows))


class GenTest(unittest.TestCase):
    def test_to_ascii_and_normalize(self):
        self.assertEqual(gen.to_ascii("Cañon City"), "Canon City")
        self.assertEqual(gen.to_ascii("Utqiaġvik"), "Utqiagvik")
        self.assertEqual(gen.to_ascii("Doña Ana"), "Dona Ana")
        self.assertEqual(gen.to_ascii("Hawaiʻi Kai"), "Hawaii Kai")
        self.assertEqual(gen.to_ascii("Browne’s Addition"), "Browne's Addition")
        self.assertEqual(gen.to_ascii("Łódź"), "Lodz")
        self.assertEqual(gen.normalize("Hawai‘i  Kai"), "hawaii kai")
        self.assertEqual(gen.normalize("Tōkyō 東京"), "tokyo")

    def test_climate_sentence(self):
        state = {"climates": {"temperate": {"high": 70, "sky": 30, "desert": 0}, "dry": {"desert": 75, "sky": 10, "high": 15},
                              "subarctic": {"high": 100}},
                 "regionLabels": {"high": "the high country", "desert": "the low desert"}}
        s = gen.climate_sentence(state)
        self.assertIn("Temperate maps: mostly the high country, plus sky.", s)
        self.assertIn("Dry maps: mostly the low desert, plus the high country and sky.", s)
        self.assertIn("Subarctic maps: the high country.", s)
        self.assertIn("Tropical maps and climates from other mods use the whole state.", s)
        self.assertEqual(gen.climate_sentence({}), "")

    def test_counts(self):
        self.assertEqual(gen.count_of(1, "ferry terminals"), "1 ferry terminal")
        self.assertEqual(gen.count_of(3, "ports"), "3 ports")
        self.assertEqual(gen.join_and(["a", "b", "c"]), "a, b and c")
        self.assertEqual(gen.join_and(["a"]), "a")

    def test_description_without_harbours_or_neighbourhoods(self):
        state = {"key": "us_zz", "name": "Zed", "setName": "Zed (Towns & Streets)", "harborWord": "ports",
                 "examples": {"stops": "Main Street", "stations": "Union Station"},
                 "climates": {"dry": {"desert": 1}}, "changelog": []}
        towns = [{"n": "Alpha", "t": ["desert"], "p": 100}, {"n": "Beta", "t": ["desert"], "p": 50}]
        cities = {"Alpha": {"streets": ["Main Street"], "rail": ["Union Station"], "airport": ["Alpha Airport"]}}
        text = gen.description(state, towns, cities, ["Oak Street"])
        self.assertIn("real names for train stations and airports.", text)
        self.assertIn("(1 rail station, 1 airport)", text)
        self.assertNotIn(" ports", text.split("Settings")[0])
        self.assertNotIn("Neighbourhood names", text)
        self.assertNotIn("ferry", text)
        self.assertIn("from big cities to small towns", text)
        self.assertIn("in the local style.</li>", text)
        cities = {"Alpha": {"streets": ["Main Street"]}}
        text = gen.description(state, towns, cities, ["Oak Street"])
        self.assertNotIn("Real station names</strong>: new", text)
        self.assertIn("2 real towns from Alpha to Beta, and real streets for your bus stops.", text)
        self.assertIn("carry a Zed city's name", text)
        text = gen.description(dict(state, name="Arizona"), towns, cities, ["Oak Street"])
        self.assertIn("carry an Arizona city's name", text)
        towns3 = towns + [{"n": "Gamma", "t": ["desert"], "p": 10}]
        text = gen.description(dict(state, introTowns=["Alpha", "Gamma"]), towns3, cities, ["Oak Street"])
        self.assertIn("3 real towns from Alpha to Gamma", text)
        with self.assertRaises(SystemExit):
            gen.description(dict(state, introTowns=["Alpha", "Nowhere"]), towns3, cities, ["Oak Street"])

    def test_ascii_fallback_and_floors(self):
        tmp = tempfile.TemporaryDirectory()
        old = gen.DATA_DIR
        try:
            d = Path(tmp.name) / "us_zz"
            d.mkdir()
            (d / "state.lua").write_text(
                'return { key = "us_zz", name = "Zed", setName = "Zed (Towns & Streets)", modName = "Zed Towns & Streets",\n'
                ' summary = "Real Zed towns, plus real local names for the stops and stations you build.", revision = 1, changelog = {}, asciiFallback = true,\n'
                ' minTowns = 2, minPool = 1, minStreetCities = 1,\n'
                ' examples = { stops = "Peña Street", stations = "Cañon Depot" },\n'
                ' climates = { dry = { desert = 1 } } }\n', encoding="utf-8")
            (d / "towns.tsv").write_text("name\ttags\tpopulation\tlat\tlon\tnote\nCañon City\tdesert\t100\t0\t0\tn\n"
                                         "Utqiaġvik\tdesert\t50\t0\t0\tn\n", encoding="utf-8")
            (d / "streets.lua").write_text('return { "Oak Street", "Mesa Drive" }\n', encoding="utf-8")
            (d / "cities.lua").write_text('-- Cañon City — comment\nreturn { ["Cañon City"] = { streets = { "Peña Street" },'
                                          ' rail = { "Cañon Depot" } } }\n', encoding="utf-8")
            gen.DATA_DIR = d.parent
            gen.all_claims.cache_clear()
            mod_id, files, errors = gen.render("us_zz")
            self.assertEqual(errors, [])
            by_name = {p.name: t for p, t in files.items()}
            self.assertIn('"Canon City"', by_name["towns.lua"])
            self.assertIn('"Utqiagvik"', by_name["towns.lua"])
            self.assertIn('["Canon City"]', by_name["cities.lua"])
            self.assertIn('"Pena Street"', by_name["cities.lua"])
            self.assertIn("like Pena Street", by_name["description.html"])
            self.assertNotIn("ñ", by_name["description.html"])
            # SQPERF: the copy tools/sqperf_sync.py would write, and the debug param after the two saved ones
            mod_dir = gen.MODS_DIR / mod_id
            self.assertEqual(files[mod_dir / "content" / "sqperf" / f"{mod_id}.lua"].encode("utf-8"),
                             (gen.ROOT / "tools" / "sqperf" / "sqperf.lua").read_bytes())
            self.assertIn("record SquareNamesUsZzSqPerf", files[mod_dir / "content" / "sqperf" / f"{mod_id}_types.d.tl"])
            params = json.loads(files[mod_dir / "mod.json"])["params"]
            self.assertEqual([p["key"] for p in params], ["streetNames", "stationNames", "sqperf_log"])
            self.assertEqual(params[2]["values"], ["Off", "On"])
            # i18n: every game language; the set name keeps the state name; keys in tools/i18n.py's order
            strings = json.loads(files[mod_dir / "strings.json"])
            self.assertEqual(list(strings), list(gen.LANGS[1:]))
            self.assertEqual(strings["de"]["Zed (Towns & Streets)"], "Zed (Orte & Strassen)")
            self.assertEqual(list(strings["ru"])[:2], ["Zed (Towns & Streets)", "Real street names"])
            loc = json.loads(files[mod_dir / "_metadata" / "modinfo.json"])["localization"]
            self.assertEqual(sorted(loc), sorted(gen.LANGS[1:]))
            self.assertEqual(loc["fr"]["name"], "Zed : villes et rues")
            (d / "state.lua").write_text((d / "state.lua").read_text(encoding="utf-8").replace("minTowns = 2", "minTowns = 3"),
                                         encoding="utf-8")
            _, _, errors = gen.render("us_zz")
            self.assertTrue(any("want >= 3" in e for e in errors), errors)
        finally:
            gen.DATA_DIR = old
            gen.all_claims.cache_clear()
            tmp.cleanup()

    def test_contested(self):
        tmp = tempfile.TemporaryDirectory()
        old = gen.DATA_DIR
        try:
            root = Path(tmp.name)
            for key, pop, alias in (("us_oregon", 650000, None), ("us_maine", 68000, "Portland City"),
                                    ("us_zz", 1, None)):
                d = root / key
                d.mkdir()
                (d / "state.lua").write_text(f'return {{ key = "{key}" }}\n', encoding="utf-8")
                name = "Salem" if key == "us_zz" else "Portland"
                (d / "towns.tsv").write_text(f"name\ttags\tpopulation\tlat\tlon\tnote\n{name}\tx\t{pop}\t0\t0\tn\n"
                                             f"Salem\tx\t{pop // 2}\t0\t0\tn\n", encoding="utf-8")
                aliases = f', aliases = {{ "{alias}" }}' if alias else ""
                (d / "cities.lua").write_text(f'return {{ ["{name}"] = {{ streets = {{ "A" }}{aliases} }},'
                                              f' ["Salem"] = {{ streets = {{ "B" }} }} }}\n', encoding="utf-8")
            gen.DATA_DIR = root
            gen.all_claims.cache_clear()
            self.assertEqual(gen.contested_map("us_maine"), {"portland": "square_names_us_oregon",
                                                             "salem": "square_names_us_oregon"})
            # us_zz's Salem has towns.tsv population 0 (1 // 2): Oregon (325000) wins
            self.assertEqual(gen.contested_map("us_zz"), {"salem": "square_names_us_oregon"})
            lua = gen.contested_lua("us_maine", gen.contested_map("us_maine"))
            self.assertIn('["portland"] = "square_names_us_oregon",', lua)
            self.assertEqual(gen.contested_map("us_nowhere"), {})
        finally:
            gen.DATA_DIR = old
            gen.all_claims.cache_clear()
            tmp.cleanup()


if __name__ == "__main__":
    unittest.main()

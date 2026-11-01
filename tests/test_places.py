"""The bundled city list is searched offline, without regard to accents; a location in the settings is checked (no display needed)."""
import json
import unittest
import reader

class CityTests(unittest.TestCase):
    def test_small_with_credit_and_every_time_zone_is_real(self):
        path=reader.ROOT/"data"/"cities.json"
        self.assertLess(path.stat().st_size,1_500_000)
        data=json.loads(path.read_text()); self.assertIn("CC BY 4.0",data["credit"]); self.assertIn("GeoNames",data["credit"])
        self.assertTrue(all(reader.badi.valid_zone(zone) for zone in data["zones"]))
        self.assertIn("GeoNames",(reader.ROOT/"DATA-NOTICE.md").read_text()); self.assertIn("creativecommons.org/licenses/by/4.0",(reader.ROOT/"DATA-NOTICE.md").read_text())
    def test_finds_places_with_or_without_accents(self):
        haifa=reader.search_cities("haifa")[0]; self.assertEqual((haifa[0],haifa[5]),("Haifa","Asia/Jerusalem")); self.assertIn("Israel",haifa[2])
        for typed in ("Tromsø","tromso","TROMSØ"): self.assertEqual(reader.search_cities(typed)[0][0],"Tromsø",typed)
        self.assertEqual(reader.search_cities("sao paulo")[0][0],"São Paulo")
        self.assertEqual(reader.search_cities("Tehran")[0][5],"Asia/Tehran")
    def test_largest_exact_match_first_and_a_country_narrows_it(self):
        self.assertIn("Australia",reader.search_cities("Sydney")[0][2])
        self.assertIn("Canada",reader.search_cities("Sydney, Canada")[0][2])
        self.assertIn("Texas",reader.search_cities("Tyler, Texas")[0][2])
    def test_exact_before_prefix_before_inside(self):
        rows=[("Haifaville","Haifaville","a",0,0,"UTC"),("New Haifa","New Haifa","b",0,0,"UTC"),("Xhaifa","Xhaifa","c",0,0,"UTC"),("Haifa","Haifa","d",0,0,"UTC")]
        self.assertEqual([r[0] for r in reader.search_cities("haifa",cities=rows)],["Haifa","Haifaville","New Haifa","Xhaifa"])
    def test_empty_and_unknown(self):
        self.assertEqual(reader.search_cities("  "),[]); self.assertEqual(reader.search_cities("zzqqxx"),[])
    def test_limit(self):
        self.assertEqual(len(reader.search_cities("san")),8)

class SettingsTests(unittest.TestCase):
    def test_location_is_cleaned_and_a_bad_one_dropped_keeping_the_rest(self):
        kept=reader.clean_settings({"saved":["hidden:1"],"location":{"label":"Haifa","lat":32.818,"lon":34.989,"tz":"Asia/Jerusalem"}})
        self.assertEqual(kept["location"],{"label":"Haifa","lat":32.82,"lon":34.99,"tz":"Asia/Jerusalem"})
        self.assertEqual(reader.clean_settings({"saved":["hidden:1"],"location":{"lat":999}}),{"saved":["hidden:1"]})

class ClockTests(unittest.TestCase):
    def test_follows_the_locales_own_format(self):
        self.assertEqual(reader.clock_style("03:00:00 PM","PM"),12); self.assertEqual(reader.clock_style("15:00:00",""),24)
        self.assertEqual(reader.clock_style("15:00:00","PM"),24)  # en_GB has an AM/PM word but a 24-hour clock
    def test_clock_shows_the_wall_time_of_the_place(self):
        moment=reader.datetime.datetime(2026,6,21,15,7,tzinfo=reader.badi.ZoneInfo("Asia/Jerusalem"))
        self.assertIn(reader.clock(moment),("15:07","3:07 PM"))

if __name__=="__main__": unittest.main()

"""Saved passages in named collections: migration and damaged settings never lose a passage (no display needed)."""
import json
import tempfile
import unittest
from pathlib import Path
import reader

class CollectionTests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        self.path=Path(temp.name)/"settings.json"

    def test_settings_from_before_collections_load_unchanged(self):
        self.path.write_text(json.dumps({"saved":["prayers:258","hidden:1"],"section":"saved"}))
        prefs,notice=reader.load_settings(self.path)
        self.assertIsNone(notice)
        self.assertEqual(prefs,{"saved":["prayers:258","hidden:1"],"section":"saved"})

    def test_collections_round_trip(self):
        data={"saved":["prayers:258","hidden:1","hidden:2"],"collections":[{"name":"Morning","items":["prayers:258"]},{"name":"Evening","items":[]}]}
        self.assertEqual(reader.clean_settings(data),data)

    def test_damaged_collections_keep_every_saved_passage(self):
        prefs=reader.clean_settings({"saved":["hidden:1"],"collections":[
            {"name":"Morning","items":["prayers:258",7,"hidden:1"]},
            {"name":"  morning ","items":["hidden:2","prayers:258"]},  # same name: merged
            {"name":"","items":["hidden:3"]}, {"name":"Unsorted","items":["hidden:4"]},  # unusable names: passages stay saved
            "junk", {"name":"Bad items","items":"hidden:5"}]})
        self.assertEqual(prefs["collections"],[{"name":"Morning","items":["prayers:258","hidden:1","hidden:2"]},{"name":"Bad items","items":[]}])
        self.assertEqual(prefs["saved"],["hidden:1","prayers:258","hidden:2","hidden:3","hidden:4"])

    def test_filed_passages_survive_a_damaged_saved_list(self):
        prefs=reader.clean_settings({"saved":"oops","collections":[{"name":"Healing","items":["prayers:10"]}]})
        self.assertEqual(prefs["saved"],["prayers:10"])
        self.assertEqual(reader.clean_settings({"collections":{"not":"a list"},"saved":["hidden:1"]}),{"collections":[],"saved":["hidden:1"]})

    def test_a_second_damaged_file_does_not_replace_the_first_backup(self):
        first='{"saved":["prayers:258"],"collections":[{"name":"Mine","items":["prayers:258"]}],'
        self.path.write_text(first); reader.load_settings(self.path)
        self.path.write_text("[]"); prefs,notice=reader.load_settings(self.path)
        self.assertEqual(prefs,{})
        self.assertEqual((self.path.parent/"settings.json.bad").read_text(),first)
        self.assertEqual((self.path.parent/"settings.json.bad.1").read_text(),"[]")
        self.assertIn("settings.json.bad.1",notice)

if __name__=="__main__": unittest.main()

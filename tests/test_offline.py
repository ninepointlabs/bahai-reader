import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import reader

class OfflineTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path=Path(self.temp.name)
        patcher=patch.object(reader,"LIBRARY",self.path)
        patcher.start(); self.addCleanup(patcher.stop)
        patcher=patch.object(reader,"CACHE",self.path/"cache")
        patcher.start(); self.addCleanup(patcher.stop)

    def test_english_never_needs_network(self):
        with patch.object(reader,"fetch_json",side_effect=AssertionError("network")):
            self.assertEqual(len(reader.load_library(1)),2616)

    def test_download_is_atomic_and_language_specific(self):
        data=json.loads((reader.ROOT/"data/prayers.json").read_text())
        for row in data["Prayers"]: row["LanguageId"]=4
        languages={key:[] for key in reader.FEEDS}
        languages["prayers"]=[{"Id":4}]
        with patch.object(reader,"fetch_json",return_value=data):
            reader.download_language(4,languages)
        before=(self.path/"4.json").read_bytes()
        with patch.object(reader,"fetch_json",side_effect=OSError("offline")):
            with self.assertRaises(OSError): reader.download_language(4,languages)
        self.assertEqual((self.path/"4.json").read_bytes(),before)
        items=reader.load_library(4)
        self.assertEqual(len(items),473)
        self.assertTrue(all(i["id"].startswith("4:") and i["section"]=="prayers" for i in items))

    def test_new_collections_and_references(self):
        items=reader.load_library()
        ids={item["id"] for item in items}
        for key in ("aqdas","saq","days","ridvan"):
            self.assertTrue(any(i["id"].startswith(key+":") for i in items))
        for item in items:
            for target,label in item["references"]: self.assertIn(target,ids)
        self.assertEqual({i["subgroup"] for i in items if i["id"].startswith("aqdas:")}, {"Text","Questions and Answers","Notes"})

    def test_old_english_pack_gains_bundled_collections(self):
        pack={k:json.loads((reader.ROOT/"data"/f"{k}.json").read_text()) for k in ("prayers","hidden","gleanings","meditations","tablets","iqan")}
        reader.atomic_json(self.path/"1.json",pack)
        self.assertEqual(len(reader.load_library()),2616)

    def test_wrong_language_rejected(self):
        data=json.loads((reader.ROOT/"data/prayers.json").read_text())
        with self.assertRaises(ValueError): reader.validate_feed("prayers",data,4)

    def test_missing_language_does_not_fall_back_to_english(self):
        self.assertEqual(reader.load_library(4),[])

if __name__=="__main__": unittest.main()

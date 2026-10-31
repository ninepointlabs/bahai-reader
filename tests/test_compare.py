"""Side-by-side languages pair passages by their numbering, offline (no display needed)."""
import collections
import tempfile
import unittest
from pathlib import Path
import reader
from compare_pack import write_pack

class CompareTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.items=reader.load_library()

    def test_numbered_books_pair_one_to_one(self):
        counts=collections.Counter(i["match"] for i in self.items if i["match"])
        self.assertEqual(max(counts.values()),1)
        books={m.split(":")[0] for m in counts}
        self.assertEqual(books,set(reader.ALIGN))
        hidden=next(i for i in self.items if i["id"]=="hidden:1")
        self.assertEqual(hidden["match"],"hidden:True:1")

    def test_prayers_and_unnumbered_books_are_not_paired(self):
        for item in self.items:
            if item["id"].split(":")[0] in ("prayers","days","ridvan"): self.assertIsNone(item["match"],item["id"])

    def test_iqan_pairs_by_part_and_number(self):
        iqan=[i["match"] for i in self.items if i["id"].startswith("iqan:")]
        self.assertIn("iqan:1:1",iqan); self.assertIn("iqan:2:1",iqan)

    def test_a_downloaded_library_pairs_with_english(self):
        temp=tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        original=reader.LIBRARY; reader.LIBRARY=Path(temp.name); self.addCleanup(setattr,reader,"LIBRARY",original)
        write_pack(reader.LIBRARY)
        spanish={i["match"]:i for i in reader.load_library(4) if i["match"]}
        english=next(i for i in self.items if i["id"]=="hidden:1")
        self.assertEqual(" ".join(spanish[english["match"]]["text"].split())," ".join(("[4] "+english["text"]).split()))

    def test_compare_setting(self):
        self.assertEqual(reader.clean_settings({"compare":4}),{"compare":4})
        for bad in ("4",True,None,4.5): self.assertEqual(reader.clean_settings({"compare":bad}),{})

if __name__=="__main__": unittest.main()

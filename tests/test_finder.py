"""Ctrl+K search: matching that ignores accents and apostrophes, and where a match is in the original text. No display needed."""
import unittest
import reader
from bahai_reader import search, finder

class Folding(unittest.TestCase):
    def test_map_gives_the_same_text_as_fold(self):
        for text in ("Bahá’u’lláh","‘Abdu’l‑Bahá","Kitáb-i-Íqán","ÆSIR ß","Ma<u>sh</u>riq"):
            self.assertEqual(search.fold_map(text)[0],reader.fold(text),text)
    def test_the_whole_library_maps_exactly(self):
        for item in reader.load_library(1)[::25]:
            folded,where=search.fold_map(item["text"])
            self.assertEqual(folded,reader.fold(item["text"]),item["id"]); self.assertEqual(len(where),len(folded))
    def test_find_returns_the_original_span(self):
        text="Praise be to Bahá’u’lláh, the Glory of God."
        start,end=search.find(text,reader.fold("Bahaullah"))
        self.assertEqual(text[start:end],"Bahá’u’lláh")
        self.assertIsNone(search.find(text,"zzz"))
    def test_snippet_bolds_the_match_and_cuts_at_words(self):
        text=" ".join(f"word{n}" for n in range(60))+" Justice "+" ".join(f"more{n}" for n in range(60))
        before,match,after=search.snippet(text,search.find(text,"justice"))
        self.assertEqual(match,"Justice"); self.assertTrue(before.startswith("…") and after.endswith("…"))
        self.assertFalse(before[1:].startswith(" ")); self.assertLess(len(before)+len(after),200)

class Searching(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.items=reader.load_library(1)
    def test_everything_and_one_book(self):
        everything=search.search_passages(self.items,"justice")
        hidden=search.search_passages([i for i in self.items if i["section"]=="hidden"],"justice")
        self.assertGreater(len(everything),len(hidden)); self.assertTrue(hidden)
        self.assertIn("hidden:2",[i["id"] for i in hidden])
    def test_accents_and_apostrophes_do_not_matter(self):
        self.assertEqual({i["id"] for i in search.search_passages(self.items,"Bahaullah")},{i["id"] for i in search.search_passages(self.items,"Bahá’u’lláh")})
    def test_empty_query_finds_nothing(self):
        self.assertEqual(search.search_passages(self.items,"   "),[])
    def test_results_are_listed_under_their_book_or_category(self):
        hidden=next(i for i in self.items if i["id"]=="hidden:2"); prayer=next(i for i in self.items if i["section"]=="prayers" and i["tags"]==["Healing"])
        self.assertEqual(finder.place_of(hidden),"The Hidden Words"); self.assertEqual(finder.place_of(prayer),"Prayers · Healing")

if __name__=="__main__": unittest.main()

"""Search folding (no display needed)."""
import unittest
import reader

class SearchTests(unittest.TestCase):
    def test_accents_apostrophes_and_hyphens_are_ignored(self):
        for typed,text in [("Bahaullah","Bahá’u’lláh"),("Baha'u'llah","Bahá’u’lláh"),("Naw-Ruz","Naw-Rúz"),("abdul-baha","‘Abdu’l‑Bahá"),("ridvan","Riḍván"),("BAB","the Báb")]:
            self.assertIn(reader.fold(typed),reader.fold(text),typed)

    def test_qa_queries_find_passages(self):
        items=reader.load_library()
        haystacks=[reader.fold(i["title"]+" "+i["text"]+" "+" ".join(i["tags"])) for i in items if i["section"]=="prayers"]
        exact=sum(reader.fold("Bahá’u’lláh") in h for h in haystacks)
        self.assertGreater(exact,0)
        for typed in ("Baha'u'llah","Bahaullah"):
            self.assertEqual(sum(reader.fold(typed) in h for h in haystacks),exact)
        for typed in ("Naw-Ruz","abdul-baha"):
            self.assertTrue(any(reader.fold(typed) in h for h in haystacks),typed)

if __name__=="__main__": unittest.main()

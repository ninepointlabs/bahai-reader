"""The Obligatory prayers section gathers bundled texts only (no display needed)."""
import unittest
import reader

class ObligatoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.items=reader.load_library()
        cls.groups=reader.obligatory(cls.items)

    def test_short_medium_and_long_in_that_order(self):
        prayers=self.groups["The three prayers"]
        self.assertEqual([p["tags"] for p in prayers],[["Short Obligatory Prayer"],["Medium Obligatory Prayer"],["Long Obligatory Prayer"]])
        self.assertTrue(all(p["section"]=="prayers" and p["citation"]=="Bahá’u’lláh" for p in prayers))

    def test_guidance_is_the_prayer_paragraphs_with_their_linked_notes_and_answers(self):
        guidance=self.groups["Kitáb-i-Aqdas"]
        self.assertEqual(guidance[0]["id"],"aqdas:Paragraphs:6")
        self.assertIn("We have enjoined obligatory prayer upon you",guidance[0]["text"])
        numbered=[(i["subgroup"],i["title"].split(" · ")[0]) for i in guidance]
        self.assertEqual(numbered,[("Text",str(n)) for n in (6,8,10,12,13,14)]
            +[("Questions and Answers",str(n)) for n in (14,20,21,58,59,60,61,63,64,65,66,67,70,74,81,82,83,85,93,103)]
            +[("Notes",str(n)) for n in (3,4,5,6,7,8,9,10,11,13,14,15,16,17,19,20,21,22)])
        self.assertIn("When traveling",guidance[5]["text"])
        # Each passage once, though several paragraphs link to it (Q&A 63, 85, 93).
        self.assertEqual(len({i["id"] for i in guidance}),len(guidance))
        self.assertIn("three prayers are revealed",guidance[numbered.index(("Questions and Answers","65"))]["text"])
        # Every entry is the bundled passage itself, not a copy.
        self.assertTrue(all(any(g is i for i in self.items) for g in guidance))

    def test_directions_are_marked_and_the_prayer_is_not(self):
        prayers={p["tags"][0]:p for p in self.groups["The three prayers"]}
        def marked(name):
            text=prayers[name]["text"]; return [text[a:b].strip() for a,b in reader.directions(prayers[name])]
        short=marked("Short Obligatory Prayer")
        self.assertEqual(len(short),3)
        self.assertTrue(short[0].startswith("To be recited") and short[1].startswith("God hath exempted") and short[2].startswith('"The daily obligatory'))
        self.assertFalse(any("I bear witness, O my God" in m for m in short))
        medium=marked("Medium Obligatory Prayer")
        self.assertIn("Whoso wisheth to pray, let him wash his hands, and while he washeth, let him say:",medium)
        self.assertTrue(any(m.startswith("(If anyone choose") for m in medium))
        self.assertFalse(any(m.startswith("Strengthen my hand") for m in medium))
        long=marked("Long Obligatory Prayer")
        self.assertEqual(sum(m.endswith("say:") for m in long),15)
        self.assertEqual(long[-1],"1. Alláh-u-Abhá")
        self.assertFalse(any(m.startswith("O Thou Who art the Lord of all names") for m in long))
        # The title stays as it is; other passages have no directions.
        self.assertTrue(all(a>0 for p in prayers.values() for a,_ in reader.directions(p)))
        self.assertEqual(reader.directions(next(i for i in self.items if i["id"]=="hidden:1")),[])

    def test_a_library_without_them_is_empty(self):
        self.assertEqual(reader.obligatory([i for i in self.items if i["section"]=="hidden"]),{})

    def test_section_is_remembered(self):
        self.assertEqual(reader.clean_settings({"section":"obligatory"}),{"section":"obligatory"})

if __name__=="__main__": unittest.main()

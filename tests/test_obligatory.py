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

    def test_guidance_is_paragraph_6_with_its_linked_notes_and_answers(self):
        guidance=self.groups["Kitáb-i-Aqdas"]
        self.assertEqual(guidance[0]["id"],"aqdas:Paragraphs:6")
        self.assertIn("We have enjoined obligatory prayer upon you",guidance[0]["text"])
        numbered=[(i["subgroup"],i["title"].split(" · ")[0]) for i in guidance]
        self.assertEqual(numbered,[("Text","6")]+[("Questions and Answers",str(n)) for n in (14,63,65,66,67,81,82,83,93)]+[("Notes",str(n)) for n in range(3,9)])
        self.assertIn("three prayers are revealed",guidance[3]["text"])
        # Every entry is the bundled passage itself, not a copy.
        self.assertTrue(all(any(g is i for i in self.items) for g in guidance))

    def test_a_library_without_them_is_empty(self):
        self.assertEqual(reader.obligatory([i for i in self.items if i["section"]=="hidden"]),{})

    def test_section_is_remembered(self):
        self.assertEqual(reader.clean_settings({"section":"obligatory"}),{"section":"obligatory"})

if __name__=="__main__": unittest.main()

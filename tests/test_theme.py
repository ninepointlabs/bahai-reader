"""Palette contrast rules (no display needed)."""
import unittest
import reader

class ThemeTests(unittest.TestCase):
    def test_contrast_ratio(self):
        self.assertAlmostEqual(reader.contrast("#000000","#ffffff"),21,places=3)
        self.assertAlmostEqual(reader.contrast("#ffffff","#ffffff"),1)
        # The QA report's White theme current row: accent on selection.
        self.assertLess(reader.contrast("#6e6e6e","#c0c0c0"),3)

    def test_white_theme_current_passage_is_readable(self):
        color=reader.readable("#c0c0c0","#6e6e6e","#000000")
        self.assertEqual(color,"#000000")
        self.assertGreaterEqual(reader.contrast(color,"#c0c0c0"),4.5)

    def test_readable_accent_is_kept(self):
        self.assertEqual(reader.readable("#e2e9df","#45654c","#252b27"),"#45654c")

    def test_falls_back_to_strongest(self):
        self.assertEqual(reader.readable("#808080","#7a7a7a","#909090"),"#909090")

if __name__=="__main__": unittest.main()

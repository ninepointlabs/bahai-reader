"""The libadwaita window's data: the library, Continue reading, settings and the theme mapping. Needs no display."""
import unittest
import reader
from bahai_reader import shell, theme

FLEXOKI=dict(background="#FFFCF0",foreground="#100F0F",accent="#205EA6",selection="#CECDC3")

class Library(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.items=reader.load_library(1); cls.shelf=reader.books(cls.items)
    def test_the_books_replace_the_a_to_z_list(self):
        self.assertEqual(len(self.shelf),18)
        self.assertIn("The Hidden Words",self.shelf); self.assertIn("God Passes By",self.shelf)
        # Every writing and Hidden Word is in exactly one book; prayers are not books.
        self.assertEqual(sum(len(v) for v in self.shelf.values()),sum(1 for i in self.items if i["section"] in ("writings","hidden")))
        self.assertIsNone(reader.book_of(next(i for i in self.items if i["section"]=="prayers")))
    def test_card_lines(self):
        self.assertEqual(reader.book_summary(self.shelf["The Hidden Words"]),"153 passages · 8k words")
        self.assertEqual(reader.book_summary(self.shelf["The Kitáb-i-Íqán"]),"2 parts · 52k words")
    def test_progress_is_by_words_through_the_whole_book(self):
        gpb=self.shelf["God Passes By"]
        self.assertEqual(reader.book_progress(gpb,gpb[0]),(0,sum(i["word_count"] for i in gpb)))
        before,total=reader.book_progress(gpb,gpb[2])
        self.assertEqual(before,gpb[0]["word_count"]+gpb[1]["word_count"]); self.assertGreater(total,before)
    def test_authors_in_order(self):
        self.assertLess(shell.author_rank("Bahá’u’lláh"),shell.author_rank("Shoghi Effendi"))
        self.assertLess(shell.author_rank("The Universal House of Justice"),shell.author_rank("Someone else"))

class Settings(unittest.TestCase):
    def test_home_is_a_section(self):
        self.assertEqual(reader.clean_settings({"section":"home"})["section"],"home")
    def test_continue_reading_is_cleaned(self):
        prefs=reader.clean_settings({"positions":{"God Passes By":"se:1","bad":3},"recent":["A","A",4,"B","C","D","E","F","G"],"book":7})
        self.assertEqual(prefs["positions"],{"God Passes By":"se:1"})
        self.assertEqual(prefs["recent"],["A","B","C","D","E","F"]); self.assertNotIn("book",prefs)
        self.assertEqual(reader.clean_settings({"positions":[],"recent":"x"}),{"positions":{},"recent":[]})

class ThemeMapping(unittest.TestCase):
    def test_omarchy_colours_become_libadwaita_named_colours(self):
        named=theme.adwaita_colors(FLEXOKI,{"dark_background":"#f2efe4"})
        self.assertEqual(named["window_bg_color"],"#FFFCF0"); self.assertEqual(named["window_fg_color"],"#100F0F")
        self.assertEqual(named["sidebar_bg_color"],"#f2efe4"); self.assertEqual(named["accent_bg_color"],"#205EA6")
    def test_text_on_the_accent_and_the_accent_as_text_are_readable(self):
        for accent in ("#205EA6","#c9ab70","#ffd700","#45654c"):
            named=theme.adwaita_colors(dict(FLEXOKI,accent=accent))
            self.assertGreaterEqual(theme.contrast(named["accent_fg_color"],accent),4.5,accent)
            self.assertGreaterEqual(theme.contrast(named["accent_color"],FLEXOKI["background"]),4.5,accent)
    def test_an_unreadable_sidebar_is_mixed_instead(self):
        named=theme.adwaita_colors(FLEXOKI,{"dark_background":"#202020"})
        self.assertGreaterEqual(theme.contrast(named["sidebar_bg_color"],FLEXOKI["foreground"]),7)
    def test_without_omarchy_the_sidebar_is_mixed(self):
        dark=dict(background="#161b19",foreground="#e6e1d3",accent="#c9ab70",selection="#303b35")
        self.assertNotEqual(theme.adwaita_colors(dark)["sidebar_bg_color"],dark["background"])
    def test_stylesheet_sets_named_colours_and_keeps_the_reading_font(self):
        css=theme.adwaita_stylesheet(FLEXOKI,{"font":"Noto Serif","size":24},variables=True)
        self.assertIn("@define-color window_bg_color #FFFCF0;",css)
        self.assertIn("--window-bg-color: #FFFCF0;",css); self.assertIn("--accent-bg-color: #205EA6;",css)
        self.assertIn('textview { font-family: "Noto Serif"; font-size: 24px; }',css)
        # No per-widget overrides of buttons or entries: libadwaita draws those from the named colours.
        self.assertNotRegex(css,r"(^|\n)(button|entry) \{"); self.assertNotIn("monospace",css)
        self.assertNotIn(":root",theme.adwaita_stylesheet(FLEXOKI,{},variables=False))
    def test_mix(self):
        self.assertEqual(theme.mix("#000000","#ffffff",0.5),"#808080"); self.assertEqual(theme.mix("#123456","#123456",0.3),"#123456")

class Choosing(unittest.TestCase):
    def test_classic_can_be_asked_for(self):
        import os
        saved=os.environ.get("BAHAI_READER_SHELL")
        try:
            os.environ["BAHAI_READER_SHELL"]="classic"; self.assertIsNone(shell.adwaita())
        finally:
            if saved is None: os.environ.pop("BAHAI_READER_SHELL",None)
            else: os.environ["BAHAI_READER_SHELL"]=saved

if __name__=="__main__": unittest.main()

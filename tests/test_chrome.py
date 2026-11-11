"""Phase 1 labels and chrome, without a display: headings, list names, subtitles and the stylesheet."""
import unittest
import reader

def item(id,title,section="writings",tags=(),subgroup=None,author=None,text="",words=100):
    return {"id":id,"title":title,"section":section,"tags":list(tags),"subgroup":subgroup,"author":author,"text":text,"word_count":words}

PALETTE=dict(background="#fafaf7",foreground="#252b27",accent="#45654c",selection="#e2e9df")

class Headings(unittest.TestCase):
    def test_a_prayer_is_headed_by_its_category(self):
        healing=item("prayers:1","O God, my God!","prayers",["Healing"],author="Bahá’u’lláh")
        self.assertEqual(reader.heading(healing),"Healing")
        self.assertEqual(reader.subtitle(healing),"Bahá’u’lláh · 100 words")
    def test_the_category_it_was_opened_in_wins(self):
        canada=item("prayers:2","O Thou incomparable God!","prayers",["Tablets of the Divine Plan","Canada"],author="‘Abdu’l‑Bahá")
        self.assertEqual(reader.heading(canada),"Tablets of the Divine Plan")
        self.assertEqual(reader.heading(canada,"Canada"),"Canada")
        self.assertEqual(reader.subtitle(canada,"Canada"),"‘Abdu’l‑Bahá · Tablets of the Divine Plan · 100 words")
    def test_obligatory_prayers_by_name(self):
        medium=item("prayers:3","TO BE RECITED DAILY","prayers",["Medium Obligatory Prayer"],text="Whoso wisheth to pray")
        self.assertEqual(reader.heading(medium),"Medium Obligatory Prayer")
        # bahai.org's text starts with the name already, so the heading says where the prayer is instead of repeating it.
        short=item("prayers:4","TO BE RECITED ONCE","prayers",["Short Obligatory Prayer"],text="Short Obligatory Prayer\n\nTO BE RECITED",author="Bahá’u’lláh")
        self.assertEqual(reader.heading(short),"Obligatory prayers")
        self.assertIn("Short Obligatory Prayer",reader.subtitle(short))
    def test_the_subtitle_never_repeats_the_heading(self):
        epistle=item("prayers:13691","Epistle to the Son of the Wolf",tags=["Epistle to the Son of the Wolf"],author="Bahá’u’lláh")
        self.assertEqual(reader.heading(epistle),"Epistle to the Son of the Wolf")
        self.assertEqual(reader.subtitle(epistle),"Bahá’u’lláh")
    def test_the_author_is_not_repeated_when_the_book_names_him(self):
        gleanings=item("gleanings:1","I · LAUDED",tags=["Gleanings from the Writings of Bahá’u’lláh"],author="Bahá’u’lláh")
        self.assertEqual(reader.subtitle(gleanings),"Gleanings from the Writings of Bahá’u’lláh")

class ListNames(unittest.TestCase):
    def test_obligatory_prayers_by_name_not_directions(self):
        for name in reader.OBLIGATORY_PRAYERS:
            self.assertEqual(reader.list_title(item("prayers:9","TO BE RECITED ONCE IN TWENTY-FOUR HOURS","prayers",[name])),name)
    def test_other_passages_keep_their_titles(self):
        self.assertEqual(reader.list_title(item("hidden:1","1 · O SON OF SPIRIT!","hidden",["From the Arabic"])),"1 · O SON OF SPIRIT!")
    def test_the_library_names_all_three(self):
        items=reader.load_library(1)
        names=[reader.list_title(i) for g in [reader.obligatory(items)["The three prayers"]] for i in g]
        self.assertEqual(names,list(reader.OBLIGATORY_PRAYERS))
        # The official text itself is untouched.
        self.assertTrue(all(i["text"] for i in reader.obligatory(items)["The three prayers"]))

class Stylesheet(unittest.TestCase):
    def test_the_interface_is_not_monospace_by_default(self):
        css=reader.stylesheet(PALETTE,{})
        self.assertNotIn("monospace",css)
        # The reading font is still set on the text, unchanged.
        self.assertIn('textview { font-family: "DejaVu Serif"; font-size: 22px; }',css)
    def test_monospace_interface_on_request(self):
        css=reader.stylesheet(PALETTE,{"chrome_font":"Monospace","font":"Noto Serif","size":24})
        self.assertTrue(css.startswith("window, popover, tooltip { font-family: monospace; }"))
        self.assertIn('textview { font-family: "Noto Serif"; font-size: 24px; }',css)
    def test_the_setting_is_validated(self):
        self.assertNotIn("chrome_font",reader.clean_settings({"chrome_font":"Comic"}))
        self.assertEqual(reader.clean_settings({"chrome_font":"Monospace"})["chrome_font"],"Monospace")
    def test_soft_controls_and_one_primary_style(self):
        css=reader.stylesheet(PALETTE,{})
        self.assertNotIn("border-radius: 0px",css)
        self.assertIn("button.primary { background: #45654c;",css)
        self.assertIn("paned > separator { min-width: 1px;",css)
    def test_text_on_the_primary_button_is_readable(self):
        for accent in ("#45654c","#c9ab70","#ffd700","#1e3a8a"):
            palette=dict(PALETTE,accent=accent); css=reader.stylesheet(palette,{})
            colour=css.split("button.primary { background: "+accent+"; color: ")[1][:7]
            self.assertGreaterEqual(reader.contrast(colour,accent),4.5,(accent,colour))
    def test_reading_footer_divider_and_fade(self):
        css=reader.stylesheet(PALETTE,{})
        self.assertIn(".reading-footer { border-top: 1px solid #e2e9df;",css)
        self.assertIn(".reading-fade { background: linear-gradient(to bottom, alpha(#fafaf7,0), #fafaf7); }",css)

if __name__=="__main__": unittest.main()

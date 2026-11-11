"""Highlights and notes: stored by passage and words, never in the text; they follow the text if it moves. No display needed."""
import datetime
import unittest
import reader
from bahai_reader import marks, theme

ITEM={"id":"hidden:2","text":"O SON OF SPIRIT!\nThe best beloved of all things in My sight is Justice; turn not away therefrom."}

class Making(unittest.TestCase):
    def test_a_highlight_keeps_the_words_and_trims_spaces(self):
        start=ITEM["text"].index(" Justice"); record=marks.make(ITEM,start,start+8,"green",today=datetime.date(2026,11,11))  # " Justice"
        self.assertEqual(record,{"id":"hidden:2","start":start+1,"end":start+8,"words":"Justice","color":"green","created":"2026-11-11"})
        self.assertIsNone(marks.make(ITEM,16,17))  # only a line break
    def test_a_note_is_kept_and_limited(self):
        record=marks.make(ITEM,0,5,note="  "+"x"*6000)
        self.assertEqual(len(record["note"]),marks.NOTE_LIMIT)
        self.assertNotIn("note",marks.make(ITEM,0,5,note="   "))
    def test_overlapping_highlights_are_replaced(self):
        first=marks.make(ITEM,0,10); second=marks.make(ITEM,5,20,"blue"); other=marks.make(dict(ITEM,id="hidden:3"),0,10)
        records=marks.add(marks.add([first,other],second),marks.make(ITEM,40,50))
        self.assertNotIn(first,records); self.assertIn(second,records); self.assertIn(other,records); self.assertEqual(len(records),3)

class Anchoring(unittest.TestCase):
    def test_unchanged_text(self):
        record=marks.make(ITEM,ITEM["text"].index("Justice"),ITEM["text"].index("Justice")+7)
        self.assertEqual(marks.anchor(ITEM["text"],record),(record["start"],record["end"]))
    def test_moved_text_is_followed(self):
        record=marks.make(ITEM,ITEM["text"].index("Justice"),ITEM["text"].index("Justice")+7)
        moved="A new line.\n"+ITEM["text"]
        start,end=marks.anchor(moved,record); self.assertEqual(moved[start:end],"Justice")
    def test_gone_words_are_not_drawn(self):
        record=marks.make(ITEM,0,5); self.assertIsNone(marks.anchor("Something else entirely",record))
    def test_the_nearest_of_several(self):
        text="light and light and light"; record={"start":11,"end":16,"words":"light"}
        self.assertEqual(marks.anchor("x"+text,record),(11,16))

class Settings(unittest.TestCase):
    def test_damaged_records_are_dropped(self):
        good={"id":"hidden:2","start":3,"end":9,"words":"best b","color":"blue","note":"n","created":"2026-11-11"}
        bad=[3,{"id":"x"},dict(good,color="red"),dict(good,start=9,end=3),dict(good,start=True),dict(good,words=""),"junk"]
        prefs=reader.clean_settings({"highlights":[good,*bad],"highlight_color":"green"})
        self.assertEqual(prefs["highlights"],[good]); self.assertEqual(prefs["highlight_color"],"green")
        self.assertEqual(reader.clean_settings({"highlights":"oops","highlight_color":"red"}),{"highlights":[]})

class Colours(unittest.TestCase):
    def test_theme_colours_where_the_theme_has_them(self):
        colors=theme.highlight_colors("#FFFCF0",{"yellow":"#D0A215","blue":"oops"})
        self.assertEqual(colors["yellow"],"rgba(208,162,21,0.32)"); self.assertTrue(colors["blue"].startswith("rgba(63,127,196,"))
        self.assertTrue(theme.highlight_colors("#161b19")["green"].endswith(",0.4)"))
        self.assertIn(".swatch-magenta { background: rgba(",theme.marks_stylesheet(colors,"#100F0F"))

if __name__=="__main__": unittest.main()

"""Highlights and notes: stored by passage and words, never in the text; they follow the text if it moves. No display needed."""
import copy
import datetime
import tempfile
import unittest
from pathlib import Path
import reader
from bahai_reader import marks, theme
from compare_pack import write_pack

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

class LongNotes(unittest.TestCase):
    """QA M1: a 5,000-character note with no spaces made the list ask for about 50,000 px."""
    def test_the_list_shows_a_bounded_preview(self):
        note="x"*marks.NOTE_LIMIT
        shown=marks.preview(note)
        self.assertLessEqual(len(shown),marks.PREVIEW_LIMIT+1); self.assertTrue(shown.endswith("…")); self.assertTrue(note.startswith(shown[:-1]))
        self.assertEqual(marks.preview("A short note."),"A short note.")
    def test_the_list_wraps_anywhere(self):
        # The labels of the list and the passage marker break inside a word; GTK's default (WORD) would not.
        source=(Path(__file__).resolve().parents[1]/"bahai_reader"/"highlights.py").read_text()
        self.assertIn("wrap_mode=Pango.WrapMode.WORD_CHAR",source); self.assertIn("marks.preview(record[\"note\"])",source)
        self.assertNotIn('Gtk.Label(label=record["note"]',source)
    def test_a_long_note_is_stored_whole(self):
        record=marks.make(ITEM,0,5,note="x"*marks.NOTE_LIMIT)
        self.assertEqual(reader.clean_settings({"highlights":[record]})["highlights"][0]["note"],"x"*marks.NOTE_LIMIT)

class Languages(unittest.TestCase):
    """QA M2: highlights, notes and saved passages follow the reader to the same passage in another language, by the numbering
    side by side already uses (each item's match); the stored records are never rewritten."""
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(); cls.original=reader.LIBRARY; reader.LIBRARY=Path(cls.temp.name)
        # Spanish ids differ from English ones, as in the real feeds ("hidden:2" is "4:hidden:687"); only the numbering pairs them.
        write_pack(reader.LIBRARY,books=("prayers","hidden","iqan"),id_offset=685)
        cls.english=reader.load_library(1); cls.spanish=reader.load_library(4)
    @classmethod
    def tearDownClass(cls):
        reader.LIBRARY=cls.original; cls.temp.cleanup()
    def resolver(self,items):
        libraries={1:self.english,4:self.spanish}
        by_id={i["id"]:i for i in items}; by_match={i["match"]:i for i in items if i["match"]}
        matches=lambda language:{i["id"]:i["match"] for i in libraries.get(language,[]) if i["match"]}
        return lambda key:marks.follow(key,by_id,by_match,matches)
    def test_ids_name_their_language(self):
        self.assertEqual(marks.language_of("hidden:2"),1); self.assertEqual(marks.language_of("4:hidden:687"),4)
        self.assertEqual(marks.language_of("aqdas:Paragraphs:6"),1); self.assertEqual(marks.language_of("prayers:12"),1)
    def test_english_follows_to_spanish_and_back(self):
        english=next(i for i in self.english if i["id"]=="hidden:2")
        spanish=next(i for i in self.spanish if i["match"]==english["match"])
        self.assertEqual(spanish["id"],"4:hidden:687")
        self.assertIs(self.resolver(self.spanish)("hidden:2"),spanish)
        self.assertIs(self.resolver(self.english)("4:hidden:687"),english)
        # The current language's own ids resolve to themselves.
        self.assertIs(self.resolver(self.spanish)("4:hidden:687"),spanish); self.assertIs(self.resolver(self.english)("hidden:2"),english)
        iqan=next(i for i in self.english if i["id"].startswith("iqan:"))
        self.assertEqual(self.resolver(self.spanish)(iqan["id"])["match"],iqan["match"])
    def test_the_stored_record_is_unchanged(self):
        english=next(i for i in self.english if i["id"]=="hidden:2")
        record=marks.make(english,2,10,"blue",note="Mine",today=datetime.date(2026,11,1)); before=copy.deepcopy(record)
        self.resolver(self.spanish)(record["id"])
        self.assertEqual(record,before)
        self.assertEqual(reader.clean_settings({"highlights":[record],"saved":["hidden:2"]}),{"highlights":[before],"saved":["hidden:2"]})
    def test_unmatched_passages_stay_unresolved(self):
        spanish=self.resolver(self.spanish)
        for item in self.english:
            if item["id"].split(":")[0] in ("prayers","days","ridvan") or item.get("official_id") and item["match"] is None:
                self.assertIsNone(spanish(item["id"]),item["id"])
        feeds={j["id"] for j in reader.load_bahaiprayers(1)}
        uhj=[i for i in self.english if i["id"] not in feeds]  # bahai.org-only: UHJ messages, Shoghi Effendi
        self.assertTrue(uhj)
        for item in uhj: self.assertIsNone(spanish(item["id"]),item["id"])
        # A language that is not downloaded resolves nothing, and nothing breaks.
        self.assertIsNone(spanish("7:hidden:2")); self.assertIsNone(spanish("nonsense"))
        # Gleanings are not in this stand-in Spanish library: no counterpart.
        self.assertIsNone(spanish(next(i["id"] for i in self.english if i["id"].startswith("gleanings:"))))
    def test_settings_keep_marks_from_every_language(self):
        good=[{"id":"hidden:2","start":3,"end":9,"words":"best b","color":"blue","note":"n","created":"2026-11-11"},
              {"id":"4:hidden:687","start":0,"end":4,"words":"[4] ","color":"green"}]
        bad=[{"id":"4:hidden:687"},dict(good[1],color="red"),dict(good[1],end=0),None]
        prefs=reader.clean_settings({"highlights":[good[0],*bad,good[1]],"saved":["hidden:2","4:hidden:687",3],
                                     "collections":[{"name":"Morning","items":["hidden:2","4:hidden:687"]}]})
        self.assertEqual(prefs["highlights"],good); self.assertEqual(prefs["saved"],["hidden:2","4:hidden:687"])
        self.assertEqual(prefs["collections"],[{"name":"Morning","items":["hidden:2","4:hidden:687"]}])

class Colours(unittest.TestCase):
    def test_theme_colours_where_the_theme_has_them(self):
        colors=theme.highlight_colors("#FFFCF0",{"yellow":"#D0A215","blue":"oops"})
        self.assertEqual(colors["yellow"],"rgba(208,162,21,0.32)"); self.assertTrue(colors["blue"].startswith("rgba(63,127,196,"))
        self.assertTrue(theme.highlight_colors("#161b19")["green"].endswith(",0.4)"))
        self.assertIn(".swatch-magenta { background: rgba(",theme.marks_stylesheet(colors,"#100F0F"))

if __name__=="__main__": unittest.main()

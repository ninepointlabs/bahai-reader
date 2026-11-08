"""bahai.org texts: the importer's parsing (on made-up documents shaped like bahai.org's XHTML) and the bundled data."""
import html
import importlib.util
import json
import os
import re
import tempfile
import unittest
import unittest.mock
from pathlib import Path
import reader

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("importer",ROOT/"scripts/import-bahai-library.py")
importer=importlib.util.module_from_spec(spec); spec.loader.exec_module(importer)

STYLE="""<style>@charset "UTF-8";
.b p { font-size: 1.7rem; }
.b .d, .b .e .f .g { font-size: 3.6rem; }
.b .k, .b .l, .b h3.m { font-size: 2.3rem; }
.b .s, .b .t, .b .u, .b .v, .b .w, .b h5.x { font-size: 1.9rem; }
.b .hb, .b .ib { font-style: italic; }
.gc li.mc { list-style-type: decimal; }
.b .jb, .b .kb { font-weight: bold; }
</style>"""

def page(body,title="Test"):
    return f"""<!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml"><head><meta charset="utf-8" /><title>{title}</title>
<meta content="19990101" name="date" />{STYLE}</head><body class="a"><div class="b"><div>{body}</div></div>
<div class="wf"><p>This document has been downloaded from the Bahá’í Reference Library.</p></div></body></html>"""

MESSAGE=page("""<p class="c"> <a class="sf" id="1"></a>The Universal House of Justice</p>
<p class="rb"> <a class="sf" id="2"></a>Dear friends, the Ma<u>sh</u>riqu’l-A<u>dh</u>kár and the <span class="hb">Kitáb-i-Aqdas</span>
   are named here,<sup class="ye"><a href="#n1">1</a></sup> and   spaces    collapse.</p>
<blockquote class="kd"><p class="zd"> <a class="sf" id="3"></a>A quoted line,<br />and its second line.</p></blockquote>
<table><tr><td class="dd"><a class="sf" id="4"></a>Mr. A</td> <td class="dd"><a class="sf" id="5"></a>Mr. B</td></tr></table>
<ul><li value="3" class="mc"><a class="sf" id="6"></a>Third item</li></ul>
<p class="pb"><a class="sf" id="7"></a>[signed: The Universal <wbr />House <wbr />of Justice]</p>
<div class="bf"><ul><li><h3><a class="sf" id="8"></a>Notes</h3><ul><li><div><a class="td jf">1</a><p> <a class="sf" id="n1"></a>A note with <span class="hb">a title</span>.<a class="jc" href="#2"></a> </p></div></li></ul></li></ul></div>""")

def passage(document):
    parsed=importer.Reader(document); result=importer.Passage()
    for block in parsed.blocks: result.add_block(block,parsed.notes)
    result.add_notes(parsed.notes)
    return parsed,result

def spans(result,kind): return [result.text[a:b] for a,b,k in result.spans if k==kind]

class ParserTests(unittest.TestCase):
    def test_text_is_copied_exactly_with_its_paragraphs(self):
        _,result=passage(MESSAGE)
        self.assertEqual(result.text.split("\n\n")[:3],["The Universal House of Justice",
            "Dear friends, the Mashriqu’l-Adhkár and the Kitáb-i-Aqdas are named here,¹ and spaces collapse.",
            "A quoted line,\nand its second line."])
        self.assertIn("Mr. A\tMr. B",result.text)
        self.assertIn("[signed: The Universal House of Justice]",result.text)

    def test_underlining_italics_quotes_and_numbers_are_kept(self):
        _,result=passage(MESSAGE)
        self.assertEqual(spans(result,"u"),["sh","dh"])
        self.assertEqual(spans(result,"i"),["Kitáb-i-Aqdas","a title"])
        self.assertEqual(spans(result,"quote"),["A quoted line,\nand its second line."])
        self.assertIn("\n\n3. Third item\n\n",result.text)  # the list number the page's stylesheet draws

    def test_footnotes_follow_the_passage(self):
        _,result=passage(MESSAGE)
        self.assertTrue(result.text.endswith("\n\nNotes\n\n¹ A note with a title."))
        self.assertEqual(result.cited,["n1"])
        self.assertNotIn("This document has been downloaded",result.text)

    def test_missing_note_is_an_error(self):
        with self.assertRaises(ValueError): passage(MESSAGE.replace('href="#n1"','href="#n9"'))

    def test_loose_text_is_an_error_not_dropped(self):
        with self.assertRaises(ValueError): passage(page('<div>stray words<p><a class="sf" id="1"></a>Text</p></div>'))

    def test_work_splits_at_headings_and_keeps_every_paragraph(self):
        work=page("""<div class="e"><div class="f"><h1 class="g"><a class="sf" id="t"></a>A Book</h1></div><p class="re"><a class="sf" id="by"></a>by Someone</p></div>
<nav class="gc"><ul><li><h3 class="c kc"><a href="#">List of topics</a></h3><ul><li><a href="#d1">First letter, 1 May 1930</a></li><li><a href="#d2">Second letter</a></li></ul></li></ul></nav>
<div><p class="c"><a class="sf" id="d1"></a>1 May 1930</p><p class="c l"><a class="sf" id="h1"></a>First letter</p><p><a class="sf" id="p1"></a>One.</p><p><a class="sf" id="p2"></a>Two.</p></div>
<div><p class="c"><a class="sf" id="d2"></a>2 May 1930</p><p class="c l"><a class="sf" id="h2"></a>Second letter</p><p><a class="sf" id="p3"></a>Three.</p></div>""")
        parsed=importer.Reader(work); front,pieces=importer.split_work(parsed)
        self.assertEqual(front,["A Book","by Someone"])
        self.assertEqual([p["title"] for p in pieces],["First letter, 1 May 1930","Second letter"])
        self.assertEqual([len(p["blocks"]) for p in pieces],[4,3])
        self.assertEqual(pieces[1]["blocks"][0].anchor,"d2")
        self.assertIsNone(pieces[0]["part"])  # "List of topics" groups the contents; it is not a part

    def test_same_text_finds_a_message_already_in_the_app(self):
        text="".join(f"sentence number {n} of the message, " for n in range(60))
        self.assertTrue(importer.same_text(text,"The following message is being sent. "+text.replace("centre","center")))
        self.assertFalse(importer.same_text(text,"".join(f"line {n} of another letter, " for n in range(60))))
        self.assertFalse(importer.same_text(text[:len(text)//2]+"".join(f"other words {n} here " for n in range(60)),text[len(text)//2:]))

def data(name): return json.loads((ROOT/"data"/name).read_text())

class BundledDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.messages=data("uhj-messages.json"); cls.shoghi=data("shoghi-effendi.json")
        cls.items=reader.load_library(); cls.by_id={i["id"]:i for i in cls.items}

    def test_every_listed_message_is_accounted_for(self):
        m=self.messages
        self.assertEqual(len(m["items"])+len(m["duplicates"])+len(m["omitted"]),m["source"]["listed"])
        self.assertEqual((m["omitted"],m["duplicates"],len(m["items"])),([],[],515))
        documents=[r["document"] for r in m["items"]]
        self.assertEqual(len(documents),len(set(documents)))

    def test_stable_ids_and_provenance(self):
        for row in self.messages["items"]:
            self.assertRegex(row["id"],r"^uhj:\d{8}_\d{3}$"); self.assertEqual(row["id"],"uhj:"+row["document"])
            self.assertEqual(row["source_url"],f"https://www.bahai.org/library/authoritative-texts/the-universal-house-of-justice/messages/{row['document']}/{row['document']}.xhtml")
        for row in self.shoghi["items"]:
            self.assertRegex(row["id"],r"^se:[a-z0-9-]+:\d{9}$"); self.assertEqual(row["id"],f"se:{row['work']}:{row['anchor']}")
        for row in self.messages["items"]+self.shoghi["works"]+[self.messages["source"],self.shoghi["source"]]:
            self.assertTrue(row["source_url"].startswith("https://www.bahai.org/library/"))
            self.assertRegex(row["sha256"],r"^[0-9a-f]{64}$"); self.assertRegex(row["retrieved"],r"^\d{4}-\d\d-\d\d$")
        ids=[i["id"] for i in self.items]
        self.assertEqual(len(ids),len(set(ids)))

    def test_attribution(self):
        for collection in (self.messages,self.shoghi):
            self.assertEqual(collection["copyright"],"Copyright © Bahá’í International Community")
            self.assertEqual(collection["terms"],"https://www.bahai.org/legal")
        for item in self.items:
            if item["id"].startswith(("uhj:","se:")):
                self.assertTrue(item["citation"].endswith("Copyright © Bahá’í International Community, bahai.org"),item["id"])
                self.assertTrue(item["citation"].startswith(("The Universal House of Justice, ","Shoghi Effendi, ")),item["id"])
        clip=reader.clipping(self.by_id[self.shoghi["items"][0]["id"]])
        self.assertTrue(clip.endswith("Copyright © Bahá’í International Community, bahai.org"))

    def test_text_is_clean_and_spans_fit(self):
        for row in self.messages["items"]+self.shoghi["items"]:
            text=row["text"]
            self.assertNotRegex(text,r"<[a-zA-Z/][^>]*>|&[a-z]+;|&#\d+;",row["id"])
            self.assertEqual(text,text.strip()); self.assertNotIn("\n\n\n",text); self.assertNotIn("  ",text)
            self.assertEqual(row["words"],reader.word_count(text),row["id"])
            for start,end,kind in row["spans"]:
                self.assertIn(kind,("i","b","u","num","quote","heading")); self.assertTrue(0<=start<end<=len(text),row["id"])

    def test_footnotes_are_complete(self):
        works={w["work"]:w for w in self.shoghi["works"]}
        for work in works.values():
            self.assertEqual(sum(i["notes"] for i in self.shoghi["items"] if i["work"]==work["work"]),work["notes"],work["work"])
        for row in self.messages["items"]+self.shoghi["items"]:
            body,_,notes=row["text"].partition("\n\nNotes\n\n") if row["notes"] else (row["text"],"","")
            markers=re.findall(r"[⁰¹²³⁴⁵⁶⁷⁸⁹]+",body)
            listed=re.findall(r"(?:^|\n\n)([⁰¹²³⁴⁵⁶⁷⁸⁹]+) ",notes)
            self.assertEqual(len(listed),row["notes"],row["id"])
            self.assertEqual(sorted(set(markers)),sorted(set(listed)),row["id"])

    def test_fidelity_spot_checks(self):
        # Sentences copied by hand from the bahai.org pages, with their punctuation and diacritics.
        adj=next(i for i in self.shoghi["items"] if i["work"]=="advent-divine-justice")
        self.assertIn("It would be difficult indeed to adequately express the feelings of irrepressible joy and exultation that flood my heart",adj["text"])
        self.assertTrue(adj["text"].startswith("To the beloved of God and the handmaids of the Merciful throughout the United States and Canada.\n\nBest-beloved brothers and sisters \nin the love of Bahá’u’lláh:".replace(" \n","\n")))
        hour=[i for i in self.shoghi["items"] if i["work"]=="decisive-hour"]
        self.assertEqual(len(hour),165)
        self.assertIn("⁵ Literally “The Dawning-Place of the Praise of God”; the title designating a Bahá’í House of Worship.",hour[2]["text"])
        counsellors=next(r for r in self.messages["items"] if r["document"]=="20211230_001")
        self.assertIn("At Riḍván this year we described how, over the course of a quarter century, the Bahá’í world underwent a transformation",counsellors["text"])
        self.assertTrue(counsellors["text"].endswith("[signed: The Universal House of Justice]"))
        gpb=[i for i in self.shoghi["items"] if i["work"]=="god-passes-by"]
        self.assertEqual([i["title"] for i in gpb][:2],["Foreword","I. The Birth of the Bábí Revelation"])
        self.assertEqual(gpb[2]["title"],"II. The Báb’s Captivity in Ádhirbáyján")
        # The underlined "dh" of the transliteration is kept as a span over the text.
        start=gpb[2]["text"].index("Ádhirbáyján")
        self.assertIn([start+1,start+3,"u"],gpb[2]["spans"])

    def test_works(self):
        self.assertEqual(sorted(w["title"] for w in self.shoghi["works"]),
            ["Bahá’í Administration","Citadel of Faith","God Passes By","The Advent of Divine Justice","The Promised Day Is Come","The World Order of Bahá’u’lláh","This Decisive Hour"])
        for work in self.shoghi["works"]: self.assertEqual(work["author"],"Shoghi Effendi")

class DuplicateTests(unittest.TestCase):
    """The official text is used wherever bahai.org has it: each Riḍván message from BahaiPrayers.net is replaced, once, under its own id."""
    @classmethod
    def setUpClass(cls):
        cls.messages=data("uhj-messages.json"); cls.ridvan={f"ridvan:{r['Id']}":r for r in data("ridvan.json")}
        cls.items=reader.load_library()

    def test_each_ridvan_message_is_replaced_by_one_official_text(self):
        replaces=[r["replaces"] for r in self.messages["items"] if r.get("replaces")]
        self.assertEqual(sorted(replaces),sorted(self.ridvan)); self.assertEqual(self.messages["ridvan_not_on_bahai_org"],[])
        self.assertEqual(sorted(r["replaces"] for r in self.messages["replacements"]),sorted(self.ridvan))

    def test_library_shows_the_official_text_once(self):
        by_id={}
        for item in self.items: by_id.setdefault(item["id"],[]).append(item)
        official={r["id"]:r for r in self.messages["items"]}
        for key in self.ridvan:
            self.assertEqual(len(by_id[key]),1,key)
            item=by_id[key][0]
            self.assertEqual(item["text"],official[item["official_id"]]["text"])
            self.assertTrue(item["citation"].endswith("Copyright © Bahá’í International Community, bahai.org"))
        replaced={r["id"] for r in self.messages["items"] if r.get("replaces")}
        self.assertFalse(replaced & set(by_id))  # not listed a second time under its bahai.org id
        # No BahaiPrayers.net copy of a message is left beside the official one.
        bp=[importer.shingles(re.sub(r"<[^>]+>"," ",html.unescape(r["Text"]))) for r in self.ridvan.values()]
        for item in self.items:
            if item["author"]=="The Universal House of Justice" and not item.get("official_id"): self.fail(item["id"])
        self.assertEqual(sum(1 for i in self.items if i["tags"]==["Riḍván Messages"]),65)
        new=[r for r in self.messages["items"] if not r.get("replaces")]
        for row in new:
            grams=importer.shingles(row["text"])
            self.assertFalse(any(importer.overlap(grams,other)>=importer.DUPLICATE for other in bp),row["id"])

class OfficialBooksTests(unittest.TestCase):
    """The app's BahaiPrayers.net books, now in bahai.org's text where bahai.org has the same passage."""
    @classmethod
    def setUpClass(cls):
        cls.data=data("bahai-org-books.json"); cls.books={b["key"]:b for b in cls.data["books"]}
        cls.items={i["id"]:i for i in reader.load_library()}
        cls.before={i["id"]:i for i in reader.load_bahaiprayers(1)}

    def test_every_passage_is_replaced_or_reported(self):
        for book in self.data["books"]:
            kept=sum(len(book["kept"][k]) for k in ("unmatched","split","partial","extra"))
            self.assertEqual(book["replaced"]+kept,book["rows"],book["key"])
            self.assertTrue(book["source_url"].startswith("https://www.bahai.org/library/authoritative-texts/"))
            self.assertRegex(book["sha256"],r"^[0-9a-f]{64}$")
        for ident,row in self.data["replacements"].items():
            self.assertIn(ident,self.before); self.assertIn(row["book"],self.books)

    def test_replaced_passages_keep_their_place_and_show_the_official_text(self):
        for ident,row in self.data["replacements"].items():
            item,old=self.items[ident],self.before[ident]
            self.assertEqual(item["text"],row["text"])
            self.assertEqual((item["section"],item["tags"],item["subgroup"],item["match"],item["references"]),(old["section"],old["tags"],old["subgroup"],old["match"],old["references"]))
            self.assertEqual(item["citation"],old["citation"]+". Copyright © Bahá’í International Community, bahai.org")
            self.assertEqual(item["word_count"],reader.word_count(item["text"]))
            self.assertNotRegex(item["title"],r"^(\d+) · \1 ")  # no doubled number from bahai.org's margin numbers
            for start,end,kind in row["spans"]: self.assertTrue(0<=start<end<=len(row["text"]))

    def test_hidden_words(self):
        book=self.books["hidden"]
        self.assertEqual((book["rows"],book["replaced"]),(153,153))
        first=self.items["hidden:1"]["text"]
        # The opening invocation and prologue of Part One, which the earlier copy lacked, open Arabic no. 1.
        self.assertTrue(first.startswith("HE IS THE GLORY OF GLORIES\n\nTHIS is that which hath descended from the realm of glory"))
        self.assertIn("\n\n1 O SON OF SPIRIT!\nMy first counsel is this: Possess a pure, kindly and radiant heart",first)
        start=first.index("\n\n1 ")+2; self.assertIn([start,start+1,"num"],self.data["replacements"]["hidden:1"]["spans"])
        self.assertTrue(self.items["hidden:72"]["text"].startswith("In the Name of the Lord of Utterance, the Mighty.\n\n1 O YE PEOPLE THAT HAVE MINDS"))
        self.assertIn("Sadratu’l-Muntahá",self.items["hidden:148"]["text"])  # the diacritic the earlier copy dropped
        self.assertEqual(self.items["hidden:148"]["title"][:22],"77 · O SON OF JUSTICE!")
        self.assertEqual(reader.heading(self.items["hidden:148"]),"Persian no. 77")

    def test_gleanings(self):
        book=self.books["gleanings"]
        self.assertEqual((book["rows"],book["replaced"]),(166,166))
        # bahai.org's edition capitalises the pronouns of the Manifestation in section XXXIX, where the earlier copy did not.
        self.assertIn("My persecutors decapitated Me, and, carrying aloft My head",self.items["gleanings:39"]["text"])
        self.assertTrue(self.items["gleanings:1"]["text"].startswith("LAUDED and glorified art Thou"))
        self.assertEqual(self.items["gleanings:1"]["title"][:20],"I · LAUDED and glori")
        self.assertEqual(reader.heading(self.items["gleanings:1"]),"I")
        # The section numbers are the passage headings, not repeated in the text.
        self.assertFalse(any("– I –" in i["text"] for k,i in self.items.items() if k.startswith("gleanings:")))

    def test_prayers_and_meditations(self):
        book=self.books["meditations"]
        self.assertEqual((book["rows"],book["replaced"]),(184,184))
        # Dotted letters the earlier copy lacked.
        self.assertIn("Thy Friend (Muḥammad)",self.items["meditations:38"]["text"]); self.assertIn("the horizon of Ḥijáz",self.items["meditations:38"]["text"])
        self.assertIn("(Riḍván)",self.items["meditations:2"]["text"])

    def test_tablets(self):
        book=self.books["tablets"]
        self.assertEqual((book["rows"],book["replaced"]),(660,660))
        # Lines the app keeps as passages of their own are placed on their own, not left behind or repeated.
        self.assertEqual(self.items["tablets:442"]["text"],"HE IS THE ALL-KNOWING")
        self.assertTrue(self.items["tablets:443"]["text"].startswith("O VAFÁ! Render thanks unto thy Lord"))
        self.assertTrue(self.items["tablets:141"]["text"].startswith("The word of God which the Abhá Pen hath revealed and inscribed on the"))
        self.assertNotIn("The word of God which",self.items["tablets:142"]["text"])
        # Notes follow the passage that cites them, and the app's footnotes passage lists bahai.org's notes by tablet.
        self.assertIn("the She-Serpent¹⁵ whose cruelty",self.items["tablets:506"]["text"])
        self.assertIn("\n\nNotes\n\n¹⁵ The Imám-Jum’ih of Iṣfáhán",self.items["tablets:506"]["text"])
        notes=self.items["tablets:660"]["text"]
        self.assertTrue(notes.startswith("2. Lawḥ-i-Aqdas (The Most Holy Tablet)\n\n¹ Sometimes referred to as Tablet to the Christians."))
        self.assertEqual(self.data["replacements"]["tablets:660"]["notes"],sum(1 for l in notes.split("\n\n") if re.match(r"[⁰¹²³⁴⁵⁶⁷⁸⁹]+ ",l)))

    def test_kitab_i_iqan(self):
        book=self.books["iqan"]
        self.assertEqual((book["rows"],book["replaced"]),(287,287))
        self.assertIn("the dayspring of Baṭḥá³⁴ unto Yathrib,³⁵ He",self.items["iqan:54"]["text"])
        self.assertIn("\n\nNotes\n\n³³ The direction toward which the face must be turned when praying.",self.items["iqan:54"]["text"])
        self.assertTrue(self.items["iqan:287"]["text"].startswith("Part One\n\n¹ Qur’án 36:30.\n\n² Qur’án 40:5."))

    def test_kitab_i_aqdas(self):
        book=self.books["aqdas"]
        self.assertEqual((book["rows"],book["replaced"]),(491,491))
        # Passages bahai.org has revised are placed by position and listed for review.
        self.assertEqual(sorted(r[0] for r in book["kept"]["revised"]),["aqdas:Notes:108","aqdas:Notes:113","aqdas:Notes:124","aqdas:Notes:140","aqdas:Notes:88","aqdas:QAs:49"])
        self.assertIn("“…it is enjoined upon you to offer a feast…” Is this obligatory or not?",self.items["aqdas:QAs:49"]["text"])
        # bahai.org's wording for cross-references, which the earlier copy had rewritten ("Q&A 66, Q&A 67").
        self.assertIn("Questions and Answers, numbers 66, 67, 81, and 82.",self.items["aqdas:Notes:3"]["text"])
        # The numbers the page draws before a list's items.
        self.assertIn("in the case of intestacy are:\n\n1. If the deceased is a father",self.items["aqdas:Notes:38"]["text"])
        # A note's closing remark stays with its note, not the next one.
        self.assertTrue(self.items["aqdas:Notes:21"]["text"].endswith("Numbers 21, 58, 59, 60, and 61 in Questions and Answers amplify this provision."))
        self.assertTrue(self.items["aqdas:Notes:22"]["text"].startswith("22. "))
        # Footnotes of the Questions and Answers follow them.
        self.assertIn("\n\nNotes\n\n¹ Bahá’u’lláh",self.items["aqdas:QAs:3"]["text"])
        # The obligatory prayer guidance still finds its paragraphs, notes and answers.
        groups=reader.obligatory(list(self.items.values()))
        self.assertEqual([i["id"] for i in groups["Kitáb-i-Aqdas"][:2]],["aqdas:Paragraphs:6","aqdas:Paragraphs:8"])

    def test_epistle_to_the_son_of_the_wolf(self):
        book=self.books["epistle"]; epistle=self.items["prayers:13691"]
        self.assertEqual((book["rows"],book["replaced"]),(1,1))
        self.assertTrue(epistle["text"].startswith("IN THE NAME OF GOD, THE ONE, THE INCOMPARABLE, THE ALL-POWERFUL"))
        self.assertIn("the greatest means for ensuring the tranquillity of",epistle["text"])
        self.assertNotIn("Translated by Shoghi Effendi",epistle["text"][:300])  # the title page stays out
        self.assertEqual((epistle["section"],epistle["tags"],epistle["title"]),("writings",["Epistle to the Son of the Wolf"],"Epistle to the Son of the Wolf"))

class UserDataTests(unittest.TestCase):
    """Bookmarks, collections, the last passage and preferences keep pointing at the same passages."""
    def test_existing_ids_are_unchanged(self):
        items=reader.load_library(); ids={i["id"] for i in items}
        # Every id the app had before is still there (73 of them now carry bahai.org's text).
        before={i["id"] for i in reader.load_bahaiprayers(1)}
        self.assertEqual(len(before),2616); self.assertLessEqual(before,ids)
        for known in ("prayers:13691","aqdas:Paragraphs:18","ridvan:1343","ridvan:1"): self.assertIn(known,ids)

    def test_saved_settings_survive(self):
        prefs={"saved":["ridvan:1343","prayers:13691","uhj:20211230_001","se:advent-divine-justice:316204556"],
               "collections":[{"name":"Study","items":["ridvan:1343","uhj:20211230_001"]}],"last":"ridvan:1","section":"writings","theme":"Sepia","size":24}
        clean=reader.clean_settings(json.loads(json.dumps(prefs)))
        self.assertEqual(clean["saved"],prefs["saved"]); self.assertEqual(clean["collections"],prefs["collections"])
        self.assertEqual((clean["last"],clean["section"],clean["theme"],clean["size"]),("ridvan:1","writings","Sepia",24))
        ids={i["id"] for i in reader.load_library()}
        for item in prefs["saved"]: self.assertIn(item,ids)

    def test_writings_grouping_setting(self):
        for value in ("book","author"): self.assertEqual(reader.clean_settings({"writings_by":value})["writings_by"],value)
        for bad in ("title",3,None): self.assertNotIn("writings_by",reader.clean_settings({"writings_by":bad}))

    def test_every_writing_has_an_author(self):
        for item in reader.load_library():
            if item["section"]=="writings": self.assertIn(item["author"],reader.AUTHOR_ORDER,item["id"])

    def test_other_languages_do_not_get_english_official_texts(self):
        with tempfile.TemporaryDirectory() as folder, unittest.mock.patch.object(reader,"LIBRARY",Path(folder)):
            self.assertEqual(reader.load_library(4),[])

@unittest.skipUnless(os.environ.get("BAHAI_LIBRARY_SOURCES"),"set BAHAI_LIBRARY_SOURCES to the importer's download folder")
class ReproducibleTests(unittest.TestCase):
    def test_build_from_sources_matches_data(self):
        self.assertEqual(importer.build(os.environ["BAHAI_LIBRARY_SOURCES"],write=False),[])

if __name__=="__main__": unittest.main()

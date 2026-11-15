"""QA findings on 0.2.1, in whichever window this system gets (CI runs it in both):
M1, a 5,000-character note with no spaces keeps the Highlights & notes page, Home and later views drawn at a normal width;
M2, highlights and saved passages made in English follow the reader to the same passage in another language, and back,
without the stored records changing; L2, the note editor counts characters and stops at the 5,000 a note keeps.
Run with xvfb-run -a /usr/bin/python3 tests/marks_qa_ui.py [installed|flatpak]."""
import copy
import json
import sys
import tempfile
from pathlib import Path
sys.path.insert(0, "/usr/share/bahai-reader" if "installed" in sys.argv else "/app/share/bahai-reader" if "flatpak" in sys.argv else str(Path(__file__).resolve().parents[1]))
sys.path.insert(1, str(Path(__file__).resolve().parent))
import reader
from bahai_reader import marks
from compare_pack import write_pack
from gi.repository import Gio, GLib, Gtk

WIDE=2000  # px; before the fix the page asked for about 50,000
LONG="x"*5000
with tempfile.TemporaryDirectory() as temp:
    reader.STATE=Path(temp)/"settings.json"; reader.LIBRARY=Path(temp)/"libraries"; reader.CACHE=Path(temp)/"cache"
    # A stand-in Spanish (4) library whose Hidden Words ids differ from English, so only the numbering can pair them.
    write_pack(reader.LIBRARY,books=("prayers","hidden"),id_offset=685)
    english=next(i for i in reader.load_library(1) if i["id"]=="hidden:2")
    prayer=next(i for i in reader.load_library(1) if i["section"]=="prayers")
    # Near the top of the passage, as in highlights_ui: under Xvfb a popover opened under the pointer (mid-screen) can crash
    # GTK 4.14 once it is closed, on main too.
    words="Justice"; start=english["text"].index(words)
    stored=[{"id":"hidden:2","start":start,"end":start+len(words),"words":words,"color":"blue","note":"Kept in English.","created":"2026-11-01"},
            {"id":prayer["id"],"start":0,"end":5,"words":prayer["text"][:5],"color":"green","created":"2026-11-02"},
            {"id":"hidden:3","start":0,"end":1,"words":"O","color":"yellow","note":LONG,"created":"2026-11-03"}]
    settings={"section":"hidden","last":"hidden:2","highlights":stored,"saved":["hidden:2",prayer["id"]],"collections":[{"name":"Morning","items":["hidden:2"]}]}
    reader.STATE.write_text(json.dumps(settings))
    original=copy.deepcopy(settings)
    app=reader.Reader(); app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
    errors=[]; passed=[]
    def width(widget):
        return widget.measure(Gtk.Orientation.HORIZONTAL,-1)[0]
    def starred():
        return app.star.get_icon_name()=="starred-symbolic" if app.adwaita else app.star.get_label().startswith("★")
    def drawn(widget):
        return widget.get_mapped() and widget.get_width()>0 and widget.get_height()>0
    def steps():
        while not (app.window and app.window.get_mapped()): yield
        shell="libadwaita" if app.adwaita else "classic"; print("window:",shell)
        # ----- M1: the long no-space note -----
        app.navigate("saved"); yield
        app.marks_row.emit("clicked"); yield; yield
        assert app.views.get_visible_child_name()=="highlights"
        card=next(c for r,c in app.mark_cards if r.get("note")==LONG)
        assert width(card)<WIDE and width(app.views)<WIDE and width(app.window)<WIDE, f"the list asks for {width(app.views)} px"
        assert app.window.get_width()<WIDE and drawn(card), "the Highlights & notes page is not drawn"
        # Home and the views opened after it are still drawn.
        app.navigate("home" if app.adwaita else "today"); yield; yield
        view=app.views.get_visible_child()
        assert drawn(view) and view.get_width()<WIDE and width(app.views)<WIDE, f"{shell}: Home went blank"
        app.navigate("hidden"); yield; yield
        assert app.views.get_visible_child_name()=="reading" and drawn(app.reader) and app.reader.get_width()<WIDE, f"{shell}: reading view went blank"
        # The note itself is kept whole.
        assert app.prefs["highlights"][2]["note"]==LONG
        # L2: the note editor counts characters and stops at the limit (lowered here, so the test types a few words, not thousands).
        assert app.current["id"]=="hidden:2"
        app.edit_highlight(app.prefs["highlights"][0]); yield
        count=app.mark_note_count; assert count.get_text()=="16 / 5,000" and count.get_visible(), count.get_text()
        limit=marks.NOTE_LIMIT; marks.NOTE_LIMIT=20
        try:
            buffer=app.mark_note.get_buffer(); text=lambda:buffer.get_text(buffer.get_start_iter(),buffer.get_end_iter(),False)
            buffer.insert(buffer.get_end_iter()," and more"); yield  # a paste keeps what fits
            assert text()=="Kept in English. and" and count.get_text()=="20 / 20" and count.has_css_class("warning"), (text(),count.get_text())
            buffer.insert(buffer.get_end_iter(),"x"); yield  # typing past the limit does nothing
            assert text()=="Kept in English. and" and count.get_text()=="20 / 20"
            buffer.set_text("Kept in English."); yield
            assert count.get_text()=="16 / 20" and not count.has_css_class("warning"), count.get_text()
        finally: marks.NOTE_LIMIT=limit
        app.mark_popover.popdown(); yield; yield
        assert app.prefs["highlights"][0]["note"]=="Kept in English."
        # ----- M2: switch to Spanish -----
        app.use_language(4); yield
        spanish=next(i for i in app.items if i.get("match")==english["match"])
        assert spanish["id"]!="hidden:2" and spanish["id"].startswith("4:hidden:"), spanish["id"]
        # Saved and its collection show the Spanish passage; the star is on.
        app.navigate("saved"); yield
        assert spanish in app.filed()["Morning"], "an English saved passage is not in its collection in Spanish"
        app.marks_row.emit("clicked"); yield
        cards={r["id"]:c for r,c in app.mark_cards}
        assert cards["hidden:2"].get_sensitive(), "the English highlight is listed as not in the current library"
        assert not cards[prayer["id"]].get_sensitive(), "a prayer has no counterpart and must stay unlisted"
        cards["hidden:2"].emit("clicked"); yield
        assert app.current is spanish and app.saved_key()=="hidden:2"
        assert starred(), "the English bookmark does not show as saved in Spanish"
        # The Spanish passage shows a passage-level marker with the note, and paints no word range.
        assert app.mark_notice.get_visible() and drawn(app.mark_notice), "no passage-level marker"
        texts=[]; stack=[app.mark_notice]
        while stack:
            w=stack.pop(); texts.append(w.get_label() if isinstance(w,Gtk.Label) else "")
            c=w.get_first_child()
            while c: stack.append(c); c=c.get_next_sibling()
        assert any("Kept in English." in t for t in texts), "the note is not shown on the Spanish passage"
        assert not app.painted, "an English word range was painted on the Spanish text"
        # Toggling the star there unsaves the English id, and nothing new is written.
        app.bookmark(); yield
        assert "hidden:2" not in app.prefs["saved"] and spanish["id"] not in app.prefs["saved"]
        assert app.prefs["collections"][0]["items"]==[] and not starred()
        app.bookmark(); yield
        assert app.prefs["saved"][-1]==spanish["id"]
        # A new highlight in Spanish is stored under the Spanish id and follows back to English.
        buffer=app.reader.get_buffer(); buffer.select_range(buffer.get_iter_at_offset(0),buffer.get_iter_at_offset(3))
        made=app.highlight_selection("magenta"); assert made and made["id"]==spanish["id"]
        # The English records are unchanged, field for field.
        assert app.prefs["highlights"][:3]==original["highlights"], "a stored highlight changed"
        assert json.loads(reader.STATE.read_text())["highlights"][:3]==original["highlights"]
        # ----- back to English -----
        app.use_language(1); yield
        app.navigate("hidden"); yield
        back=next(i for i in app.items if i["id"]=="hidden:2"); app.show_passage(back,[back]); yield
        assert app.saved_key()==spanish["id"], "the Spanish bookmark does not follow back to English"
        assert [r["id"] for r in app.painted]==["hidden:2"], "the English highlight is not drawn on its own words"
        assert app.mark_notice.get_visible(), "the Spanish highlight has no marker in English"
        app.navigate("saved"); yield; app.marks_row.emit("clicked"); yield
        assert all(c.get_sensitive() for r,c in app.mark_cards if r["id"]!=prayer["id"])
        passed.append(True); print("Marks QA UI test passed")
    walk=steps()
    def tick():
        try: next(walk); return True
        except StopIteration: pass
        except Exception as exc: errors.append(exc)
        app.quit(); return False
    GLib.timeout_add(400,tick)
    app.run([])
    if errors: raise errors[0]
    if not passed: raise SystemExit("Marks QA UI test did not complete")

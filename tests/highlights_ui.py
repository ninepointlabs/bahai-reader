"""Highlights and notes in whichever window this system gets (CI runs it in both): the bar on a selection, Ctrl+H, editing a
note, the list under Saved, opening a highlight, removing one, and that the text and copies are untouched.
Run with xvfb-run -a /usr/bin/python3 tests/highlights_ui.py [installed|flatpak]."""
import json
import sys
import tempfile
from pathlib import Path
sys.path.insert(0, "/usr/share/bahai-reader" if "installed" in sys.argv else "/app/share/bahai-reader" if "flatpak" in sys.argv else str(Path(__file__).resolve().parents[1]))
import reader
from gi.repository import Gio, Gdk, GLib

with tempfile.TemporaryDirectory() as temp:
    reader.STATE=Path(temp)/"settings.json"; reader.LIBRARY=Path(temp)/"libraries"; reader.CACHE=Path(temp)/"cache"
    reader.STATE.write_text('{"section":"hidden","last":"hidden:2"}')
    app=reader.Reader(); app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
    errors=[]; passed=[]
    def select(word):
        buffer=app.reader.get_buffer(); start=app.current["text"].index(word)
        buffer.select_range(buffer.get_iter_at_offset(start),buffer.get_iter_at_offset(start+len(word))); return start
    def tags_at(offset):
        return {t.get_property("name") for t in app.reader.get_buffer().get_iter_at_offset(offset).get_tags()}
    def steps():
        while not (app.window and app.window.get_mapped()): yield
        print("window:", "libadwaita" if app.adwaita else "classic")
        item=app.current; assert item["id"]=="hidden:2"
        original=app.reader.get_buffer().get_text(*app.reader.get_buffer().get_bounds(),False)
        # Selecting words brings up the bar once the selection settles.
        start=select("Justice")
        for _ in range(10):
            if app.mark_popover: break
            yield
        assert app.mark_popover and app.mark_popover.get_visible(), "the highlight bar did not appear"
        # A colour highlights the words.
        swatch=app.mark_bar.get_first_child().get_first_child().get_next_sibling()  # green
        swatch.emit("clicked"); yield
        records=app.prefs["highlights"]; assert len(records)==1 and records[0]["color"]=="green" and records[0]["words"]=="Justice"
        assert "hl-green" in tags_at(start) and "hl-green" not in tags_at(start-2)
        assert json.loads(reader.STATE.read_text())["highlights"][0]["words"]=="Justice", "saved to settings.json"
        # The text itself is unchanged, and so is what Copy copies.
        assert app.reader.get_buffer().get_text(*app.reader.get_buffer().get_bounds(),False)==original
        assert app.copy_passage()==reader.clipping(item)
        # Clicking a highlight opens it: write a note.
        app.edit_highlight(records[0]); yield
        app.mark_note.get_buffer().set_text("Read this every morning."); app.mark_popover.popdown(); yield; yield
        assert records[0]["note"]=="Read this every morning." and "hl-note" in tags_at(start)
        # Ctrl+H highlights a new selection in the last colour and opens its note.
        start2=select("thine own eyes")
        assert app.key_pressed(None,Gdk.KEY_h,0,Gdk.ModifierType.CONTROL_MASK); yield
        assert len(app.prefs["highlights"])==2 and app.prefs["highlights"][1]["color"]=="green" and app.mark_editing is app.prefs["highlights"][1]
        assert "hl-green" in tags_at(start2)
        app.mark_popover.popdown(); yield
        # Ctrl+H with nothing selected does nothing.
        buffer=app.reader.get_buffer(); buffer.select_range(*([buffer.get_start_iter()]*2))
        assert not app.key_pressed(None,Gdk.KEY_h,0,Gdk.ModifierType.CONTROL_MASK)
        # Saved → Highlights & notes lists them, newest first, with the note.
        app.navigate("saved"); yield
        assert app.marks_row.get_parent() is app.toc and app.marks_row.label.get_text()=="Highlights & notes · 2"
        app.marks_row.emit("clicked"); yield
        assert app.views.get_visible_child_name()=="highlights" and [r["words"] for r,_ in app.mark_cards]==["thine own eyes","Justice"]
        assert "2 highlights, 1 with a note" in app.marks_count.get_text()
        # Opening one goes to its passage.
        app.navigate("prayers"); app.navigate("saved"); app.marks_row.emit("clicked"); yield
        app.mark_cards[1][1].emit("clicked"); yield
        assert app.current["id"]=="hidden:2" and app.views.get_visible_child_name()=="reading" and "hl-green" in tags_at(start)
        # Another passage has none drawn.
        app.step(1); yield
        assert app.current["id"]!="hidden:2" and not app.painted
        app.step(-1); yield
        # Remove.
        app.remove_highlight(app.prefs["highlights"][0]); yield
        assert [r["words"] for r in app.prefs["highlights"]]==["thine own eyes"] and "hl-green" not in tags_at(start)
        passed.append(True); print("Highlights UI test passed")
    walk=steps()
    def tick():
        try: next(walk); return True
        except StopIteration: pass
        except Exception as exc: errors.append(exc)
        app.quit(); return False
    GLib.timeout_add(400,tick)
    app.run([])
    if errors: raise errors[0]
    if not passed: raise SystemExit("Highlights UI test did not complete")

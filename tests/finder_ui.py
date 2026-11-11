"""Ctrl+K search in whichever window this system gets (CI runs it in both): scopes, results grouped by book, opening a result
at the match, and the libadwaita reader's place line and book progress.
Run with xvfb-run -a /usr/bin/python3 tests/finder_ui.py [installed|flatpak]."""
import sys
import tempfile
from pathlib import Path
sys.path.insert(0, "/usr/share/bahai-reader" if "installed" in sys.argv else "/app/share/bahai-reader" if "flatpak" in sys.argv else str(Path(__file__).resolve().parents[1]))
import reader
from gi.repository import Gio, Gdk, GLib

def rows(listbox):
    found=[]; n=0
    while (row:=listbox.get_row_at_index(n)) is not None: found.append(row); n+=1
    return found

with tempfile.TemporaryDirectory() as temp:
    reader.STATE=Path(temp)/"settings.json"; reader.LIBRARY=Path(temp)/"libraries"; reader.CACHE=Path(temp)/"cache"
    reader.STATE.write_text('{"section":"hidden","last":"hidden:5"}')
    app=reader.Reader(); app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
    errors=[]; passed=[]
    def steps():
        while not (app.window and app.window.get_mapped()): yield
        print("window:", "libadwaita" if app.adwaita else "classic")
        assert app.section=="hidden" and app.current["id"]=="hidden:5"
        # Ctrl+K opens it; with the Hidden Words open, "This book" is offered.
        assert app.key_pressed(None,Gdk.KEY_k,0,Gdk.ModifierType.CONTROL_MASK) and app.finder is not None; yield
        assert app.finder_book=="The Hidden Words" and app.finder_scope_book.get_visible() and app.finder_scope_every.get_active()
        assert not rows(app.finder_results) and "Type a word" in app.finder_status.get_text()
        app.finder_entry.set_text("justice"); app.finder_update(); yield
        everything=rows(app.finder_results)
        assert everything and len(everything)<=60 and app.finder_scope_every.get_label().startswith("Everything · ")
        total=int(app.finder_scope_every.get_label().split("· ")[1]); assert total==len(reader.search_passages(app.items,"justice"))
        assert len({r.place for r in everything})>1, "results come from several books"
        # Grouped: each book's results together.
        places=[r.place for r in everything]; assert places==sorted(places,key=places.index)
        # This book only.
        app.finder_scope_book.set_active(True); yield
        hidden=rows(app.finder_results)
        assert hidden and all(r.place=="The Hidden Words" for r in hidden) and app.finder_scope_book.get_label()==f"This book · {len(hidden)}"
        # Opening a result: its passage, with the match selected.
        target=next(r for r in hidden if r.item["id"]=="hidden:2")
        app.finder_results.emit("row-activated",target); yield
        assert app.finder is None and app.current["id"]=="hidden:2" and app.views.get_visible_child_name()=="reading"
        buffer=app.reader.get_buffer(); bounds=buffer.get_selection_bounds()  # PyGObject: (start, end), or () with no selection
        assert bounds and buffer.get_text(*bounds,False)=="Justice", buffer.get_text(*bounds,False) if bounds else "no selection"
        # Accents and apostrophes do not matter, and Enter opens the first result.
        app.open_finder(); yield
        app.finder_scope_every.set_active(True); app.finder_entry.set_text("Bahaullah"); app.finder_update(); yield
        first=app.finder_results.get_row_at_index(0).item; app.finder_entry.emit("activate"); yield
        assert app.current is first and app.finder is None
        # Nothing found says so.
        app.open_finder(); app.finder_entry.set_text("zzqqxx"); app.finder_update(); yield
        assert not rows(app.finder_results) and "No passages match" in app.finder_status.get_text()
        app.close_finder(); yield
        assert app.finder is None
        if app.adwaita:
            # The reader's place: the book above the heading, passage and reading time below, progress through the book.
            app.open_book("God Passes By"); yield
            gpb=reader.books(app.items)["God Passes By"]; chapter=gpb[2]; app.show_passage(chapter,app.groups[chapter["id"]]); yield
            assert app.subtitle.has_css_class("eyebrow") and app.subtitle.get_parent().get_first_child() is app.subtitle
            assert app.reading_meta.get_text().startswith("Passage 3 of 27 · about ")
            before,total=reader.book_progress(gpb,chapter)
            assert abs(app.book_bar.get_fraction()-before/total)<1e-6 and app.progress_percent.get_text()==f"{round(100*before/total)}% of the book"
            assert app.progress_where.get_text()=="God Passes By · 3 of 27" and not app.position.get_visible()
            # A prayer: its place in its category, no book percentage.
            app.navigate("prayers"); prayer=next(i for i in app.items if i["section"]=="prayers" and i["tags"]==["Healing"])
            app.show_passage(prayer,app.groups[prayer["id"]]); yield
            assert app.reading_meta.get_text()=="" and app.progress_percent.get_text()=="" and app.progress_where.get_text().endswith(f"of {len(app.groups[prayer['id']])}")
        passed.append(True); print("Finder UI test passed")
    walk=steps()
    def tick():
        try: next(walk); return True
        except StopIteration: pass
        except Exception as exc: errors.append(exc)
        app.quit(); return False
    GLib.timeout_add(400,tick)
    app.run([])
    if errors: raise errors[0]
    if not passed: raise SystemExit("Finder UI test did not complete")

"""The libadwaita window: Home, the library, a book's contents in the sidebar, Continue reading, Prayers with the obligatory
prayers, narrow windows, focus mode, toasts and the theme mapping. Needs libadwaita 1.4 or newer; without it the test says so
and passes (the classic window is tested by the other UI tests).
Run with xvfb-run -a /usr/bin/python3 tests/shell_ui.py [installed|flatpak]."""
import os
import sys
import tempfile
from pathlib import Path
os.environ.setdefault("BAHAI_READER_SHELL","adwaita")
sys.path.insert(0, "/usr/share/bahai-reader" if "installed" in sys.argv else "/app/share/bahai-reader" if "flatpak" in sys.argv else str(Path(__file__).resolve().parents[1]))
import reader
from bahai_reader import shell
from gi.repository import Gio, Gdk, GLib

if os.environ["BAHAI_READER_SHELL"]=="classic" or not shell.adwaita():
    print("libadwaita 1.4 or newer is not available here: the classic window is used, and tested by the other UI tests. Shell UI test skipped.")
    raise SystemExit(0)

with tempfile.TemporaryDirectory() as temp:
    reader.STATE=Path(temp)/"settings.json"; reader.LIBRARY=Path(temp)/"libraries"; reader.CACHE=Path(temp)/"cache"
    reader.STATE.write_text('{"theme":"Light"}')
    app=reader.Reader(); app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
    errors=[]; passed=[]
    def steps():
        while not (app.window and app.window.get_mapped()): yield
        assert app.adwaita and isinstance(app.window,app.Adw.ApplicationWindow)
        # A new install opens on Home: the four sections, the day at a glance, and the library as books by author.
        assert app.section=="home" and app.views.get_visible_child_name()=="home"
        assert list(app.switcher_rows)==["home","prayers","writings","saved"] and app.switcher.get_selected_row() is app.switcher_rows["home"]
        assert not app.contents_box.get_visible(), "Home has no contents list"
        assert ("date","Open Today") in app.home_buttons
        shelf=reader.books(app.items)
        assert set(app.home_cards)==set(shelf) and len(shelf)==18
        assert not app.continue_cards and not app.continue_title.get_visible(), "nothing read yet"
        # Writings is the library, not a list of 2,901 passages.
        app.switcher.select_row(app.switcher_rows["writings"]); yield
        assert app.section=="writings" and app.book is None and app.views.get_visible_child_name()=="library" and not app.contents_box.get_visible()
        assert set(app.library_cards)==set(shelf) and app.content_title.get_title()=="Library"
        # A book: its contents in the sidebar, Back to the library, its passage on the right.
        app.library_cards["God Passes By"].emit("clicked"); yield
        gpb=shelf["God Passes By"]
        assert app.section=="writings" and app.book=="God Passes By" and app.views.get_visible_child_name()=="reading"
        assert app.current is gpb[0] and app.book_back.get_visible() and not app.switcher.get_visible()
        assert app.side_title.get_title()=="God Passes By" and app.side_title.get_subtitle().startswith("Shoghi Effendi · ")
        assert {i["id"] for i,_ in app.passage_buttons}=={i["id"] for i in gpb}, "the contents are this book only"
        assert app.content_title.get_title()=="God Passes By"
        chapter=gpb[2]; app.open_from_list(chapter,app.groups[chapter["id"]]); yield
        # The parts that hold it open, so the contents show where the reader is.
        button=next(b for i,b in app.passage_buttons if i is chapter)
        assert button.container.expander.get_expanded() and button.get_mapped()
        assert app.prefs["positions"]["God Passes By"]==chapter["id"] and app.prefs["recent"][0]=="God Passes By"
        app.leave_book(); yield
        assert app.section=="writings" and app.book is None and app.views.get_visible_child_name()=="library"
        # The Hidden Words is a book too.
        app.library_cards["The Hidden Words"].emit("clicked"); yield
        assert app.section=="hidden" and app.book_back.get_visible() and app.side_title.get_title()=="The Hidden Words"
        assert app.switcher.get_selected_row() is app.switcher_rows["writings"]
        # Continue reading on Home, most recent first, back at the same passage.
        app.navigate("home"); yield
        assert [b for b,_ in app.continue_cards]==["The Hidden Words","God Passes By"] and app.continue_title.get_visible()
        dict(app.continue_cards)["God Passes By"].emit("clicked"); yield
        assert app.book=="God Passes By" and app.current is chapter
        # Prayers: the obligatory prayers are its first group; they open as their own page with Back to Prayers.
        app.switcher.select_row(app.switcher_rows["prayers"]); yield
        assert app.section=="prayers" and app.toc.get_first_child() is app.obligatory_row and not app.book_back.get_visible()
        app.obligatory_row.emit("clicked"); yield
        assert app.section=="obligatory" and app.switcher.get_selected_row() is app.switcher_rows["prayers"]
        assert app.book_back.get_visible() and app.side_title.get_title()=="Obligatory prayers" and "Short Obligatory Prayer" in app.current["tags"]
        app.leave_book(); yield
        assert app.section=="prayers"
        # Today opens from Home's card and with Ctrl+T; it belongs to Home in the sidebar.
        app.navigate("home"); yield
        app.home_buttons["date","Open Today"].emit("clicked"); yield
        assert app.section=="today" and app.views.get_visible_child_name()=="today" and app.switcher.get_selected_row() is app.switcher_rows["home"]
        app.navigate("home"); yield
        assert app.key_pressed(None,Gdk.KEY_t,0,Gdk.ModifierType.CONTROL_MASK) and app.section=="today"
        # Saving counts in the sidebar.
        app.library_cards["The Hidden Words"].emit("clicked"); yield
        app.bookmark(); assert app.nav_counts["saved"].get_text()=="1" and app.star.get_icon_name()=="starred-symbolic"
        # Focus mode: F11 hides the sidebar and the header; Esc brings them back.
        bars=app.splitview.get_content().get_child()
        assert app.key_pressed(None,Gdk.KEY_F11,0,0) and app.focus_mode and not bars.get_reveal_top_bars() and app.splitview.get_collapsed()
        yield
        assert app.key_pressed(None,Gdk.KEY_Escape,0,0) and not app.focus_mode and bars.get_reveal_top_bars() and not app.splitview.get_collapsed()
        # Settings windows are libadwaita preferences dialogs; closing them clears them as before.
        Adw=app.Adw; kind=Adw.PreferencesDialog if hasattr(Adw,"PreferencesDialog") else Adw.PreferencesWindow
        for opener,name in ((app.location_dialog,"location_window"),(app.language_dialog,"language_window"),(app.collections_dialog,"collections_window")):
            opener(); yield
            window=getattr(app,name); assert isinstance(window,kind), (name,type(window))
            window.close(); yield
            assert getattr(app,name) is None, name
        # Closed while still animating open, a dialog still goes away (libadwaita 1.5, Ubuntu 24.04, otherwise leaves it stuck).
        app.location_dialog(); quick=app.location_window; quick.close()
        for _ in range(12):
            if quick.get_parent() is None: break
            yield
        assert quick.get_parent() is None and app.location_window is None, "a dialog closed as it opened stayed on screen"
        # The location window's content works inside it: the city search finds Haifa.
        app.location_dialog(); yield
        app.location_search.set_text("Haifa"); yield; yield
        assert app.location_results.get_first_child() is not None
        app.location_window.close(); yield
        # Keyboard shortcuts: libadwaita's dialog (1.8+) or GTK's shortcuts window, from Ctrl+?.
        assert app.key_pressed(None,Gdk.KEY_question,0,Gdk.ModifierType.CONTROL_MASK|Gdk.ModifierType.SHIFT_MASK); yield
        assert app.shortcuts_window is not None and type(app.shortcuts_window).__name__ in ("ShortcutsDialog","ShortcutsWindow"), type(app.shortcuts_window)
        app.shortcuts_window.close(); yield
        assert app.shortcuts_window is None
        # Notices are toasts.
        app.notice("A test notice."); assert app.notice_texts()[-1]=="A test notice."
        # The palette reaches libadwaita through its named colours.
        css=app.provider.to_string()
        assert "window_bg_color" in css or "--window-bg-color" in css or "#fafaf7" in css.lower(), css[:300]
        # Narrow: the split view collapses; the sidebar and the reader take turns.
        app.window.set_default_size(420,760)
        for _ in range(20):
            if app.narrow: break
            yield
        assert app.narrow and app.splitview.get_collapsed() and not app.panel_button.get_visible() and not app.copy.get_visible()
        app.show_list(True); yield
        assert not app.splitview.get_show_content()
        item=app.section_items[3]; app.open_from_list(item,app.groups[item["id"]]); yield
        assert app.splitview.get_show_content() and app.current is item
        assert app.key_pressed(None,Gdk.KEY_Escape,0,0) and not app.splitview.get_show_content()
        app.navigate("home"); yield
        assert app.splitview.get_show_content() and app.home_today.get_orientation()==reader.Gtk.Orientation.VERTICAL
        app.window.set_default_size(1160,790)
        for _ in range(20):
            if not app.narrow: break
            yield
        assert not app.narrow and not app.splitview.get_collapsed() and app.panel_button.get_visible()
        passed.append(True); print("Shell UI test passed")
    walk=steps()
    def tick():
        try: next(walk); return True
        except StopIteration: pass
        except Exception as exc: errors.append(exc)
        app.quit(); return False
    GLib.timeout_add(400,tick)
    app.run([])
    if errors: raise errors[0]
    if not passed: raise SystemExit("Shell UI test did not complete")

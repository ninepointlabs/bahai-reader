"""Search keeps the reading position; keyboard paging; empty states.
Run with xvfb-run -a /usr/bin/python3 tests/navigation_ui.py [installed|flatpak]."""
import sys
import tempfile
import time
from pathlib import Path
sys.path.insert(0, "/usr/share/bahai-reader" if "installed" in sys.argv else "/app/share/bahai-reader" if "flatpak" in sys.argv else str(Path(__file__).resolve().parents[1]))
import reader
from gi.repository import Gio, Gdk
with tempfile.TemporaryDirectory() as temp:
    reader.STATE=Path(temp)/"settings.json"; reader.LIBRARY=Path(temp)/"libraries"; reader.CACHE=Path(temp)/"cache"
    app=reader.Reader(); app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
    errors=[]; passed=[]
    def search(text):
        app.search.set_text(text); app.filter()  # search-changed itself is delayed
    def exercise():
        try:
            app.navigate("prayers")
            search("short")
            assert app.visible and app.count.get_text()==f"{len(app.visible)} passage{'s' if len(app.visible)!=1 else ''}"
            chosen=app.visible[-1]; app.show_passage(chosen,app.groups[chosen["id"]])
            search("Bahaullah")  # does not contain the open passage: the reader stays put
            assert app.current is chosen and app.visible, "typing moved the reading position"
            search("")
            assert app.current is chosen, f"clearing the search moved to {app.current['id']} (QA M6)"
            assert len(app.visible)==sum(i["section"]=="prayers" for i in app.items)
            search("zzzz-no-such-word")
            assert app.no_match.get_visible() and app.current is chosen and app.count.get_text()=="0 passages"
            search("")
            # One match: singular label (QA C2).
            word=max(app.section_items,key=lambda i:len(i["text"]))["text"].split()[0:6]
            search(" ".join(word)); assert app.count.get_text()=="1 passage" or len(app.visible)>1
            search("")
            # Hide rows instead of rebuilding them (QA L6).
            app.navigate("writings"); search("Bahaullah")  # first search also folds the section's text
            start=time.perf_counter(); search("Bahaulla"); search("Bahaull"); elapsed=(time.perf_counter()-start)/2
            print(f"Writings filter: {elapsed*1000:.0f} ms per keystroke")
            search("")
            # Previous/Next from the keyboard (QA L1).
            app.navigate("hidden"); first=app.current; group=app.active_group
            assert app.page_key(None,Gdk.KEY_Right,0,Gdk.ModifierType.ALT_MASK) and app.current is group[group.index(first)+1]
            assert app.page_key(None,Gdk.KEY_Page_Up,0,Gdk.ModifierType.CONTROL_MASK) and app.current is first
            assert not app.page_key(None,Gdk.KEY_Right,0,0)
            # Tab leaves the contents list in one step.
            assert app.list_key(None,Gdk.KEY_Tab,0,0) and app.list_key(None,Gdk.KEY_ISO_Left_Tab,0,Gdk.ModifierType.SHIFT_MASK)
            # Empty Saved passages explains how to save (QA L12).
            app.navigate("saved")
            assert app.heading.get_text()=="No saved passages yet" and "Ctrl+D" in app.subtitle.get_text()
            app.navigate("hidden"); app.bookmark(); app.navigate("saved")
            assert len(app.visible)==1 and app.count.get_text()=="1 passage"
            # Ctrl+Q works while About has focus (QA L5).
            app.about_dialog()
            assert app.quit_key(None,Gdk.KEY_q,0,Gdk.ModifierType.CONTROL_MASK)
            passed.append(True); print("Navigation UI test passed")
        except Exception as exc:
            errors.append(exc)
        app.quit(); return False
    reader.GLib.timeout_add(500,exercise)
    app.run([])
    if errors: raise errors[0]
    if not passed: raise SystemExit("Navigation UI test did not complete")

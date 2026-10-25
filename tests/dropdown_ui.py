"""Run with xvfb-run -a /usr/bin/python3 tests/dropdown_ui.py. Settings and language choices use Gtk.DropDown (QA I1)."""
import json
import sys
import tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import reader
from gi.repository import Gio, Gtk

def widgets(root):
    child=root.get_first_child()
    while child:
        yield child; yield from widgets(child)
        child=child.get_next_sibling()

with tempfile.TemporaryDirectory() as temp:
    reader.STATE=Path(temp)/"settings.json"
    reader.LIBRARY=Path(temp)/"libraries"
    reader.CACHE=Path(temp)/"cache"
    reader.STATE.write_text(json.dumps({"theme":"Sepia"}))
    app=reader.Reader()
    app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
    errors=[]
    passed=[]
    def exercise():
        try:
            assert not any(isinstance(w,Gtk.ComboBox) for w in widgets(app.window))
            choices=[w for w in widgets(app.window) if isinstance(w,reader.Choice)]
            theme=next(c for c in choices if c.ids==["Omarchy","Light","Dark","Sepia"])
            assert theme.get_active_text()=="Sepia", theme.get_active_text()
            font=next(c for c in choices if c is not theme)
            assert font.get_active_id()==app.prefs.get("font",font.get_active_id()) and font.get_active_id() in font.ids
            theme.set_selected(1)
            assert app.prefs["theme"]=="Light" and json.loads(reader.STATE.read_text())["theme"]=="Light"
            theme.set_active_id("Not a theme")
            assert theme.get_active_id()=="Light"
            app.language_dialog()
            language=next(w for w in widgets(app.language_window) if isinstance(w,reader.Choice))
            assert language.get_enable_search() and language.get_active_id()=="1"
            assert len(language.ids)==len(app.languages["prayers"])==language.get_model().get_n_items()
            labels=[w for w in widgets(app.language_window) if isinstance(w,Gtk.Label)]
            info=next(l for l in labels if l.get_text().startswith("Available offline"))
            other=next(i for i in language.ids if i!="1")
            language.set_active_id(other)
            assert language.get_active_id()==other and info.get_text().startswith("Download needed"), info.get_text()
            language.remove_all()
            assert language.get_active_id() is None and language.get_active_text() is None
            app.language_window.close()
            passed.append(True)
            print("Dropdown UI test passed")
        except Exception as exc:
            errors.append(exc)
        app.quit()
        return False
    reader.GLib.timeout_add(500,exercise)
    app.run([])
    if errors: raise errors[0]
    if not passed: raise SystemExit("Dropdown UI test did not complete")

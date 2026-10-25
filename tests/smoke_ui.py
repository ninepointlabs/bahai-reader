"""Run with xvfb-run -a /usr/bin/python3 tests/smoke_ui.py [installed|flatpak]."""
import sys
import tempfile
from pathlib import Path
sys.path.insert(0, "/usr/share/bahai-reader" if "installed" in sys.argv else "/app/share/bahai-reader" if "flatpak" in sys.argv else str(Path(__file__).resolve().parents[1]))
import reader
from gi.repository import Gio
with tempfile.TemporaryDirectory() as temp:
    reader.STATE=Path(temp)/"settings.json"
    reader.LIBRARY=Path(temp)/"libraries"
    reader.CACHE=Path(temp)/"cache"
    app=reader.Reader()
    app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
    errors=[]
    passed=[]
    def exercise():
        try:
            assert len(app.items)==2616
            app.navigate("writings")
            assert len([p for p in app.branches if p.count("/")==1])==9
            app.navigate("hidden")
            assert len(app.visible)==153
            buffer=app.reader.get_buffer()
            assert buffer.get_text(buffer.get_start_iter(),buffer.get_end_iter(),False).endswith("— "+app.current["citation"])
            app.language_dialog()
            assert app.language_window.get_visible()
            app.language_window.close()
            assert app.key_pressed(None,reader.Gdk.KEY_F1,0,0)
            about=app.about_window
            assert about.get_visible() and about.get_transient_for() is app.window
            assert list(app.about_rows)==["Made by","Created","License","Texts","Support","Privacy","Built with"]
            assert "bahaiprayers.net" in app.privacy() and "No accounts, no telemetry" in app.privacy()
            assert not app.about_license.get_visible()
            app.about_rows["License"].get_last_child().emit("clicked")
            assert app.about_license.get_visible() and app.about_license.get_text().startswith("MIT License")
            assert "BahaiPrayers.net" in app.about_license.get_text()
            assert app.details().startswith("Bahá’í Reader "+reader.version())
            about.close()
            assert app.about_window is None
            app.prefs["theme"]="Light"
            app.apply_theme()
            passed.append(True)
            print("Native GTK smoke test passed")
        except Exception as exc:
            errors.append(exc)
        app.quit()
        return False
    reader.GLib.timeout_add(500,exercise)
    app.run([])
    if errors: raise errors[0]
    # A failure inside activate() is logged by PyGObject but does not stop run().
    if not passed: raise SystemExit("Native GTK smoke test did not complete")

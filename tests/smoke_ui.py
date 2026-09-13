"""Run with xvfb-run -a /usr/bin/python3 tests/smoke_ui.py [installed]."""
import sys
import tempfile
from pathlib import Path
sys.path.insert(0, "/usr/share/bahai-reader" if "installed" in sys.argv else str(Path(__file__).resolve().parents[1]))
import reader
from gi.repository import Gio
with tempfile.TemporaryDirectory() as temp:
    reader.STATE=Path(temp)/"settings.json"
    reader.LIBRARY=Path(temp)/"libraries"
    reader.CACHE=Path(temp)/"cache"
    app=reader.Reader()
    app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
    errors=[]
    def exercise():
        try:
            assert len(app.items)==2616
            app.navigate("writings")
            assert len([p for p in app.branches if p.count("/")==1])==8
            app.navigate("hidden")
            assert len(app.visible)==153
            app.language_dialog()
            assert app.language_window.get_visible()
            app.language_window.close()
            app.prefs["theme"]="Light"
            app.apply_theme()
            print("Native GTK smoke test passed")
        except Exception as exc:
            errors.append(exc)
        app.quit()
        return False
    reader.GLib.timeout_add(500,exercise)
    app.run([])
    if errors: raise errors[0]

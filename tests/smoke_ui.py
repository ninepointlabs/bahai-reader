"""Run with xvfb-run -a /usr/bin/python3 tests/smoke_ui.py [installed|flatpak]."""
import sys
import tempfile
from pathlib import Path
sys.path.insert(0, "/usr/share/bahai-reader" if "installed" in sys.argv else "/app/share/bahai-reader" if "flatpak" in sys.argv else str(Path(__file__).resolve().parents[1]))
import reader
import gi
gi.require_version("GdkPixbuf","2.0")
from gi.repository import Gio, Gtk, Graphene, GdkPixbuf

def pixel(widget,x,y):
    """Render a widget offscreen and return the #rrggbb color at (x, y)."""
    width,height=widget.get_width(),widget.get_height()
    snapshot=Gtk.Snapshot(); Gtk.WidgetPaintable.new(widget).snapshot(snapshot,width,height)
    node=snapshot.to_node()
    if node is None: return None  # not drawn since its last layout yet
    texture=widget.get_native().get_renderer().render_texture(node,Graphene.Rect().init(0,0,width,height))
    loader=GdkPixbuf.PixbufLoader(); loader.write_bytes(texture.save_to_png_bytes()); loader.close()
    image=loader.get_pixbuf(); data=image.get_pixels(); offset=y*image.get_rowstride()+x*image.get_n_channels()
    return "#%02x%02x%02x"%tuple(data[offset:offset+3])
with tempfile.TemporaryDirectory() as temp:
    reader.STATE=Path(temp)/"settings.json"
    reader.LIBRARY=Path(temp)/"libraries"
    reader.CACHE=Path(temp)/"cache"
    # Light palette from the start, so the first frame is drawn with it.
    reader.STATE.write_text('{"theme":"Light"}')
    app=reader.Reader()
    app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
    errors=[]
    passed=[]
    waits=[]
    def exercise():
        if pixel(app.sidebar,1,1) is None and len(waits)<100:
            waits.append(1); return True  # wait for the first frame after layout
        try:
            assert len(app.items)==2616
            # The contents list follows the reading palette, not the GTK theme's sidebar color (QA H1).
            assert pixel(app.sidebar,app.sidebar.get_width()//2,app.sidebar.get_height()-4)==app.colors["background"]=="#fafaf7"
            app.navigate("writings")
            assert len([p for p in app.branches if p.count("/")==1])==8
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
    reader.GLib.timeout_add(100,exercise)
    app.run([])
    if errors: raise errors[0]
    # A failure inside activate() is logged by PyGObject but does not stop run().
    if not passed: raise SystemExit("Native GTK smoke test did not complete")

"""Run with xvfb-run -a /usr/bin/python3 tests/smoke_ui.py [installed|flatpak]."""
import sys
import tempfile
from pathlib import Path
sys.path.insert(0, "/usr/share/bahai-reader" if "installed" in sys.argv else "/app/share/bahai-reader" if "flatpak" in sys.argv else str(Path(__file__).resolve().parents[1]))
import reader
import struct
import zlib
from collections import Counter
from gi.repository import Gio, Gtk, Graphene
from compare_pack import write_pack

def png_pixels(data):
    """Decode a non-interlaced 8/16-bit RGB(A) PNG; GdkPixbuf's loader can't run in the Flatpak sandbox."""
    width,height,depth,kind=struct.unpack(">IIBB",data[16:26])
    chunks=b""; i=8
    while i<len(data):
        length,name=struct.unpack(">I4s",data[i:i+8])
        if name==b"IDAT": chunks+=data[i+8:i+8+length]
        i+=12+length
    raw=zlib.decompress(chunks); channels={2:3,6:4}[kind]; size=depth//8; bpp=channels*size; stride=width*bpp
    rows=[]; previous=bytearray(stride); pos=0
    for _ in range(height):
        kind_filter=raw[pos]; line=bytearray(raw[pos+1:pos+1+stride]); pos+=1+stride
        for x in range(stride):
            a=line[x-bpp] if x>=bpp else 0; b=previous[x]; c=previous[x-bpp] if x>=bpp else 0
            if kind_filter==1: line[x]=(line[x]+a)&255
            elif kind_filter==2: line[x]=(line[x]+b)&255
            elif kind_filter==3: line[x]=(line[x]+(a+b)//2)&255
            elif kind_filter==4:
                p=a+b-c; pa,pb,pc=abs(p-a),abs(p-b),abs(p-c)
                line[x]=(line[x]+(a if pa<=pb and pa<=pc else b if pb<=pc else c))&255
        rows.append(line); previous=line
    return width,height,lambda x,y: tuple(rows[y][x*bpp+k*size] for k in range(3))

def background(widget):
    """Most common #rrggbb in the lower half of a widget rendered offscreen, or None before its first frame."""
    width,height=widget.get_width(),widget.get_height()
    snapshot=Gtk.Snapshot(); Gtk.WidgetPaintable.new(widget).snapshot(snapshot,width,height)
    try: node=snapshot.to_node()
    except TypeError: return "unsupported"  # PyGObject before 3.44 can't pass render nodes (Debian 12)
    if node is None: return None  # not drawn since its last layout yet
    texture=widget.get_native().get_renderer().render_texture(node,Graphene.Rect().init(0,0,width,height))
    w,h,pixel=png_pixels(texture.save_to_png_bytes().get_data())
    return "#%02x%02x%02x"%Counter(pixel(x,y) for x in range(0,w,3) for y in range(h//2,h,3)).most_common(1)[0][0]

def close(first,second,tolerance=3):
    return all(abs(int(first[i:i+2],16)-int(second[i:i+2],16))<=tolerance for i in (1,3,5))

# A dark GTK theme under the Light palette is where the contents list went dark (QA H1).
Gtk.Settings.get_default().set_property("gtk-application-prefer-dark-theme",True)
with tempfile.TemporaryDirectory() as temp:
    reader.STATE=Path(temp)/"settings.json"
    reader.LIBRARY=Path(temp)/"libraries"
    reader.CACHE=Path(temp)/"cache"
    # Light palette from the start, so the first frame is drawn with it; side by side with a downloaded language.
    reader.STATE.write_text('{"theme":"Light","compare":4}')
    write_pack(reader.LIBRARY)
    # Reading, including side by side, never uses the network.
    def offline(*args,**kwargs): raise AssertionError(f"network request while reading: {args}")
    reader.urllib.request.urlopen=offline
    app=reader.Reader()
    app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
    errors=[]
    passed=[]
    waits=[]
    def exercise():
        color=background(app.sidebar)
        if color is None and len(waits)<100:
            waits.append(1); return True  # wait for the first frame after layout
        try:
            assert len(app.items)==2616
            # The contents list follows the reading palette, not the GTK theme's sidebar color (QA H1).
            if color=="unsupported": print("Note: this PyGObject cannot render widgets offscreen; contents list color not checked")
            else: assert color and close(color,"#fafaf7"), f"contents list background is {color}, not the Light palette's #fafaf7"
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
            # Side by side: on from the start; a Hidden Word pairs with the downloaded library by its number.
            app.navigate("hidden")
            second=app.second.get_buffer(); text=lambda: second.get_text(second.get_start_iter(),second.get_end_iter(),False)
            assert app.secondscroll.get_visible() and app.current["match"]=="hidden:True:1", app.current["match"]
            assert text().split("\n")[1].startswith("[4] ") and app.current["text"][:40] in text(), text()[:120]
            app.navigate("prayers")
            assert app.secondscroll.get_visible() and "cannot be shown side by side" in text()
            app.navigate("writings"); gleaning=next(i for i in app.section_items if i["id"]=="gleanings:1"); app.show_passage(gleaning,app.groups[gleaning["id"]])
            assert "not in the downloaded" in text()
            app.fill_compare()
            assert app.compare.ids==["","4"] and app.compare.get_active_id()=="4"
            app.compare.set_active_id("")
            assert not app.secondscroll.get_visible() and "compare" not in reader.json.loads(reader.STATE.read_text())
            app.compare.set_active_id("4"); assert app.secondscroll.get_visible() and reader.json.loads(reader.STATE.read_text())["compare"]==4
            app.use_language(4)  # reading the downloaded language: English is offered beside it
            app.fill_compare(); assert app.compare.ids==["","1"] and not app.secondscroll.get_visible()
            app.compare.set_active_id("1"); app.navigate("hidden")
            assert app.current["text"].startswith("[4]") and text().startswith("ENGLISH\n") and "[4]" not in text()
            app.use_language(1)
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

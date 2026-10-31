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
    # Light palette from the start, so the first frame is drawn with it.
    reader.STATE.write_text('{"theme":"Light"}')
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
            # Obligatory prayers: the three prayers first, open, then the Aqdas guidance; Next stays among the prayers.
            app.navigate("obligatory")
            assert list(p for p in app.branches if p.count("/")==1)==["obligatory/The three prayers","obligatory/Kitáb-i-Aqdas"]
            assert app.branches["obligatory/The three prayers"].get_expanded() and len(app.visible)==19
            assert app.current["tags"]==["Short Obligatory Prayer"] and app.heading.get_text()=="Prayer"
            app.step(1); assert app.current["tags"]==["Medium Obligatory Prayer"]
            app.step(1); app.step(1); assert app.current["tags"]==["Long Obligatory Prayer"]
            app.navigate("hidden")
            assert len(app.visible)==153
            buffer=app.reader.get_buffer()
            assert buffer.get_text(buffer.get_start_iter(),buffer.get_end_iter(),False).endswith("— "+app.current["citation"])
            # Ctrl+Shift+C puts the passage and its citation on the clipboard.
            assert app.key_pressed(None,reader.Gdk.KEY_C,0,reader.Gdk.ModifierType.CONTROL_MASK|reader.Gdk.ModifierType.SHIFT_MASK)
            assert app.copy.get_label()=="Copied"
            pasted=[]; loop=reader.GLib.MainLoop()
            app.window.get_clipboard().read_text_async(None,lambda c,r:(pasted.append(c.read_text_finish(r)),loop.quit()))
            reader.GLib.timeout_add(3000,loop.quit); loop.run()
            assert pasted==[app.current["text"]+"\n\n— "+app.current["citation"]], pasted
            start=buffer.get_start_iter(); end=start.copy(); end.forward_word_end(); buffer.select_range(start,end)
            assert app.copy_passage()==buffer.get_text(start,end,False)+"\n\n— "+app.current["citation"]
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

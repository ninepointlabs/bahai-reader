"""Narrow and wide windows keep the text and Previous/Next on screen (QA M2, L3, C1).
Run with xvfb-run -a /usr/bin/python3 tests/layout_ui.py [installed|flatpak]; each size runs in its own process."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

SIZES=[(436,700),(360,420),(1160,790)]

def child(width,height,temp):
    sys.path.insert(0, "/usr/share/bahai-reader" if "installed" in sys.argv else "/app/share/bahai-reader" if "flatpak" in sys.argv else str(Path(__file__).resolve().parents[1]))
    import reader
    from gi.repository import Gio, GLib, Gtk
    temp=Path(temp)
    reader.STATE=temp/"settings.json"; reader.LIBRARY=temp/"libraries"; reader.CACHE=temp/"cache"
    # A sidebar width saved by an older version that hid the reading pane.
    reader.STATE.write_text(json.dumps({"section":"hidden","sidebar_width":1381}))
    app=reader.Reader(); app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
    app.connect("window-added",lambda _a,window: window.set_default_size(width,height))
    result={}
    def bounds(widget):
        ok,rect=widget.compute_bounds(app.window)
        return [rect.get_x(),rect.get_x()+rect.get_width()] if ok else None
    def check():
        # Some backends (Broadway) size windows themselves; ask again and re-evaluate.
        app.window.set_default_size(width,height); app.window_resized()
        nav=app.position.get_parent()
        titlebar=app.window.get_titlebar()
        # The app's own content; a desktop's window buttons in the title bar are reported separately.
        result.update(window=app.window.get_width(),minimum=app.window.get_child().measure(Gtk.Orientation.HORIZONTAL,-1)[0],
                      titlebar=titlebar.measure(Gtk.Orientation.HORIZONTAL,-1)[0] if titlebar else None,star=app.star.get_label(),narrow=app.narrow,
                      sidebar=app.sidebar.get_visible(),content=app.content.get_visible(),nav=bounds(nav),reader=bounds(app.readscroll),
                      margin=app.reader.get_left_margin(),heading=app.heading.get_text(),position=app.position.get_text())
        if app.narrow:
            app.toggle_sidebar(); result["list"]=[app.sidebar.get_visible(),app.content.get_visible()]
            item=app.section_items[1]; app.open_passage(item,app.groups[item["id"]]); result["after_open"]=[app.sidebar.get_visible(),app.content.get_visible()]
        app.quit(); return False
    GLib.timeout_add(1500,check)
    app.run([])
    print(json.dumps(result))

def main():
    failures=[]
    for width,height in SIZES:
        with tempfile.TemporaryDirectory() as temp:
            run=subprocess.run([sys.executable,__file__,"--size",str(width),str(height),temp,*sys.argv[1:]],capture_output=True,text=True,timeout=120)
            lines=[l for l in run.stdout.splitlines() if l.startswith("{")]
            if run.returncode or not lines: failures.append(f"{width}x{height}: exit {run.returncode}\n{run.stderr[-2000:]}"); continue
            r=json.loads(lines[-1]); problems=[]
            if r["minimum"]>width: problems.append(f"window cannot shrink below {r['minimum']} px")
            if r["window"]==width:
                if r["nav"] is None or r["nav"][0]<0 or r["nav"][1]>r["window"]: problems.append(f"Previous/Next outside the window: {r['nav']}")
                if r["reader"] is None or r["reader"][1]>r["window"] or r["reader"][1]-r["reader"][0]<300: problems.append(f"reading pane clipped: {r['reader']}")
            else: print(f"note {width}x{height}: the display server kept the window at {r['window']} px; on-screen bounds not checked")
            if r["titlebar"]: print(f"note {width}x{height}: title bar with this desktop's window buttons needs {r['titlebar']} px")
            if width<700 and r["star"] not in ("☆","★"): problems.append(f"Save button not compact: {r['star']!r}")
            if r["heading"]!="Arabic no. 1" or r["position"]!="1 of 71": problems.append(f"heading {r['heading']!r}, position {r['position']!r}")
            if width<700:
                if not r["narrow"] or r["sidebar"] or not r["content"]: problems.append(f"narrow window shows both panes: {r}")
                if r.get("list")!=[True,False] or r.get("after_open")!=[False,True]: problems.append(f"☰ does not switch panes: {r}")
            elif not (r["sidebar"] and r["content"]): problems.append(f"wide window hides a pane: {r}")
            if problems: failures.append(f"{width}x{height}: "+"; ".join(problems))
            else: print(f"ok {width}x{height}: margin {r['margin']}, nav {r['nav']}")
    if failures: raise SystemExit("\n".join(failures))
    print("Layout UI test passed")

if __name__=="__main__":
    if "--size" in sys.argv:
        i=sys.argv.index("--size"); child(int(sys.argv[i+1]),int(sys.argv[i+2]),sys.argv[i+3])
    else: main()

"""Narrow and wide windows keep the text, Today, the counter and Previous/Next on screen.
Run with xvfb-run -a /usr/bin/python3 tests/layout_ui.py [installed|flatpak]; each size runs in its own process."""
import os
os.environ["BAHAI_READER_SHELL"]="classic"  # the classic window's layout (the libadwaita window's is tested in shell_ui.py)
import json
import subprocess
import sys
import tempfile
from pathlib import Path

SIZES=[(320,480),(436,700),(699,700),(700,700),(1160,790)]

def child(width,height,temp):
    sys.path.insert(0, "/usr/share/bahai-reader" if "installed" in sys.argv else "/app/share/bahai-reader" if "flatpak" in sys.argv else str(Path(__file__).resolve().parents[1]))
    import reader
    from gi.repository import Gio, GLib, Gtk
    temp=Path(temp)
    reader.STATE=temp/"settings.json"; reader.LIBRARY=temp/"libraries"; reader.CACHE=temp/"cache"
    # A sidebar width saved by an older version that hid the reading pane; the longest Today card there is.
    reader.STATE.write_text(json.dumps({"section":"hidden","sidebar_width":1381,"theme":"Dark","prayer":"medium","collections":[{"name":"A collection with quite a long name","items":[]}],"location":{"label":"Haifa, Israel","lat":32.81,"lon":35.0,"tz":"Asia/Jerusalem"}}))
    # The header in the window's own content, as on Omarchy, so that its width counts here on every desktop.
    which=reader.shutil.which; reader.shutil.which=lambda name:"/usr/bin/omarchy" if name=="omarchy" else which(name)
    app=reader.Reader(); app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
    app.connect("window-added",lambda _a,window: window.set_default_size(width,height))
    result={"minimums":{}}
    measure=lambda:app.window.get_child().measure(Gtk.Orientation.HORIZONTAL,-1)[0]
    def bounds(widget):
        ok,rect=widget.compute_bounds(app.window)
        return [rect.get_x(),rect.get_x()+rect.get_width()] if ok else None
    def steps():
        # Wait for the window to be on screen: asked before the display server's first configure, the size can be lost to the
        # window's 1160 px default when that configure arrives (a slower start makes this likelier).
        while not (app.window and app.window.get_mapped()): yield
        yield
        # Some backends (Broadway) size windows themselves; ask again and re-evaluate.
        app.window.set_default_size(width,height); app.window_resized(); yield; yield; yield
        nav=app.position.get_parent()
        result.update(window=app.window.get_width(),star=app.star.get_label(),narrow=app.narrow,sidebar=app.sidebar.get_visible(),content=app.views.get_visible(),nav=bounds(nav),reader=bounds(app.readscroll),
                      margin=app.reader.get_left_margin(),heading=app.heading.get_text(),position=app.position.get_text(),copy=app.copy.get_visible(),entries=[e.get_visible() for e in app.narrow_entries],previous=app.previous.get_label())
        result["minimums"]["reading"]=measure()
        # Saved, with its collection row showing.
        app.bookmark(); yield
        result["minimums"]["saved"]=measure(); app.bookmark(); yield
        # Side by side stacks in a narrow window.
        app.secondscroll.set_visible(True); yield
        result["minimums"]["side by side"]=measure(); result["stacked"]=app.pages.get_orientation()==Gtk.Orientation.VERTICAL; app.secondscroll.set_visible(False)
        app.show_counter(); yield
        result["minimums"]["counter"]=measure(); app.leave_counter(); yield
        if app.narrow:
            app.toggle_sidebar(); result["list"]=[app.sidebar.get_visible(),app.views.get_visible()]; yield
            result["minimums"]["list"]=measure()
            # Choosing a section stays in the list, to pick from it.
            app.navigate("prayers"); result["section_stays"]=[app.sidebar.get_visible(),app.views.get_visible()]; app.navigate("hidden"); yield
            item=app.section_items[1]; app.open_from_list(item,app.groups[item["id"]]); result["after_open"]=[app.sidebar.get_visible(),app.views.get_visible()]; yield
            app.key_pressed(None,reader.Gdk.KEY_Escape,0,0); result["escape"]=[app.sidebar.get_visible(),app.views.get_visible()]; yield
            app.random_passage(); result["random"]=[app.sidebar.get_visible(),app.views.get_visible()]; yield
            app.toggle_sidebar(); yield
            app.navigate("today"); result["today"]=[app.sidebar.get_visible(),app.views.get_visible()]; yield
        else: app.navigate("today"); yield
        yield
        result["minimums"]["today"]=measure()
        if app.narrow:
            # Back to wide: everything returns.
            app.window.set_default_size(1160,790); yield; yield; yield
            result["wide_again"]=[app.narrow,app.sidebar.get_visible(),app.views.get_visible(),app.copy.get_visible(),app.app_title.get_visible(),app.star.get_label()]
    walk=steps()
    def tick():
        try: next(walk); return True
        except StopIteration: app.quit(); return False
    GLib.timeout_add(700,tick)
    app.run([])
    print(json.dumps(result))

def main():
    failures=[]
    for width,height in SIZES:
        with tempfile.TemporaryDirectory() as temp:
            run=subprocess.run([sys.executable,__file__,"--size",str(width),str(height),temp,*sys.argv[1:]],capture_output=True,text=True,timeout=120)
            lines=[l for l in run.stdout.splitlines() if l.startswith("{")]
            if run.returncode or not lines: failures.append(f"{width}x{height}: exit {run.returncode}\n{run.stderr[-2000:]}"); continue
            r=json.loads(lines[-1]); problems=[]; narrow=width<700
            for view,minimum in r["minimums"].items():
                if minimum>width: problems.append(f"{view}: window cannot shrink below {minimum} px")
            if r["window"]==width:
                if r["nav"] is None or r["nav"][0]<0 or r["nav"][1]>r["window"]: problems.append(f"Previous/Next outside the window: {r['nav']}")
                if r["reader"] is None or r["reader"][1]>r["window"] or r["reader"][1]-r["reader"][0]<280: problems.append(f"reading pane clipped: {r['reader']}")
            else: print(f"note {width}x{height}: the display server kept the window at {r['window']} px; on-screen bounds not checked")
            if r["window"]==width and narrow and r["margin"]!=min(80,max(12,(width-360)//2)): problems.append(f"page margin {r['margin']} at {width} px")
            if r["heading"]!="Arabic no. 1" or r["position"]!="1 of 71": problems.append(f"heading {r['heading']!r}, position {r['position']!r}")
            if r["narrow"]!=narrow: problems.append(f"narrow is {r['narrow']}")
            if narrow:
                if r["star"] not in ("☆","★"): problems.append(f"Save button not compact: {r['star']!r}")
                if r["sidebar"] or not r["content"]: problems.append(f"narrow window shows both panes or neither: {r}")
                if r["copy"] or r["entries"]!=[True] or r["previous"]!="←": problems.append(f"header not compact: {r}")
                if not r["stacked"]: problems.append("side by side not stacked")
                for name,want in (("list",[True,False]),("section_stays",[True,False]),("after_open",[False,True]),("escape",[True,False]),("random",[False,True]),("today",[False,True])):
                    if r.get(name)!=want: problems.append(f"{name}: {r.get(name)}, wanted {want}")
                if r.get("wide_again")!=[False,True,True,True,True,"☆ Save"]: problems.append(f"wide again: {r.get('wide_again')}")
            else:
                if not (r["sidebar"] and r["content"]): problems.append(f"wide window hides a pane: {r}")
                if not r["copy"] or any(r["entries"]) or r["previous"]!="← Previous": problems.append(f"header not full: {r}")
            if problems: failures.append(f"{width}x{height}: "+"; ".join(problems))
            else: print(f"ok {width}x{height}: margin {r['margin']}, minimums {r['minimums']}")
    if failures: raise SystemExit("\n".join(failures))
    print("Layout UI test passed")

if __name__=="__main__":
    if "--size" in sys.argv:
        i=sys.argv.index("--size"); child(int(sys.argv[i+1]),int(sys.argv[i+2]),sys.argv[i+3])
    else: main()

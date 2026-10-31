"""Damaged settings and libraries still open a window with a notice.
Run with xvfb-run -a /usr/bin/python3 tests/robustness_ui.py [installed|flatpak]; each case runs in its own process."""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

CASES={
    "wrong-types":('{"size":"abc","margin":1e9,"section":"bogus","saved":["hidden:1"]}',None),
    "not-an-object":("[]","settings.json.bad"),
    "invalid-json":('{"saved":["prayers:258"],"la',"settings.json.bad"),
    "read-only-folder":('{"saved":["hidden:1"]}',"cannot be stored"),
    "corrupt-pack":('{"language":4}',"could not be read, so English is shown"),
    "damaged-collections":('{"saved":"oops","collections":[{"name":"Kept","items":["hidden:2",3]},"junk",{"items":["hidden:1"]}]}',None),
}

def child(case,temp):
    sys.path.insert(0, "/usr/share/bahai-reader" if "installed" in sys.argv else "/app/share/bahai-reader" if "flatpak" in sys.argv else str(Path(__file__).resolve().parents[1]))
    import reader
    from gi.repository import Gio, GLib
    temp=Path(temp); config=temp/"config"; config.mkdir()
    reader.STATE=config/"settings.json"; reader.LIBRARY=temp/"libraries"; reader.CACHE=temp/"cache"
    reader.STATE.write_text(CASES[case][0])
    if case=="corrupt-pack":
        reader.LIBRARY.mkdir(); (reader.LIBRARY/"4.json").write_text('{"prayers":')
    if case=="read-only-folder": config.chmod(0o500)
    app=reader.Reader(); app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
    result={}
    def check():
        if case=="read-only-folder": app.bookmark()  # a save that cannot be written
        row=app.notice_box.get_first_child(); notices=[]
        while row: notices.append(row.get_first_child().get_text()); row=row.get_next_sibling()
        result.update(window=app.window is not None and app.window.get_visible(), notices=notices, prefs=app.prefs, section=app.section, language=app.language,
                      files=sorted(p.name for p in config.iterdir()))
        app.quit(); return False
    GLib.timeout_add(500,check)
    app.run([])
    if case=="read-only-folder": config.chmod(0o700)
    print(json.dumps(result))

def main():
    failures=[]
    for case,(_,expected) in CASES.items():
        with tempfile.TemporaryDirectory() as temp:
            run=subprocess.run([sys.executable,__file__,"--case",case,temp,*sys.argv[1:]],capture_output=True,text=True,timeout=120)
            lines=[l for l in run.stdout.splitlines() if l.startswith("{")]
            if run.returncode or not lines:
                failures.append(f"{case}: exit {run.returncode}\n{run.stderr[-2000:]}"); continue
            result=json.loads(lines[-1]); problems=[]
            if not result["window"]: problems.append("no window")
            if expected and not any(expected in n for n in result["notices"]) and expected not in result["files"]: problems.append(f"expected {expected!r} in notices/files: {result}")
            if case=="wrong-types":
                if result["prefs"].get("saved")!=["hidden:1"] or "size" in result["prefs"] or result["prefs"].get("margin")!=160 or result["section"]!="prayers": problems.append(str(result))
            if case=="invalid-json" and not any("saved passages" in n for n in result["notices"]): problems.append(str(result))
            if case=="corrupt-pack" and result["language"]!=1: problems.append(str(result))
            if case=="damaged-collections" and (result["prefs"].get("saved")!=["hidden:2","hidden:1"] or result["prefs"].get("collections")!=[{"name":"Kept","items":["hidden:2"]}]): problems.append(str(result))
            if problems: failures.append(f"{case}: "+"; ".join(problems))
            else: print(f"ok {case}")
    if failures: raise SystemExit("\n".join(failures))
    print("Robustness UI test passed")

if __name__=="__main__":
    if "--case" in sys.argv:
        i=sys.argv.index("--case"); child(sys.argv[i+1],sys.argv[i+2])
    else: main()

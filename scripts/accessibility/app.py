"""Runs the app through its main screens for the accessibility audit, moving keyboard focus as a user would.
Writes the current step's name to /tmp/a11y-state, and waits for the auditor to say "done" in /tmp/a11y-ack."""
import sys, tempfile, json, os, time
from pathlib import Path
sys.path.insert(0,sys.argv[1]); import reader
from gi.repository import Gio, GLib, Gdk
t=tempfile.mkdtemp(); reader.STATE=Path(t)/"s.json"; reader.LIBRARY=Path(t)/"l"; reader.CACHE=Path(t)/"c"
reader.STATE.write_text(json.dumps({"theme":"Light","location":{"label":"Haifa, Israel","lat":32.81,"lon":35.0,"tz":"Asia/Jerusalem"},"prayer":"short"}))
app=reader.Reader(); app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
def focus(widget): widget.grab_focus()
def probe():
    from gi.repository import Gtk
    app.navigate("prayers")
    b=Gtk.Button(); bx=Gtk.Box(); bx.append(Gtk.Label(label="probe-inner")); b.set_child(bx)
    b.update_property([Gtk.AccessibleProperty.LABEL],["PROBE-DIRECT"]); app.toc.prepend(b)
    c=Gtk.Button(); cx=Gtk.Box(); cx.append(Gtk.Label(label="probe2-inner")); c.set_child(cx); app.name_widget(c,"PROBE-NAMEWIDGET"); app.toc.prepend(c)
    try: app.obligatory_row.update_property([Gtk.AccessibleProperty.LABEL],["OBLIG-RENAMED"])
    except Exception as e: print("rename failed",e,flush=True)
steps=[("home",lambda:(app.navigate("home"),focus(app.switcher_rows["home"]))),
       ("home-card",lambda:focus(app.home_cards["The Hidden Words"])),
       ("library",lambda:(app.navigate("writings"),focus(app.library_cards["God Passes By"]))),
       ("book",lambda:(app.open_book("The Hidden Words"),focus(app.next))),
       ("contents",lambda:(app.show_list(True),app.focus_list())),
       ("reader-text",lambda:focus(app.reader)),
       ("star",lambda:focus(app.star)),
       ("prayers",lambda:(app.navigate("prayers"),focus(app.obligatory_row))),
       ("obligatory",lambda:(app.navigate("obligatory"),focus(app.said_toggle) if app.said_toggle.get_visible() else focus(app.next))),
       ("counter",lambda:app.show_counter()),
       ("today",lambda:(app.navigate("today"),app.focus_view())),
       ("search",lambda:(app.open_finder(),app.finder_entry.set_text("justice"),app.finder_update())),
       ("search-result",lambda:(app.finder_results.get_row_at_index(0).grab_focus())),
       ("menu",lambda:(app.close_finder(),app.app_menu.popup())),
       ("highlights",lambda:(app.close_finder(),app.navigate("saved"),app.show_marks(),focus(app.marks_row) if getattr(app,"marks_row",None) else None)),
      ]
pending=list(steps); last=[None]
def tick():
    if last[0] is not None:
        ack=Path("/tmp/a11y-ack")
        if not ack.exists() or ack.read_text()!=last[0]: return True
    if not pending:
        Path("/tmp/a11y-state").write_text("end"); app.quit(); return False
    name,action=pending.pop(0)
    try: action()
    except Exception as exc: print("step failed",name,exc,flush=True)
    def mark():
        Path("/tmp/a11y-state").write_text(name); last[0]=name; return False
    GLib.timeout_add(900,mark)
    last[0]="__waiting__"
    return True
def started(*_):
    app.window.set_default_size(1200,800)
    GLib.timeout_add(1500,lambda:(GLib.timeout_add(300,tick),False)[1])
app.connect_after("activate",started)
app.run([])

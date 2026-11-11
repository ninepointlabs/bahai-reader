"""The section switcher, the header, list names and tooltips, and the reading footer (UX Phase 1).
Run with xvfb-run -a /usr/bin/python3 tests/chrome_ui.py [installed|flatpak]."""
import os
os.environ["BAHAI_READER_SHELL"]="classic"  # the classic window's chrome (UX Phase 1); the libadwaita window is tested in shell_ui.py
import sys
import tempfile
from pathlib import Path
sys.path.insert(0, "/usr/share/bahai-reader" if "installed" in sys.argv else "/app/share/bahai-reader" if "flatpak" in sys.argv else str(Path(__file__).resolve().parents[1]))
import reader
from gi.repository import Gio, Gtk, Gdk

def children(widget):
    child=widget.get_first_child()
    while child: yield child; child=child.get_next_sibling()

def descendants(widget):
    for child in children(widget):
        yield child; yield from descendants(child)

def labels(widget):
    return [w.get_label() for w in descendants(widget) if isinstance(w,Gtk.Label)]

with tempfile.TemporaryDirectory() as temp:
    reader.STATE=Path(temp)/"settings.json"; reader.LIBRARY=Path(temp)/"libraries"; reader.CACHE=Path(temp)/"cache"
    app=reader.Reader(); app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
    errors=[]; passed=[]; frames=[]
    def exercise():
        try:
            # One compact list of sections, Today among them and nowhere else as a button.
            rows=list(children(app.switcher))
            assert [r.section for r in rows]==list(reader.SECTIONS), [r.section for r in rows]
            assert [labels(r)[0] for r in rows]==["Today","Prayers","Obligatory prayers","The Hidden Words","Writings","Saved passages"]
            assert app.switcher.get_selected_row().section=="today"
            buttons=[w for w in descendants(app.window) if isinstance(w,Gtk.Button) and w.get_mapped()]
            texts=[b.get_label() for b in buttons]
            assert "Today" not in texts and "Random" not in texts, texts
            assert not [b for b in buttons if b.get_ancestor(Gtk.ListBox) is app.switcher], "sections are rows, not bordered buttons"
            # Choosing a row navigates; navigating elsewhere selects the row.
            app.switcher.select_row(app.switcher_rows["hidden"]); assert app.section=="hidden"
            app.navigate("prayers"); assert app.switcher.get_selected_row() is app.switcher_rows["prayers"]
            # Ctrl+R still opens a random passage.
            assert app.key_pressed(None,Gdk.KEY_r,0,Gdk.ModifierType.CONTROL_MASK) and app.current
            # Branch names that do not fit keep their whole name in a tooltip.
            app.navigate("prayers")
            for path,expander in app.branches.items():
                label=expander.get_label_widget().get_first_child()
                assert label.get_tooltip_text()==label.get_label() and label.get_hexpand(), path
            # Obligatory prayers: named rows, and a heading that says where the reader is.
            app.navigate("obligatory")
            box=app.branches["obligatory/The three prayers"].get_child()
            assert [labels(b)[0] for b in children(box)]==list(reader.OBLIGATORY_PRAYERS), [labels(b) for b in children(box)]
            assert all(b.get_tooltip_text() for b in children(box))
            assert app.heading.get_text()=="Obligatory prayers" and "Short Obligatory Prayer" in app.subtitle.get_text()
            app.step(1); assert app.heading.get_text()=="Obligatory prayers" and "Medium Obligatory Prayer" in app.subtitle.get_text()
            # A prayer is headed by its category, not "Prayer".
            app.navigate("prayers"); healing=next(i for i in app.items if i["section"]=="prayers" and i["tags"]==["Healing"])
            app.show_passage(healing,app.groups[healing["id"]]); assert app.heading.get_text()=="Healing", app.heading.get_text()
            assert app.subtitle.get_text().startswith(healing["author"]+" · ")
            # The citation sits right under the text: one line break, no empty paragraph.
            buffer=app.reader.get_buffer(); text=buffer.get_text(buffer.get_start_iter(),buffer.get_end_iter(),False)
            assert text==healing["text"]+"\n— "+healing["citation"], repr(text[-200:])
            frames.append(1); return False
        except Exception as exc:
            errors.append(exc); app.quit(); return False
    def footer():
        if not frames: return True
        try:
            # Previous/Next sit under a divider, below the text, and the fade covers the text's lower edge, not the buttons.
            app.window.set_default_size(1000,700)
            ok,pages=app.pages.compute_bounds(app.window); ok2,fade=app.fade.compute_bounds(app.window); ok3,bar=app.footer.compute_bounds(app.window)
            if not (ok and ok2 and ok3) or fade.get_height()<=0:
                frames.append(1)
                if len(frames)<100: return True
                raise AssertionError("the footer was never laid out")
            pb=pages.get_y()+pages.get_height(); fb=fade.get_y()+fade.get_height()
            assert abs(fb-pb)<=1 and fade.get_height()==reader.FADE_HEIGHT, (pb,fb,fade.get_height())
            assert bar.get_y()>=pb-1, (bar.get_y(),pb)
            assert app.footer.has_css_class("reading-footer") and app.next.has_css_class("primary")
            assert not app.fade.get_can_target(), "the fade must not catch clicks or scrolling"
            # The text can always scroll clear of the fade.
            assert app.reader.get_bottom_margin()>=reader.FADE_HEIGHT
            passed.append(True); print("Chrome UI test passed")
        except Exception as exc:
            errors.append(exc)
        app.quit(); return False
    reader.GLib.timeout_add(500,exercise)
    reader.GLib.timeout_add(700,footer)
    app.run([])
    if errors: raise errors[0]
    if not passed: raise SystemExit("Chrome UI test did not complete")

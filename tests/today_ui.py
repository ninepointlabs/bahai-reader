"""The Today view at fixed moments, and first run versus an existing reading position.
Run with xvfb-run -a /usr/bin/python3 tests/today_ui.py [installed|flatpak]."""
import datetime
import json
import sys
import tempfile
from pathlib import Path
sys.path.insert(0, "/usr/share/bahai-reader" if "installed" in sys.argv else "/app/share/bahai-reader" if "flatpak" in sys.argv else str(Path(__file__).resolve().parents[1]))
import reader
from gi.repository import Gio, Gdk
UTC=datetime.timezone.utc
HAIFA={"label":"Haifa, Israel","lat":32.81,"lon":35.0,"tz":"Asia/Jerusalem"}
TROMSO={"label":"Tromsø, Norway","lat":69.65,"lon":18.96,"tz":"Europe/Oslo"}

def texts(app,card):
    found=[]; child=app.today_cards[card].get_first_child()
    while child:
        found.append(child.get_label()); child=child.get_next_sibling()
    return found

with tempfile.TemporaryDirectory() as temp:
    reader.STATE=Path(temp)/"settings.json"; reader.LIBRARY=Path(temp)/"libraries"; reader.CACHE=Path(temp)/"cache"
    app=reader.Reader(); app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
    errors=[]; passed=[]
    def at(*moment,place=None):
        app.fixed_now=datetime.datetime(*moment,tzinfo=UTC)
        app.prefs.pop("location",None)
        if place: app.prefs["location"]=place
        app.navigate("today")
    def exercise():
        try:
            assert reader.json.loads(reader.STATE.read_text())["section"]=="today", "a new install opens on Today"
            # No location: one quiet line and a button; the date follows the calendar day.
            at(2026,11,11,20,0)
            assert texts(app,"date")[0]=="8 Qudrat 183 B.E.", texts(app,"date")
            assert "11 November 2026" in texts(app,"date")[1] and "The month of Qudrat: Power." in texts(app,"date") and any("begins at sunset" in t for t in texts(app,"date"))
            assert texts(app,"sun")[1]=="Add your location to see sunrise, noon and sunset" and ("sun","Add location…") in app.today_buttons
            # With a location: the Badí‘ day changes at local sunset, about 14:50 UTC in Haifa.
            at(2026,11,10,12,0,place=HAIFA); assert texts(app,"date")[0]=="7 Qudrat 183 B.E."
            at(2026,11,10,16,0,place=HAIFA); assert texts(app,"date")[0]=="8 Qudrat 183 B.E." and "after sunset" in texts(app,"date")[1], texts(app,"date")
            assert any(t.startswith("Sunrise:") for t in texts(app,"sun")) and "Haifa, Israel" in texts(app,"sun")
            # Next Feast and Holy Day, with work suspended noted and a link to its readings.
            at(2026,11,1,10,0,place=HAIFA)
            events=texts(app,"events"); assert "Feast of Qudrat (Power)" in events and "Begins at sunset on 3 November." in events, events
            assert "Birth of the Báb" in events and "Begins at sunset on 9 November. Work is suspended." in events, events
            app.today_buttons["events","Readings for Birth of the Báb"].emit("clicked")
            assert app.section=="writings" and reader.badi_days_tag(app.current)=="BIRTHBAB" and app.subtitle.get_text().startswith("Readings for Birth of the Báb")
            assert all(reader.badi_days_tag(i)=="BIRTHBAB" for i in app.active_group)
            # Near Naw-Rúz and Ayyám-i-Há: prayers from the feed.
            at(2027,2,20,10,0,place=HAIFA)
            events=texts(app,"events"); assert "Ayyám-i-Há" in events and ("events","Prayers for Ayyám-i-Há") in app.today_buttons, events
            app.today_buttons["events","Prayers for Ayyám-i-Há"].emit("clicked"); assert "Intercalary Days" in app.current["tags"]
            at(2027,3,15,10,0,place=HAIFA)
            assert "Naw-Rúz" in texts(app,"events") and ("events","Prayers for Naw-Rúz") in app.today_buttons
            app.today_buttons["events","Prayers for Naw-Rúz"].emit("clicked"); assert "Naw-Rúz" in app.current["tags"]
            # The calendar in the sidebar, and search narrowing it.
            at(2026,11,1,10,0,place=HAIFA)
            assert app.branches["today/Upcoming"].get_expanded() and app.branches["today/This year"].get_expanded()
            names=[i["title"] for i in app.section_items]; assert "Birth of the Báb" in names and "Qudrat (Power)" in names and "Ayyám-i-Há" in names, names
            assert len([i for i in app.section_items if i["group"].startswith("This year")])==20
            assert all(i["group"]=="This year, 183 B.E." for i in app.section_items if i["title"]=="Qudrat (Power)")
            app.search.set_text("naw ruz".replace(" ","-")); app.filter()
            assert [i["title"] for i in app.visible]==["Naw-Rúz"] and app.count.get_text()=="1 date", [i["title"] for i in app.visible]
            app.search.set_text("zzzz"); app.filter(); assert app.no_match.get_visible() and "No dates match" in app.no_match.get_text()
            app.search.set_text(""); app.filter()
            birth=next(b for i,b in app.passage_buttons if i["title"]=="Birth of the Báb"); birth.emit("clicked")
            assert reader.badi_days_tag(app.current)=="BIRTHBAB"
            # Polar day: no sunset, and the date says so.
            at(2026,6,21,22,0,place=TROMSO)
            assert "The sun does not set today." in texts(app,"sun") and any("does not set here today" in t for t in texts(app,"date"))
            # After 221 B.E.: nothing is guessed.
            at(2065,3,20,10,0,place=HAIFA)
            assert reader.badi.UNPUBLISHED in texts(app,"date") and reader.badi.UNPUBLISHED in texts(app,"events") and not app.section_items, texts(app,"date")
            assert any("20 March 2065" in t for t in texts(app,"date"))
            # A card that hasn't changed isn't rebuilt: the focused button survives the 30-second refresh.
            at(2026,11,1,10,0,place=HAIFA)
            button=app.today_buttons["sun","Change location…"]; app.fixed_now+=datetime.timedelta(seconds=30); app.tick(); assert app.today_buttons["sun","Change location…"] is button
            # Tab from the contents goes to Today's first action; every action is a real button.
            assert app.list_key(None,Gdk.KEY_Tab,0,0)
            app.navigate("hidden"); assert app.views.get_visible_child_name()=="reading" and app.star.get_sensitive()
            passed.append(True); print("Today UI test passed")
        except Exception as exc:
            errors.append(exc)
        app.quit(); return False
    reader.GLib.timeout_add(300,exercise)
    app.run([])
    if errors: raise errors[0]
    if not passed: raise SystemExit("Today UI test did not complete")
    # An existing user keeps their section and position.
    reader.STATE.write_text(json.dumps({"section":"hidden","last":"hidden:5"}))
    app=reader.Reader(); app.set_flags(Gio.ApplicationFlags.NON_UNIQUE); kept=[]
    def check():
        kept.append((app.section,app.current["id"] if app.current else None,app.views.get_visible_child_name())); app.quit(); return False
    reader.GLib.timeout_add(300,check)
    app.run([])
    assert kept==[("hidden","hidden:5","reading")], kept

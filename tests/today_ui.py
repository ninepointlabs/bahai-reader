"""The Today view at fixed moments, and first run versus an existing reading position.
Run with xvfb-run -a /usr/bin/python3 tests/today_ui.py [installed|flatpak]."""
import datetime
import json
import sys
import tempfile
from pathlib import Path
sys.path.insert(0, "/usr/share/bahai-reader" if "installed" in sys.argv else "/app/share/bahai-reader" if "flatpak" in sys.argv else str(Path(__file__).resolve().parents[1]))
import reader
from gi.repository import Gio, Gdk, Gtk
UTC=datetime.timezone.utc
HAIFA={"label":"Haifa, Israel","lat":32.81,"lon":35.0,"tz":"Asia/Jerusalem"}
TROMSO={"label":"Tromsø, Norway","lat":69.65,"lon":18.96,"tz":"Europe/Oslo"}

def texts(app,card):
    found=[]; child=app.today_cards[card].get_first_child()
    while child:
        if isinstance(child,Gtk.FlowBox):
            item=child.get_first_child()
            while item: found.append(item.get_child().get_label()); item=item.get_next_sibling()
        else: found.append(child.get_label())
        child=child.get_next_sibling()
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
            assert reader.json.loads(reader.STATE.read_text())["section"]==app.first_section(), "a new install opens on Today (Home in the libadwaita window)"
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
            # The obligatory prayer. Nothing chosen: a quiet prompt, and no reminder of anything.
            at(2026,11,1,10,0,place=HAIFA)
            assert texts(app,"prayer")[1].startswith("Choose which obligatory prayer") and ("prayer","Choose a prayer…") in app.today_buttons
            # Short, noon till sunset in Haifa: open at 10:00 UTC (12:00 local), the toggle is the same state everywhere.
            app.prefs["prayer"]="short"; app.refresh_today()
            lines=texts(app,"prayer"); assert any(t.startswith("Open now, until") for t in lines), lines
            toggle=app.today_buttons["prayer","Said today"]; assert not toggle.get_active()
            toggle.set_active(True)
            assert reader.json.loads(reader.STATE.read_text())["records"]["said"]==["2026-11-01:short:noon"]
            assert app.today_buttons["prayer","Said today"].get_active() and "✓ Said today" in texts(app,"prayer")
            app.today_buttons["prayer","Open the Short Obligatory Prayer"].emit("clicked")
            assert app.section=="obligatory" and "Short Obligatory Prayer" in app.current["tags"] and app.active_group==reader.obligatory(app.items)["The three prayers"]
            assert app.said_toggle.get_visible() and app.said_toggle.get_active() and app.said_toggle.get_label()=="✓ Said today"
            app.said_toggle.set_active(False); assert app.said_marks()==[]
            app.step(1); assert app.said_toggle.get_visible() and "Medium Obligatory Prayer" in app.current["tags"] and app.said_toggle.get_label()=="Said at noon"
            app.step(1); assert "Long Obligatory Prayer" in app.current["tags"] and app.said_toggle.get_visible() and "Said today" in app.said_toggle.get_label(), "the long prayer has its toggle while reading"
            app.navigate("hidden"); assert not app.said_toggle.get_visible()
            # The day moves on: the toggle is fresh the next day, and yesterday's mark stays in the record.
            at(2026,11,1,10,0,place=HAIFA); app.prefs["prayer"]="short"; app.refresh_today(); app.today_buttons["prayer","Said today"].set_active(True)
            at(2026,11,2,10,0,place=HAIFA); assert not app.today_buttons["prayer","Said today"].get_active() and app.said_marks()==["2026-11-01:short:noon"]
            # After sunset, nothing says anything was missed.
            at(2026,11,2,16,0,place=HAIFA); lines=texts(app,"prayer"); assert any("Its time has ended" in t for t in lines) and not any("miss" in t.casefold() for t in lines), lines
            # Medium: three windows, each with its own mark; the morning quotes Note 5.
            app.prefs["prayer"]="medium"; at(2026,11,2,5,0,place=HAIFA); lines=texts(app,"prayer")
            assert any(t.startswith("Morning: Open now") for t in lines) and any(t.startswith("Noon: Opens at") for t in lines) and any(t.startswith("Evening: Opens at") for t in lines) and any("as early as dawn (Note 5)" in t for t in lines), lines
            app.today_buttons["prayer","Said this morning"].set_active(True); assert "2026-11-02:medium:morning" in app.said_marks()
            assert not app.today_buttons["prayer","Said at noon"].get_active()
            app.today_buttons["prayer","Read the guidance (Question and Answer 83)"].emit("clicked"); assert app.current["title"].startswith("83 · ") and app.current["subgroup"]=="Questions and Answers" and app.section=="obligatory" and "sunrise, noon and sunset" in app.current["text"]
            # Long: the period is the user's choice, sunset to sunset unless changed, and the card says no ruling has been made.
            app.prefs["prayer"]="long"; at(2026,11,2,5,0,place=HAIFA); lines=texts(app,"prayer")
            assert any("Once in twenty-four hours" in t for t in lines) and any(t.startswith("Sunset to sunset: this period ends") for t in lines) and any("has not made any ruling" in t for t in lines) and "Said today" in lines, lines
            assert not any("not available yet" in t for t in lines), lines
            app.mark_long(True); assert any(k.endswith(":long:sunset") for k in app.said_marks()), app.said_marks()
            assert any(t.startswith("✓") for t in texts(app,"prayer")), texts(app,"prayer")
            at(2026,11,2,16,0,place=HAIFA); assert not any(t.startswith("✓") for t in texts(app,"prayer")), "after sunset a new period has begun"
            # Rolling: 24 hours from the moment it was marked, however long ago the card was drawn.
            app.prefs["long_period"]="rolling"; at(2026,11,2,16,0,place=HAIFA); assert any("24 hours run from then" in t for t in texts(app,"prayer")), texts(app,"prayer")
            at(2026,11,2,18,0,place=HAIFA); app.mark_long(True); assert app.long_window().opens.timestamp()==app.fixed_now.timestamp()
            assert any(t.startswith("Said at") for t in texts(app,"prayer")), texts(app,"prayer")
            app.mark_long(False); assert not any(":long:at:" in k for k in app.said_marks()), app.said_marks()
            app.prefs.pop("long_period"); app.prefs["records"]={"said":[],"fasted":[]}
            # The settings show the Long prayer's period and an opt-in nudge only when it is chosen, and the nudge starts off.
            at(2026,11,2,5,0,place=HAIFA); app.location_dialog()
            assert app.long_box.get_visible() and not app.reminder_checks["prayer"].get_visible() and not app.reminder_checks["long"].get_active() and app.long_period_choice.get_active_id()=="sunset" and app.long_lead_spin.get_value_as_int()==2
            app.long_period_choice.set_active_id("noon"); assert app.prefs["long_period"]=="noon"; app.long_period_choice.set_active_id("sunset")
            app.prayer_choice.set_active_id("short"); assert not app.long_box.get_visible() and app.reminder_checks["prayer"].get_visible()
            app.prayer_choice.set_active_id("long"); app.location_window.close(); app.navigate("today")
            app.today_buttons["prayer","Read the guidance (Question and Answer 82)"].emit("clicked"); assert app.current["title"].startswith("82 · ") and "Once in twenty-four hours" in app.current["text"]
            # Polar night: no window, and the card points to ¶10 rather than inventing hours.
            app.prefs["prayer"]="short"; at(2026,12,21,10,0,place=TROMSO); lines=texts(app,"prayer"); assert any("gauge the times of prayer by clocks" in t for t in lines) and not any("Said" in t for t in lines), lines
            lines=texts(app,"prayer"); assert any("National Spiritual Assembly" in t for t in lines) and "Use clock times…" in lines, lines
            # Clock times: entered hours replace the sun on every card, and a bad entry changes nothing.
            app.location_dialog(); app.clock_entries["sunrise"].set_text("07:00"); app.clock_entries["noon"].set_text("05:00"); app.clock_entries["sunset"].set_text("19:00"); app.clock_check.set_active(True)
            assert "clock_hours" not in app.prefs and app.clock_message.get_visible(), "times out of order are refused"
            app.clock_entries["noon"].set_text("12:30"); app.clock_apply(); assert app.prefs["clock_hours"]=={"sunrise":420,"noon":750,"sunset":1140} and not app.clock_message.get_visible()
            assert "Tromsø" in app.location_summary.get_text() and "Clock" not in app.location_summary.get_text(), app.location_summary.get_text()
            at(2026,12,21,12,0,place=TROMSO); lines=texts(app,"prayer"); assert any("clock times you set" in t for t in lines) and "Said today" in lines and not any("gauge" in t for t in lines), lines
            assert texts(app,"sun")[0]=="Clock times" and any(t.startswith("Sunset hour: ") and ("19:00" in t or "7:00" in t) for t in texts(app,"sun")) and not any("does not rise" in t for t in texts(app,"sun")), texts(app,"sun")
            assert any("sunset hour you set" in t for t in texts(app,"date")), texts(app,"date")
            at(2026,12,21,18,30,place=TROMSO); assert "after sunset" in texts(app,"date")[1], "19:30 in Tromsø is past the sunset hour"
            at(2026,12,21,12,0); assert texts(app,"sun")[0]=="Clock times" and not any("Add location" in t for t in texts(app,"sun")), "works without a location"
            app.clock_check.set_active(False); assert "clock_hours" not in app.prefs
            at(2026,12,21,10,0,place=TROMSO); assert any("gauge the times of prayer by clocks" in t for t in texts(app,"prayer")), "off again, the sun returns"
            app.location_window.close()
            # No location: the clock stands in, and the card says so.
            at(2026,11,2,13,0); lines=texts(app,"prayer"); assert any("use the clock" in t for t in lines) and ("prayer","Add location…") in app.today_buttons, lines
            # "Don't track": no card, no toggle while reading.
            app.prefs["prayer"]="none"; at(2026,11,2,10,0,place=HAIFA); assert not app.today_cards["prayer"].get_visible()
            app.navigate("obligatory"); assert not app.said_toggle.get_visible()
            # The settings window: choosing, turning the history off, and clearing with a confirmation.
            app.prefs["prayer"]="short"; at(2026,11,2,10,0,place=HAIFA); app.today_buttons["prayer","Said today"].set_active(True)
            app.location_dialog(); assert app.prayer_choice.get_active_id()=="short"
            app.prayer_choice.set_active_id("medium"); assert reader.json.loads(reader.STATE.read_text())["prayer"]=="medium"
            app.records_clear.emit("clicked"); assert app.said_marks()!=[] and app.records_confirm.get_visible()
            app.records_confirm.emit("clicked"); assert reader.json.loads(reader.STATE.read_text())["records"]=={"said":[],"fasted":[]} and not app.records_confirm.get_visible()
            app.mark_said("2020-01-01:short:noon",True); app.records_check.set_active(False)
            assert app.said_marks()==[] and reader.json.loads(reader.STATE.read_text())["keep_records"] is False
            app.mark_said("2026-11-02:medium:noon",True); assert app.said_marks()==["2026-11-02:medium:noon"], "today's state still works with the history off"
            app.records_check.set_active(True); app.location_window.close(); app.prefs["prayer"]="none"
            # The Fast: hidden far from it, a line when near, and during it the day, the hours and a private check.
            at(2026,11,1,10,0,place=HAIFA); assert not app.today_cards["fast"].get_visible()
            at(2027,2,10,10,0,place=HAIFA); assert texts(app,"fast")[1]=="The Fast begins at sunrise on 2 March.", texts(app,"fast")
            at(2027,3,8,8,0,place=HAIFA); lines=texts(app,"fast")
            assert "Day 7 of 19" in lines and any(t.startswith("Fasting hours: sunrise at") for t in lines), lines
            toggle=app.today_buttons["fast","Fasted today"]; assert not toggle.get_active(); toggle.set_active(True)
            assert reader.json.loads(reader.STATE.read_text())["records"]["fasted"]==["2027-03-08"] and app.today_buttons["fast","Fasted today"].get_active()
            app.today_buttons["fast","Prayers for the Fast"].emit("clicked"); assert "The Fast" in app.current["tags"]
            at(2027,3,8,8,0,place=HAIFA); app.today_buttons["fast","Read about the Fast (¶16)"].emit("clicked")
            assert app.current["title"].startswith("16 · ") and "fasting" in app.current["text"].casefold() and app.section=="writings"
            # The evening before a day of the Fast already counts as that day; the last evening does not.
            at(2027,3,8,17,0,place=HAIFA); assert "Day 8 of 19" in texts(app,"fast"), texts(app,"fast")
            at(2027,3,20,17,0,place=HAIFA); assert not app.today_cards["fast"].get_visible()
            # Without a location: the hours in words, and a way to add one. No streak or score anywhere.
            at(2027,3,8,8,0); lines=texts(app,"fast"); assert "The fasting hours run from sunrise to sunset." in lines and ("fast","Add location…") in app.today_buttons and not any("streak" in t.casefold() or "score" in t.casefold() for t in lines), lines
            # Polar: the sun doesn't set near the end of the Fast only in far southern places; the text points to the guidance.
            at(2027,3,8,8,0,place={"label":"South","lat":-85.0,"lon":0.0,"tz":"UTC"}); lines=texts(app,"fast"); assert any("gauge the times by clocks" in t for t in lines) and ("fast","Read the guidance (Note 17)") in app.today_buttons, lines
            app.today_buttons["fast","Read the guidance (Note 17)"].emit("clicked"); assert app.current["title"].startswith("17 · ")
            # After 221 B.E. the Fast isn't guessed either.
            at(2065,3,25,10,0,place=HAIFA); assert not app.today_cards["fast"].get_visible()
            # Clearing covers the Fast too, with a confirmation first.
            at(2027,3,8,8,0,place=HAIFA); assert app.fasted_marks()==["2027-03-08"]
            app.location_dialog(); app.records_clear.emit("clicked"); assert app.fasted_marks()==["2027-03-08"]; app.records_confirm.emit("clicked"); assert app.fasted_marks()==[]
            # Each reminder has its own switch, off until turned on, and each is stored.
            assert all(not check.get_active() for check in app.reminder_checks.values()) and set(app.reminder_checks)==set(reader.REMINDER_SWITCHES)
            app.reminder_checks["holy"].set_active(True); assert reader.json.loads(reader.STATE.read_text())["reminders"]["holy"] is True
            app.reminder_checks["holy"].set_active(False); app.location_window.close()
            # Polar day: no sunset, and the date says so.
            at(2026,6,21,22,0,place=TROMSO)
            assert "The sun does not set today." in texts(app,"sun") and any("does not set here today" in t for t in texts(app,"date"))
            # After 221 B.E.: nothing is guessed.
            at(2065,3,20,10,0,place=HAIFA)
            assert reader.badi.UNPUBLISHED in texts(app,"date") and reader.badi.UNPUBLISHED in texts(app,"events") and not app.section_items, texts(app,"date")
            assert any("20 March 2065" in t for t in texts(app,"date"))
            # The keyboard: Ctrl+T lands on Today's first action, and Tab walks the cards from top to bottom.
            app.navigate("hidden"); assert app.key_pressed(None,Gdk.KEY_t,0,Gdk.ModifierType.CONTROL_MASK) and app.views.get_visible_child_name()=="today"
            first=app.window.get_focus(); assert isinstance(first,Gtk.Button) and first.is_ancestor(app.today_cards["sun"]), first
            app.location_dialog(); app.location_window.close()
            # A library without the guidance offers no button for it, rather than one that does nothing.
            app.items=[i for i in app.items if reader.BOOKS["aqdas"] not in i["tags"]]; app.prefs["prayer"]="short"; at(2026,11,2,10,0,place=HAIFA)
            assert not any("guidance" in t for t in texts(app,"prayer")) and app.today_cards["passage"].get_visible(), texts(app,"prayer")
            app.show_counter(); assert not app.counter_verse.get_visible(); app.leave_counter()
            app._items=None; app.prefs["prayer"]="none"
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

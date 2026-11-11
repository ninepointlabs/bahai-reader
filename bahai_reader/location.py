"""Location & reminders window."""
import datetime
import os
from gi.repository import Gtk
import badi

from .desktop import clock
from .search import search_cities
from .ui import CLOCK_ASSEMBLY
from .widgets import Choice

class LocationMixin:
    """Reader methods: location & reminders window."""
    def set_place(self,place):
        """Saves a location, or forgets it with None; only the label, rounded coordinates and time zone are stored."""
        place=badi.clean_place(place) if place else None
        if place: self.prefs["location"]=place
        else: self.prefs.pop("location",None)
        self.save()
        if self.section=="today": self.rebuild()
        self.refresh_today()
        return place

    def place_summary(self):
        """The saved place, its time zone and today's sun times, as a check."""
        place=self.prefs.get("location")
        if not place: return "No location set."
        now=datetime.datetime.now(badi.ZoneInfo(place["tz"]))
        sun=badi.place_sun(place,now.date())
        return f"{place['label']}\nTime zone: {place['tz']}\n{badi.sun_summary(sun,clock) if sun else 'Sun times are not available.'}"

    def location_dialog(self,*_):
        if getattr(self,"location_window",None):
            self.location_window.present(); return
        window,box=self.small_window("location_window","Location & reminders",height=640)
        title=Gtk.Label(label="Location",xalign=0); title.add_css_class("heading"); box.append(title)
        box.append(Gtk.Label(label="Used to work out sunrise, noon and sunset. It stays on this computer and is never sent anywhere.",wrap=True,xalign=0,max_width_chars=56))
        summary=Gtk.Label(wrap=True,xalign=0,max_width_chars=56,selectable=False); box.append(summary); self.location_summary=summary
        clear=self.button("Clear location",lambda *_: use(None)); clear.set_halign(Gtk.Align.START)
        search=Gtk.SearchEntry(placeholder_text="Type a city…"); self.name_widget(search,"Type a city"); box.append(search); self.location_search=search
        results=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=4); box.append(results); self.location_results=results
        message=Gtk.Label(wrap=True,xalign=0,max_width_chars=56,visible=False); message.add_css_class("dim-label"); box.append(message)
        by_hand=Gtk.Expander(label="Or enter latitude, longitude and time zone"); box.append(by_hand)
        form=Gtk.Grid(column_spacing=10,row_spacing=8,margin_top=8); by_hand.set_child(form)
        latitude=Gtk.Entry(placeholder_text="32.82",hexpand=True); longitude=Gtk.Entry(placeholder_text="34.99",hexpand=True)
        self.name_widget(latitude,"Latitude"); self.name_widget(longitude,"Longitude")
        zones=Choice(search=True); self.name_widget(zones,"Time zone")
        for zone in sorted(badi.available_timezones()): zones.append_text(zone)
        current=self.prefs["location"]["tz"] if self.prefs.get("location") else os.environ.get("TZ","")
        zones.set_active_id(current)
        form.attach(Gtk.Label(label="Latitude (north is positive)",xalign=0),0,0,1,1); form.attach(latitude,1,0,1,1)
        form.attach(Gtk.Label(label="Longitude (east is positive)",xalign=0),0,1,1,1); form.attach(longitude,1,1,1,1)
        form.attach(Gtk.Label(label="Time zone",xalign=0),0,2,1,1); form.attach(zones,1,2,1,1)
        def refresh():
            summary.set_text(self.place_summary()); clear.set_sensitive(bool(self.prefs.get("location")))
        def use(place):
            self.set_place(place); refresh(); message.set_visible(False)
            search.set_text(""); fill()
        def fill(*_):
            while child:=results.get_first_child(): results.remove(child)
            query=search.get_text().strip()
            if not query: return
            rows=search_cities(query)
            if not rows: results.append(Gtk.Label(label=f"No city matches “{query}”. You can enter its coordinates below.",wrap=True,xalign=0,max_width_chars=56))
            for row in rows:
                place=dict(label=row[2],lat=row[3],lon=row[4],tz=row[5])
                entry=self.button(f"{row[2]} · {row[5]}",lambda _,p=place: use(p)); entry.get_child().set_xalign(0); entry.get_child().set_wrap(True); results.append(entry)
        search.connect("search-changed",fill)
        def apply_coordinates(*_):
            try: lat,lon=float(latitude.get_text().strip()),float(longitude.get_text().strip())
            except ValueError: lat=lon=None
            if lat is None or not (-90<=lat<=90 and -180<=lon<=180):
                message.set_text("Enter a latitude from -90 to 90 and a longitude from -180 to 180."); message.set_visible(True); return
            if not zones.get_active_id():
                message.set_text("Choose a time zone."); message.set_visible(True); return
            use(dict(label=f"{round(lat,2)}, {round(lon,2)}",lat=lat,lon=lon,tz=zones.get_active_id()))
            latitude.set_text(""); longitude.set_text("")
        self.location_apply=apply_coordinates; self.location_latitude=latitude; self.location_longitude=longitude; self.location_zones=zones; self.location_message=message
        latitude.connect("activate",apply_coordinates); longitude.connect("activate",apply_coordinates)
        form.attach(self.button("Use these coordinates",apply_coordinates),0,3,2,1)
        box.append(clear)
        heading=Gtk.Label(label="Clock times",xalign=0,margin_top=10); heading.add_css_class("heading"); box.append(heading)
        box.append(Gtk.Label(label=CLOCK_ASSEMBLY+" This app sets no hours of its own. Once set, they replace the sun for prayer times, the Fast, reminders and when the Badí‘ date changes.",wrap=True,xalign=0,max_width_chars=56))
        saved_hours=self.prefs.get("clock_hours") or {}
        use_clock=Gtk.CheckButton(label="Use clock times instead of the sun",active=bool(saved_hours)); self.clock_check=use_clock; box.append(use_clock)
        clock_form=Gtk.Grid(column_spacing=10,row_spacing=8); box.append(clock_form); self.clock_entries={}
        for row,(key,label) in enumerate((("sunrise","Sunrise hour"),("noon","Noon hour"),("sunset","Sunset hour"))):
            entry=Gtk.Entry(placeholder_text="HH:MM",hexpand=True); self.name_widget(entry,label); self.clock_entries[key]=entry
            if key in saved_hours: entry.set_text(f"{saved_hours[key]//60:02d}:{saved_hours[key]%60:02d}")
            clock_form.attach(Gtk.Label(label=label,xalign=0),0,row,1,1); clock_form.attach(entry,1,row,1,1)
        clock_message=Gtk.Label(wrap=True,xalign=0,max_width_chars=56,visible=False); clock_message.add_css_class("dim-label"); box.append(clock_message); self.clock_message=clock_message
        def apply_clock(*_):
            clock_message.set_visible(False)
            if not use_clock.get_active(): self.prefs.pop("clock_hours",None)
            else:
                hours=badi.clean_clock_hours({k:badi.parse_clock(e.get_text()) for k,e in self.clock_entries.items()})
                if not hours:
                    self.prefs.pop("clock_hours",None); clock_message.set_text("Enter all three as HH:MM, in order within one day: sunrise, noon, sunset. Until then the app follows the sun."); clock_message.set_visible(True)
                else: self.prefs["clock_hours"]=hours
            self.save(); self.show_said(); self.refresh_today(); self.tick()
        self.clock_apply=apply_clock; use_clock.connect("toggled",apply_clock)
        for entry in self.clock_entries.values(): entry.connect("activate",apply_clock)
        apply_button=self.button("Use these times",apply_clock); apply_button.set_halign(Gtk.Align.START); box.append(apply_button)
        heading=Gtk.Label(label="Obligatory prayer",xalign=0,margin_top=10); heading.add_css_class("heading"); box.append(heading)
        box.append(Gtk.Label(label="Which prayer you say. Its times then appear on Today.",wrap=True,xalign=0,max_width_chars=56))
        choice=Choice(); self.name_widget(choice,"Which prayer you say"); self.prayer_choice=choice
        for key,name in (("short","Short"),("medium","Medium"),("long","Long"),("none","Don’t track")): choice.append(key,name)
        choice.set_active_id(self.prefs.get("prayer","none")); box.append(choice)
        def prayer_changed(c):
            if c.get_active_id():
                self.prefs["prayer"]=c.get_active_id(); self.save(); self.show_said(); self.refresh_today()
                reminder.set_visible(c.get_active_id()!="long"); reminder.set_sensitive(badi.is_tracked(c.get_active_id())); long_box.set_visible(c.get_active_id()=="long")
        choice.connect("changed",prayer_changed)
        reminder=Gtk.CheckButton(label="Remind me when its time opens and before it closes",active=self.prefs.get("reminders",{}).get("prayer",False)); self.reminder_checks={"prayer":reminder}; box.append(reminder)
        def switch(check,key):
            self.prefs.setdefault("reminders",{})[key]=check.get_active(); self.save(); self.tick()
        reminder.connect("toggled",switch,"prayer"); reminder.set_sensitive(badi.is_tracked(self.prefs.get("prayer","none"))); reminder.set_visible(self.prefs.get("prayer")!="long")
        long_box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=8,visible=self.prefs.get("prayer")=="long"); box.append(long_box); self.long_box=long_box
        long_box.append(Gtk.Label(label="No text says which twenty-four hours are meant, and the House of Justice has made no ruling, so this is your choice. Sunset to sunset is the Bahá’í day the app’s date already follows.",wrap=True,xalign=0,max_width_chars=56))
        period=Choice(); self.name_widget(period,"Twenty-four hours for the Long prayer"); self.long_period_choice=period
        for key,name in badi.LONG_PERIODS: period.append(key,name)
        period.set_active_id(badi.long_period(self.prefs)); long_box.append(period)
        def period_changed(c):
            if c.get_active_id(): self.prefs["long_period"]=c.get_active_id(); self.save(); self.show_said(); self.refresh_today()
        period.connect("changed",period_changed)
        nudge=Gtk.CheckButton(child=Gtk.Label(label="Remind me once before the period resets, if it isn’t marked",wrap=True,xalign=0,max_width_chars=52),active=self.prefs.get("reminders",{}).get("long",False)); self.reminder_checks["long"]=nudge
        nudge.connect("toggled",switch,"long"); long_box.append(nudge)
        lead_row=Gtk.Box(spacing=8); long_box.append(lead_row)
        lead=Gtk.SpinButton.new_with_range(badi.LONG_LEAD_MIN,badi.LONG_LEAD_MAX,1); lead.set_value(badi.long_lead(self.prefs)); self.name_widget(lead,"Hours before the period resets"); self.long_lead_spin=lead
        def lead_changed(s): self.prefs["long_lead_hours"]=s.get_value_as_int(); self.save(); self.tick()
        lead.connect("value-changed",lead_changed); lead_row.append(lead); lead_row.append(Gtk.Label(label="hours before",xalign=0))
        clock_note=Gtk.Label(label="Without a location, reminders use clock times. Add a location and they follow the sun.",wrap=True,xalign=0,max_width_chars=56); clock_note.add_css_class("dim-label"); box.append(clock_note)
        record=Gtk.CheckButton(child=Gtk.Label(label="Keep a private record of “Said today” and “Fasted today” on this computer",wrap=True,xalign=0,max_width_chars=52),active=self.prefs.get("keep_records",True)); self.records_check=record; box.append(record)
        def record_changed(check):
            self.prefs["keep_records"]=check.get_active()
            records=self.prefs.get("records")
            if records and not check.get_active():
                for kind in ("said","fasted"): records[kind]=badi.prune_said(records[kind],self.now().date(),False)
            self.save()
        record.connect("toggled",record_changed)
        box.append(Gtk.Label(label="These records are never sent anywhere. There are no scores or streaks.",wrap=True,xalign=0,max_width_chars=56))
        clearing=Gtk.Box(spacing=8); box.append(clearing)
        forget=self.button("Clear my records",lambda *_: ask(True)); clearing.append(forget)
        confirm=self.button("Yes, clear them",lambda *_: (self.clear_records(),ask(False),forget.grab_focus())); confirm.set_visible(False); clearing.append(confirm)
        cancel=self.button("Keep them",lambda *_: (ask(False),forget.grab_focus())); cancel.set_visible(False); clearing.append(cancel)
        self.records_clear=forget; self.records_confirm=confirm
        def ask(showing):
            confirm.set_visible(showing); cancel.set_visible(showing); forget.set_visible(not showing)
            if showing: cancel.grab_focus()
        heading=Gtk.Label(label="Feasts, Holy Days and the Fast",xalign=0,margin_top=10); heading.add_css_class("heading"); box.append(heading); self.events_heading=heading
        for key,label in (("feast","Nineteen Day Feasts, on the afternoon of the day each begins"),("holy","Holy Days, the day before and on the day"),("fast","The Fast, 5, 3 and 1 days before it begins"),("fast_daily","During the Fast, before sunrise and at sunset each day")):
            check=Gtk.CheckButton(child=Gtk.Label(label=label,wrap=True,xalign=0,max_width_chars=52),active=self.prefs.get("reminders",{}).get(key,False)); self.reminder_checks[key]=check
            check.connect("toggled",switch,key); box.append(check)
        running=Gtk.CheckButton(child=Gtk.Label(label="Keep reminders running when the window is closed",wrap=True,xalign=0,max_width_chars=52),active=bool(self.prefs.get("keep_running"))); self.keep_running_check=running; box.append(running)
        explain=Gtk.Label(label="A quiet background process starts when you log in and has no tray icon. Turn this off to stop it.",wrap=True,xalign=0,max_width_chars=56); explain.add_css_class("dim-label"); box.append(explain)
        running_status=Gtk.Label(wrap=True,xalign=0,max_width_chars=56,visible=False); self.keep_running_status=running_status; box.append(running_status)
        running.connect("toggled",lambda check:self.set_keep_running(check.get_active()))
        close=self.button("Close",lambda *_: window.close()); close.set_halign(Gtk.Align.END); box.append(close)
        refresh(); window.present(); search.grab_focus()

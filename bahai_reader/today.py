"""The Today view and obligatory prayer tracking."""
import datetime
from gi.repository import Gtk, Pango
import badi

from .config import BOOKS
from .desktop import clock
from .library import AYYAM_PRAYERS, DAYS_OF_NOTE, FAST_PRAYERS, obligatory, passage_of_the_day, unnumbered
from .ui import CLOCK_ASSEMBLY

class TodayMixin:
    """Reader methods: the Today view and obligatory prayer tracking."""
    def build_today(self):
        scroll=Gtk.ScrolledWindow(vexpand=True,hexpand=True,hscrollbar_policy=Gtk.PolicyType.NEVER); self.views.add_named(scroll,"today")
        # One calm column; it narrows with the window.
        self.today_box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=14,halign=Gtk.Align.CENTER,margin_top=32,margin_bottom=32,margin_start=16,margin_end=16)
        scroll.set_child(self.today_box); self.today_cards={}; self.today_rows={}; self.today_buttons={}
        for key in ("date","sun","prayer","counter","events","fast","passage"):
            card=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=8,visible=False); card.add_css_class("today-card")
            self.today_box.append(card); self.today_cards[key]=card
        self.today_box.append(Gtk.Label(label="x"*200,max_width_chars=68,ellipsize=Pango.EllipsizeMode.END,opacity=0,accessible_role=Gtk.AccessibleRole.PRESENTATION))

    def today_content(self):
        """{card: rows} for the moment, where a row is (kind, text[, action]). Plain data, so a card is only rebuilt when it changes."""
        moment=self.now(); place=self.place(); day=badi.observed_date(moment,place); today=badi.from_gregorian(day); self.today_day=day
        sun=badi.place_sun(place,moment.date())
        cards={}
        # Date
        rows=[]
        if today:
            rows.append(("large",str(today)))
            evening=day!=moment.date()
            rows.append(("text",badi.gregorian_text(moment.date(),year=True)+(", after sunset" if day>moment.date() else ", before sunset" if evening else "")))
            if today.month==badi.INTERCALARY: rows.append(("text",f"{badi.AYYAM_I_HA}: the days before the month of ‘Alá’."))
            else: rows.append(("text",f"The month of {today.month_name}: {today.meaning}."))
            if not place: rows.append(("dim","The Bahá’í day begins at sunset. Without a location, this date follows the calendar day."))
            elif sun and sun.clock: rows.append(("dim","The Bahá’í day begins at sunset. Here this date changes at the sunset hour you set."))
            elif sun and sun.polar=="day": rows.append(("dim","The Bahá’í day begins at sunset. The sun does not set here today, so this date follows the calendar day."))
            elif sun and sun.polar=="night": rows.append(("dim","The Bahá’í day begins at sunset. The sun does not rise here today, so this date follows the calendar day."))
            else: rows.append(("dim","The Bahá’í day begins at sunset."))
        else:
            rows.append(("text",badi.gregorian_text(moment.date(),year=True)))
            rows.append(("text",badi.UNPUBLISHED))
            rows.append(("dim","Badí‘ dates here come from the Universal House of Justice’s table for 172 to 221 B.E."))
        cards["date"]=rows
        # Sun
        rows=[("title","Clock times" if sun and sun.clock else "Sun")]
        if sun and sun.clock:
            rows+=[("text",f"Sunrise hour: {clock(sun.sunrise)}"),("text",f"Noon hour: {clock(sun.noon)}"),("text",f"Sunset hour: {clock(sun.sunset)}")]
            rows.append(("dim","Hours you set, used instead of the sun."))
            rows.append(("button","Change clock times…",self.location_dialog))
        elif sun:
            if sun.sunrise: rows.append(("text",f"Sunrise: {clock(sun.sunrise)}"))
            rows.append(("text",f"Solar noon: {clock(sun.noon)}"))
            if sun.sunset: rows.append(("text",f"Sunset: {clock(sun.sunset)}"))
            if sun.polar=="day": rows.append(("text","The sun does not set today."))
            if sun.polar=="night": rows.append(("text","The sun does not rise today."))
            rows.append(("dim",place["label"]))
            rows.append(("button","Change location…",self.location_dialog))
        else:
            rows.append(("text","Add your location to see sunrise, noon and sunset"))
            rows.append(("button","Add location…",self.location_dialog))
        cards["sun"]=rows
        # Obligatory prayer
        rows=self.prayer_card(moment)
        if rows: cards["prayer"]=rows
        # Alláh-u-Abhá
        cards["counter"]=[("title","Alláh-u-Abhá"),("dim","Kitáb-i-Aqdas ¶18"),("button","Open the counter",self.show_counter)]
        # Next Feast and Holy Day
        rows=[("title","Next Feast and Holy Day")]
        feast=badi.next_feast(day); holy=badi.next_holy_day(day)
        if feast:
            rows.append(("text",f"{feast.name} ({feast.meaning})"))
            rows.append(("dim",badi.event_summary(feast,day)))
            opener=self.event_opener(feast)
            if opener: rows.append(("button",f"Prayers for {feast.name}",opener))
        if holy:
            rows.append(("text",holy.name))
            rows.append(("dim",badi.event_summary(holy,day)+(" Work is suspended." if holy.work_suspended else " Work is not suspended.")))
            if holy.readings and self.readings_group(holy.readings): rows.append(("button",f"Readings for {holy.name}",self.event_opener(holy)))
            opener=self.prayer_opener(holy.prayers,f"Prayers for {holy.name}")
            if opener: rows.append(("button",f"Prayers for {holy.name}",opener))
        ayyam=badi.next_ayyam_i_ha(day)
        if ayyam and (ayyam.first-day).days<=DAYS_OF_NOTE:
            rows.append(("text",badi.AYYAM_I_HA))
            begins=ayyam.first-datetime.timedelta(1)
            rows.append(("dim","Now." if ayyam.first<=day else f"Begins at sunset on {badi.gregorian_text(begins)}."))
            opener=self.prayer_opener(AYYAM_PRAYERS,f"Prayers for {badi.AYYAM_I_HA}")
            if opener: rows.append(("button",f"Prayers for {badi.AYYAM_I_HA}",opener))
        if not feast and not holy: rows.append(("text",badi.UNPUBLISHED))
        else: rows.append(("button","Reminders…",self.location_dialog))
        cards["events"]=rows
        # The Fast
        rows=self.fast_card(day,moment)
        if rows: cards["fast"]=rows
        # Passage of the day
        passage=passage_of_the_day(self.items,moment.date())
        if passage:
            opening=" ".join(unnumbered(passage).split()); excerpt=opening if len(opening)<=240 else opening[:240].rsplit(" ",1)[0]+"…"
            rows=[("title","Passage of the day"),("reading",excerpt)]
            if passage["citation"]: rows.append(("dim","— "+passage["citation"]))
            rows.append(("button","Read the passage of the day",lambda *_:self.daily_passage()))
            cards["passage"]=rows
        return cards

    def fast_card(self,observed,moment):
        """During the month of ‘Alá’ its day, the fasting hours and a private check; near it, when it begins; otherwise nothing."""
        state=badi.fast_state(observed); place=self.place()
        if not state: return None
        rows=[("title","The Fast")]
        if state.day is None:
            rows.append(("text",f"The Fast begins at sunrise on {badi.gregorian_text(state.date)}."))
        else:
            rows.append(("text",f"Day {state.day} of {badi.MONTH_DAYS}"))
            sun=badi.place_sun(place,state.date)
            if sun and sun.sunrise and sun.sunset:
                if sun.clock: rows.append(("text",f"Fasting hours, by the clock times you set: {clock(sun.sunrise)} to {clock(sun.sunset)}"))
                else: rows.append(("text",f"Fasting hours: sunrise at {clock(sun.sunrise)} to sunset at {clock(sun.sunset)}"))
            elif sun:
                rows.append(("text","The sun does not rise or set here today. In such regions the Kitáb-i-Aqdas says to gauge the times by clocks."))
                opener=self.aqdas_opener("Notes",17)
                if opener: rows.append(("button","Read the guidance (Note 17)",opener))
                rows.append(("dim",CLOCK_ASSEMBLY)); rows.append(("button","Use clock times…",self.location_dialog))
            else:
                rows.append(("text","The fasting hours run from sunrise to sunset."))
                rows.append(("button","Add location…",self.location_dialog))
            key=state.date.isoformat()
            rows.append(("toggle","Fasted today",key in self.fasted_marks(),lambda active,k=key:self.mark_fasted(k,active)))
        opener=self.prayer_opener(FAST_PRAYERS,"Prayers for the Fast")
        if opener: rows.append(("button","Prayers for the Fast",opener))
        opener=self.aqdas_opener("Text",16)
        if opener: rows.append(("button","Read about the Fast (¶16)",opener))
        rows.append(("button","Reminders…",self.location_dialog))
        return rows

    def aqdas_opener(self,part,number):
        """Opens a Kitáb-i-Aqdas passage among its own, by its printed number."""
        item=next((i for i in self.items if BOOKS["aqdas"] in i["tags"] and i["subgroup"]==part and i["title"].startswith(f"{number} · ")),None)
        if not item: return None
        return lambda *_:self.open_in_section(item,[i for i in self.items if i["tags"]==item["tags"] and i["subgroup"]==part],f"Kitáb-i-Aqdas, {part}")

    def fasted_marks(self):
        return self.prefs.get("records",{}).get("fasted",[])

    def mark_fasted(self,key,active):
        records=self.prefs.setdefault("records",{"said":[],"fasted":[]})
        if active and key not in records["fasted"]: records["fasted"].append(key)
        elif not active and key in records["fasted"]: records["fasted"].remove(key)
        records["fasted"]=badi.prune_said(records["fasted"],self.now().date(),self.prefs.get("keep_records",True))
        self.save(); self.refresh_today()

    def prayer_card(self,moment):
        """The chosen prayer's times and "Said" state; a quiet prompt when none is chosen; nothing with "Don't track"."""
        chosen=self.prefs.get("prayer"); place=self.place()
        if chosen=="none": return None
        rows=[("title","Obligatory prayer")]
        if chosen is None:
            rows+=[("text","Choose which obligatory prayer you say to see its times here."),("button","Choose a prayer…",self.location_dialog)]
            return rows
        name=badi.PRAYERS[chosen]; rows.append(("text",name))
        if chosen=="long":
            rows.append(("text","Once in twenty-four hours, at whatever time you find yourself in a state of humbleness and longing adoration."))
            rows.append(("button","Read the guidance (Question and Answer 82)",self.guidance_opener("Questions and Answers",82)))
            window=self.long_window(); marked=window.key in self.said_marks()
            rows.append(("text",badi.long_line(self.prefs,window,marked,clock)))
            rows.append(("toggle",badi.said_label(window),marked,lambda active:self.mark_long(active)))
            rows.append(("dim",badi.LONG_GUIDANCE))
            rows.append(("dim","So the period is your choice, in Location & reminders. This app makes no ruling."))
        else:
            windows=badi.prayer_windows(chosen,badi.prayer_day(chosen,moment,place),place)
            if not windows:
                rows.append(("text","The sun does not rise or set here today, so its times cannot be taken from the sun. In such regions the Kitáb-i-Aqdas says to gauge the times of prayer by clocks."))
                rows.append(("button","Read the guidance (¶10)",self.guidance_opener("Text",10)))
                rows.append(("dim",CLOCK_ASSEMBLY)); rows.append(("button","Use clock times…",self.location_dialog))
            for window in windows:
                label=badi.window_line(window,moment,clock)
                rows.append(("text",label if chosen=="short" else f"{badi.PART_NAMES[window.part]}: {label}"))
                if window.part=="morning" and moment.timestamp()<window.closes.timestamp(): rows.append(("dim","The morning prayer may be said as early as dawn (Note 5)."))
                rows.append(("toggle",badi.said_label(window),window.key in self.said_marks(),lambda active,key=window.key:self.mark_said(key,active)))
            if windows and place and place.get("clock"): rows.append(("dim","These use the clock times you set."))
            if windows and not place:
                rows.append(("dim","Without a location these use the clock instead of the sun. Add a location to follow the sun."))
                rows.append(("button","Add location…",self.location_dialog))
            if windows: rows.append(("button","Read the guidance (Question and Answer 83)",self.guidance_opener("Questions and Answers",83)))
        prayer=self.prayer_item(chosen)
        if prayer: rows.append(("button",f"Open the {name}",lambda *_:self.open_obligatory(prayer)))
        if badi.is_tracked(chosen): rows.append(("button","Reminders…",self.location_dialog))
        return rows

    def prayer_item(self,chosen):
        return next((i for i in self.items if i["section"]=="prayers" and badi.PRAYERS[chosen] in i["tags"]),None)

    def obligatory_group(self,item):
        """The passage's group within the Obligatory prayers section, so Next stays among them."""
        return next((g for g in obligatory(self.items).values() if item in g),[item])

    def open_obligatory(self,item,label=None):
        if self.section!="obligatory": self.navigate("obligatory")
        elif self.search.get_text(): self.search.set_text(""); self.filter()
        self.show_passage(item,self.obligatory_group(item)); self.show_content()
        if label: self.subtitle.set_text(label+" · "+self.subtitle.get_text())

    def guidance_opener(self,part,number):
        """Opens a Kitáb-i-Aqdas passage by its printed number; Ids in the feed are not always the same as numbers."""
        item=next((i for i in self.items if BOOKS["aqdas"] in i["tags"] and i["subgroup"]==part and i["title"].startswith(f"{number} · ")),None)
        if not item: return None
        return lambda *_:self.open_obligatory(item)

    def long_window(self):
        return badi.long_window(self.prefs,self.now(),self.place(),self.said_marks())

    def mark_long(self,active):
        """Worked out at the click: with "24 hours since last said", the 24 hours run from this moment, not from when the card was drawn."""
        self.mark_said(self.long_window().key,active)

    def said_marks(self):
        return self.prefs.get("records",{}).get("said",[])

    def mark_said(self,key,active):
        """The one place "Said" changes: the Today card, the toggle while reading and the notification action all come here."""
        records=self.prefs.setdefault("records",{"said":[],"fasted":[]})
        if active and key not in records["said"]: records["said"].append(key)
        elif not active and key in records["said"]: records["said"].remove(key)
        records["said"]=badi.prune_said(records["said"],self.now().date(),self.prefs.get("keep_records",True))
        self.save(); self.show_said(); self.refresh_today()

    def clear_records(self):
        self.prefs["records"]={"said":[],"fasted":[]}; self.save(); self.show_said(); self.refresh_today()

    def said_window(self,item):
        """The window to mark for the obligatory prayer being read, or None for other passages, the long prayer and "Don't track"."""
        if not item or self.prefs.get("prayer")=="none": return None
        prayer=next((k for k,name in badi.PRAYERS.items() if name in item["tags"]),None)
        if not prayer or not badi.is_tracked(prayer): return None
        if prayer=="long": return self.long_window()
        return badi.current_window(prayer,self.now(),self.place())

    def show_said(self):
        if not hasattr(self,"said_toggle"): return
        window=self.said_window(self.current)
        self.said_toggle.set_visible(window is not None)
        if not window: return
        self.said_syncing=True
        said=window.key in self.said_marks()
        self.said_toggle.set_label(("✓ " if said else "")+badi.said_label(window)); self.said_toggle.set_active(said); self.said_toggle.window_key=window.key
        self.said_syncing=False

    def said_toggled(self,toggle):
        if getattr(self,"said_syncing",False) or not getattr(toggle,"window_key",None): return
        if ":long:" in toggle.window_key: self.mark_long(toggle.get_active())
        else: self.mark_said(toggle.window_key,toggle.get_active())

    def refresh_today(self):
        """Rebuilds only the cards whose content changed, so the keyboard focus stays where it is."""
        if not getattr(self,"today_box",None) or not self.window: return
        cards={key:[r for r in rows if r[0] not in ("button","toggle") or r[2] is not None] for key,rows in self.today_content().items()}; focus=self.window.get_focus()
        focused=next((name for name,widget in self.today_buttons.items() if widget is focus),None)
        for key,card in self.today_cards.items():
            rows=cards.get(key)
            signature=[(r[0],r[1],r[2]) if r[0]=="toggle" else r[:2] for r in rows] if rows else None
            if signature==self.today_rows.get(key): continue
            self.today_rows[key]=signature
            held=focus is not None and focus.is_ancestor(card)
            while child:=card.get_first_child(): card.remove(child)
            card.set_visible(bool(rows))
            actions=None
            for row in rows or []:
                # Neighbouring actions share a line that wraps, rather than a tall stack.
                if row[0] in ("button","toggle"):
                    if actions is None:
                        actions=Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE,column_spacing=8,row_spacing=8,max_children_per_line=6,homogeneous=False); card.append(actions)
                    actions.append(self.today_row(key,row))
                    actions.get_last_child().set_focusable(False)
                else:
                    actions=None; card.append(self.today_row(key,row))
            if held:
                # Back on the same action if it is still there, else the card's first.
                again=self.today_buttons.get(focused) if focused and focused[0]==key else None
                again.grab_focus() if again and again.is_ancestor(card) else card.child_focus(Gtk.DirectionType.TAB_FORWARD)

    def today_row(self,key,row):
        kind,text=row[:2]
        if kind=="button":
            widget=self.button(text,lambda _,action=row[2]:action()); widget.set_halign(Gtk.Align.START); self.today_buttons[key,text]=widget
            widget.get_child().set_wrap(True)  # the longest labels are wider than a narrow window
            return widget
        if kind=="toggle":
            widget=Gtk.ToggleButton(label=("✓ " if row[2] else "")+text,active=row[2],halign=Gtk.Align.START); self.today_buttons[key,text]=widget
            widget.connect("toggled",lambda toggle,action=row[3]:action(toggle.get_active()))
            return widget
        label=Gtk.Label(label=text,wrap=True,xalign=0)
        label.add_css_class({"title":"heading","large":"today-large","reading":"today-reading","dim":"dim-label"}.get(kind,"today-text"))
        return label

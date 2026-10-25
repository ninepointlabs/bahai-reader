#!/usr/bin/python3
"""A quiet, native Linux reader for Bahá’í prayers and writings."""
import json
import math
import os
import re
import threading
import subprocess
import shutil
import tomllib
import urllib.request
import tempfile
import sys
import unicodedata
from pathlib import Path
from html.parser import HTMLParser
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, GLib, Pango

APP_NAME = "Bahá’í Reader"
TAGLINE = "A quiet, native Linux reader for Bahá’í prayers and writings."
ORGANIZATION = "Nine Point Labs"
SUPPORT_EMAIL = "help@ninepointlabs.com"
CREATED = "September 13, 2026"  # first commit
LICENSE_NAME = "MIT License"
COPYRIGHT = "© 2026 Nine Point Labs"  # matches LICENSE

ROOT = Path(__file__).resolve().parent
STATE = Path(os.environ.get("XDG_CONFIG_HOME", Path.home()/".config"))/"bahai-reader"/"settings.json"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home()/".cache"))/"bahai-reader"
FEEDS = {"prayers": "prayersystembylanguage?html=true&languageid=1", "hidden": "HiddensByLanguage?languageid=1", "gleanings": "GleaningsByLanguage?languageid=1"}

BOOKS = {"gleanings": "Gleanings from the Writings of Bahá’u’lláh", "meditations": "Prayers and Meditations", "tablets": "Tablets of Bahá’u’lláh", "iqan": "The Kitáb-i-Íqán"}
FEEDS.update({"meditations": "PMsByLanguage?languageid=1", "tablets": "TabsByLanguage?languageid=1", "iqan": "IqansByLanguage?languageid=1"})

BOOKS.update({"aqdas":"The Kitáb-i-Aqdas", "saq":"Some Answered Questions", "days":"Days of Remembrance", "ridvan":"Riḍván Messages"})
FEEDS.update({"aqdas":"AqdasByLanguage?languageid=1&html=true", "saq":"SaqTopicsByLanguage?languageid=1", "days":"DaysRemembersByLanguage?languageid=1", "ridvan":"RidvansByLanguage?languageid=1"})
LIBRARY = Path(os.environ.get("XDG_DATA_HOME", Path.home()/".local/share"))/"bahai-reader"/"libraries"
LANGUAGE_ENDPOINTS = {"prayers":"Languages", "hidden":"HiddenLanguages", "gleanings":"GleaningLanguages", "meditations":"PMLanguages", "tablets":"TabLanguages", "iqan":"IqanLanguages"}
LANGUAGE_ENDPOINTS.update({"aqdas":"AqdasLanguages", "saq":"SaqLanguages", "days":"DaysRememberLanguages", "ridvan":"RidvanLanguages"})
HOLY_DAYS={"NAWRUZ":"Naw-Rúz", "RIDVAN":"Riḍván", "DECLARATIONBAB":"Declaration of the Báb", "MARTYRDOMBAB":"Martyrdom of the Báb", "ASCENSIONBAHAULLAH":"Ascension of Bahá’u’lláh", "BIRTHBAB":"Birth of the Báb", "BIRTHBAHAULLAH":"Birth of Bahá’u’lláh"}
AQDAS_SECTIONS={"Paragraphs":"Text", "QAs":"Questions and Answers", "Notes":"Notes"}
SECTION_NAMES = {"prayers":"Prayers", "hidden":"The Hidden Words", **BOOKS}
# BahaiPrayers.net sends only a numeric AuthorId for prayers; names verified against the feed's tags.
PRAYER_AUTHORS={1:"The Báb", 2:"Bahá’u’lláh", 3:"‘Abdu’l‑Bahá"}
BOOK_AUTHORS={"hidden":"Bahá’u’lláh", "gleanings":"Bahá’u’lláh", "meditations":"Bahá’u’lláh", "tablets":"Bahá’u’lláh", "iqan":"Bahá’u’lláh", "aqdas":"Bahá’u’lláh", "saq":"‘Abdu’l‑Bahá", "days":"Bahá’u’lláh", "ridvan":"The Universal House of Justice"}

def shipped(*names):
    # Checkout, native package (/usr/share/licenses, icons) and AppImage layouts.
    for name in names:
        for path in (ROOT/name, ROOT.parent/name):
            if path.is_file(): return path
    return None

def version():
    path=shipped("VERSION")
    return path.read_text().strip() if path else "unknown"

def fetch_json(endpoint):
    with urllib.request.urlopen("https://bahaiprayers.net/api/prayer/"+endpoint, timeout=30) as response:
        return json.load(response)

def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name=tempfile.mkstemp(dir=path.parent, prefix=".download-")
    try:
        with os.fdopen(fd,"w") as file:
            json.dump(data,file,ensure_ascii=False); file.flush(); os.fsync(file.fileno())
        os.replace(name,path)
    finally:
        if os.path.exists(name): os.unlink(name)

def catalog():
    for file in (LIBRARY/"languages.json", ROOT/"data/languages.json"):
        try:
            data={**json.loads((ROOT/"data/languages.json").read_text()), **json.loads(file.read_text())}
            if not all(isinstance(data[k],list) and data[k] and all(isinstance(r,dict) and isinstance(r.get("Id"),int) and isinstance(r.get("Name"),str) for r in data[k]) for k in FEEDS): raise ValueError("Invalid catalog")
            return data
        except (OSError, ValueError, KeyError, TypeError): pass
    raise ValueError("Language catalog is unavailable")

def validate_feed(key,data,language):
    if key=="prayers":
        if not isinstance(data,dict) or data.get("IsInError"): raise ValueError("Prayer API returned an error")
        rows=data.get("Prayers")
    elif key=="aqdas":
        if not isinstance(data,dict) or data.get("Language",{}).get("Id")!=language:raise ValueError("Unexpected Aqdas language")
        rows=[]
        for section in AQDAS_SECTIONS:
            entries=data.get(section)
            if not isinstance(entries,list) or not entries:raise ValueError("Incomplete Aqdas collection")
            for entry in entries:
                if not isinstance(entry,dict):raise ValueError("Invalid Aqdas entry")
                rows.append({**entry, "Id":f"{section}:{entry.get('Id')}", "AqdasSection":section})
    else: rows=data
    if not isinstance(rows,list) or not rows: raise ValueError(f"No content returned for {SECTION_NAMES[key]}")
    for row in rows:
        if not isinstance(row,dict) or "Id" not in row or not isinstance(row.get("Text"),str) or row.get("LanguageId")!=language: raise ValueError("Unexpected language or content format")
        if key=="hidden" and not isinstance(row.get("IsArabic"),bool): raise ValueError("Invalid Hidden Words section")
        if key=="prayers" and not isinstance(row.get("Tags",[]),list): raise ValueError("Invalid prayer categories")
    return rows

def local_pack(language):
    try:
        data=json.loads((LIBRARY/f"{language}.json").read_text())
        if not isinstance(data,dict) or "prayers" not in data: return None
        for key,feed in data.items():
            if key not in FEEDS: return None
            validate_feed(key,feed,language)
        return data
    except (OSError,ValueError,TypeError,KeyError): return None

def download_language(language,languages,progress=lambda message:None):
    downloads={}
    for key,endpoint in FEEDS.items():
        if not any(row["Id"]==language for row in languages[key]): continue
        progress("Downloading "+SECTION_NAMES[key]+"…")
        data=fetch_json(endpoint.replace("languageid=1",f"languageid={language}"))
        validate_feed(key,data,language); downloads[key]=data
    if "prayers" not in downloads: raise ValueError("No prayer collection available")
    # Publish the entire language in one atomic replacement; failures preserve the old pack.
    atomic_json(LIBRARY/f"{language}.json",downloads)
    return downloads

class PlainText(HTMLParser):
    def __init__(self):
        super().__init__(); self.parts=[]
    def handle_starttag(self, tag, attrs):
        if tag in ("p", "br", "h1", "h2", "h3", "div"): self.parts.append("\n\n")
    def handle_data(self, data): self.parts.append(data)

def plain(value):
    parser=PlainText(); parser.feed(value or "")
    return re.sub(r"\n\s*\n", "\n\n", "".join(parser.parts)).strip()

def fold(text):
    """Search form without case, accents, apostrophes or hyphens: Bahaullah finds Bahá’u’lláh."""
    text="".join(c for c in unicodedata.normalize("NFKD",text) if not unicodedata.combining(c)).casefold()
    return re.sub(r"[’‘ʼʻ'`´\-‐‑]","",text)

def roman(number):
    numerals=[(1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),(100,"C"),(90,"XC"),(50,"L"),(40,"XL"),(10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")]
    result=""
    for value,letters in numerals:
        while number>=value: result+=letters; number-=value
    return result

def citation(key,row):
    # Author and book location only; the API carries no edition or page data.
    author=BOOK_AUTHORS.get(key); number=row.get("Number","")
    if key=="prayers": return PRAYER_AUTHORS.get(row.get("AuthorId"))
    if key=="hidden": where=f"{'Arabic' if row['IsArabic'] else 'Persian'} no. {number}"
    elif key=="gleanings": where=row.get("Roman") or str(number)
    elif key=="meditations": where=roman(number) if isinstance(number,int) and number>0 else str(number)
    elif key=="tablets":
        where=row.get("Title") or f"Tablet {row.get('TabletNumber','')}"
        if row.get("SubTitle")=="Footnotes": author=None
        elif row.get("SubTitle"): where+=f" ({row['SubTitle']})"
    elif key=="iqan": where=f"Part {row.get('Part','')}, no. {number}"
    elif key=="aqdas":
        section=row["AqdasSection"]
        where={"Paragraphs":f"¶{number}", "QAs":f"Question and Answer {number}", "Notes":f"Note {number}"}[section]
        if section=="Notes": author=None
    elif key=="saq": where=f"chapter {number}"
    elif key=="days": where=HOLY_DAYS.get(row.get("HolyDay"),row.get("HolyDay") or "")
    elif key=="ridvan": return ", ".join(filter(None,[author,f"Riḍván {row.get('Year','')}".strip()]))
    else: where=""
    return ", ".join(part for part in (author,SECTION_NAMES[key],where) if part)

def word_count(text):
    # Keep apostrophes and hyphens inside words; em/en dashes separate words.
    return len(re.findall(r"[^\W_]+(?:[’‘ʼ'\-‑][^\W_]+)*", text, re.UNICODE))

def word_label(item):
    count=item["word_count"]
    return f"{count} word{'s' if count != 1 else ''}"

def load_library(language=1):
    result=[]; pack=local_pack(language)
    for key in FEEDS:
        if pack is not None and key in pack:
            data=pack[key]
        elif language==1:
            file=CACHE/f"{key}.json"
            try:
                data=json.loads(file.read_text()); validate_feed(key,data,1)
            except (OSError,ValueError,KeyError,TypeError): data=json.loads((ROOT/"data"/f"{key}.json").read_text())
        else: continue
        rows=validate_feed(key,data,language)
        for position,row in enumerate(rows,1):
            text=plain(row.get("Text", ""))
            if not text: continue
            group=("From the Arabic" if row["IsArabic"] else "From the Persian") if key=="hidden" else BOOKS.get(key, "Prayers")
            tags=[t["Name"] for t in row.get("Tags", [])] if key=="prayers" else [group]
            number=row.get("Roman", row.get("Number", ""))
            opening=" ".join(text.split())
            title=opening[:90] if key=="prayers" else f"{number} · {opening[:72]}"
            subgroup=(row.get("SubTitle") or row.get("Title") or f"Tablet {row.get('TabletNumber', '')}") if key=="tablets" else (f"Part {row.get('Part', '')}" if key=="iqan" else None)
            references=[]
            if key=="aqdas":
                subgroup=AQDAS_SECTIONS[row["AqdasSection"]]
                title=f"{number} · {opening[:72]}"
                for section in AQDAS_SECTIONS:
                    values=row.get(section,[])
                    if not isinstance(values,list):continue
                    for value in values:
                        match=next((r for r in rows if r["AqdasSection"]==section and r.get("Number")==value),None)
                        if match:references.append((("" if language==1 else f"{language}:")+f"aqdas:{match['Id']}",f"{AQDAS_SECTIONS[section]} {value}"))
                if row.get("AqdasNumber"):
                    target=next((r for r in rows if r["AqdasSection"]=="Paragraphs" and r.get("Number")==row["AqdasNumber"]),None)
                    if target:references.append((("" if language==1 else f"{language}:")+f"aqdas:{target['Id']}",f"Text {row['AqdasNumber']}"))
            elif key=="saq":
                subgroup=f"{row.get('PartNumber','')} · {row.get('PartTitle','')}"
                title=f"{number} · {row.get('Title') or opening[:72]}"
            elif key=="days":
                subgroup=HOLY_DAYS.get(row.get("HolyDay"),row.get("HolyDay","Selections"))
                title=f"{position} · {opening[:72]}"
            elif key=="ridvan":
                year=row.get("Year",""); subgroup=f"{int(year)//10*10}s" if str(year).isdigit() else "Messages"
                title=f"{year} · {row.get('Title') or 'Riḍván message'}"
            result.append(dict(id=("" if language==1 else f"{language}:")+f"{key}:{row['Id']}", section="writings" if key in BOOKS else key, tags=tags, title=title, text=text, subgroup=subgroup, word_count=word_count(text), references=references, citation=citation(key,row)))
    return result

class Reader(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.bahai.Reader")
        try: self.prefs=json.loads(STATE.read_text())
        except (OSError, ValueError): self.prefs={}
        self.languages=catalog(); self.language=int(self.prefs.get("language",1)); self.downloading=False
        if self.language!=1 and local_pack(self.language) is None: self.language=1
        self.items=load_library(self.language); self.section="prayers"; self.current=None; self.signature=None; self.palette_source=None; self.resolved_colors={}
        self.connect("activate", self.activate)
    def save(self):
        STATE.parent.mkdir(parents=True, exist_ok=True)
        temp=STATE.with_suffix(".tmp"); temp.write_text(json.dumps(self.prefs)); temp.replace(STATE)
    def button(self, text, callback):
        b=Gtk.Button(label=text); b.connect("clicked", callback); return b
    def activate(self, app):
        if hasattr(self, "window"): self.window.present(); return
        self.window=Gtk.ApplicationWindow(application=self, title="Bahá’í Reader", default_width=1160, default_height=790)
        outer=Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        header=Gtk.HeaderBar(); header.set_show_title_buttons(not bool(shutil.which("omarchy"))); header.set_title_widget(Gtk.Label(label="BAHÁ’Í READER"))
        header.pack_start(self.button("☰", lambda *_: self.sidebar.set_visible(not self.sidebar.get_visible())))
        self.star=self.button("☆ Save", self.bookmark); header.pack_end(self.star)
        menu=Gtk.MenuButton(label="Aa"); pop=Gtk.Popover(); menu.set_popover(pop); header.pack_end(menu)
        settings=Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        for edge in ("top", "bottom", "start", "end"): getattr(settings, "set_margin_"+edge)(18)
        pop.set_child(settings)
        self.option(settings, "Appearance", "theme", ["Omarchy", "Light", "Dark", "Sepia"], "Omarchy")
        fonts=sorted({f.get_name() for f in self.window.get_pango_context().list_families()})
        self.option(settings, "Reading font", "font", fonts, "Noto Serif" if "Noto Serif" in fonts else "DejaVu Serif")
        self.slider(settings, "Text size", "size", 15, 36, 22)
        self.slider(settings, "Line spacing", "spacing", 0, 20, 8)
        self.slider(settings, "Page margins", "margin", 24, 160, 80)
        settings.append(self.button("Languages & offline libraries…", self.language_dialog))
        settings.append(self.button("About Bahá’í Reader (F1)", lambda *_: (pop.popdown(), self.about_dialog())))
        self.window.set_child(outer)
        if shutil.which("omarchy"): outer.append(header); self.window.set_decorated(False)
        else: self.window.set_titlebar(header)
        keys=Gtk.EventControllerKey(); keys.connect("key-pressed", self.key_pressed); self.window.add_controller(keys)
        # Previous/Next before the reading view's own cursor keys see them.
        paging=Gtk.EventControllerKey(propagation_phase=Gtk.PropagationPhase.CAPTURE); paging.connect("key-pressed", self.page_key); self.window.add_controller(paging)
        body=Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL, wide_handle=True)
        self.split=body; self.panel_width_ready=False; self.panel_programmatic=False; self.panel_save_source=None; self.panel_window_width=0
        body.set_resize_start_child(False); body.set_shrink_start_child(True)
        body.set_resize_end_child(True); body.set_shrink_end_child(True)
        outer.append(body); body.set_vexpand(True)
        body.connect("notify::position",self.panel_moved)
        body.add_tick_callback(self.panel_layout)
        self.sidebar=Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10); self.sidebar.set_size_request(220,-1); self.sidebar.add_css_class("sidebar")
        for edge in ("top", "bottom", "start", "end"): getattr(self.sidebar,"set_margin_"+edge)(16)
        body.set_start_child(self.sidebar)
        for title,key in [("Prayers","prayers"),("The Hidden Words","hidden"),("Writings","writings"),("Saved passages","saved")]:
            b=self.button(title, lambda _,k=key: self.navigate(k)); self.sidebar.append(b)
        self.search=Gtk.SearchEntry(placeholder_text="Search this section…"); self.search.connect("search-changed", self.filter); self.sidebar.append(self.search)
        into_list=Gtk.EventControllerKey(); into_list.connect("key-pressed", self.search_key); self.search.add_controller(into_list)
        self.count=Gtk.Label(xalign=0); self.count.add_css_class("dim-label"); self.sidebar.append(self.count)
        scroll=Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.EXTERNAL); self.sidebar.append(scroll)
        self.toc=Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4); scroll.set_child(self.toc)
        # The contents list is one Tab stop; arrow keys move inside it.
        out_of_list=Gtk.EventControllerKey(propagation_phase=Gtk.PropagationPhase.CAPTURE); out_of_list.connect("key-pressed", self.list_key); scroll.add_controller(out_of_list)
        self.branches={}; self.passage_buttons=[]; self.active_group=[]; self.restoring=False; self.query=None
        right=Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, hexpand=True)
        right.set_margin_top(32); body.set_end_child(right)
        self.heading=Gtk.Label(label="Prayers", wrap=True); self.heading.add_css_class("heading"); right.append(self.heading)
        self.subtitle=Gtk.Label(label="A moment for reflection"); self.subtitle.add_css_class("dim-label"); right.append(self.subtitle)
        self.reader=Gtk.TextView(editable=False, cursor_visible=False, wrap_mode=Gtk.WrapMode.WORD, vexpand=True, hexpand=True)
        self.reader.set_top_margin(24); self.reader.set_bottom_margin(50)
        self.readscroll=Gtk.ScrolledWindow(vexpand=True, kinetic_scrolling=True); self.readscroll.set_child(self.reader); right.append(self.readscroll)
        self.scroll_tick=None; self.scroll_target=0.0; self.scroll_time=None; self.scroll_direction=0
        wheel=Gtk.EventControllerScroll.new(Gtk.EventControllerScrollFlags.VERTICAL)
        wheel.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        wheel.connect("scroll",self.reader_scroll); self.readscroll.add_controller(wheel)
        click=Gtk.GestureClick(); click.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        click.connect("pressed",lambda *_:self.stop_scroll()); self.readscroll.add_controller(click)
        self.related=Gtk.MenuButton(label="Related passages",visible=False); right.append(self.related)
        nav=Gtk.Box(spacing=12, halign=Gtk.Align.CENTER); nav.append(self.button("← Previous", lambda *_: self.step(-1))); nav.append(self.button("Next →", lambda *_: self.step(1))); right.append(nav)
        self.status=Gtk.Label(label="English · Available offline · Texts: BahaiPrayers.net", margin_bottom=16); self.status.add_css_class("dim-label"); right.append(self.status)
        self.provider=Gtk.CssProvider(); Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(),self.provider,Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.update_status(); self.navigate(self.prefs.get("section", "prayers")); self.apply_theme(); GLib.timeout_add_seconds(1,self.apply_theme)
        self.window.present()
    def stop_scroll(self):
        if self.scroll_tick is not None:
            self.readscroll.remove_tick_callback(self.scroll_tick); self.scroll_tick=None
        self.scroll_time=None; self.scroll_direction=0
    def reader_scroll(self,controller,dx,dy):
        event=controller.get_current_event()
        # Preserve the compositor/GTK's native pixel-precise touchpad gestures.
        if event is None or event.get_unit()!=Gdk.ScrollUnit.WHEEL:
            self.stop_scroll(); return False
        if event.get_modifier_state() & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK):
            self.stop_scroll(); return False
        if not Gtk.Settings.get_default().get_property("gtk-enable-animations"):
            self.stop_scroll(); return False
        return self.queue_scroll(dy)
    def queue_scroll(self,dy):
        if not dy:return False
        adjustment=self.readscroll.get_vadjustment()
        direction=1 if dy>0 else -1
        if self.scroll_tick is None or direction!=self.scroll_direction:
            self.scroll_target=adjustment.get_value()
        self.scroll_direction=direction
        distance=max(32,int(self.prefs.get("size",22))*2+int(self.prefs.get("spacing",8)))
        self.scroll_target=max(adjustment.get_lower(),min(adjustment.get_upper()-adjustment.get_page_size(),self.scroll_target+dy*distance))
        if self.scroll_tick is None:
            self.scroll_time=None; self.scroll_tick=self.readscroll.add_tick_callback(self.animate_scroll)
        return True
    def animate_scroll(self,widget,clock):
        now=clock.get_frame_time()
        dt=min(0.05,(now-self.scroll_time)/1_000_000) if self.scroll_time else 1/60
        self.scroll_time=now
        adjustment=self.readscroll.get_vadjustment()
        target=max(adjustment.get_lower(),min(adjustment.get_upper()-adjustment.get_page_size(),self.scroll_target))
        current=adjustment.get_value(); difference=target-current
        if abs(difference)<0.4:
            adjustment.set_value(target); self.scroll_tick=None; self.scroll_time=None; return False
        adjustment.set_value(current+difference*(1-math.exp(-dt/0.055)))
        return True
    def panel_layout(self,widget,clock):
        width=widget.get_width()
        if width<=0 or not self.sidebar.get_visible(): return True
        if width!=self.panel_window_width or not self.panel_width_ready:
            self.panel_window_width=width
            # Start at 28% of the actual allocated window; remember manual sizing.
            desired=self.prefs.get("sidebar_width", min(400,max(260,round(width*0.28))))
            position=min(max(220,int(desired)),max(220,int(width*0.60)))
            self.panel_programmatic=True; widget.set_position(position); self.panel_programmatic=False
            self.panel_width_ready=True
        return True
    def panel_moved(self,widget,_):
        if not self.panel_width_ready or self.panel_programmatic or not self.sidebar.get_visible():return
        self.prefs["sidebar_width"]=widget.get_position()
        if self.panel_save_source:GLib.source_remove(self.panel_save_source)
        def persist():
            self.panel_save_source=None; self.save(); return False
        self.panel_save_source=GLib.timeout_add(250,persist)
    def key_pressed(self, controller, key, code, modifiers):
        if modifiers & Gdk.ModifierType.CONTROL_MASK:
            if key==Gdk.KEY_f: self.sidebar.set_visible(True); self.search.grab_focus(); return True
            if key==Gdk.KEY_q: self.quit(); return True
            if key==Gdk.KEY_d: self.bookmark(); return True
        if key==Gdk.KEY_F1: self.about_dialog(); return True
        if key==Gdk.KEY_Escape: self.sidebar.set_visible(True); return True
        return False
    def page_key(self, controller, key, code, modifiers):
        # Alt+Left/Right and Ctrl+Page Up/Down, as in browsers and document viewers.
        if modifiers & Gdk.ModifierType.ALT_MASK and key in (Gdk.KEY_Left,Gdk.KEY_Right):
            self.step(-1 if key==Gdk.KEY_Left else 1); return True
        if modifiers & Gdk.ModifierType.CONTROL_MASK and key in (Gdk.KEY_Page_Up,Gdk.KEY_Page_Down):
            self.step(-1 if key==Gdk.KEY_Page_Up else 1); return True
        return False
    def quit_key(self, controller, key, code, modifiers):
        # Dialogs are plain windows; keep Ctrl+Q working while they have focus.
        if modifiers & Gdk.ModifierType.CONTROL_MASK and key==Gdk.KEY_q: self.quit(); return True
        return False
    def search_key(self, controller, key, code, modifiers):
        if key in (Gdk.KEY_Tab,Gdk.KEY_Down) and not modifiers & (Gdk.ModifierType.SHIFT_MASK|Gdk.ModifierType.CONTROL_MASK):
            return self.focus_list()
        return False
    def focus_list(self):
        current=next((b for i,b in self.passage_buttons if self.current and i["id"]==self.current["id"] and b.is_drawable()),None)
        target=current or next((e for e,*_ in self.branch_rows if e.get_visible()),None)
        return bool(target) and target.grab_focus()
    def list_key(self, controller, key, code, modifiers):
        if key==Gdk.KEY_ISO_Left_Tab or (key==Gdk.KEY_Tab and modifiers & Gdk.ModifierType.SHIFT_MASK):
            self.search.grab_focus(); return True
        if key==Gdk.KEY_Tab: self.reader.grab_focus(); return True
        return False
    def option(self, box, title, key, options, default):
        box.append(Gtk.Label(label=title,xalign=0)); combo=Gtk.ComboBoxText()
        for item in options: combo.append_text(item)
        fallback=default if default in options else (options[0] if options else "")
        value=self.prefs.get(key,fallback); combo.set_active(options.index(value) if value in options else options.index(fallback))
        def change(c): self.prefs[key]=c.get_active_text(); self.save(); self.signature=None; self.apply_theme()
        combo.connect("changed",change); box.append(combo)
    def slider(self,box,title,key,low,high,default):
        box.append(Gtk.Label(label=title,xalign=0)); scale=Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL,low,high,1)
        scale.set_value(self.prefs.get(key,default)); scale.set_draw_value(True)
        def change(s): self.prefs[key]=int(s.get_value()); self.save(); self.signature=None; self.apply_theme()
        scale.connect("value-changed",change); box.append(scale)
    def navigate(self,key):
        self.section="writings" if key=="gleanings" else key
        self.prefs["section"]=self.section; self.save(); self.search.set_text(""); self.rebuild()
    def rebuild(self):
        """Build the contents tree for the section once; searching only hides rows."""
        if not hasattr(self,"toc"): return
        saved=self.prefs.get("saved",[])
        self.section_items=[i for i in self.items if (i["id"] in saved if self.section=="saved" else i["section"]==self.section)]
        while child:=self.toc.get_first_child(): self.toc.remove(child)
        self.branches={}; self.branch_rows=[]; self.passage_buttons=[]; self.groups={}
        groups={}
        for item in self.section_items:
            for tag in item["tags"] or ["Uncategorized"]: groups.setdefault(tag,[]).append(item)
        for tag,items in sorted(groups.items()):
            path=f"{self.section}/{tag}"
            container=self.branch(self.toc,tag,path,items)
            subgroups={}
            for item in items: subgroups.setdefault(item["subgroup"],[]).append(item)
            for subgroup,entries in subgroups.items():
                parent=self.branch(container,subgroup,path+"/"+subgroup,entries) if subgroup else container
                for item in entries:
                    self.groups.setdefault(item["id"],entries)
                    button=self.button("",lambda _,i=item,g=entries:self.show_passage(i,g))
                    label=Gtk.Label(label=item["title"],xalign=0,ellipsize=Pango.EllipsizeMode.END,max_width_chars=29)
                    content=Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
                    content.append(label)
                    if item["section"]=="prayers":
                        count_label=Gtk.Label(label=word_label(item), xalign=0)
                        count_label.add_css_class("dim-label"); content.append(count_label)
                    button.set_child(content)
                    button.set_tooltip_text(item["title"]+(" — "+word_label(item) if item["section"]=="prayers" else ""))
                    button.add_css_class("toc-passage")
                    parent.append(button); self.passage_buttons.append((item,button))
        self.no_match=Gtk.Label(wrap=True,xalign=0,visible=False); self.no_match.add_css_class("dim-label"); self.toc.append(self.no_match)
        self.query=None; self.filter()
    def filter(self,*_):
        if not hasattr(self,"section_items"): return
        query=fold(self.search.get_text().strip())
        if query==self.query: return
        self.query=query
        if query:
            for item in self.section_items:
                if "search" not in item: item["search"]=fold(item["title"]+" "+item["text"]+" "+" ".join(item["tags"]))
        matches={i["id"] for i in self.section_items if query in i["search"]} if query else {i["id"] for i in self.section_items}
        self.visible=[i for i in self.section_items if i["id"] in matches]
        for item,button in self.passage_buttons: button.set_visible(item["id"] in matches)
        self.restoring=True
        for expander,total,path,items in self.branch_rows:
            count=sum(1 for i in items if i["id"] in matches)
            expander.set_visible(count>0); total.set_text(self.unit_label(count))
            expander.set_expanded(bool(query) or self.prefs.get("expanded",{}).get(path,False))
        self.restoring=False
        self.count.set_text(f"{len(self.visible)} passage{'s' if len(self.visible)!=1 else ''}")
        self.no_match.set_text(f"No passages match “{self.search.get_text().strip()}”." if query else "")
        self.no_match.set_visible(bool(query) and not self.visible)
        # Searching never moves the reading position; it only narrows the list.
        current=next((i for i in self.section_items if self.current and i["id"]==self.current["id"]),None)
        if current is not None:
            if current is not self.current: self.show_passage(current,self.groups[current["id"]])
            else: self.highlight()
        elif self.section_items:
            item=next((i for i in self.section_items if i["id"]==self.prefs.get("last")),self.section_items[0])
            self.show_passage(item,self.groups[item["id"]])
        else:
            self.related.set_visible(False); self.current=None; self.active_group=[]; self.reader.get_buffer().set_text(""); self.star.set_sensitive(False)
            if self.section=="saved":
                self.heading.set_text("No saved passages yet"); self.subtitle.set_text("Press Ctrl+D or ☆ Save to keep one here.")
            else:
                self.heading.set_text("No passages found"); self.subtitle.set_text("Check this language’s available books in Languages & offline libraries.")
    def unit_label(self,count):
        unit="prayer" if self.section=="prayers" else "passage"
        return f"{count} {unit}{'s' if count != 1 else ''}"
    def branch(self,parent,title,path,items):
        expander=Gtk.Expander(hexpand=True, vexpand=False)
        expander.add_css_class("toc-branch")
        heading=Gtk.Box(spacing=8, halign=Gtk.Align.START, margin_end=12)
        label=Gtk.Label(label=title, xalign=0,
                        ellipsize=Pango.EllipsizeMode.END, max_width_chars=18)
        heading.append(label)
        total=Gtk.Label(label=self.unit_label(len(items))); total.add_css_class("dim-label")
        heading.append(total)
        expander.set_label_widget(heading)
        expander.set_tooltip_text(title)
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=3,margin_start=14,margin_top=6,margin_bottom=6)
        expander.set_child(box); parent.append(expander); self.branches[path]=expander; self.branch_rows.append((expander,total,path,items))
        def toggled(widget,_):
            if not self.restoring and not self.query:
                self.prefs.setdefault("expanded",{})[path]=widget.get_expanded(); self.save()
        expander.connect("notify::expanded",toggled)
        return box
    def highlight(self):
        for item,button in self.passage_buttons:
            if self.current and item["id"]==self.current["id"]: button.add_css_class("current-passage")
            else: button.remove_css_class("current-passage")
    def show_passage(self,item,group):
        self.current=item; self.active_group=group; self.prefs["last"]=item["id"]; self.save()
        self.heading.set_text("Prayer" if item["section"]=="prayers" else item["title"].split(" · ")[0])
        self.subtitle.set_text(" · ".join(item["tags"]+([item["subgroup"]] if item["subgroup"] else [])+([word_label(item)] if item["section"]=="prayers" else [])))
        self.subtitle.set_wrap(True)
        self.reader.set_direction(Gtk.TextDirection.LTR if self.language_info().get("IsLeftToRight",True) else Gtk.TextDirection.RTL)
        self.stop_scroll()
        buffer=self.reader.get_buffer(); buffer.set_text(item["text"])
        if item["citation"]:
            tag=buffer.get_tag_table().lookup("citation") or buffer.create_tag("citation",style=Pango.Style.ITALIC,scale=0.85,pixels_above_lines=18)
            buffer.insert_with_tags(buffer.get_end_iter(),"\n\n— "+item["citation"],tag)
        self.readscroll.get_vadjustment().set_value(0)
        self.related.set_visible(bool(item["references"]))
        if item["references"]:
            pop=Gtk.Popover(); links=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=4)
            for target,label in item["references"]:
                def jump(_,target=target):
                    other=next((i for i in self.items if i["id"]==target),None)
                    if other:self.show_passage(other,[i for i in self.items if i["tags"]==other["tags"] and i["subgroup"]==other["subgroup"]])
                links.append(self.button(label,jump))
            scroller=Gtk.ScrolledWindow(max_content_height=320,propagate_natural_height=True,min_content_width=240)
            scroller.set_child(links); pop.set_child(scroller); self.related.set_popover(pop)
        self.star.set_sensitive(True); self.star.set_label("★ Saved" if item["id"] in self.prefs.get("saved",[]) else "☆ Save")
        self.highlight()
    def step(self,delta):
        if self.current in self.active_group:
            index=self.active_group.index(self.current)+delta
            if 0<=index<len(self.active_group): self.show_passage(self.active_group[index],self.active_group)
    def bookmark(self,*_):
        if not self.current: return
        saved=self.prefs.setdefault("saved",[]); key=self.current["id"]
        saved.remove(key) if key in saved else saved.append(key); self.save()
        self.star.set_label("★ Saved" if key in saved else "☆ Save")
        if self.section=="saved": self.rebuild()
    def apply_theme(self):
        mode=self.prefs.get("theme","Omarchy"); colors={}
        if mode=="Omarchy":
            states=[os.environ.get("HOST_XDG_STATE_HOME"),os.environ.get("XDG_STATE_HOME"),Path.home()/".local/state"]
            paths=[Path(state)/"omarchy/current/theme/colors.toml" for state in states if state]+[Path.home()/".config/omarchy/current/theme/colors.toml"]
            for path in paths:
                try:
                    source=path.read_text()
                    if source != self.palette_source:
                        colors=tomllib.loads(source)
                        if shutil.which("omarchy"):
                            try:
                                resolved=subprocess.run(["omarchy","theme","color","--file",str(path),"--all"],capture_output=True,text=True,timeout=3,check=True)
                                colors.update(dict(line.split("\t",1) for line in resolved.stdout.splitlines() if "\t" in line))
                            except (OSError,subprocess.SubprocessError): pass
                        self.palette_source=source; self.resolved_colors=colors
                    colors=self.resolved_colors
                    break
                except (OSError,ValueError): pass
        base={"background":"#161b19","foreground":"#e6e1d3","accent":"#c9ab70","selection":"#303b35"}
        if mode=="Light": base.update(background="#fafaf7",foreground="#252b27",accent="#45654c",selection="#e2e9df")
        if mode=="Sepia": base.update(background="#f2e9d7",foreground="#463c2f",accent="#7e5d28",selection="#e2d4b9")
        base.update({k:v for k,v in colors.items() if k in base and isinstance(v,str) and re.fullmatch(r"#[0-9a-fA-F]{6}",v)})
        signature=json.dumps([base,self.prefs],sort_keys=True)
        if signature==self.signature:return True
        self.signature=signature; bg,fg,accent,selection=[base[k] for k in ("background","foreground","accent","selection")]
        font=self.prefs.get("font","DejaVu Serif").replace('"','').replace('\\','')
        size=int(self.prefs.get("size",22))
        self.provider.load_from_data(f'''window {{ font-family: monospace; }}
window, textview, textview text {{ background: {bg}; color: {fg}; }}
headerbar, popover contents, list, row, entry, button, combobox {{ background: {bg}; color: {fg}; }}
button {{ border: 1px solid {selection}; border-radius: 0px; padding: 8px 12px; }}
.toc-passage {{ border: none; padding: 8px; }}
.toc-branch > title {{ min-height: 32px; padding: 6px 0; }}
.toc-passage {{ min-height: 28px; }}
button.current-passage {{ color: {accent}; background: {selection}; }}
button:hover, row:selected {{ background: {selection}; }}
paned > separator {{ min-width: 5px; background: {selection}; }}
paned > separator:hover {{ background: {accent}; }}
headerbar {{ border-bottom: 1px solid {selection}; }}
.heading {{ color: {accent}; font-size: 19px; }}
/* Allow room for hinted glyphs and accents at fractional display scales. */
label {{ padding-top: 2px; padding-bottom: 2px; }}
.dim-label {{ opacity: 0.7; font-size: 13px; min-height: 18px; padding-top: 3px; padding-bottom: 3px; }}
textview {{ font-family: "{font}"; font-size: {size}px; }}
textview text selection {{ background: {selection}; }}'''.encode())
        self.reader.set_pixels_inside_wrap(int(self.prefs.get("spacing",8))); self.reader.set_pixels_below_lines(14)
        self.reader.set_left_margin(int(self.prefs.get("margin",80))); self.reader.set_right_margin(int(self.prefs.get("margin",80)))
        return True
    def language_info(self,language=None):
        language=self.language if language is None else language
        return next((r for r in self.languages["prayers"] if r["Id"]==language), {"Name":str(language)})
    def update_status(self):
        self.status.set_text(f"{self.language_info()['Name']} · Available offline · Texts: BahaiPrayers.net")
    def use_language(self,language):
        items=load_library(language)
        if not items: raise ValueError("Download this language before switching")
        self.language=language; self.items=items; self.prefs["language"]=language; self.save()
        self.rebuild(); self.update_status()
    def details(self):
        """Version details to paste into a support email."""
        display=Gdk.Display.get_default()
        return (f"{APP_NAME} {version()}\n"
                f"Python {sys.version.split()[0]}, GTK {Gtk.get_major_version()}.{Gtk.get_minor_version()}.{Gtk.get_micro_version()}, PyGObject {gi.__version__}, Pango {Pango.version_string()}\n"
                f"{os.environ.get('XDG_CURRENT_DESKTOP','unknown desktop')}, {type(display).__name__ if display else 'no display'}")
    def privacy(self):
        home=str(Path.home())
        short=lambda path:str(path).replace(home,"~",1) if str(path).startswith(home) else str(path)
        return ("No accounts, no telemetry, no analytics. English is bundled, so starting, reading, searching and switching "
                "to a downloaded language never use the network. The app connects only when you choose Download & use, "
                "Update downloaded content or Check available languages: it then asks bahaiprayers.net over HTTPS for that "
                "language’s texts or the language list. The request carries only the collection, the language number and "
                f"Python’s standard user agent; like any web request, the site sees your IP address. Downloads are saved in {short(LIBRARY)}. Settings and saved "
                f"passages stay in {short(STATE)} and are never sent anywhere.")
    def about_dialog(self,*_):
        if getattr(self,"about_window",None):
            self.about_window.present(); return
        window=Gtk.Window(title="About Bahá’í Reader",transient_for=self.window,modal=True,default_width=560)
        self.about_window=window
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=14)
        for edge in ("top","bottom","start","end"): getattr(box,"set_margin_"+edge)(20)
        scroller=Gtk.ScrolledWindow(propagate_natural_height=True,max_content_height=640,hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroller.set_child(box); window.set_child(scroller)
        top=Gtk.Box(spacing=16); box.append(top)
        icon=shipped("packaging/org.bahai.Reader.svg","icons/hicolor/scalable/apps/org.bahai.Reader.svg")
        image=Gtk.Image.new_from_file(str(icon)) if icon else Gtk.Image.new_from_icon_name("org.bahai.Reader")
        image.set_pixel_size(64); image.set_valign(Gtk.Align.START); top.append(image)
        names=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=2); top.append(names)
        title=Gtk.Label(label=APP_NAME,xalign=0); title.add_css_class("heading"); names.append(title)
        names.append(Gtk.Label(label=TAGLINE,xalign=0,wrap=True,max_width_chars=44))
        about_version=Gtk.Label(label="Version "+version(),xalign=0); about_version.add_css_class("dim-label"); names.append(about_version)
        grid=Gtk.Grid(column_spacing=18,row_spacing=10); box.append(grid)
        def row(name,widget):
            label=Gtk.Label(label=name,xalign=0,valign=Gtk.Align.START); label.add_css_class("dim-label")
            index=len(self.about_rows); self.about_rows[name]=widget
            grid.attach(label,0,index,1,1); grid.attach(widget,1,index,1,1)
        def text(value):
            return Gtk.Label(label=value,xalign=0,wrap=True,max_width_chars=52,hexpand=True)
        def actions(value,*buttons):
            line=Gtk.Box(spacing=10); line.append(Gtk.Label(label=value,xalign=0))
            for name,callback in buttons: line.append(self.button(name,callback))
            return line
        self.about_rows={}
        license_path=shipped("LICENSE","licenses/bahai-reader/LICENSE")
        notice_path=shipped("DATA-NOTICE.md","licenses/bahai-reader/DATA-NOTICE.md")
        license_view=text("\n\n".join(" ".join(p.split()).lstrip("# ") for path in (license_path,notice_path) if path for p in path.read_text().split("\n\n") if p.strip()) or f"{LICENSE_NAME}, {COPYRIGHT}")
        license_view.set_visible(False); self.about_license=license_view
        def toggle_license(button):
            license_view.set_visible(not license_view.get_visible()); button.set_label("Hide" if license_view.get_visible() else "Read it")
        def email(*_):
            uri="mailto:"+SUPPORT_EMAIL+"?subject="+GLib.Uri.escape_string(f"{APP_NAME} {version()}",None,False)+"&body="+GLib.Uri.escape_string("\n\n--\n"+self.details(),None,False)
            if hasattr(Gtk,"UriLauncher"): Gtk.UriLauncher.new(uri).launch(window,None,None)
            else: Gtk.show_uri(window,uri,Gdk.CURRENT_TIME)
        row("Made by",text(ORGANIZATION))
        row("Created",text(CREATED))
        row("License",actions(f"{LICENSE_NAME}, {COPYRIGHT}",("Read it",toggle_license)))
        row("Texts",text("From BahaiPrayers.net, which permits their use in apps. The texts and translations are not covered by the MIT license, and no ownership is claimed (DATA-NOTICE.md). Not an official publication of a Bahá’í institution."))
        row("Support",actions(SUPPORT_EMAIL,("Email",email),("Copy",lambda *_: window.get_clipboard().set(SUPPORT_EMAIL))))
        row("Privacy",text(self.privacy()))
        row("Built with",text(f"GTK {Gtk.get_major_version()}.{Gtk.get_minor_version()}.{Gtk.get_micro_version()}, PyGObject {gi.__version__}, Pango {Pango.version_string()}, Python {sys.version.split()[0]}"))
        box.append(license_view)
        buttons=Gtk.Box(spacing=10,halign=Gtk.Align.END); box.append(buttons)
        buttons.append(self.button("Copy version details",lambda *_: window.get_clipboard().set(self.details())))
        close=self.button("Close",lambda *_: window.close()); buttons.append(close)
        keys=Gtk.EventControllerKey()
        keys.connect("key-pressed",lambda _c,key,*_: key==Gdk.KEY_Escape and (window.close() or True))
        window.add_controller(keys)
        keys=Gtk.EventControllerKey(); keys.connect("key-pressed",self.quit_key); window.add_controller(keys)
        def closed(*_):
            self.about_window=None; return False
        window.connect("close-request",closed); window.present(); close.grab_focus()
    def language_dialog(self,*_):
        if hasattr(self,"language_window") and self.language_window:
            self.language_window.present(); return
        window=Gtk.Window(title="Languages & offline libraries",transient_for=self.window,modal=True,default_width=490)
        self.language_window=window
        keys=Gtk.EventControllerKey(); keys.connect("key-pressed",self.quit_key); window.add_controller(keys)
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=14)
        for edge in ("top","bottom","start","end"): getattr(box,"set_margin_"+edge)(20)
        window.set_child(box)
        intro=Gtk.Label(label="English is included. Download another language once to read it offline. Your choice is remembered.",wrap=True,xalign=0,max_width_chars=52); box.append(intro)
        choice=Gtk.ComboBoxText(); box.append(choice)
        info=Gtk.Label(wrap=True,xalign=0,max_width_chars=52); box.append(info)
        progress=Gtk.Label(wrap=True,xalign=0,max_width_chars=52); box.append(progress)
        action=self.button("",lambda *_: start(False)); box.append(action)
        refresh=self.button("Update downloaded content",lambda *_: start(True)); box.append(refresh)
        update_catalog=self.button("Check available languages",lambda *_: check_catalog()); box.append(update_catalog)
        def populate(selected):
            choice.remove_all()
            available={r["Id"] for r in self.languages["prayers"] if r["Id"]==1 or local_pack(r["Id"]) is not None}
            for row in sorted(self.languages["prayers"],key=lambda r:(r["Id"] not in available,r["Id"]!=1,r.get("English",r["Name"]).casefold())):
                name=row["Name"]; english=row.get("English",name)
                label=name if name==english else f"{name} — {english}"
                if row["Id"] in available:label+=" · Offline"
                choice.append(str(row["Id"]),label)
            choice.set_active_id(str(selected))
        def details(*_):
            if choice.get_active_id() is None:return
            language=int(choice.get_active_id()); available=language==1 or local_pack(language) is not None
            books=[SECTION_NAMES[k] for k in FEEDS if any(r["Id"]==language for r in self.languages[k])]
            stored=local_pack(language)
            missing=[SECTION_NAMES[k] for k in FEEDS if language!=1 and stored is not None and k not in stored and any(r["Id"]==language for r in self.languages[k])]
            offline_state="Available offline" if available else "Download needed"
            if missing:offline_state+=" — update to add: "+", ".join(missing)
            info.set_text(offline_state+"\n\nContent offered in this language:\n"+"\n".join(books))
            action.set_label("Use this language" if available else "Download & use")
            refresh.set_sensitive(available and not self.downloading)
        def busy(value):
            self.downloading=value
            for widget in (choice,action,refresh,update_catalog):widget.set_sensitive(not value)
            if not value:details()
        def report(message):
            GLib.idle_add(progress.set_text,message)
        def start(force):
            if self.downloading:return
            language=int(choice.get_active_id())
            if not force and (language==1 or local_pack(language) is not None):
                self.use_language(language); progress.set_text("Ready to read offline."); return
            busy(True); progress.set_text("Starting download…")
            def worker():
                error=None
                try: download_language(language,self.languages,report)
                except Exception as exc:error=str(exc)
                def done():
                    busy(False)
                    if error:progress.set_text("Download failed. Existing offline content is unchanged.\n"+error)
                    else:self.use_language(language); populate(language); progress.set_text("Downloaded and ready to read offline.")
                GLib.idle_add(done)
            threading.Thread(target=worker,daemon=True).start()
        def check_catalog():
            if self.downloading:return
            selected=int(choice.get_active_id()); busy(True); progress.set_text("Checking available languages…")
            def worker():
                error=None; fresh=None
                try:
                    fresh={key:fetch_json(endpoint) for key,endpoint in LANGUAGE_ENDPOINTS.items()}
                    if not all(isinstance(rows,list) and rows and all(isinstance(r,dict) and isinstance(r.get("Id"),int) and isinstance(r.get("Name"),str) for r in rows) for rows in fresh.values()):raise ValueError("Invalid language catalog")
                    atomic_json(LIBRARY/"languages.json",fresh)
                except Exception as exc:error=str(exc)
                def done():
                    if not error:self.languages=fresh; populate(selected)
                    busy(False); progress.set_text("Could not update language list. The saved list is still available." if error else "Language list updated.")
                GLib.idle_add(done)
            threading.Thread(target=worker,daemon=True).start()
        def close(*_):
            if self.downloading:
                progress.set_text("Please wait for the download to finish."); return True
            self.language_window=None; return False
        window.connect("close-request",close); choice.connect("changed",details)
        populate(self.language); details(); window.present()

if __name__=="__main__":
    # X11 WM_CLASS comes from the program name; match StartupWMClass and the Wayland app_id.
    GLib.set_prgname("org.bahai.Reader")
    Reader().run()

#!/usr/bin/python3
"""A quiet, native Linux reader for Bahá’í prayers and writings."""
import json
import datetime
import math
import os
import random
import re
import threading
import subprocess
import shutil
import tomllib
import urllib.error
import urllib.request
import tempfile
import sys
import unicodedata
from pathlib import Path
from html.parser import HTMLParser
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, GLib, GObject, Pango

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
# The prayer feed also carries whole books; these are listed under Writings instead of Prayers.
PRAYER_FEED_BOOKS = {"Epistle to the Son of the Wolf"}
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

SECTIONS=("prayers","obligatory","hidden","writings","saved")
THEMES=("Omarchy","Light","Dark","Sepia")
# Slider ranges; loaded values are clamped to them.
LIMITS={"size":(15,36,22),"spacing":(0,20,8),"margin":(24,160,80)}

def short_path(path):
    home=str(Path.home())
    return str(path).replace(home,"~",1) if str(path).startswith(home) else str(path)

def number(value):
    return isinstance(value,(int,float)) and not isinstance(value,bool) and math.isfinite(value)

def clean_settings(data):
    """Drop or clamp values of the wrong type, keeping everything that is usable."""
    prefs=dict(data)
    for key,(low,high,_) in LIMITS.items():
        if key in prefs:
            if number(prefs[key]): prefs[key]=min(high,max(low,int(prefs[key])))
            else: del prefs[key]
    if "sidebar_width" in prefs:
        if number(prefs["sidebar_width"]): prefs["sidebar_width"]=max(220,int(prefs["sidebar_width"]))
        else: del prefs["sidebar_width"]
    if not (isinstance(prefs.get("language"),int) and not isinstance(prefs.get("language"),bool)): prefs.pop("language",None)
    if not (isinstance(prefs.get("compare"),int) and not isinstance(prefs.get("compare"),bool)): prefs.pop("compare",None)
    if prefs.get("section")=="gleanings": prefs["section"]="writings"
    if prefs.get("section") not in SECTIONS: prefs.pop("section",None)
    if prefs.get("theme") not in THEMES: prefs.pop("theme",None)
    for key in ("font","last"):
        if not isinstance(prefs.get(key),str): prefs.pop(key,None)
    saved=prefs.get("saved")
    if saved is not None: prefs["saved"]=[i for i in saved if isinstance(i,str)] if isinstance(saved,list) else []
    if "collections" in prefs: prefs["collections"]=clean_collections(prefs["collections"],prefs.setdefault("saved",[]))
    expanded=prefs.get("expanded")
    if expanded is not None: prefs["expanded"]={k:v for k,v in expanded.items() if isinstance(v,bool)} if isinstance(expanded,dict) else {}
    return prefs

UNSORTED="Unsorted"

def collection_name(name):
    return " ".join(name.split()) if isinstance(name,str) else ""

def clean_collections(collections,saved):
    """[{"name","items"}] with usable names, each passage in one collection at most.
    Every passage filed in a collection stays saved, even when the saved list itself was damaged."""
    clean={}; filed=set()
    for entry in collections if isinstance(collections,list) else []:
        if not isinstance(entry,dict): continue
        items=[i for i in entry.get("items",[]) if isinstance(i,str)] if isinstance(entry.get("items"),list) else []
        saved.extend(i for i in dict.fromkeys(items) if i not in saved)
        name=collection_name(entry.get("name"))
        # A nameless entry's passages stay saved, as Unsorted; same-named collections are merged.
        if not name or name.casefold()==UNSORTED.casefold(): continue
        target=next((c for c in clean.values() if c["name"].casefold()==name.casefold()),None) or clean.setdefault(name,{"name":name,"items":[]})
        for item in items:
            if item not in filed: filed.add(item); target["items"].append(item)
    return list(clean.values())

def load_settings(path):
    """Returns (settings, notice). An unreadable file is set aside, never overwritten."""
    try: text=path.read_text()
    except FileNotFoundError: return {},None
    except (OSError,UnicodeDecodeError) as exc:
        print(f"bahai-reader: could not read {path}: {exc}",file=sys.stderr)
        return {},f"Your settings could not be read ({getattr(exc,'strerror',None) or exc}), so default settings are in use."
    try: data=json.loads(text)
    except ValueError: data=None
    if isinstance(data,dict): return clean_settings(data),None
    backup=path.with_name(path.name+".bad"); copy=0
    # Never replace an earlier backup: it may hold the only copy of someone's saved passages.
    while backup.exists(): copy+=1; backup=path.with_name(f"{path.name}.bad.{copy}")
    try:
        os.replace(path,backup); kept=f"The unreadable file, with any saved passages in it, was kept as {short_path(backup)}."
    except OSError as exc:
        print(f"bahai-reader: could not set aside {path}: {exc}",file=sys.stderr); kept=f"The file was left at {short_path(path)}."
    return {},"Your settings file could not be read, so default settings are in use. "+kept

def download_problem(exc):
    """A sentence for people; the raw error goes to the log."""
    print(f"bahai-reader: download failed: {exc!r}",file=sys.stderr)
    if isinstance(exc,(urllib.error.URLError,TimeoutError,ConnectionError)): return "Could not reach bahaiprayers.net. Check your connection and try again."
    if isinstance(exc,OSError): return f"The download could not be saved: {exc.strerror or exc}."
    if isinstance(exc,ValueError): return "bahaiprayers.net sent content the app could not use. Try again later."
    return "The download did not complete. Try again later."

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

def clipping(item,excerpt=None):
    """The passage, or a selected part of it, followed by its citation, for pasting elsewhere."""
    text=(excerpt or item["text"]).strip(); cite=item["citation"]
    # A selection that runs into (or is only) the citation line under the passage.
    if cite: text=text.split("— "+cite)[0].strip() or item["text"]
    # Prayers carry only an author; the category is the nearest thing to a reference.
    if item["section"]=="prayers" and item["tags"]: cite=", ".join(filter(None,(cite,"Prayers",item["tags"][0])))
    return f"{text}\n\n— {cite}" if cite else text

def luminance(color):
    channels=[int(color[i:i+2],16)/255 for i in (1,3,5)]
    r,g,b=[c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4 for c in channels]
    return 0.2126*r+0.7152*g+0.0722*b

def contrast(first,second):
    # WCAG 2 contrast ratio between two #rrggbb colors.
    light,dark=sorted((luminance(first),luminance(second)),reverse=True)
    return (light+0.05)/(dark+0.05)

def readable(background,*candidates,minimum=4.5):
    # First candidate that meets the minimum on this background, else the strongest one.
    return next((c for c in candidates if contrast(c,background)>=minimum),max(candidates,key=lambda c:contrast(c,background)))

def word_count(text):
    # Keep apostrophes and hyphens inside words; em/en dashes separate words.
    return len(re.findall(r"[^\W_]+(?:[’‘ʼ'\-‑][^\W_]+)*", text, re.UNICODE))

def word_label(item):
    count=item["word_count"]
    return f"{count} word{'s' if count != 1 else ''}"

# Passages line up across languages by their numbering, as in BahaiPrayers.net's Matrix (comparison) feeds.
# Prayers, Days of Remembrance and Riḍván messages (several per year) share no numbering, so they are not paired.
ALIGN={"hidden":("IsArabic","Number"), "gleanings":("Number",), "meditations":("Number",), "tablets":("TabletNumber","Number"),
       "iqan":("Part","Number"), "aqdas":("AqdasSection","Number"), "saq":("Number",)}

def align(key,row):
    fields=ALIGN.get(key)
    return ":".join([key]+[str(row.get(f)) for f in fields]) if fields else None

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
            shelf="writings" if key in BOOKS else key; book=None
            if key=="prayers" and PRAYER_FEED_BOOKS.intersection(tags):
                book=min(PRAYER_FEED_BOOKS.intersection(tags)); shelf="writings"; tags=[book]; title=book
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
            result.append(dict(id=("" if language==1 else f"{language}:")+f"{key}:{row['Id']}", section=shelf, tags=tags, title=title, text=text, subgroup=subgroup, word_count=word_count(text), references=references, match=align(key,row), citation=", ".join(filter(None,(citation(key,row),book)))))
    return result

OBLIGATORY_PRAYERS=("Short Obligatory Prayer","Medium Obligatory Prayer","Long Obligatory Prayer")

def obligatory(items):
    """Contents of the Obligatory prayers section, as {group: passages}.
    The three prayers by their prayer-feed category, then Kitáb-i-Aqdas ¶6, which enjoins obligatory
    prayer, with the notes and Questions and Answers that the Aqdas data itself links to ¶6."""
    groups={}
    for name in OBLIGATORY_PRAYERS:
        prayer=next((i for i in items if i["section"]=="prayers" and name in i["tags"]),None)
        if prayer: groups.setdefault("The three prayers",[]).append(prayer)
    paragraph=next((i for i in items if i["id"].endswith("aqdas:Paragraphs:6")),None)
    if paragraph:
        by_id={i["id"]:i for i in items}
        guidance=[paragraph]+[by_id[target] for target,_ in paragraph["references"] if target in by_id]
        groups["Kitáb-i-Aqdas"]=sorted(guidance,key=lambda i:list(AQDAS_SECTIONS.values()).index(i["subgroup"]))
    return groups
# Passages short enough to read in a moment, from the prayers, the Hidden Words, Gleanings and Prayers and Meditations.
REFLECTION_BOOKS={BOOKS["gleanings"],BOOKS["meditations"]}
REFLECTION_WORDS=500

def reflections(items):
    pool=[i for i in items if (i["section"] in ("prayers","hidden") or REFLECTION_BOOKS.intersection(i["tags"])) and i["word_count"]<=REFLECTION_WORDS]
    return sorted(pool,key=lambda i:i["id"])

def passage_of_the_day(items,day):
    """The same passage all day; a fixed shuffle walked one step a day, so consecutive days always differ."""
    pool=reflections(items)
    if not pool: return None
    order=list(range(len(pool))); random.Random(1844).shuffle(order)
    return pool[order[day.toordinal()%len(pool)]]

class Choice(Gtk.DropDown):
    """Gtk.DropDown (ComboBoxText is deprecated since GTK 4.10) with string ids and a "changed" signal."""
    __gsignals__={"changed":(GObject.SignalFlags.RUN_FIRST,None,())}
    def __init__(self,search=False):
        super().__init__(enable_search=search)
        self.ids=[]; self.labels=Gtk.StringList()
        # Search needs an expression; PyGObject before 3.44 (Debian 12) cannot pass one, so those lists don't search.
        try: self.set_expression(Gtk.PropertyExpression.new(Gtk.StringObject,None,"string"))
        except TypeError: self.set_enable_search(False)
        self.set_model(self.labels)
        self.connect("notify::selected",lambda *_:self.emit("changed"))
    def append(self,id,label): self.ids.append(id); self.labels.append(label)
    def append_text(self,label): self.append(label,label)
    def remove_all(self): self.ids=[]; self.labels.splice(0,self.labels.get_n_items(),[])
    def get_active_id(self):
        index=self.get_selected(); return self.ids[index] if index<len(self.ids) else None
    def get_active_text(self):
        index=self.get_selected(); return self.labels.get_string(index) if index<len(self.ids) else None
    def set_active_id(self,id):
        if id in self.ids: self.set_selected(self.ids.index(id))

class Reader(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.bahai.Reader")
        self.window=None; self.notices=[]; self.save_failed=False
        self.prefs,notice=load_settings(STATE)
        if notice: self.notices.append(notice)
        self.languages=catalog(); self.language=self.prefs.get("language",1); self.downloading=False
        if self.language!=1 and local_pack(self.language) is None:
            name=self.language_info().get("English",self.language_info()["Name"])
            if (LIBRARY/f"{self.language}.json").exists(): self.notices.append(f"The downloaded {name} library could not be read, so English is shown. Download it again in Aa → Languages & offline libraries.")
            else: self.notices.append(f"The {name} library is not downloaded, so English is shown.")
            self.language=1
        self.items=load_library(self.language); self.section="prayers"; self.current=None; self.signature=None; self.palette_source=None; self.resolved_colors={}
        self.connect("activate", self.activate)
    def save(self):
        temp=STATE.with_suffix(".tmp")
        try:
            STATE.parent.mkdir(parents=True, exist_ok=True)
            temp.write_text(json.dumps(self.prefs)); temp.replace(STATE)
        except OSError as exc:
            # Reading still works; say so once instead of failing every click.
            print(f"bahai-reader: could not save {STATE}: {exc}",file=sys.stderr)
            if not self.save_failed: self.notice(f"Settings and saved passages cannot be stored ({exc.strerror or exc}). Changes last until you close the app.")
            self.save_failed=True
            try: temp.unlink(missing_ok=True)
            except OSError: pass
    def notice(self,text):
        if not hasattr(self,"notice_box"): self.notices.append(text); return
        row=Gtk.Box(spacing=12); row.add_css_class("notice")
        row.append(Gtk.Label(label=text,wrap=True,xalign=0,hexpand=True))
        row.append(self.button("Dismiss",lambda *_: (self.notice_box.remove(row), self.notice_box.set_visible(self.notice_box.get_first_child() is not None))))
        self.notice_box.append(row); self.notice_box.set_visible(True)
    def button(self, text, callback):
        b=Gtk.Button(label=text); b.connect("clicked", callback); return b
    def activate(self, app):
        if self.window: self.window.present(); return
        try: self.build()
        except Exception:
            # Never leave a running instance without a window; later launches would find it.
            if self.window: self.window.destroy()
            self.window=None; self.quit(); raise
    def build(self):
        self.window=Gtk.ApplicationWindow(application=self, title="Bahá’í Reader", default_width=1160, default_height=790)
        outer=Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        header=Gtk.HeaderBar(); header.set_show_title_buttons(not bool(shutil.which("omarchy"))); header.set_title_widget(Gtk.Label(label="BAHÁ’Í READER"))
        header.pack_start(self.button("☰", lambda *_: self.sidebar.set_visible(not self.sidebar.get_visible())))
        today=self.button("Today",lambda *_: self.daily_passage()); today.set_tooltip_text("Passage of the day (Ctrl+T)"); header.pack_start(today)
        chance=self.button("Random",lambda *_: self.random_passage()); chance.set_tooltip_text("A random passage (Ctrl+R)"); header.pack_start(chance)
        self.star=self.button("☆ Save", self.bookmark); header.pack_end(self.star)
        self.copy=self.button("Copy", self.copy_passage); self.copy.set_tooltip_text("Copy the passage with its citation (Ctrl+Shift+C)"); header.pack_end(self.copy)
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
        settings.append(Gtk.Label(label="Side by side",xalign=0)); self.compare=Choice(); settings.append(self.compare)
        self.compare.connect("changed",self.compare_changed); self.compare_cache=(None,{}); self.filling_compare=False
        pop.connect("show",lambda *_: self.fill_compare())
        settings.append(self.button("Languages & offline libraries…", self.language_dialog))
        settings.append(self.button("About Bahá’í Reader (F1)", lambda *_: (pop.popdown(), self.about_dialog())))
        self.window.set_child(outer)
        if shutil.which("omarchy"): outer.append(header); self.window.set_decorated(False)
        else: self.window.set_titlebar(header)
        self.notice_box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,visible=False); outer.append(self.notice_box)
        for text in self.notices: self.notice(text)
        self.notices=[]
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
        for title,key in [("Prayers","prayers"),("Obligatory prayers","obligatory"),("The Hidden Words","hidden"),("Writings","writings"),("Saved passages","saved")]:
            b=self.button(title, lambda _,k=key: self.navigate(k)); self.sidebar.append(b)
        self.manage=self.button("Manage collections…",self.collections_dialog); self.manage.set_visible(False); self.sidebar.append(self.manage)
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
        self.pages=Gtk.Box(homogeneous=True, vexpand=True); right.append(self.pages)
        self.readscroll=Gtk.ScrolledWindow(vexpand=True, kinetic_scrolling=True); self.readscroll.set_child(self.reader); self.pages.append(self.readscroll)
        # A second language beside the passage, from a downloaded library; never fetched while reading.
        self.second=Gtk.TextView(editable=False, cursor_visible=False, wrap_mode=Gtk.WrapMode.WORD, vexpand=True, hexpand=True)
        self.second.set_top_margin(24); self.second.set_bottom_margin(50)
        self.secondscroll=Gtk.ScrolledWindow(vexpand=True, visible=False); self.secondscroll.set_child(self.second); self.pages.append(self.secondscroll)
        self.readscroll.get_vadjustment().connect("value-changed",self.follow_scroll)
        self.scroll_tick=None; self.scroll_target=0.0; self.scroll_time=None; self.scroll_direction=0
        wheel=Gtk.EventControllerScroll.new(Gtk.EventControllerScrollFlags.VERTICAL)
        wheel.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        wheel.connect("scroll",self.reader_scroll); self.readscroll.add_controller(wheel)
        click=Gtk.GestureClick(); click.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        click.connect("pressed",lambda *_:self.stop_scroll()); self.readscroll.add_controller(click)
        self.related=Gtk.MenuButton(label="Related passages",visible=False); right.append(self.related)
        self.filing=Gtk.Box(spacing=10,halign=Gtk.Align.CENTER,visible=False); right.append(self.filing)
        self.filing.append(Gtk.Label(label="Collection")); self.collection=Choice(); self.filing.append(self.collection)
        self.collection.connect("changed",self.file_current); self.filling=False
        self.filing.append(self.button("Manage…",self.collections_dialog))
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
            if key==Gdk.KEY_t: self.daily_passage(); return True
            if key==Gdk.KEY_r: self.random_passage(); return True
            if key==Gdk.KEY_f: self.sidebar.set_visible(True); self.search.grab_focus(); return True
            if key==Gdk.KEY_q: self.quit(); return True
            if key==Gdk.KEY_d: self.bookmark(); return True
            if key in (Gdk.KEY_c,Gdk.KEY_C) and modifiers & Gdk.ModifierType.SHIFT_MASK: self.copy_passage(); return True
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
        box.append(Gtk.Label(label=title,xalign=0)); combo=Choice()
        for item in options: combo.append_text(item)
        fallback=default if default in options else (options[0] if options else "")
        value=self.prefs.get(key,fallback); combo.set_active_id(value if value in options else fallback)
        def change(c): self.prefs[key]=c.get_active_text(); self.save(); self.signature=None; self.apply_theme()
        combo.connect("changed",change); box.append(combo)
    def slider(self,box,title,key,low,high,default):
        box.append(Gtk.Label(label=title,xalign=0)); scale=Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL,low,high,1)
        scale.set_value(self.prefs.get(key,default)); scale.set_draw_value(True)
        def change(s): self.prefs[key]=int(s.get_value()); self.save(); self.signature=None; self.apply_theme()
        scale.connect("value-changed",change); box.append(scale)
    def navigate(self,key):
        self.section="writings" if key=="gleanings" else key
        self.prefs["section"]=self.section; self.save(); self.search.set_text(""); self.manage.set_visible(self.section=="saved"); self.rebuild()
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
        if self.section=="obligatory":
            # Prayers first, then the guidance, in reading order rather than alphabetically.
            groups=obligatory(self.items); self.section_items=[i for g in groups.values() for i in g]
        if self.section=="saved":
            # A personal prayerbook: collections in their own order, then whatever is not filed yet.
            groups=self.filed(); self.section_items=[i for g in groups.values() for i in g]
        for tag,items in (groups.items() if self.section in ("obligatory","saved") else sorted(groups.items())):
            path=f"{self.section}/{tag}"
            container=self.branch(self.toc,tag,path,items)
            subgroups={}
            for item in items: subgroups.setdefault(item["subgroup"] if self.section!="saved" else None,[]).append(item)
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
        self.query=None; self.filter(); self.show_second()
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
            expander.set_expanded(bool(query) or self.prefs.get("expanded",{}).get(path,self.section=="obligatory"))
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
            self.related.set_visible(False); self.current=None; self.active_group=[]; self.reader.get_buffer().set_text(""); self.star.set_sensitive(False); self.copy.set_sensitive(False); self.filing.set_visible(False)
            if self.section=="saved":
                self.heading.set_text("No saved passages yet"); self.subtitle.set_text("Press Ctrl+D or ☆ Save to keep one here.")
            else:
                self.heading.set_text("No passages found")
                self.subtitle.set_text("This language’s library does not mark the obligatory prayers." if self.section=="obligatory" else "Check this language’s available books in Languages & offline libraries.")
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
        self.show_second()
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
        self.copy.set_sensitive(True)
        self.show_filing()
        self.highlight()
    def step(self,delta):
        if self.current in self.active_group:
            index=self.active_group.index(self.current)+delta
            if 0<=index<len(self.active_group): self.show_passage(self.active_group[index],self.active_group)
    def bookmark(self,*_):
        if not self.current: return
        saved=self.prefs.setdefault("saved",[]); key=self.current["id"]
        saved.remove(key) if key in saved else saved.append(key)
        # Unsaving takes the passage out of its collection too.
        for collection in self.prefs.get("collections",[]):
            if key in collection["items"] and key not in saved: collection["items"].remove(key)
        self.save()
        self.star.set_label("★ Saved" if key in saved else "☆ Save"); self.show_filing()
        if self.section=="saved": self.rebuild()
    def copy_passage(self,*_):
        """Copies the selected words, or the whole passage, with the citation."""
        if not self.current: return None
        buffer=self.reader.get_buffer(); bounds=buffer.get_selection_bounds()
        excerpt=buffer.get_text(*bounds,False).strip() if bounds else None
        text=clipping(self.current,excerpt or None); self.window.get_clipboard().set(text)
        self.copy.set_label("Copied")
        if getattr(self,"copy_reset",None): GLib.source_remove(self.copy_reset)
        def reset():
            self.copy_reset=None; self.copy.set_label("Copy"); return False
        self.copy_reset=GLib.timeout_add(1500,reset)
        return text
    def filed(self):
        """{collection name: saved passages in it} for this language, then Unsorted."""
        by_id={i["id"]:i for i in self.items}; groups={}; filed=set()
        for collection in self.prefs.get("collections",[]):
            groups[collection["name"]]=[by_id[i] for i in collection["items"] if i in by_id]; filed.update(collection["items"])
        groups[UNSORTED]=[by_id[i] for i in self.prefs.get("saved",[]) if i in by_id and i not in filed]
        return groups
    def collection_of(self,key):
        return next((c["name"] for c in self.prefs.get("collections",[]) if key in c["items"]),None)
    def show_filing(self):
        saved=bool(self.current) and self.current["id"] in self.prefs.get("saved",[])
        self.filing.set_visible(saved)
        if not saved: return
        self.filling=True
        self.collection.remove_all(); self.collection.append("",UNSORTED)
        for collection in self.prefs.get("collections",[]): self.collection.append(collection["name"],collection["name"])
        self.collection.set_active_id(self.collection_of(self.current["id"]) or "")
        self.filling=False
    def file_current(self,choice):
        if self.filling or not self.current or choice.get_active_id() is None: return
        self.move_passage(self.current["id"],choice.get_active_id() or None)
    def move_passage(self,key,name):
        """Files a saved passage in the named collection, or in none (Unsorted)."""
        if key not in self.prefs.get("saved",[]) or name==self.collection_of(key): return
        for collection in self.prefs.get("collections",[]):
            if key in collection["items"]: collection["items"].remove(key)
            if collection["name"]==name: collection["items"].append(key)
        self.save()
        if self.section=="saved": self.rebuild()
    def name_problem(self,name,current=None):
        if not name: return "Type a name for the collection."
        if name.casefold()==UNSORTED.casefold(): return f"“{UNSORTED}” is where passages outside a collection go; choose another name."
        if any(c["name"].casefold()==name.casefold() and c["name"]!=current for c in self.prefs.get("collections",[])): return f"There is already a collection called “{name}”."
        return None
    def create_collection(self,name):
        """Returns a problem to show, or None once created."""
        name=collection_name(name); problem=self.name_problem(name)
        if problem: return problem
        self.prefs.setdefault("collections",[]).append({"name":name,"items":[]}); self.collections_changed(); return None
    def rename_collection(self,old,new):
        new=collection_name(new); problem=self.name_problem(new,current=old)
        if problem: return problem
        for collection in self.prefs.get("collections",[]):
            if collection["name"]==old: collection["name"]=new
        expanded=self.prefs.get("expanded",{})
        if f"saved/{old}" in expanded: expanded[f"saved/{new}"]=expanded.pop(f"saved/{old}")
        self.collections_changed(); return None
    def delete_collection(self,name):
        """Removes the collection only; its passages stay saved, under Unsorted."""
        self.prefs["collections"]=[c for c in self.prefs.get("collections",[]) if c["name"]!=name]
        self.prefs.get("expanded",{}).pop(f"saved/{name}",None); self.collections_changed()
    def collections_changed(self):
        self.save(); self.show_filing()
        if self.section=="saved": self.rebuild()
        if getattr(self,"collections_window",None): self.collections_window.refresh()
    def collections_dialog(self,*_):
        if getattr(self,"collections_window",None):
            self.collections_window.present(); return
        window=Gtk.Window(title="Collections",transient_for=self.window,modal=True,default_width=460)
        self.collections_window=window
        keys=Gtk.EventControllerKey(); keys.connect("key-pressed",self.quit_key); window.add_controller(keys)
        keys=Gtk.EventControllerKey(); keys.connect("key-pressed",lambda _c,key,*_: key==Gdk.KEY_Escape and (window.close() or True)); window.add_controller(keys)
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=12)
        for edge in ("top","bottom","start","end"): getattr(box,"set_margin_"+edge)(20)
        window.set_child(box)
        box.append(Gtk.Label(label=f"Group saved passages into collections. Deleting a collection keeps its passages saved, under {UNSORTED}.",wrap=True,xalign=0,max_width_chars=52))
        rows=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=8); box.append(rows)
        message=Gtk.Label(wrap=True,xalign=0,max_width_chars=52); message.add_css_class("dim-label"); box.append(message)
        create=Gtk.Box(spacing=8); box.append(create)
        entry=Gtk.Entry(placeholder_text="New collection name",hexpand=True); create.append(entry)
        def add(*_):
            problem=self.create_collection(entry.get_text())
            message.set_text(problem or "")
            if not problem: entry.set_text("")
        entry.connect("activate",add); create.append(self.button("Create",add))
        close=self.button("Close",lambda *_: window.close()); close.set_halign(Gtk.Align.END); box.append(close)
        def refresh():
            while child:=rows.get_first_child(): rows.remove(child)
            if not self.prefs.get("collections"): rows.append(Gtk.Label(label="No collections yet.",xalign=0))
            for collection in self.prefs.get("collections",[]):
                line=Gtk.Box(spacing=8); rows.append(line)
                name=Gtk.Entry(text=collection["name"],hexpand=True); line.append(name)
                count=len(collection["items"]); total=Gtk.Label(label=f"{count} passage{'s' if count!=1 else ''}"); total.add_css_class("dim-label"); line.append(total)
                def rename(*_,old=collection["name"],field=name):
                    problem=self.rename_collection(old,field.get_text()); message.set_text(problem or "")
                name.connect("activate",rename)
                line.append(self.button("Rename",rename))
                line.append(self.button("Delete",lambda *_,n=collection["name"]: (self.delete_collection(n),message.set_text(f"Deleted “{n}”; its passages are under {UNSORTED}."))))
        window.refresh=refresh; refresh()
        def closed(*_):
            self.collections_window=None; return False
        window.connect("close-request",closed); window.present(); entry.grab_focus()
    def daily_passage(self):
        item=passage_of_the_day(self.items,datetime.date.today())
        if item: self.open_passage(item,"Passage of the day")
        return item
    def random_passage(self):
        pool=[i for i in reflections(self.items) if i is not self.current]
        item=random.choice(pool) if pool else None
        if item: self.open_passage(item,"Random passage")
        return item
    def open_passage(self,item,label):
        """Shows a passage from any section, in its place in that section's contents."""
        if self.section!=item["section"]: self.navigate(item["section"])
        elif self.search.get_text(): self.search.set_text(""); self.filter()
        self.show_passage(item,self.groups[item["id"]])
        self.subtitle.set_text(label+" · "+self.subtitle.get_text())
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
        # Some themes (White) use an accent too close to the selection for text on it.
        current=readable(selection,accent,fg); focus=readable(bg,accent,fg,minimum=3); current_focus=readable(selection,fg,accent,minimum=3)
        self.colors=dict(background=bg,foreground=fg,accent=accent,selection=selection,current=current)
        font=self.prefs.get("font","DejaVu Serif").replace('"','').replace('\\','')
        size=int(self.prefs.get("size",22))
        self.provider.load_from_data(f'''window {{ font-family: monospace; }}
window, textview, textview text {{ background: {bg}; color: {fg}; }}
headerbar, popover contents, list, row, entry, button, combobox {{ background: {bg}; color: {fg}; }}
/* The GTK theme paints .sidebar itself; keep the contents list on the reading palette. */
.sidebar, .sidebar scrolledwindow, .sidebar viewport, .sidebar expander {{ background: {bg}; color: {fg}; }}
button {{ border: 1px solid {selection}; border-radius: 0px; padding: 8px 12px; }}
.toc-passage {{ border: none; padding: 8px; }}
.toc-branch > title {{ min-height: 32px; padding: 6px 0; }}
.toc-passage {{ min-height: 28px; }}
button.current-passage {{ color: {current}; background: {selection}; }}
button:hover, row:selected {{ background: {selection}; }}
button:focus-visible, .toc-branch > title:focus-visible {{ outline: 2px solid {focus}; outline-offset: -2px; }}
button.current-passage:focus-visible {{ outline-color: {current_focus}; }}
paned > separator {{ min-width: 5px; background: {selection}; }}
paned > separator:hover {{ background: {accent}; }}
headerbar {{ border-bottom: 1px solid {selection}; }}
.heading {{ color: {accent}; font-size: 19px; }}
/* Allow room for hinted glyphs and accents at fractional display scales. */
label {{ padding-top: 2px; padding-bottom: 2px; }}
.dim-label {{ opacity: 0.7; font-size: 13px; min-height: 18px; padding-top: 3px; padding-bottom: 3px; }}
textview {{ font-family: "{font}"; font-size: {size}px; }}
textview text selection {{ background: {selection}; }}
.notice {{ background: {selection}; color: {fg}; padding: 8px 16px; border-bottom: 1px solid {accent}; }}'''.encode())
        for view in (self.reader,self.second):
            view.set_pixels_inside_wrap(int(self.prefs.get("spacing",8))); view.set_pixels_below_lines(14)
            view.set_left_margin(int(self.prefs.get("margin",80))); view.set_right_margin(int(self.prefs.get("margin",80)))
        return True
    def compare_languages(self):
        """English and every downloaded library, except the language being read."""
        downloaded=sorted(int(p.stem) for p in LIBRARY.glob("*.json") if p.stem.isdigit()) if LIBRARY.is_dir() else []
        return [l for l in dict.fromkeys([1,*downloaded]) if l!=self.language]
    def fill_compare(self):
        self.filling_compare=True
        self.compare.remove_all(); self.compare.append("","Off")
        for language in self.compare_languages():
            info=self.language_info(language); self.compare.append(str(language),info.get("English",info["Name"]))
        self.compare.set_active_id(str(self.prefs.get("compare","")) if str(self.prefs.get("compare","")) in self.compare.ids else "")
        self.filling_compare=False
    def compare_changed(self,choice):
        if self.filling_compare or choice.get_active_id() is None: return
        if choice.get_active_id(): self.prefs["compare"]=int(choice.get_active_id())
        else: self.prefs.pop("compare",None)
        self.save(); self.show_second()
    def second_items(self,language):
        """{alignment key: passage} for a language, loaded from disk once."""
        if self.compare_cache[0]!=language:
            try: items=load_library(language)
            except (OSError,ValueError,KeyError,TypeError): items=[]
            self.compare_cache=(language,{i["match"]:i for i in items if i["match"]})
        return self.compare_cache[1]
    def show_second(self):
        language=self.prefs.get("compare")
        shown=language is not None and language!=self.language and self.current is not None
        self.secondscroll.set_visible(shown)
        if not shown: return
        info=self.language_info(language); name=info.get("English",info["Name"])
        other=self.second_items(language); match=self.current.get("match"); item=other.get(match) if match else None
        buffer=self.second.get_buffer(); buffer.set_text("")
        table=buffer.get_tag_table()
        label=table.lookup("language") or buffer.create_tag("language",scale=0.7,pixels_below_lines=12)
        note=table.lookup("note") or buffer.create_tag("note",style=Pango.Style.ITALIC,scale=0.85)
        cite=table.lookup("citation") or buffer.create_tag("citation",style=Pango.Style.ITALIC,scale=0.85,pixels_above_lines=18)
        buffer.insert_with_tags(buffer.get_end_iter(),info["Name"].upper()+"\n",label)
        if item:
            self.second.set_direction(Gtk.TextDirection.LTR if info.get("IsLeftToRight",True) else Gtk.TextDirection.RTL)
            buffer.insert(buffer.get_end_iter(),item["text"])
            if item["citation"]: buffer.insert_with_tags(buffer.get_end_iter(),"\n\n— "+item["citation"],cite)
        else:
            self.second.set_direction(Gtk.TextDirection.LTR)
            if not other: text=f"The {name} library is not downloaded or could not be read. Download it in Aa → Languages & offline libraries."
            elif not match: text="Prayers, Days of Remembrance and Riḍván messages are not numbered the same way in every language, so they cannot be shown side by side."
            else: text=f"This passage is not in the downloaded {name} library."
            buffer.insert_with_tags(buffer.get_end_iter(),text,note)
        self.secondscroll.get_vadjustment().set_value(0)
    def follow_scroll(self,adjustment):
        # Keep the second language at the same point in the passage, proportionally.
        if not self.secondscroll.get_visible(): return
        other=self.secondscroll.get_vadjustment(); span=adjustment.get_upper()-adjustment.get_page_size()
        if span>0: other.set_value(adjustment.get_value()/span*(other.get_upper()-other.get_page_size()))
    def language_info(self,language=None):
        language=self.language if language is None else language
        return next((r for r in self.languages["prayers"] if r["Id"]==language), {"Name":str(language)})
    def update_status(self):
        self.status.set_text(f"{self.language_info()['Name']} · Available offline · Texts: BahaiPrayers.net")
    def use_language(self,language):
        items=load_library(language)
        if not items: raise ValueError("Download this language before switching")
        self.language=language; self.items=items; self.prefs["language"]=language; self.save(); self.compare_cache=(None,{})
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
        choice=Choice(search=True); box.append(choice)
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
                except Exception as exc:error=download_problem(exc)
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
                except Exception as exc:error=download_problem(exc)
                def done():
                    if not error:self.languages=fresh; populate(selected)
                    busy(False); progress.set_text(f"Could not update the language list. The saved list is still available.\n{error}" if error else "Language list updated.")
                GLib.idle_add(done)
            threading.Thread(target=worker,daemon=True).start()
        def close(*_):
            if self.downloading:
                progress.set_text("Please wait for the download to finish."); return True
            self.language_window=None; return False
        window.connect("close-request",close); choice.connect("changed",details)
        populate(self.language); details(); window.present()

def usage():
    return (f"Usage: bahai-reader [--help | --version]\n\n{TAGLINE}\n"
            "With no options it opens the reader window; a second launch shows the open window.\n\n"
            "Options:\n  -h, --help     Show this help and exit\n  --version      Show the version and exit\n\n"
            f"Settings and saved passages: {short_path(STATE)}\nDownloaded languages: {short_path(LIBRARY)}\n"
            f"Support: {SUPPORT_EMAIL}")

def main(args):
    if args in (["-h"],["--help"]): print(usage()); return 0
    if args==["--version"]: print(f"{APP_NAME} {version()}"); return 0
    if args:
        print(f"bahai-reader: unknown option {args[0]!r}. Try bahai-reader --help.",file=sys.stderr); return 2
    # X11 WM_CLASS comes from the program name; match StartupWMClass and the Wayland app_id.
    GLib.set_prgname("org.bahai.Reader")
    return Reader().run([sys.argv[0]])

if __name__=="__main__":
    sys.exit(main(sys.argv[1:]))

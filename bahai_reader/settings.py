"""Reading, cleaning and validating settings.json, so a damaged file never stops the app."""
import json
import math
import os
import re
import sys
import badi

from .config import short_path
SECTIONS=("today","prayers","obligatory","hidden","writings","saved")

# "Monospace" is the look before 0.2, the fontconfig monospace family (Omarchy's configured font).
CHROME_FONTS={"System":None,"Monospace":"monospace"}

WRITINGS_GROUPINGS={"book":"Group by book","author":"Group by author"}

AUTHOR_ORDER=("The Báb","Bahá’u’lláh","‘Abdu’l‑Bahá","Shoghi Effendi","The Universal House of Justice")

THEMES=("Omarchy","Light","Dark","Sepia")

LIMITS={"size":(15,36,22),"spacing":(0,20,8),"margin":(24,160,80)}

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
    if prefs.get("chrome_font") not in CHROME_FONTS: prefs.pop("chrome_font",None)
    if prefs.get("writings_by") not in WRITINGS_GROUPINGS: prefs.pop("writings_by",None)
    for key in ("font","last"):
        if not isinstance(prefs.get(key),str): prefs.pop(key,None)
    saved=prefs.get("saved")
    if saved is not None: prefs["saved"]=[i for i in saved if isinstance(i,str)] if isinstance(saved,list) else []
    if "collections" in prefs: prefs["collections"]=clean_collections(prefs["collections"],prefs.setdefault("saved",[]))
    if "location" in prefs:
        place=badi.clean_place(prefs["location"])
        if place: prefs["location"]=place
        else: del prefs["location"]
    if "counter_target" in prefs:
        target=prefs["counter_target"] if isinstance(prefs["counter_target"],int) else None
        if badi.Counter.valid_target(target): pass
        else: del prefs["counter_target"]
    if prefs.get("prayer") not in ("short","medium","long","none"): prefs.pop("prayer",None)
    if "reminders" in prefs:
        reminders=prefs["reminders"] if isinstance(prefs["reminders"],dict) else {}
        prefs["reminders"]={k:v for k,v in reminders.items() if k in REMINDER_SWITCHES and isinstance(v,bool)}
    if "clock_hours" in prefs:
        hours=badi.clean_clock_hours(prefs["clock_hours"])
        if hours: prefs["clock_hours"]=hours
        else: del prefs["clock_hours"]
    if prefs.get("long_period") not in dict(badi.LONG_PERIODS): prefs.pop("long_period",None)
    if "long_lead_hours" in prefs and badi.long_lead({"long_lead_hours":prefs["long_lead_hours"]})!=prefs["long_lead_hours"]: del prefs["long_lead_hours"]
    if not isinstance(prefs.get("keep_running"),bool): prefs.pop("keep_running",None)
    if "reminders_sent" in prefs:
        sent=prefs["reminders_sent"] if isinstance(prefs["reminders_sent"],list) else []
        prefs["reminders_sent"]=[k for k in sent if isinstance(k,str) and DAY_KEY.match(k)]
    if not isinstance(prefs.get("keep_records"),bool): prefs.pop("keep_records",None)
    if "records" in prefs: prefs["records"]=clean_records(prefs["records"])
    expanded=prefs.get("expanded")
    if expanded is not None: prefs["expanded"]={k:v for k,v in expanded.items() if isinstance(v,bool)} if isinstance(expanded,dict) else {}
    return prefs

UNSORTED="Unsorted"

REMINDER_SWITCHES=("prayer","long","feast","holy","fast","fast_daily")

SAID_KEY=re.compile(r"\d{4}-\d\d-\d\d:((short|medium):(morning|noon|evening)|long:(sunset|noon|midnight|at:\d+))")

DAY_KEY=re.compile(r"\d{4}-\d\d-\d\d")

def clean_records(records):
    """{"said":[marks],"fasted":[days]}: the private history. Anything not in its form is dropped, the rest kept."""
    records=records if isinstance(records,dict) else {}
    said=records.get("said") if isinstance(records.get("said"),list) else []
    fasted=records.get("fasted") if isinstance(records.get("fasted"),list) else []
    return dict(said=[k for k in said if isinstance(k,str) and SAID_KEY.fullmatch(k)],fasted=[k for k in fasted if isinstance(k,str) and DAY_KEY.fullmatch(k)])

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

"""Accent- and apostrophe-insensitive matching, for the contents search and the offline city list."""
import json
import re
import unicodedata

from . import config
def fold(text):
    """Search form without case, accents, apostrophes or hyphens: Bahaullah finds Bahá’u’lláh."""
    text="".join(c for c in unicodedata.normalize("NFKD",text) if not unicodedata.combining(c)).casefold()
    return re.sub(r"[’‘ʼʻ'`´\-‐‑]","",text)

def load_cities(path=None):
    """The bundled city list, largest first, as (name, ASCII name, label, latitude, longitude, zone); loaded when first searched."""
    if path is None and CITIES: return CITIES
    data=json.loads((path or config.ROOT/"data"/"cities.json").read_text())
    rows=[]
    for line in data["cities"].split(";"):
        name,ascii_name,country,region,lat,lon,zone=line.split("|")
        region=data["regions"][int(region)]
        label=", ".join(dict.fromkeys(part for part in (name,region,data["countries"].get(country,country)) if part))
        rows.append((name,ascii_name or name,label,float(lat),float(lon),data["zones"][int(zone)]))
    if path is None: CITIES.extend(rows)
    return rows

CITIES=[]

def search_cities(query,limit=8,cities=None):
    """Places matching what was typed, without regard to accents: exact names, then names starting with it, then any word
    starting with it, then anything containing it; largest first within each. "Paris, Texas" narrows by region or country."""
    city,_,rest=query.partition(",")
    city=fold(city.strip()); rest=fold(rest.strip())
    if not city: return []
    found=[[],[],[],[]]
    for row in load_cities() if cities is None else cities:
        names=(fold(row[0]),fold(row[1]))
        if not any(city in n for n in names): continue
        if rest and rest not in fold(row[2]): continue
        if city in names: rank=0
        elif any(n.startswith(city) for n in names): rank=1
        elif any(w.startswith(city) for n in names for w in n.split()): rank=2
        else: rank=3
        found[rank].append(row)
    return [row for rank in found for row in rank][:limit]

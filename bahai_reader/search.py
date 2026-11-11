"""Accent- and apostrophe-insensitive matching, for the contents search and the offline city list."""
import json
import re
import unicodedata

from . import config
def fold(text):
    """Search form without case, accents, apostrophes or hyphens: Bahaullah finds Bahá’u’lláh."""
    text="".join(c for c in unicodedata.normalize("NFKD",text) if not unicodedata.combining(c)).casefold()
    return re.sub(r"[’‘ʼʻ'`´\-‐‑]","",text)

PUNCTUATION=re.compile(r"[’‘ʼʻ'`´\-‐‑]")

def fold_map(text):
    """fold(text), and for each of its characters the index in text it came from, so a match can be shown in the original."""
    out=[]; where=[]
    for i,c in enumerate(text):
        for d in unicodedata.normalize("NFKD",c):
            if unicodedata.combining(d): continue
            for e in d.casefold():
                if not PUNCTUATION.fullmatch(e): out.append(e); where.append(i)
    return "".join(out),where

def find(text,query):
    """Where query (already folded) first occurs in text, as (start, end) in text, or None."""
    folded,where=fold_map(text)
    at=folded.find(query)
    if at<0 or not query: return None
    return where[at],where[at+len(query)-1]+1

def search_passages(items,query):
    """Passages matching query anywhere in their title, text or categories, in library order. Matching uses each passage's
    folded text, made once and kept; where the match is in the text is worked out only for the results shown (find)."""
    query=fold(query.strip())
    if not query: return []
    found=[]
    for item in items:
        if "search" not in item: item["search"]=fold(item["title"]+" "+item["text"]+" "+" ".join(item["tags"]))
        if query in item["search"]: found.append(item)
    return found

def snippet(text,span,width=150):
    """(before, match, after) around span, cut at word boundaries, with … where text was left out."""
    if not span:
        flat=" ".join(text.split()); cut=flat[:width].rsplit(" ",1)[0] if len(flat)>width else flat
        return (cut+("…" if len(flat)>width else ""),"","")
    start,end=span; left=max(0,start-width//2); right=min(len(text),end+width//2)
    if left: left=text.find(" ",left)+1 or left
    if right<len(text): right=text.rfind(" ",end,right) if text.rfind(" ",end,right)>end else right
    clean=lambda t:" ".join(t.split())
    before=("…" if left else "")+clean(text[left:start])+(" " if text[left:start][-1:].isspace() else "")
    after=(" " if text[end:right][:1].isspace() else "")+clean(text[end:right])+("…" if right<len(text) else "")
    return before,text[start:end],after

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

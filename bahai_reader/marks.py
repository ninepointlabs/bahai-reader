"""Highlights and notes on passages: kept in settings.json beside saved passages, by passage id and character offsets into the
passage's text, with the highlighted words themselves so a highlight finds its place again if a later update moves the text.
They are never written into the texts. No GTK here."""
import datetime

COLORS=("yellow","green","blue","magenta")
NOTE_LIMIT=5000  # characters kept in one note

def clean_highlights(records):
    """Only well-formed highlights; anything else in the file is dropped rather than stopping the app."""
    if not isinstance(records,list): return []
    result=[]
    for r in records:
        if not isinstance(r,dict): continue
        start,end=r.get("start"),r.get("end")
        if not (isinstance(r.get("id"),str) and isinstance(start,int) and isinstance(end,int) and not isinstance(start,bool) and 0<=start<end): continue
        if r.get("color") not in COLORS or not isinstance(r.get("words"),str) or not r["words"]: continue
        record={"id":r["id"],"start":start,"end":end,"words":r["words"],"color":r["color"]}
        if isinstance(r.get("note"),str) and r["note"].strip(): record["note"]=r["note"][:NOTE_LIMIT]
        if isinstance(r.get("created"),str): record["created"]=r["created"]
        result.append(record)
    return result

def make(item,start,end,color="yellow",note=None,today=None):
    """A highlight of item["text"][start:end]."""
    text=item["text"]
    # Never begin or end on a space.
    while start<end and text[start].isspace(): start+=1
    while end>start and text[end-1].isspace(): end-=1
    if start>=end: return None
    record={"id":item["id"],"start":start,"end":end,"words":text[start:end],"color":color if color in COLORS else COLORS[0],
            "created":(today or datetime.date.today()).isoformat()}
    if note and note.strip(): record["note"]=note.strip()[:NOTE_LIMIT]
    return record

def anchor(text,record):
    """Where a highlight is in text now: its offsets if the words are still there, else the nearest place the same words are
    found, else None (the text changed; the highlight is kept and listed, but not drawn)."""
    start,end=record["start"],record["end"]
    if text[start:end]==record["words"]: return start,end
    places=[]; at=text.find(record["words"])
    while at>=0: places.append(at); at=text.find(record["words"],at+1)
    if not places: return None
    best=min(places,key=lambda p:abs(p-start))
    return best,best+len(record["words"])

def of_passage(records,item_id):
    return [r for r in records if r["id"]==item_id]

def overlapping(records,item_id,start,end):
    """The passage's highlights that touch start..end."""
    return [r for r in of_passage(records,item_id) if r["start"]<end and start<r["end"]]

def add(records,record):
    """Adds a highlight; any highlight of the same passage it overlaps is replaced by it (one colour per word)."""
    keep=[r for r in records if not (r["id"]==record["id"] and r["start"]<record["end"] and record["start"]<r["end"])]
    return keep+[record]

def excerpt(words,limit=220):
    flat=" ".join(words.split())
    return flat if len(flat)<=limit else flat[:limit].rsplit(" ",1)[0]+"…"

"""The texts: BahaiPrayers.net feeds and downloaded language packs, bahai.org official texts, and how they are grouped."""
import json
import random
import re
import urllib.error
import urllib.request
import sys
from html.parser import HTMLParser

from . import config
from .citations import BAHAI_ORG_NOTICE, citation
from .config import AQDAS_SECTIONS, BOOKS, BOOK_AUTHORS, FEEDS, HOLY_DAYS, PRAYER_AUTHORS, PRAYER_FEED_BOOKS, SECTION_NAMES, atomic_json
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

def catalog():
    for file in (config.LIBRARY/"languages.json", config.ROOT/"data/languages.json"):
        try:
            data={**json.loads((config.ROOT/"data/languages.json").read_text()), **json.loads(file.read_text())}
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
        data=json.loads((config.LIBRARY/f"{language}.json").read_text())
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
    atomic_json(config.LIBRARY/f"{language}.json",downloads)
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


def word_count(text):
    # Keep apostrophes and hyphens inside words; em/en dashes separate words.
    return len(re.findall(r"[^\W_]+(?:[’‘ʼ'\-‑][^\W_]+)*", text, re.UNICODE))

# Passages line up across languages by their numbering, as in BahaiPrayers.net's Matrix (comparison) feeds.
# Prayers, Days of Remembrance and Riḍván messages (several per year) share no numbering, so they are not paired.
ALIGN={"hidden":("IsArabic","Number"), "gleanings":("Number",), "meditations":("Number",), "tablets":("TabletNumber","Number"),
       "iqan":("Part","Number"), "aqdas":("AqdasSection","Number"), "saq":("Number",)}

def align(key,row):
    fields=ALIGN.get(key)
    return ":".join([key]+[str(row.get(f)) for f in fields]) if fields else None

# Official texts from the Bahá’í Reference Library (bahai.org), imported by scripts/import-bahai-library.py.
# English only; they are bundled in data/ and never downloaded by the app.
OFFICIAL=("uhj-messages","shoghi-effendi")

def official_items(name):
    """The passages of one bahai.org collection, as reader items. Each keeps its source URL and its styled spans."""
    try: data=json.loads((config.ROOT/"data"/f"{name}.json").read_text())
    except (OSError,ValueError): return []
    result=[]
    for row in data.get("items",[]):
        if not isinstance(row,dict) or not isinstance(row.get("text"),str) or not row["text"]: continue
        author=row.get("author") or data.get("author")
        if name=="uhj-messages":
            year=row["iso_date"][:4]; subgroup=f"{int(year)//10*10}s"; head=row["date"]
            to=row["to"][:1].lower()+row["to"][1:] if row["to"].startswith("To ") else row["to"]
            citation=f"{author}, {row['date']}, {to}. {BAHAI_ORG_NOTICE}"
            # bahai.org's own classification: its Riḍván messages (dated Riḍván, or 21 April) form their own group.
            if row.get("riḍván") or row["iso_date"].endswith("-04-21"):
                group=data.get("ridvan_group",BOOKS["ridvan"])
                title=f"{year} · "+("Riḍván message" if row["to"] in ("To the Bahá’ís of the World","The Bahá’ís of the World") else row["to"])
            else: group=data["group"]; title=f"{row['date']} · {row['summary'] or row['to']}"
        else:
            group=row["book"]; subgroup=row.get("part"); title=row["title"]; head=row["title"]
            citation=f"{author}, {row['book']}, {row['title']}. {BAHAI_ORG_NOTICE}"
        spans=[tuple(s) for s in row.get("spans",[]) if isinstance(s,list) and len(s)==3]
        # An official text that replaces a BahaiPrayers.net copy takes that copy's id, so saved passages and the reading position follow it.
        result.append(dict(id=row.get("replaces") or row["id"],official_id=row["id"],author=author,section="writings",tags=[group],title=title,heading=head,text=row["text"],subgroup=subgroup,
                           word_count=row["words"] if isinstance(row.get("words"),int) else word_count(row["text"]),references=[],match=None,citation=citation,spans=spans,source=row.get("page_url")))
    return result

def official_replacements():
    """{app id: official passage} from data/bahai-org-books.json: bahai.org's text for passages the app has from BahaiPrayers.net."""
    try: data=json.loads((config.ROOT/"data"/"bahai-org-books.json").read_text())
    except (OSError,ValueError): return {}
    rows=data.get("replacements")
    return {k:v for k,v in rows.items() if isinstance(v,dict) and isinstance(v.get("text"),str) and v["text"]} if isinstance(rows,dict) else {}

def use_official(item,row):
    """Puts bahai.org's text in a BahaiPrayers.net passage, keeping its id, place, numbering and links."""
    old=" ".join(item["text"].split()); new=row.get("opening") if isinstance(row.get("opening"),str) and row["opening"] else " ".join(row["text"].split())
    title=item["title"]
    if item["section"]=="prayers": title=new[:90]
    elif title.endswith(old[:72]): title=title[:len(title)-len(old[:72])]+new[:72]
    spans=[tuple(s) for s in row.get("spans",[]) if isinstance(s,list) and len(s)==3]
    citation=item["citation"]
    # A prayer's citation names the bahai.org book its text was taken from.
    book=row.get("source") if item["section"]=="prayers" and isinstance(row.get("source"),str) else None
    if book: citation=", ".join(filter(None,(citation,book))); item["official_book"]=book
    item.update(text=row["text"],title=title,spans=spans,word_count=row["words"] if isinstance(row.get("words"),int) else word_count(row["text"]),
                citation=(citation+". " if citation else "")+BAHAI_ORG_NOTICE,official_id=f"{row.get('book')}:{row.get('anchor')}")
    item.pop("search",None)

def load_library(language=1):
    """The library for a language. In English, bahai.org's official text is used wherever it has the same text as BahaiPrayers.net."""
    result=load_bahaiprayers(language)
    if language==1:
        books=official_replacements()
        for item in result:
            if item["id"] in books: use_official(item,books[item["id"]])
        official=[i for name in OFFICIAL for i in official_items(name)]
        replaced={i["id"] for i in official}
        result=[i for i in result if i["id"] not in replaced]+official
    return result

def load_bahaiprayers(language=1):
    result=[]; pack=local_pack(language)
    for key in FEEDS:
        if pack is not None and key in pack:
            data=pack[key]
        elif language==1:
            file=config.CACHE/f"{key}.json"
            try:
                data=json.loads(file.read_text()); validate_feed(key,data,1)
            except (OSError,ValueError,KeyError,TypeError): data=json.loads((config.ROOT/"data"/f"{key}.json").read_text())
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
            author=PRAYER_AUTHORS.get(row.get("AuthorId")) if key=="prayers" else BOOK_AUTHORS.get(key)
            result.append(dict(id=("" if language==1 else f"{language}:")+f"{key}:{row['Id']}", author=author, section=shelf, tags=tags, title=title, text=text, subgroup=subgroup, word_count=word_count(text), references=references, match=align(key,row), citation=", ".join(filter(None,(citation(key,row),book)))))
    return result

OBLIGATORY_PRAYERS=("Short Obligatory Prayer","Medium Obligatory Prayer","Long Obligatory Prayer")

# individual, not congregational (12), women in their courses (13), travel (14).
AQDAS_ON_PRAYER=(6,8,10,12,13,14)

def obligatory(items):
    """Contents of the Obligatory prayers section, as {group: passages}.
    The three prayers by their prayer-feed category, then the Kitáb-i-Aqdas paragraphs on obligatory prayer,
    with the notes and Questions and Answers that the Aqdas data itself links to them."""
    groups={}
    for name in OBLIGATORY_PRAYERS:
        prayer=next((i for i in items if i["section"]=="prayers" and name in i["tags"]),None)
        if prayer: groups.setdefault("The three prayers",[]).append(prayer)
    by_id={i["id"]:i for i in items}; guidance={}
    for number in AQDAS_ON_PRAYER:
        paragraph=next((i for i in items if i["id"].endswith(f"aqdas:Paragraphs:{number}")),None)
        if paragraph:
            for passage in [paragraph]+[by_id[target] for target,_ in paragraph["references"] if target in by_id]: guidance.setdefault(passage["id"],passage)
    if guidance:
        def order(i):
            number=i["title"].split(" · ")[0]
            return list(AQDAS_SECTIONS.values()).index(i["subgroup"]),int(number) if number.isdigit() else 0
        groups["Kitáb-i-Aqdas"]=sorted(guidance.values(),key=order)
    return groups

# Paragraphs of an obligatory prayer that tell when and how to say it, or comment on it, rather than words to be said.
DIRECTION=re.compile(r'To be recited|God hath exempted|"The daily obligatory|\(|\d+\. ')

def unnumbered(item):
    """The text without bahai.org's margin numbers, for plain labels (the counter's verse, the passage of the day)."""
    numbers=sorted((a,b) for a,b,k in item.get("spans",()) if k=="num")
    if not numbers: return item["text"]
    text=item["text"]; out=[]; at=0
    for a,b in numbers:
        out.append(text[at:a]); at=b+1 if text[b:b+1]==" " else b
    return "".join(out)+text[at:]

def directions(item):
    """Character spans of an obligatory prayer's directions, shown in italics so the prayer itself stands out."""
    if not set(OBLIGATORY_PRAYERS).intersection(item["tags"]): return []
    if item.get("official_id"):
        # bahai.org sets the directions in italics itself: whole paragraphs in italics.
        text=item["text"]; starts={0}|{m.end() for m in re.finditer(r"\n\n",text)}
        return [(a,b) for a,b,k in item.get("spans",()) if k=="i" and a in starts and (b==len(text) or text.startswith("\n\n",b))]
    spans=[]; start=0
    for paragraph in item["text"].split("\n\n"):
        text=paragraph.strip()
        if start and text and (text.endswith(":") or DIRECTION.match(text)): spans.append((start,start+len(paragraph)))
        start+=len(paragraph)+2
    return spans

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

def badi_days_tag(item):
    """The HolyDay tag of a Days of Remembrance passage, or None."""
    if BOOKS["days"] not in item["tags"]: return None
    return next((tag for tag,name in HOLY_DAYS.items() if name==item["subgroup"]),None)

# Prayer-feed categories for the periods that have no Holy Day of their own.
AYYAM_PRAYERS="Intercalary Days"

FAST_PRAYERS="The Fast"

DAYS_OF_NOTE=30  # how near Ayyám-i-Há must be to be mentioned on Today

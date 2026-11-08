#!/usr/bin/python3
"""Imports official texts from the Bahá’í Reference Library (https://www.bahai.org/library/) into data/.

Run by hand; the app itself never goes online for these texts.

    scripts/import-bahai-library.py fetch SOURCES   download the index pages and every work's XHTML into SOURCES
    scripts/import-bahai-library.py build SOURCES   rebuild data/uhj-messages.json and data/shoghi-effendi.json from SOURCES
    scripts/import-bahai-library.py check SOURCES   rebuild into memory and fail if data/ differs (reproducibility)

fetch keeps what it already has (pass --refresh to download again) and waits a second between requests.
SOURCES holds the raw downloads and fetch-log.json (URL, SHA-256, date, HTTP headers); they are not committed.
The build records each source's URL, SHA-256 and download date next to the text it produced.

The text is taken as published: words, punctuation and diacritics are copied character for character. Only the
presentation changes: paragraphs become blank-line-separated text, and italics, bold, underlining (as in
Ma<u>sh</u>riqu’l-A<u>dh</u>kár) and footnote markers are kept as styled spans over that text, which the reader
draws as such. Footnotes follow the passage that cites them. See DATA-NOTICE.md for the terms of use.
"""
import argparse
import datetime
import difflib
import hashlib
import html
import json
import re
import sys
import tempfile
import time
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SITE = "https://www.bahai.org"
UHJ_INDEX = SITE+"/library/authoritative-texts/the-universal-house-of-justice/messages/"
SE_INDEX = SITE+"/library/authoritative-texts/shoghi-effendi/"
AGENT = "bahai-reader-importer/1 (+https://github.com/ninepointlabs/bahai-reader; manual run)"
COPYRIGHT = "Copyright © Bahá’í International Community"
TERMS = SITE+"/legal"
PARSER_VERSION = 1
UHJ = "The Universal House of Justice"
SHOGHI = "Shoghi Effendi"
UHJ_GROUP = "Messages of the Universal House of Justice"
X = "{http://www.w3.org/1999/xhtml}"

# The app's BahaiPrayers.net collections and their official bahai.org editions: collection key -> (category, slug).
BOOK_SOURCES={
    "hidden":("bahaullah","hidden-words"),
    "gleanings":("bahaullah","gleanings-writings-bahaullah"),
    "meditations":("bahaullah","prayers-meditations"),
    "tablets":("bahaullah","tablets-bahaullah"),
    "iqan":("bahaullah","kitab-i-iqan"),
    "aqdas":("bahaullah","kitab-i-aqdas"),
    "epistle":("bahaullah","epistle-son-wolf"),
    "saq":("abdul-baha","some-answered-questions"),
    "days":("bahaullah","days-remembrance"),
    "prayers":("prayers","bahai-prayers"),
}

# ---------------------------------------------------------------- fetching

def download(url):
    request=urllib.request.Request(url,headers={"User-Agent":AGENT})
    with urllib.request.urlopen(request,timeout=60) as response:
        return response.read(),{k:response.headers.get(k) for k in ("Last-Modified","ETag","Content-Type")}

class Fetcher:
    def __init__(self,folder,refresh=False,delay=1.0):
        self.folder=Path(folder); self.refresh=refresh; self.delay=delay
        self.log_path=self.folder/"fetch-log.json"
        self.log=json.loads(self.log_path.read_text()) if self.log_path.exists() else {}
        self.last=0.0
    def get(self,url,name):
        path=self.folder/name
        if path.exists() and not self.refresh and url in self.log: return path.read_bytes()
        wait=self.last+self.delay-time.monotonic()
        if wait>0: time.sleep(wait)
        for attempt in range(3):
            try:
                body,headers=download(url); break
            except Exception as error:  # noqa: BLE001 - report and retry, then give up on this one
                if attempt==2: raise
                print(f"  retry {url}: {error}",file=sys.stderr); time.sleep(5*(attempt+1))
        self.last=time.monotonic()
        path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(body)
        self.log[url]=dict(path=name,sha256=hashlib.sha256(body).hexdigest(),retrieved=datetime.date.today().isoformat(),
                           bytes=len(body),**{k.lower().replace("-","_"):v for k,v in headers.items() if v})
        self.save()
        return body
    def save(self):
        temp=self.log_path.with_suffix(".tmp"); temp.write_text(json.dumps(self.log,ensure_ascii=False,indent=1,sort_keys=True)); temp.replace(self.log_path)

def message_rows(index_html):
    """The message list on the index page: [(document id, date, addressee, summary)], as listed."""
    rows=[]
    for match in re.finditer(r'<tr id="(\d{8}_\d{3})" class="document-row".*?</tr>',index_html,re.S):
        cells=dict(re.findall(r'<td class="col-(date|to|summary)">(.*?)</td>',match.group(0),re.S))
        text=lambda v:" ".join(html.unescape(re.sub(r"<[^>]+>"," ",v or "")).split())
        rows.append((match.group(1),text(cells.get("date")),text(cells.get("to")),text(cells.get("summary"))))
    return rows

def work_slugs(index_html):
    return sorted(set(re.findall(r'href="/library/authoritative-texts/shoghi-effendi/([a-z0-9-]+)/"',index_html)))

def xhtml_link(page,slug,category="shoghi-effendi"):
    """The XHTML download on a work's page, with the edition marker bahai.org appends (?68416325)."""
    match=re.search(rf'(/library/authoritative-texts/{category}/{slug}/{slug}\.xhtml)(?:\?([0-9a-f]+))?',page)
    if not match: raise ValueError(f"No XHTML download on the page for {slug}")
    return SITE+match.group(1),match.group(2)

def fetch(folder,refresh=False,delay=1.0,only=None):
    fetcher=Fetcher(folder,refresh,delay); failures=[]
    if only in (None,"uhj"):
        index=fetcher.get(UHJ_INDEX,"uhj/index.html").decode()
        rows=message_rows(index); print(len(rows),"messages listed")
        for number,(doc,*_) in enumerate(rows,1):
            url=f"{UHJ_INDEX}{doc}/{doc}.xhtml"
            try: fetcher.get(url,f"uhj/{doc}.xhtml")
            except Exception as error: failures.append((url,str(error)))  # noqa: BLE001
            if number%50==0: print(f"  {number}/{len(rows)}")
    if only in (None,"se"):
        index=fetcher.get(SE_INDEX,"se/index.html").decode()
        for slug in work_slugs(index):
            page=fetcher.get(f"{SE_INDEX}{slug}/",f"se/{slug}.html").decode()
            url,_=xhtml_link(page,slug)
            try: fetcher.get(url,f"se/{slug}.xhtml")
            except Exception as error: failures.append((url,str(error)))  # noqa: BLE001
    if only in (None,"books"):
        for key,(category,slug) in BOOK_SOURCES.items():
            page=fetcher.get(f"{SITE}/library/authoritative-texts/{category}/{slug}/",f"books/{slug}.html").decode()
            url,_=xhtml_link(page,slug,category)
            try: fetcher.get(url,f"books/{slug}.xhtml")
            except Exception as error: failures.append((url,str(error)))  # noqa: BLE001
    for url,error in failures: print("FAILED",url,error,file=sys.stderr)
    return not failures

# ---------------------------------------------------------------- parsing

def css_styles(document):
    """Class name -> set of styles ("i", "b") from the stylesheet inside the file; bahai.org shortens class names per build."""
    styles={}
    sheet="".join(re.findall(r"<style[^>]*>(.*?)</style>",document,re.S))
    sheet=re.sub(r"/\*.*?\*/|@charset[^;]*;","",sheet,flags=re.S)
    for selectors,body in re.findall(r"([^{}]*)\{([^{}]*)\}",sheet):
        kinds=set()
        if re.search(r"font-style:\s*italic",body): kinds.add("i")
        if re.search(r"font-weight:\s*bold",body): kinds.add("b")
        if re.search(r"text-transform:\s*uppercase",body): kinds.add("upper")
        if not kinds: continue
        for selector in selectors.split(","):
            last=selector.strip().split()[-1] if selector.strip() else ""
            for name in re.findall(r"\.([A-Za-z0-9_-]+)",last): styles.setdefault(name,set()).update(kinds)
    return styles

def css_hidden(document):
    """Classes the page never shows (display: none on .X, .b .X or .ef .b .X; bahai.org's body has class ef), such as the
    duplicate "1." line beside each numbered Hidden Word."""
    hidden=set()
    sheet=re.sub(r"/\*.*?\*/|@charset[^;]*;","","".join(re.findall(r"<style[^>]*>(.*?)</style>",document,re.S)),flags=re.S)
    for selectors,body in re.findall(r"([^{}]*)\{([^{}]*)\}",sheet):
        if not re.search(r"display:\s*none",body): continue
        for selector in selectors.split(","):
            match=re.fullmatch(r"(?:\.ef\s+)?(?:\.b\s+)?\.([A-Za-z0-9_-]+)"," ".join(selector.split()))
            if match: hidden.add(match.group(1))
    return hidden

def css_sizes(document):
    """Class name -> font size in rem, from the stylesheet inside the file: how bahai.org marks titles and headings."""
    sizes={}
    sheet="".join(re.findall(r"<style[^>]*>(.*?)</style>",document,re.S))
    for selectors,body in re.findall(r"([^{}]*)\{([^{}]*)\}",re.sub(r"/\*.*?\*/|@charset[^;]*;","",sheet,flags=re.S)):
        size=re.search(r"font-size:\s*([\d.]+)rem",body)
        if not size: continue
        for selector in selectors.split(","):
            words=selector.strip().split()
            if words and words[0]==".b":
                for name in re.findall(r"\.([A-Za-z0-9_-]+)",words[-1]): sizes[name]=max(sizes.get(name,0),float(size.group(1)))
    return sizes

def parse(document):
    # XHTML is XML; &nbsp; and friends are not XML entities, so decode the few named ones first.
    body=re.sub(r"&(?!(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);)([A-Za-z]+);",lambda m:html.unescape(m.group(0)),document)
    body=re.sub(r"<!DOCTYPE[^>]*>","",body,count=1)
    return ET.fromstring(body)

def local(tag): return tag.split("}")[-1] if isinstance(tag,str) else ""
def classes(element): return set((element.get("class") or "").split())

BLOCKS={"p","h1","h2","h3","h4","h5","h6","li","blockquote","tr","dt","dd","pre"}
CONTAINERS=BLOCKS|{"div","ul","ol","table","section"}
# Generated list markers, as the page's stylesheet draws them (.mc decimal, .nc disc, .oc upper-roman).
def roman(number):
    out=""
    for value,letters in ((1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),(100,"C"),(90,"XC"),(50,"L"),(40,"XL"),(10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")):
        while number>=value: out+=letters; number-=value
    return out

class Block:
    """One paragraph-like element: its anchor, element name, classes, and text runs [(text, styles, note target)]."""
    def __init__(self,anchor,tag,cls):
        self.anchor=anchor; self.tag=tag; self.cls=cls; self.runs=[]; self.size=0; self.quote=False
    def text(self): return "".join(r[0] for r in self.runs)

class Reader:
    def __init__(self,document):
        self.styles=css_styles(document); self.sizes=css_sizes(document); self.hidden=css_hidden(document); self.root=parse(document)
        self.body=next(e for e in self.root.iter() if local(e.tag)=="body")
        self.meta={m.get("name"):m.get("content") for m in self.root.iter() if local(m.tag)=="meta" and m.get("name")}
        self.title=next(("".join(e.itertext()).strip() for e in self.root.iter() if local(e.tag)=="title"),"")
        self.notes={}; self.blocks=[]; self.toc=[]
        content=next(e for e in self.body if "b" in classes(e))
        self.walk(content,None,set())
    def style_of(self,element):
        kinds=set(); tag=local(element.tag)
        for name in classes(element): kinds|=self.styles.get(name,set())
        if tag in ("i","em","cite"): kinds.add("i")
        if tag in ("b","strong"): kinds.add("b")
        if tag=="u": kinds.add("u")
        return kinds
    @staticmethod
    def note_entry(element):
        """<div><a class="td ...">n</a><p>…</p></div>: one footnote."""
        kids=list(element)
        return (local(element.tag)=="div" and len(kids)>=2 and local(kids[0].tag)=="a" and kids[0].get("href") is None
                and (kids[0].text or "").strip().isdigit() and local(kids[1].tag)=="p")
    def is_notes(self,element):
        """The notes list: a div of footnote entries, with nothing else in it but their headings and empty lines."""
        if local(element.tag)!="div": return False
        entries=[d for d in element.iter() if self.note_entry(d)]
        if not entries: return False
        inside={id(p) for d in entries for p in d.iter()}
        return all(id(p) in inside or not "".join(p.itertext()).strip() for p in element.iter() if local(p.tag) in ("p","blockquote","table"))
    def walk(self,element,block,inherited,quoted=False):
        tag=local(element.tag); quoted=quoted or tag=="blockquote"
        if tag=="nav": self.read_toc(element); return
        if tag in ("script","style") or self.hidden&classes(element): return
        if block is None and self.is_notes(element): self.read_notes(element); return
        if block is None and tag in BLOCKS and not any(local(d.tag) in CONTAINERS for d in element.iter() if d is not element):
            anchor=next((a.get("id") for a in element.iter() if local(a.tag)=="a" and "sf" in classes(a) and a.get("id")),None)
            block=Block(anchor,tag,classes(element)); block.quote=quoted; self.blocks.append(block)
            block.size=max([self.sizes.get(c,0) for c in block.cls]+[{"h1":3.6,"h2":2.8,"h3":2.3,"h4":2.1}.get(tag,0)])
            if tag=="li" and element.get("value"):
                marker={"mc":element.get("value")+". ","oc":roman(int(element.get("value")))+". "}
                prefix=next((v for k,v in marker.items() if k in classes(element)),None)
                if prefix: block.runs.append((prefix,frozenset(),None))
            self.inline(element,block,inherited|self.style_of(element)); return
        if tag=="li" and element.get("value") and {"mc","oc"}&classes(element): raise ValueError("A numbered list item holding paragraphs; its number would be lost")
        if tag=="hr": self.blocks.append(Block(None,"hr",classes(element))); self.blocks[-1].runs.append(("* * *",frozenset(),None)); return
        if element.text and element.text.strip() and block is None: raise ValueError(f"Loose text outside a paragraph: {element.text.strip()[:60]!r}")
        for child in element:
            self.walk(child,None,inherited|self.style_of(element),quoted)
            if child.tail and child.tail.strip(): raise ValueError(f"Loose text outside a paragraph: {child.tail.strip()[:60]!r}")
    def inline(self,element,block,styles,note=None):
        tag=local(element.tag)
        if tag=="a" and "jc" in classes(element): return  # the ↩ link back from a note
        if self.hidden&classes(element): return
        if tag=="a" and "td" in classes(element) and (element.text or "").strip().isdigit():
            # bahai.org's paragraph or item number, shown in the margin: kept, and marked as a number.
            block.runs.append((element.text.strip(),frozenset(styles|{"num"}),None)); return
        if tag=="br": block.runs.append(("\n",frozenset(styles),note))
        elif tag=="wbr": pass
        else:
            if tag=="sup":
                link=next((a for a in element.iter() if local(a.tag)=="a" and (a.get("href") or "").startswith("#")),None)
                if link is not None: note=link.get("href")[1:]; styles=styles|{"sup"}
            if tag in ("td","th") and block.text().strip(): block.runs.append(("\t",frozenset(),None))  # table cells, tab-separated
            if element.text: block.runs.append((element.text,frozenset(styles),note))
            for child in element:
                self.inline(child,block,styles|self.style_of(child),note)
                if child.tail: block.runs.append((child.tail,frozenset(styles),note))
    def read_toc(self,nav):
        def entries(ul,depth,parents):
            for li in [c for c in ul if local(c.tag)=="li"]:
                link=next((a for a in li.iter() if local(a.tag)=="a" and (a.get("href") or "").startswith("#")),None)
                heading=next((c for c in li if local(c.tag) in ("h3","h4","h5")),None)
                label=" ".join("".join((link if link is not None else li).itertext()).split())
                target=link.get("href")[1:] if link is not None and link.get("href")!="#" else None
                self.toc.append(dict(label=label,target=target,depth=depth,heading=heading is not None,parents=list(parents)))
                # A grouping line with no target ("List of topics") is not a part of the work.
                for sub in [c for c in li if local(c.tag)=="ul"]: entries(sub,depth+1,parents+([label] if target else []))
        for ul in [c for c in nav if local(c.tag)=="ul"]: entries(ul,0,[])
    def read_notes(self,element):
        group=None
        for item in element.iter():
            tag=local(item.tag)
            if tag in ("h3","h4"): group=" ".join("".join(item.itertext()).split())
            if tag=="div" and item is not element:
                number=next((a for a in item if local(a.tag)=="a" and a.text and a.text.strip().isdigit()),None)
                paragraphs=[p for p in item if local(p.tag) in ("p","blockquote")]
                if number is None or not paragraphs: continue
                # The note marker links to the first paragraph's anchor; a note can run to several paragraphs.
                anchor=next((a.get("id") for a in paragraphs[0].iter() if local(a.tag)=="a" and a.get("id")),None)
                back=next((a.get("href")[1:] for a in item.iter() if local(a.tag)=="a" and "jc" in classes(a) and a.get("href")),None)
                blocks=[]
                for paragraph in paragraphs:
                    block=Block(None,"note",classes(paragraph)); self.inline(paragraph,block,set())
                    if clean_runs(block.runs): blocks.append(block)
                if not blocks: raise ValueError(f"Note {number.text.strip()} is empty")
                if anchor in self.notes: raise ValueError(f"Note anchor {anchor} twice")
                self.notes[anchor]=dict(number=number.text.strip(),blocks=blocks,back=back,group=group)

def clean_runs(runs):
    """Whitespace as a browser renders it: runs of spaces and newlines in the source become one space; <br> stays a line break."""
    out=[]
    for text,styles,note in runs:
        if text in ("\n","\t"): out.append((text,styles,note)); continue
        text=re.sub(r"[ \t\r\n]+"," ",text)
        if text: out.append((text,styles,note))
    # Trim spaces at the edges and around line breaks.
    joined=[]
    for i,(text,styles,note) in enumerate(out):
        if text not in ("\n","\t"):
            if not joined or joined[-1][0].endswith(("\n","\t"," ")) : text=text.lstrip(" ")
        elif joined: joined[-1]=(joined[-1][0].rstrip(" "),)+joined[-1][1:]
        if text: joined.append((text,styles,note))
    while joined and not joined[-1][0].strip(" \n"): joined.pop()
    if joined: joined[-1]=(joined[-1][0].rstrip(" \n"),)+joined[-1][1:]
    return [r for r in joined if r[0]]

SUPERSCRIPT=str.maketrans("0123456789","⁰¹²³⁴⁵⁶⁷⁸⁹")

class Passage:
    """Builds a passage's text and its styled spans; footnote markers become superscript digits pointing at notes."""
    def __init__(self): self.text=""; self.spans=[]; self.cited=[]
    def add_block(self,block,notes):
        runs=clean_runs(block.runs)
        if not runs: return
        if self.text: self.text+="\n\n"
        begin=len(self.text)
        for text,styles,note in runs:
            if note:
                if note not in notes: raise ValueError(f"Footnote marker {text!r} points at missing note {note}")
                text=text.translate(SUPERSCRIPT); self.cited.append(note); styles=styles-{"sup"}
            if "upper" in styles: text=text.upper()  # text-transform: uppercase, as the page shows it
            start=len(self.text); self.text+=text
            for kind in sorted(styles):
                if kind in ("i","b","u","num"): self.add_span(start,len(self.text),kind)
        if block.quote: self.spans.append([begin,len(self.text),"quote"])
        if block.size>=HEADING: self.spans.append([begin,len(self.text),"heading"])
    def add_span(self,start,end,kind):
        if start==end: return
        if self.spans and self.spans[-1][2]==kind and self.spans[-1][1]==start: self.spans[-1][1]=end
        else: self.spans.append([start,end,kind])
    def add_notes(self,notes):
        """The notes cited in this passage, in order of first citation, under a "Notes" line."""
        seen=list(dict.fromkeys(self.cited))
        if not seen: return []
        self.text+="\n\nNotes"; self.add_span(len(self.text)-5,len(self.text),"b")
        for anchor in seen:
            note=notes[anchor]
            self.text+="\n\n"+note["number"].translate(SUPERSCRIPT)+" "
            for n,block in enumerate(note["blocks"]):
                if n: self.text+="\n\n"
                for text,styles,_ in clean_runs(block.runs):
                    if "upper" in styles: text=text.upper()
                    start=len(self.text); self.text+=text
                    for kind in sorted(styles):
                        if kind in ("i","b","u"): self.add_span(start,len(self.text),kind)
        return seen

def word_count(text):
    """The reader's word count (reader.word_count), stored so the app need not count 900 passages at startup."""
    return len(re.findall(r"[^\W_]+(?:[’‘ʼ'\-‑][^\W_]+)*", text, re.UNICODE))

def sha256(data): return hashlib.sha256(data).hexdigest()

def provenance(log,url,extra=None):
    entry=log.get(url)
    if not entry: raise ValueError(f"{url} is not in fetch-log.json; run fetch first")
    return dict(source_url=url,sha256=entry["sha256"],retrieved=entry["retrieved"],**(extra or {}))

def fold(text):
    import unicodedata
    text="".join(c for c in unicodedata.normalize("NFKD",text) if not unicodedata.combining(c)).casefold()
    return re.sub(r"[^a-z0-9]","",text)

def words(text):
    import unicodedata
    text="".join(c for c in unicodedata.normalize("NFKD",text) if not unicodedata.combining(c)).casefold()
    return re.findall(r"[a-z0-9]+",re.sub(r"[’‘ʼ'`\-‐‑]","",text))

def shingles(text,size=6):
    w=words(text); return {" ".join(w[i:i+size]) for i in range(max(1,len(w)-size+1))}

def bahaiprayers_ridvan():
    """The Riḍván messages already in the app (data/ridvan.json, from BahaiPrayers.net), as {id: (row, shingles)}."""
    rows=json.loads((ROOT/"data/ridvan.json").read_text())
    return {f"ridvan:{r['Id']}":(r,shingles(re.sub(r"<[^>]+>"," ",html.unescape(r["Text"])))) for r in rows}

DUPLICATE=0.8  # share of the shorter text's six-word sequences found in the other

def overlap(first,second):
    """How much of the shorter text's six-word sequences appear in the other (1.0: all of them)."""
    if not first or not second: return 0.0
    return len(first&second)/min(len(first),len(second))

def same_text(first,second):
    return overlap(shingles(first),shingles(second))>=DUPLICATE


def build_messages(folder,log):
    index_url=UHJ_INDEX; index=(folder/"uhj/index.html").read_text()
    rows=message_rows(index); ridvan=bahaiprayers_ridvan()
    items=[]; aliases=[]; seen_text={}; omitted=[]; discrepancies=[]; matched={}
    for doc,date,to,summary in rows:
        url=f"{UHJ_INDEX}{doc}/{doc}.xhtml"; path=folder/f"uhj/{doc}.xhtml"
        if not path.exists(): omitted.append(dict(document=doc,reason="not downloaded")); continue
        raw=path.read_bytes()
        if sha256(raw)!=log[url]["sha256"]: raise ValueError(f"{path} does not match fetch-log.json")
        reader=Reader(raw.decode("utf-8"))
        if reader.meta.get("document-id")!=f"muhj{doc}": raise ValueError(f"{doc}: document-id {reader.meta.get('document-id')}")
        if reader.meta.get("date")!=doc[:8]:
            # Recorded, not fatal: the document id, the index and the dateline in the text agree with each other.
            discrepancies.append(dict(document=doc,field="meta date",found=reader.meta.get("date"),used=doc[:8]))
        passage=Passage()
        for block in reader.blocks: passage.add_block(block,reader.notes)
        passage.add_notes(reader.notes)
        folded=fold(passage.text); grams=shingles(passage.text)
        # A Riḍván message already in the app: same year (BahaiPrayers.net files some by the Riḍván they precede), most text shared.
        scored=sorted(((overlap(grams,text),key) for key,(row,text) in ridvan.items() if abs(int(row["Year"])-int(doc[:4]))<=1),reverse=True)
        duplicate=scored[0][1] if scored and scored[0][0]>=DUPLICATE else None
        if duplicate: matched.setdefault(duplicate,[]).append(doc)
        record=dict(id=f"uhj:{doc}",document=doc,document_id=reader.meta.get("document-id"),date=date,iso_date=f"{doc[:4]}-{doc[4:6]}-{doc[6:8]}",
                    to=to,summary=summary,author=UHJ,title=reader.title,
                    **provenance(log,url,dict(page_url=f"{UHJ_INDEX}{doc}/1")))
        if folded in seen_text:
            aliases.append(dict(record,duplicate_of=seen_text[folded],reason="Same text as another bahai.org message")); continue
        seen_text[folded]=record["id"]
        item=dict(record,riḍván=summary.startswith("Riḍván Message"),text=passage.text,words=word_count(passage.text),spans=passage.spans,
                  notes=len(set(passage.cited)),paragraphs=sum(1 for b in reader.blocks if clean_runs(b.runs)))
        if duplicate:
            # The official text is used in place of the BahaiPrayers.net copy, under that copy's id, so saved passages keep working.
            row=ridvan[duplicate][0]
            item.update(replaces=duplicate,shared=round(scored[0][0],3))
            aliases.append(dict(document=doc,id=record["id"],replaces=duplicate,shared=item["shared"],
                                reason=f"Same message as BahaiPrayers.net’s Riḍván {row['Year']} entry; the bahai.org text replaces it under the id {duplicate}"))
        items.append(item)
    twice={k:v for k,v in matched.items() if len(v)>1}
    if twice: raise ValueError(f"One Riḍván message matched by several bahai.org messages: {twice}")
    unmatched=[dict(id=k,year=row["Year"],title=row.get("Title")) for k,(row,_) in ridvan.items() if k not in matched]
    return dict(collection="uhj-messages",group=UHJ_GROUP,ridvan_group="Riḍván Messages",author=UHJ,copyright=COPYRIGHT,terms=TERMS,
                source=dict(name="Bahá’í Reference Library",url=index_url,**provenance(log,index_url),listed=len(rows)),
                parser_version=PARSER_VERSION,items=items,replacements=[a for a in aliases if "replaces" in a],duplicates=[a for a in aliases if "replaces" not in a],omitted=omitted,source_discrepancies=discrepancies,ridvan_not_on_bahai_org=unmatched)

HEADING=2.1   # rem; bahai.org sets titles and headings at this size or larger, body text at 1.9 and below
PART=2.6      # part and period titles (and the book's own title)
FRONT={"g","re","j"}  # the title page: book title, byline, subtitle

def label(block): return " ".join("".join(r[0] for r in clean_runs(block.runs)).split())

def split_work(reader):
    """A Shoghi Effendi work as passages, in reading order: front matter, then one passage per heading of the work
    (letter, message, chapter or section) and per entry of its own table of contents, whichever is finer.
    Returns (front matter lines, [dict(title, part, blocks)])."""
    blocks=[b for b in reader.blocks if clean_runs(b.runs)]
    heading=[b.size>=HEADING for b in blocks]
    order={b.anchor:i for i,b in enumerate(blocks) if b.anchor}
    cuts={}
    # A run of consecutive headings starts a passage.
    for i in range(len(blocks)):
        if heading[i] and (i==0 or not heading[i-1]): cuts[i]=None
    # So does each contents entry; one pointing just under a heading run starts at the run instead.
    for entry in reader.toc:
        i=order.get(entry["target"])
        if i is None: continue
        while i>0 and heading[i-1]: i-=1
        if i not in cuts or cuts[i] is None or entry["depth"]>=cuts[i]["depth"]: cuts[i]=entry
    # Where the contents entry opens on a date line above the heading (Citadel of Faith), the heading belongs to it.
    for i in sorted(cuts):
        if cuts[i] is None:
            before=max((j for j in cuts if j<i),default=None)
            if before is not None and cuts[before] is not None and all(not heading[k] and len(label(blocks[k]))<60 for k in range(before,i)): del cuts[i]
    starts=sorted(set(cuts)|{0})
    front=[]; pending=[]; pieces=[]; part=None
    for n,start in enumerate(starts):
        chunk=blocks[start:(starts[n+1] if n+1<len(starts) else len(blocks))]
        run=[b for b in chunk[:next((k for k,b in enumerate(chunk) if b.size<HEADING),len(chunk))]]
        if n==0:
            front+=[label(b) for b in chunk if FRONT.intersection(b.cls) or b.tag=="h1"]
            rest=[b for b in chunk if not (FRONT.intersection(b.cls) or b.tag=="h1")]
            pending+=rest  # an addressee or salutation before the first section opens that section
            continue
        body=chunk[len(run):]
        if any(b.size>=PART for b in run):
            part=": ".join(label(b) for b in run if b.size>=PART)
            if not body: continue  # a part title on its own: it names the passages that follow
        entry=cuts.get(start)
        title=entry["label"] if entry else " ".join(label(b) for b in run if b.size<PART) or part
        toc_part=" — ".join(p for p in (entry["parents"] if entry else []) if p!=title)
        this_part=toc_part or (part if title!=part else None)
        if this_part==title: this_part=None
        pieces.append(dict(title=title,part=this_part,blocks=pending+chunk)); pending=[]
    if pending: raise ValueError("Text before the first section with no section to open")
    return front,pieces

def build_shoghi(folder,log):
    index_url=SE_INDEX; index=(folder/"se/index.html").read_text()
    works=[]; items=[]
    for slug in work_slugs(index):
        page=(folder/f"se/{slug}.html").read_text(); url,edition=xhtml_link(page,slug)
        raw=(folder/f"se/{slug}.xhtml").read_bytes()
        if sha256(raw)!=log[url]["sha256"]: raise ValueError(f"{slug}.xhtml does not match fetch-log.json")
        reader=Reader(raw.decode("utf-8")); title=reader.title.strip()
        cited_all=[]; work_items=[]
        front,pieces=split_work(reader)
        for piece in pieces:
            passage=Passage()
            for block in piece["blocks"]: passage.add_block(block,reader.notes)
            cited_all+=passage.add_notes(reader.notes)
            anchor=next(b.anchor for b in piece["blocks"] if b.anchor)
            work_items.append(dict(id=f"se:{slug}:{anchor}",work=slug,anchor=anchor,title=piece["title"],part=piece["part"],
                                   position=len(work_items)+1,text=passage.text,words=word_count(passage.text),spans=passage.spans,notes=len(set(passage.cited)),
                                   paragraphs=len(piece["blocks"]),
                                   page_url=f"{SITE}/library/authoritative-texts/shoghi-effendi/{slug}/1#{anchor}"))
        if len({i["id"] for i in work_items})!=len(work_items): raise ValueError(f"{slug}: passage ids repeat")
        # Completeness: every paragraph of the file is in exactly one passage or on the title page.
        if len(front)+sum(len(p["blocks"]) for p in pieces)!=sum(1 for b in reader.blocks if clean_runs(b.runs)): raise ValueError(f"{slug}: paragraphs lost in splitting")
        missing=set(reader.notes)-set(cited_all)
        if missing: raise ValueError(f"{slug}: {len(missing)} notes are never cited: {sorted(missing)[:5]}")
        works.append(dict(work=slug,title=title,front=front,author=SHOGHI,passages=len(work_items),notes=len(reader.notes),
                          document_id=reader.meta.get("document-id"),edition=edition,
                          **provenance(log,url,dict(page_url=f"{SE_INDEX}{slug}/"))))
        items+= [dict(i,book=title) for i in work_items]
    return dict(collection="shoghi-effendi",author=SHOGHI,copyright=COPYRIGHT,terms=TERMS,
                source=dict(name="Bahá’í Reference Library",url=index_url,**provenance(log,index_url)),
                parser_version=PARSER_VERSION,works=works,items=items)

# ---------------------------------------------------------------- the app's other collections

MATCH_BLOCK=0.6    # share of an official paragraph's word sequences found in an app passage, to place it there
ATTACH_BLOCKS=3; ATTACH_CHARS=600  # what counts as a short official line the app lacks
MATCH_WORDS=0.9    # or: word-by-word similarity of the two texts (difflib ratio)
MATCH_PASSAGE=0.9  # share of an app passage's word sequences covered by the official paragraphs placed in it

def app_rows(key):
    """The app's own passages for a collection, from the bundled BahaiPrayers.net data only: [(id, text)] in order."""
    if str(ROOT) not in sys.path: sys.path.insert(0,str(ROOT))
    import reader  # noqa: E402 - the app's parser, so ids and texts are exactly what the app shows
    with tempfile.TemporaryDirectory() as empty:
        reader.CACHE=Path(empty)/"cache"; reader.LIBRARY=Path(empty)/"libraries"
        items=reader.load_bahaiprayers(1)
    if key=="epistle": return [(i["id"],i["text"]) for i in items if i["id"]=="prayers:13691"]
    if key=="prayers": return [(i["id"],i["text"]) for i in items if i["id"].startswith("prayers:") and i["id"]!="prayers:13691"]
    return [(i["id"],i["text"]) for i in items if i["id"].startswith(key+":")]

def block_text(block): return "".join(r[0] for r in clean_runs(block.runs))

def match_rows(rows,blocks,size=5):
    """Places the official paragraphs in the app's passages. Returns ({row id: [block index]}, report)."""
    grams=[shingles(text,size) for _,text in rows]
    folded=[fold(text) for _,text in rows]
    owner={}; last=0
    for b,block in enumerate(blocks):
        text=block_text(block)
        if len(words(text))<size: continue
        mine=shingles(text,size)
        scores=[(len(mine&g)/len(mine),r) for r,g in enumerate(grams) if mine&g]
        good=[(score,r) for score,r in scores if score>=MATCH_BLOCK]
        if not good: continue
        best=max(score for score,_ in good)
        # A paragraph found in several passages (a repeated invocation) goes to the nearest one ahead.
        near=[r for score,r in good if score>=best-0.05]
        ahead=[r for r in near if r>=last]
        r=min(ahead) if ahead else max(near)
        owner[b]=r; last=r
    spans={}
    for b,r in owner.items(): spans.setdefault(r,[]).append(b)
    taken=set(owner); result={}; report=dict(unmatched=[],split=[],partial=[],extra=[])
    for r,(ident,text) in enumerate(rows):
        if r not in spans: report["unmatched"].append(ident); continue
        first,last_=min(spans[r]),max(spans[r])
        inside=range(first,last_+1)
        if any(b in owner and owner[b]!=r for b in inside): report["split"].append(ident); continue
        # Short lines next to the passage (a heading, "He is God!", "O Son of Spirit!") belong to it when its text has them.
        fits=lambda b: b not in taken and fold(block_text(blocks[b])) and fold(block_text(blocks[b])) in folded[r]
        while first>0 and fits(first-1): first-=1
        while last_+1<len(blocks) and fits(last_+1): last_+=1
        chosen=list(range(first,last_+1)); taken.update(chosen)
        joined="\n\n".join(block_text(blocks[b]) for b in chosen); official=shingles(joined,size)
        covered=overlap_of(grams[r],official)
        # And the other way: the official paragraphs hold nothing much the app's passage lacks.
        within=overlap_of(official,grams[r])
        if min(covered,within)<MATCH_PASSAGE:
            # Short passages lose many word sequences to one changed word ("lingers", "lingereth"); compare word by word too.
            similar=difflib.SequenceMatcher(None,words(rows[r][1]),words(joined),autojunk=False).ratio()
            if similar<MATCH_WORDS:
                report["partial" if covered<within else "extra"].append((ident,round(min(covered,within),3),round(similar,3))); continue
        result[ident]=chosen
    # Short official lines the app's copy lacks (a part's opening invocation, a line introducing the next passage) open the
    # passage that follows them. Headings are structure the contents list already shows; long stretches are left out and reported.
    starts=sorted((chosen[0],ident) for ident,chosen in result.items())
    used={b for chosen in result.values() for b in chosen}; report["added"]=[]
    for first,ident in starts:
        b=first-1; lead=[]
        while b>=0 and b not in used and blocks[b].size<HEADING and block_text(blocks[b]) and not FRONT.intersection(blocks[b].cls):
            lead.insert(0,b); b-=1
        while lead and blocks[lead[0]].tag=="hr": lead.pop(0)  # a separator does not open a passage
        if lead and len(lead)<=ATTACH_BLOCKS and all(len(block_text(blocks[x]))<=ATTACH_CHARS for x in lead) and (b<0 or b in used or blocks[b].size>=HEADING or blocks[b].tag=="hr" or not block_text(blocks[b])):
            result[ident]=lead+result[ident]; used.update(lead); report["added"].append((ident,[block_text(blocks[x])[:60] for x in lead]))
    used={b for chosen in result.values() for b in chosen}
    report["unused"]=[(b,block_text(blocks[b])[:100]) for b in range(len(blocks)) if b not in used]
    return result,report

def overlap_of(target,found):
    """Share of target's word sequences present in found."""
    return len(target&found)/len(target) if target else 0.0

def build_books(folder,log):
    books=[]; replacements={}
    for key,(category,slug) in BOOK_SOURCES.items():
        if key not in BOOKS_DONE: continue
        page=(folder/f"books/{slug}.html").read_text(); url,edition=xhtml_link(page,slug,category)
        raw=(folder/f"books/{slug}.xhtml").read_bytes()
        if sha256(raw)!=log[url]["sha256"]: raise ValueError(f"{slug}.xhtml does not match fetch-log.json")
        reader=Reader(raw.decode("utf-8")); blocks=[b for b in reader.blocks if clean_runs(b.runs)]
        rows=app_rows(key); matched,report=match_rows(rows,blocks)
        lead={ident:len(lines) for ident,lines in report["added"]}
        for ident,chosen in matched.items():
            passage=Passage()
            for b in chosen: passage.add_block(blocks[b],reader.notes)
            passage.add_notes(reader.notes)
            # The opening the contents list shows: from the app's own first paragraph, without bahai.org's margin numbers.
            first=Passage(); first.add_block(blocks[chosen[lead.get(ident,0)]],{**reader.notes})
            numbers=[(a,b) for a,b,k in first.spans if k=="num"]
            opening="".join(c for i,c in enumerate(first.text) if not any(a<=i<b for a,b in numbers))
            replacements[ident]=dict(book=key,text=passage.text,words=word_count(passage.text),spans=passage.spans,notes=len(set(passage.cited)),
                                     opening=" ".join(opening.split())[:120],anchor=next((blocks[b].anchor for b in chosen if blocks[b].anchor),None))
        books.append(dict(key=key,slug=slug,title=reader.title.strip(),author=reader.meta.get("author"),document_id=reader.meta.get("document-id"),edition=edition,
                          rows=len(rows),replaced=len(matched),kept={k:v for k,v in report.items()},
                          **provenance(log,url,dict(page_url=f"{SITE}/library/authoritative-texts/{category}/{slug}/"))))
    return dict(collection="bahai-org-books",copyright=COPYRIGHT,terms=TERMS,parser_version=PARSER_VERSION,books=books,replacements=replacements)

# Collections switched to the official text so far, one at a time.
BOOKS_DONE=("hidden",)

OUTPUTS={"uhj-messages.json":build_messages,"shoghi-effendi.json":build_shoghi,"bahai-org-books.json":build_books}

def render(data): return json.dumps(data,ensure_ascii=False,indent=0,separators=(",",":"))+"\n"

def build(folder,write=True):
    folder=Path(folder); log=json.loads((folder/"fetch-log.json").read_text()); changed=[]
    for name,builder in OUTPUTS.items():
        text=render(builder(folder,log)); target=ROOT/"data"/name
        if not target.exists() or target.read_text()!=text:
            changed.append(name)
            if write: target.write_text(text)
    return changed

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("command",choices=("fetch","build","check"))
    parser.add_argument("sources",help="folder for the raw downloads")
    parser.add_argument("--refresh",action="store_true",help="download again even when a copy exists")
    parser.add_argument("--delay",type=float,default=1.0,help="seconds between requests (default 1)")
    parser.add_argument("--only",choices=("uhj","se","books"))
    args=parser.parse_args(argv)
    if args.command=="fetch": return 0 if fetch(args.sources,args.refresh,args.delay,args.only) else 1
    changed=build(args.sources,write=args.command=="build")
    if args.command=="check":
        print("data/ matches the sources" if not changed else "differs: "+", ".join(changed)); return 1 if changed else 0
    print("updated: "+", ".join(changed) if changed else "no changes"); return 0

if __name__=="__main__": sys.exit(main())

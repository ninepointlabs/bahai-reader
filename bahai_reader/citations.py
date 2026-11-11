"""Citations and copied passages."""

from .config import BOOK_AUTHORS, HOLY_DAYS, PRAYER_AUTHORS, SECTION_NAMES
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
    # Prayers carry only an author; the category is the nearest thing to a reference (an official prayer names its book instead).
    if item["section"]=="prayers" and item["tags"] and not item.get("official_book"):
        notice=". "+BAHAI_ORG_NOTICE; official=cite.endswith(notice)
        cite=", ".join(filter(None,(cite.removesuffix(notice),"Prayers",item["tags"][0])))+(notice if official else "")
    return f"{text}\n\n— {cite}" if cite else text

BAHAI_ORG_NOTICE="Copyright © Bahá’í International Community, bahai.org"

"""The Badí‘ calendar, without GTK, so that tests and the background mode can use it alone.

Dates come from two sources of the Universal House of Justice:
- the message of 10 July 2014 fixes the Holy Days within the Badí‘ calendar;
- the table "Badí‘ dates 172 to 221 B.E." (data/badi-dates.json) gives each year's Naw-Rúz, Twin Holy Birthdays and
  length of Ayyám-i-Há, which depend on astronomical tables for Ṭihrán and are never computed here.
Outside the table the functions return None or nothing rather than a guess.
"""
import datetime
import functools
import json
from pathlib import Path
from typing import NamedTuple, Optional

ROOT=Path(__file__).resolve().parent
TABLE=ROOT/"data"/"badi-dates.json"
UNPUBLISHED="Dates for this year have not been published yet."

# Names and meanings as in table B. Ayyám-i-Há falls between the eighteenth and nineteenth months.
MONTHS=(("Bahá","Splendour"),("Jalál","Glory"),("Jamál","Beauty"),("‘Aẓamat","Grandeur"),("Núr","Light"),("Raḥmat","Mercy"),
        ("Kalimát","Words"),("Kamál","Perfection"),("Asmá’","Names"),("‘Izzat","Might"),("Mashíyyat","Will"),("‘Ilm","Knowledge"),
        ("Qudrat","Power"),("Qawl","Speech"),("Masá’il","Questions"),("Sharaf","Honour"),("Sulṭán","Sovereignty"),("Mulk","Dominion"),("‘Alá’","Loftiness"))
AYYAM_I_HA="Ayyám-i-Há"
INTERCALARY=0  # month number used for Ayyám-i-Há
FAST_MONTH=19
MONTH_DAYS=19
GREGORIAN_MONTHS=("January","February","March","April","May","June","July","August","September","October","November","December")

def month_number(name):
    return next(i for i,(month,_) in enumerate(MONTHS,1) if month==name)

class BadiDate(NamedTuple):
    year: int
    month: int  # 1-19, or INTERCALARY for Ayyám-i-Há
    day: int
    @property
    def month_name(self): return AYYAM_I_HA if self.month==INTERCALARY else MONTHS[self.month-1][0]
    @property
    def meaning(self): return None if self.month==INTERCALARY else MONTHS[self.month-1][1]
    def __str__(self): return f"{self.day} {self.month_name} {self.year} B.E."

class Event(NamedTuple):
    kind: str  # "holy" or "feast"
    name: str
    badi: BadiDate
    date: datetime.date  # the Gregorian day it falls on; it begins at sunset the evening before
    work_suspended: bool = False
    readings: Optional[str] = None  # HolyDay tag in Days of Remembrance
    prayers: Optional[str] = None  # category in the prayers feed
    meaning: Optional[str] = None
    @property
    def begins(self): return self.date-datetime.timedelta(1)

# Message of 10 July 2014: (name, month, day, work suspended, Days of Remembrance tag, prayer category).
# The nine Holy Days on which work is suspended are Naw-Rúz, the first, ninth and twelfth days of Riḍván, the Declaration
# of the Báb, the Ascension of Bahá’u’lláh, the Martyrdom of the Báb and the Twin Holy Birthdays (added per year below).
FIXED_HOLY_DAYS=(
    ("Naw-Rúz",1,1,True,"NAWRUZ","Naw-Rúz"),
    ("First day of Riḍván",2,13,True,"RIDVAN",None),
    ("Ninth day of Riḍván",3,2,True,"RIDVAN",None),
    ("Twelfth day of Riḍván",3,5,True,"RIDVAN",None),
    ("Declaration of the Báb",4,8,True,"DECLARATIONBAB",None),
    ("Ascension of Bahá’u’lláh",4,13,True,"ASCENSIONBAHAULLAH",None),
    ("Martyrdom of the Báb",6,17,True,"MARTYRDOMBAB",None),
    ("Day of the Covenant",14,4,False,None,None),
    ("Ascension of ‘Abdu’l‑Bahá",14,6,False,None,None),
)

@functools.lru_cache(maxsize=None)
def table():
    """{year: row}. A missing or damaged file leaves the calendar empty; it never stops the app."""
    try: rows=json.loads(TABLE.read_text())["years"]
    except (OSError,ValueError,KeyError,TypeError): return {}
    return {row["year"]:row for row in rows} if isinstance(rows,list) else {}

def naw_ruz(year):
    row=table().get(year)
    return datetime.date.fromisoformat(row["naw_ruz"]) if row else None

def to_gregorian(badi):
    """The Gregorian day a Badí‘ date falls on, or None outside the table."""
    row=table().get(badi.year)
    if not row: return None
    start=naw_ruz(badi.year)
    if badi.month==INTERCALARY: days=18*MONTH_DAYS+badi.day-1
    elif badi.month==FAST_MONTH: days=18*MONTH_DAYS+row["ayyam_i_ha_days"]+badi.day-1
    else: days=(badi.month-1)*MONTH_DAYS+badi.day-1
    return start+datetime.timedelta(days)

def year_length(year):
    row=table().get(year)
    return 19*MONTH_DAYS+row["ayyam_i_ha_days"] if row else None

def from_gregorian(date):
    """The Badí‘ date falling on a Gregorian day (it began at sunset the evening before), or None outside the table."""
    rows=table()
    if not rows: return None
    year=date.year-1843 if (date.month,date.day)>=(3,22) else date.year-1844
    # 20 and 21 March can fall on either side of Naw-Rúz.
    if (date.month,date.day) in ((3,20),(3,21)) and year+1 in rows and date>=naw_ruz(year+1): year+=1
    if year not in rows or date<naw_ruz(year): return None
    days=(date-naw_ruz(year)).days
    if days>=year_length(year): return None
    if days<18*MONTH_DAYS: return BadiDate(year,days//MONTH_DAYS+1,days%MONTH_DAYS+1)
    days-=18*MONTH_DAYS; extra=rows[year]["ayyam_i_ha_days"]
    if days<extra: return BadiDate(year,INTERCALARY,days+1)
    return BadiDate(year,FAST_MONTH,days-extra+1)

def holy_days(year):
    """The eleven Holy Days of a year in date order; empty outside the table."""
    row=table().get(year)
    if not row: return []
    def event(name,month,day,suspended,readings=None,prayers=None):
        badi=BadiDate(year,month,day)
        return Event("holy",name,badi,to_gregorian(badi),suspended,readings,prayers)
    twin=[event("Birth of the Báb",month_number(row["birth_bab"]["month"]),row["birth_bab"]["day"],True,"BIRTHBAB"),
          event("Birth of Bahá’u’lláh",month_number(row["birth_bahaullah"]["month"]),row["birth_bahaullah"]["day"],True,"BIRTHBAHAULLAH")]
    return sorted([event(*fixed) for fixed in FIXED_HOLY_DAYS]+twin,key=lambda e:e.date)

def feasts(year):
    """The nineteen Nineteen Day Feasts, on the first day of each month; empty outside the table."""
    if year not in table(): return []
    result=[]
    for month,(name,meaning) in enumerate(MONTHS,1):
        badi=BadiDate(year,month,1)
        result.append(Event("feast",f"Feast of {name}",badi,to_gregorian(badi),meaning=meaning,prayers="The Fast" if month==FAST_MONTH else None))
    return result

def events(year):
    return sorted(holy_days(year)+feasts(year),key=lambda e:(e.date,e.kind!="holy"))

def upcoming(date,days=365):
    """Holy Days and Feasts falling from this Gregorian day on, within the given number of days, as far as dates are published."""
    first=from_gregorian(date)
    if not first: return []
    last=date+datetime.timedelta(days)
    found=[]
    for year in range(first.year,first.year+3):
        found+=[e for e in events(year) if date<=e.date<=last]
    return found

def next_feast(date):
    return next((e for e in upcoming(date,40) if e.kind=="feast"),None)

def next_holy_day(date):
    return next((e for e in upcoming(date) if e.kind=="holy"),None)

class Period(NamedTuple):
    name: str
    meaning: Optional[str]
    badi: BadiDate
    first: datetime.date
    last: datetime.date

def year_months(year):
    """The nineteen months and Ayyám-i-Há, in order, with their Gregorian dates; empty outside the table."""
    row=table().get(year)
    if not row: return []
    periods=[]
    def add(month,length):
        badi=BadiDate(year,month,1); first=to_gregorian(badi)
        periods.append(Period(badi.month_name,badi.meaning,badi,first,first+datetime.timedelta(length-1)))
    for month in range(1,19): add(month,MONTH_DAYS)
    add(INTERCALARY,row["ayyam_i_ha_days"]); add(FAST_MONTH,MONTH_DAYS)
    return periods

def fast_days(year):
    """(first, last) Gregorian day of the Fast, the month of ‘Alá’, or None outside the table."""
    first=to_gregorian(BadiDate(year,FAST_MONTH,1))
    return (first,first+datetime.timedelta(MONTH_DAYS-1)) if first else None

def fast_day(date):
    """Which day of the Fast a Gregorian day is, 1-19, or None. Fasting runs from sunrise to sunset on that Gregorian day."""
    badi=from_gregorian(date)
    return badi.day if badi and badi.month==FAST_MONTH else None

def next_fast(date):
    """The first fasting day of the next Fast from this Gregorian day on, or None if that year's dates are not published."""
    badi=from_gregorian(date)
    if not badi: return None
    span=fast_days(badi.year)
    return span[0] if date<=span[0] else None

def gregorian_text(date,year=False):
    return f"{date.day} {GREGORIAN_MONTHS[date.month-1]}"+(f" {date.year}" if year else "")

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
import math
from pathlib import Path
from typing import NamedTuple, Optional
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError, available_timezones

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

# Sun times: the NOAA solar calculation (https://gml.noaa.gov/grad/solcalc/calcdetails.html), which is public domain and follows
# Meeus's Astronomical Algorithms, using the standard altitude of -0.833° for sunrise and sunset.
SUN_ALTITUDE=90.833

def _century(moment):
    days=(moment-datetime.datetime(2000,1,1,12,tzinfo=datetime.timezone.utc)).total_seconds()/86400
    return days/36525

def _sun(t):
    """(equation of time in minutes, declination in degrees) at t Julian centuries from J2000."""
    mean_long=math.radians((280.46646+t*(36000.76983+t*0.0003032))%360)
    anomaly=math.radians(357.52911+t*(35999.05029-0.0001537*t))
    eccentricity=0.016708634-t*(0.000042037+0.0000001267*t)
    centre=math.sin(anomaly)*(1.914602-t*(0.004817+0.000014*t))+math.sin(2*anomaly)*(0.019993-0.000101*t)+math.sin(3*anomaly)*0.000289
    omega=math.radians(125.04-1934.136*t)
    apparent=math.radians(math.degrees(mean_long)+centre-0.00569-0.00478*math.sin(omega))
    mean_obliquity=23+(26+(21.448-t*(46.815+t*(0.00059-t*0.001813)))/60)/60
    obliquity=math.radians(mean_obliquity+0.00256*math.cos(omega))
    declination=math.degrees(math.asin(math.sin(obliquity)*math.sin(apparent)))
    y=math.tan(obliquity/2)**2
    equation=(y*math.sin(2*mean_long)-2*eccentricity*math.sin(anomaly)+4*eccentricity*y*math.sin(anomaly)*math.cos(2*mean_long)
              -0.5*y*y*math.sin(4*mean_long)-1.25*eccentricity*eccentricity*math.sin(2*anomaly))
    return math.degrees(equation)*4,declination

def _hour_angle(latitude,declination):
    """Degrees either side of solar noon, or None with the reason: the sun stays up ("day") or down ("night")."""
    lat,dec=math.radians(latitude),math.radians(declination)
    value=math.cos(math.radians(SUN_ALTITUDE))/(math.cos(lat)*math.cos(dec))-math.tan(lat)*math.tan(dec)
    if value<-1: return None,"day"
    if value>1: return None,"night"
    return math.degrees(math.acos(value)),None

class SunTimes(NamedTuple):
    date: datetime.date
    sunrise: Optional[datetime.datetime]
    noon: datetime.datetime
    sunset: Optional[datetime.datetime]
    polar: Optional[str]  # "day" when the sun does not set, "night" when it does not rise

def sun_times(date,latitude,longitude,zone):
    """Sunrise, solar noon and sunset of the solar day whose noon falls on this local date, in that zone.
    On a day near the polar circles the sunset can fall after midnight, on the next calendar date."""
    if isinstance(zone,str): zone=ZoneInfo(zone)
    latitude=max(-89.99,min(89.99,latitude))
    utc=datetime.timezone.utc
    base=datetime.datetime(date.year,date.month,date.day,tzinfo=utc)
    def noon_of(day):
        moment=day+datetime.timedelta(minutes=720-4*longitude)
        for _ in range(2):
            moment=day+datetime.timedelta(minutes=720-4*longitude-_sun(_century(moment))[0])
        return moment
    noon=noon_of(base)
    # Where the zone is far from the longitude, the UTC date can differ from the local date (Kiritimati is UTC+14 at 157° W).
    for _ in range(2):
        local=noon.astimezone(zone).date()
        if local==date: break
        base+=datetime.timedelta(days=1 if local<date else -1); noon=noon_of(base)
    def event(rise):
        moment=noon; reason=None
        for _ in range(3):
            equation,declination=_sun(_century(moment))
            angle,reason=_hour_angle(latitude,declination)
            if angle is None: return None,reason
            moment=base+datetime.timedelta(minutes=720-4*(longitude+(angle if rise else -angle))-equation)
        return moment.astimezone(zone),None
    sunrise,why_rise=event(True); sunset,why_set=event(False)
    polar=why_set or why_rise
    return SunTimes(date,sunrise,noon.astimezone(zone),sunset,polar)

def valid_zone(name):
    """A time zone this computer knows. With no time zone data at all, keep what was saved instead of discarding it."""
    if not isinstance(name,str) or not name: return False
    try: ZoneInfo(name); return True
    except (ZoneInfoNotFoundError,ValueError,OSError): return not available_timezones()

def clean_place(value):
    """{"label","lat","lon","tz"} with latitude and longitude rounded to 2 decimals, or None if unusable."""
    if not isinstance(value,dict): return None
    lat,lon=value.get("lat"),value.get("lon")
    for number in (lat,lon):
        if not isinstance(number,(int,float)) or isinstance(number,bool) or not math.isfinite(number): return None
    if not (-90<=lat<=90 and -180<=lon<=180) or not valid_zone(value.get("tz")): return None
    lat,lon=round(float(lat),2),round(float(lon),2)
    label=" ".join(value["label"].split()) if isinstance(value.get("label"),str) else ""
    return dict(label=label or f"{lat}, {lon}",lat=lat,lon=lon,tz=value["tz"])

def place_sun(place,date):
    """Sun times at a saved place, or None without one, or when this computer lacks its time zone."""
    if not place: return None
    try: return sun_times(date,place["lat"],place["lon"],place["tz"])
    except (ZoneInfoNotFoundError,ValueError,OSError): return None

def sun_summary(sun,clock):
    """One line for the sun times; clock formats a datetime in the user's locale."""
    parts=[]
    if sun.sunrise: parts.append("sunrise "+clock(sun.sunrise))
    parts.append("noon "+clock(sun.noon))
    if sun.sunset: parts.append("sunset "+clock(sun.sunset))
    text=", ".join(parts); text=text[0].upper()+text[1:]
    if sun.polar=="day": text+=". The sun does not set today."
    if sun.polar=="night": text+=". The sun does not rise today."
    return text

def local_now(place=None,moment=None):
    """The time now (or at an aware moment) at a saved place, or in this computer's time zone without one.
    time.tzset() in the caller picks up a change of the system time zone."""
    moment=moment or datetime.datetime.now(datetime.timezone.utc)
    if place:
        try: return moment.astimezone(ZoneInfo(place["tz"]))
        except (ZoneInfoNotFoundError,ValueError,OSError): pass
    return moment.astimezone()

def observed_date(moment,place=None):
    """The Gregorian day whose Badí‘ date is current. With a place, the next Badí‘ day begins at local sunset; where the sun
    does not set that day, and without a place, the date follows the calendar day."""
    day=moment.date()
    if not place: return day
    before=place_sun(place,day-datetime.timedelta(1))
    # A sunset after midnight still belongs to the solar day before.
    if before and before.sunset and moment<before.sunset: return day-datetime.timedelta(1)
    sun=place_sun(place,day)
    if sun and sun.sunset and moment>=sun.sunset: return day+datetime.timedelta(1)
    return day

def ayyam_i_ha(year):
    """Ayyám-i-Há of a year as a Period, or None outside the table."""
    return next((p for p in year_months(year) if p.badi.month==INTERCALARY),None)

def next_ayyam_i_ha(date):
    """Ayyám-i-Há that is under way or still to come in this Badí‘ year, or None."""
    badi=from_gregorian(date)
    period=ayyam_i_ha(badi.year) if badi else None
    return period if period and date<=period.last else None

def event_summary(event,today):
    """When an event begins, as a sentence."""
    if event.date==today: return "Today."
    if event.begins==today: return "Begins at sunset today."
    return f"Begins at sunset on {gregorian_text(event.begins)}."

class Counter:
    """The count of Alláh-u-Abhá, kept only while the app runs; it is not a record. It stops at the target."""
    DEFAULT=95
    PRESETS=(95,19,9)
    LIMIT=9999
    def __init__(self,target=DEFAULT):
        self.count=0; self.target=self.valid_target(target) or self.DEFAULT
    @classmethod
    def valid_target(cls,value):
        """A whole number from 1 to the limit, or None."""
        if isinstance(value,bool): return None
        if isinstance(value,str):
            try: value=int(value.strip())
            except ValueError: return None
        return value if isinstance(value,int) and 1<=value<=cls.LIMIT else None
    @property
    def done(self): return self.count>=self.target
    def add(self):
        if self.done: return False
        self.count+=1; return True
    def undo(self):
        if not self.count: return False
        self.count-=1; return True
    def reset(self): self.count=0
    def set_target(self,value):
        target=self.valid_target(value)
        if target is None: return False
        self.target=target; self.count=min(self.count,target); return True
    @property
    def milestone(self):
        """Screen readers are told only at every nineteenth and at the target, so counting isn't drowned out."""
        return self.count>0 and (self.done or self.count%19==0)
    def __str__(self): return f"{self.count} of {self.target}"

# Obligatory prayer times, all from texts the app bundles:
# - Short: "To be recited once in twenty-four hours, at noon" (the prayer's own heading). Note 5 to the Kitáb-i-Aqdas: the definition of
#   "noon" as the period "from noon till sunset" applies to the short prayer as well as the medium one.
# - Medium: "To be recited daily, in the morning, at noon, and in the evening" (its heading). Q&A 83: "These are sunrise, noon and sunset.
#   The allowable times for Obligatory Prayers are from morning till noon, from noon till sunset, and from sunset till two hours thereafter."
#   Note 5 adds that, as ‘Abdu’l-Bahá stated, the morning prayer "may be said as early as dawn". The window here opens at sunrise, and the card
#   quotes the note. No dawn time is computed: the texts do not define one.
# - Long: "To be recited once in twenty-four hours" (its heading). Q&A 82: "at whatever time one findeth oneself in a state of humbleness and
#   longing adoration"; "Once in twenty-four hours is sufficient". It has no window. No text says which twenty-four hours, so it has no
#   "Said today" state or reminder until that is decided (see LONG_PRAYER_TRACKED).
# - In regions where days and nights grow long, ¶10 and Q&A 64 say to gauge times by clocks, without giving hours, so no window is shown there.
PRAYERS={"short":"Short Obligatory Prayer","medium":"Medium Obligatory Prayer","long":"Long Obligatory Prayer"}
LONG_PRAYER_TRACKED=False
EVENING_HOURS=2
# Without a location, the clock stands in for the sun. The card says so.
CLOCK_SUNRISE,CLOCK_NOON,CLOCK_SUNSET=6,12,18

class Window(NamedTuple):
    prayer: str
    part: str  # "noon", or "morning", "noon" or "evening" for the medium prayer
    date: datetime.date  # the solar day it belongs to
    opens: datetime.datetime
    closes: datetime.datetime
    @property
    def key(self): return f"{self.date.isoformat()}:{self.prayer}:{self.part}"
    def is_open(self,moment): return self.opens.timestamp()<=moment.timestamp()<self.closes.timestamp()
    def is_past(self,moment): return moment.timestamp()>=self.closes.timestamp()

def _clock_time(date,hour):
    """A clock time today on this computer, with its own daylight saving offset."""
    return datetime.datetime(date.year,date.month,date.day,hour).astimezone()

def prayer_windows(prayer,date,place=None):
    """The windows of a prayer on a day. Empty for the long prayer, and where the sun does not rise or set that day."""
    if prayer not in ("short","medium"): return []
    if place:
        sun=place_sun(place,date)
        if not sun or not sun.sunrise or not sun.sunset: return []
        sunrise,noon,sunset=sun.sunrise,sun.noon,sun.sunset
    else:
        sunrise,noon,sunset=_clock_time(date,CLOCK_SUNRISE),_clock_time(date,CLOCK_NOON),_clock_time(date,CLOCK_SUNSET)
    afternoon=Window(prayer,"noon",date,noon,sunset)
    if prayer=="short": return [afternoon]
    # Two hours by elapsed time, across a change of the clock if there is one.
    evening_end=(sunset.astimezone(datetime.timezone.utc)+datetime.timedelta(hours=EVENING_HOURS)).astimezone(sunset.tzinfo)
    return [Window(prayer,"morning",date,sunrise,noon),afternoon,Window(prayer,"evening",date,sunset,evening_end)]

def prayer_day(prayer,moment,place=None):
    """The day whose windows apply: today, or yesterday while its last window is still open after midnight."""
    today=moment.date(); yesterday=today-datetime.timedelta(1)
    return yesterday if any(w.is_open(moment) for w in prayer_windows(prayer,yesterday,place)) else today

def current_window(prayer,moment,place=None):
    """The window open now, or else the next one to open; None when there are none (the long prayer, polar days)."""
    today=moment.date()
    for day in (today-datetime.timedelta(1),today,today+datetime.timedelta(1)):
        for window in prayer_windows(prayer,day,place):
            if not window.is_past(moment): return window
    return None

def is_tracked(prayer):
    return prayer in ("short","medium") or (prayer=="long" and LONG_PRAYER_TRACKED)

PART_NAMES={"morning":"Morning","noon":"Noon","evening":"Evening"}
SAID_LABELS={"morning":"Said this morning","noon":"Said at noon","evening":"Said this evening"}

def said_label(window):
    return "Said today" if window.prayer=="short" else SAID_LABELS[window.part]

def window_line(window,moment,clock):
    """Whether a window is open, and when it opens or closes. It never says anything was missed."""
    span=f"{clock(window.opens)} to {clock(window.closes)}"
    if window.is_open(moment): return f"Open now, until {clock(window.closes)}"
    if window.is_past(moment): return f"Its time has ended ({span})"
    return f"Opens at {clock(window.opens)}, until {clock(window.closes)}"

def prune_said(said,today,keep_history=True):
    """Marks worth keeping: all of them, or with the history off only what the current day's state needs."""
    if keep_history: return said
    oldest=(today-datetime.timedelta(1)).isoformat()
    return [key for key in said if key[:10]>=oldest]

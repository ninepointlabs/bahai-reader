"""Obligatory prayer windows come from the bundled texts, and follow the sun, the clock change and the absence of a location (no display needed)."""
import datetime
import json
import os
import time
import unittest
from datetime import date
from zoneinfo import ZoneInfo
import badi

HAIFA={"label":"Haifa","lat":32.81,"lon":35.0,"tz":"Asia/Jerusalem"}
TYLER={"label":"Tyler","lat":32.35,"lon":-95.3,"tz":"America/Chicago"}
TROMSO={"label":"Tromsø","lat":69.65,"lon":18.96,"tz":"Europe/Oslo"}
fmt=lambda moment:moment.strftime("%H:%M")

class SourceTests(unittest.TestCase):
    """The texts cited in badi.py say what the code relies on."""
    @classmethod
    def setUpClass(cls):
        data=json.loads((badi.ROOT/"data"/"aqdas.json").read_text())
        cls.qa={r["Number"]:r["Text"] for r in data["QAs"]}; cls.notes={r["Number"]:r["Text"] for r in data["Notes"]}
        cls.prayers={t["Name"]:r["Text"] for r in json.loads((badi.ROOT/"data"/"prayers.json").read_text())["Prayers"] for t in r.get("Tags",[])}
    def test_question_and_answer_83_gives_the_windows(self):
        self.assertIn("These are sunrise, noon and sunset",self.qa[83])
        self.assertIn("from morning till noon, from noon till sunset, and from sunset till two hours thereafter",self.qa[83])
    def test_note_5_extends_the_noon_period_to_the_short_prayer_and_the_morning_to_dawn(self):
        self.assertIn("as early as dawn",self.notes[5]); self.assertIn("applies to the recitation of the short Obligatory Prayer",self.notes[5])
    def test_question_and_answer_82_and_the_headings(self):
        self.assertIn("Once in twenty-four hours is sufficient",self.qa[82])
        self.assertIn("To be recited once in twenty-four hours, at noon",self.prayers["Short Obligatory Prayer"])
        self.assertIn("To be recited daily, in the morning, at noon, and in the evening",self.prayers["Medium Obligatory Prayer"])
        self.assertIn("To be recited once in twenty-four hours",self.prayers["Long Obligatory Prayer"])

class WindowTests(unittest.TestCase):
    def setUp(self):
        self.sun=badi.place_sun(HAIFA,date(2026,6,21))
    def at(self,*args,zone="Asia/Jerusalem"): return datetime.datetime(*args,tzinfo=ZoneInfo(zone))

    def test_short_runs_from_noon_till_sunset(self):
        [window]=badi.prayer_windows("short",date(2026,6,21),HAIFA)
        self.assertEqual((window.part,window.opens,window.closes),("noon",self.sun.noon,self.sun.sunset))
        self.assertFalse(window.is_open(self.sun.noon-datetime.timedelta(minutes=1))); self.assertTrue(window.is_open(self.sun.noon))
        self.assertTrue(window.is_open(self.sun.sunset-datetime.timedelta(minutes=1))); self.assertFalse(window.is_open(self.sun.sunset)); self.assertTrue(window.is_past(self.sun.sunset))

    def test_medium_has_morning_noon_and_two_hours_after_sunset(self):
        morning,noon,evening=badi.prayer_windows("medium",date(2026,6,21),HAIFA)
        self.assertEqual((morning.part,morning.opens,morning.closes),("morning",self.sun.sunrise,self.sun.noon))
        self.assertEqual((noon.part,noon.opens,noon.closes),("noon",self.sun.noon,self.sun.sunset))
        self.assertEqual((evening.part,evening.opens),("evening",self.sun.sunset))
        self.assertEqual(evening.closes.timestamp()-evening.opens.timestamp(),7200)

    def test_long_has_no_window_and_is_not_tracked_until_its_day_is_settled(self):
        self.assertEqual(badi.prayer_windows("long",date(2026,6,21),HAIFA),[]); self.assertIsNone(badi.current_window("long",self.at(2026,6,21,10),HAIFA))
        self.assertFalse(badi.is_tracked("long")); self.assertTrue(badi.is_tracked("short") and badi.is_tracked("medium")); self.assertFalse(badi.is_tracked("none"))

    def test_each_window_has_its_own_key_for_its_solar_day(self):
        keys=[w.key for w in badi.prayer_windows("medium",date(2026,6,21),HAIFA)]
        self.assertEqual(keys,["2026-06-21:medium:morning","2026-06-21:medium:noon","2026-06-21:medium:evening"])

    def test_current_window_moves_through_the_day(self):
        part=lambda *moment:badi.current_window("medium",self.at(*moment),HAIFA)
        self.assertEqual(part(2026,6,21,3,0).part,"morning")  # before sunrise, the next to open
        self.assertEqual(part(2026,6,21,9,0).part,"morning"); self.assertEqual(part(2026,6,21,15,0).part,"noon"); self.assertEqual(part(2026,6,21,20,30).part,"evening")
        late=part(2026,6,21,23,0); self.assertEqual((late.part,late.date),("morning",date(2026,6,22)))

    def test_evening_crossing_midnight_stays_with_the_day_it_began(self):
        # Tromsø, late spring: sunset is close to midnight, so two hours after it falls on the next date.
        day=date(2026,5,10); evening=badi.prayer_windows("medium",day,TROMSO)[2]
        self.assertGreater(evening.closes.date(),day)
        inside=evening.closes-datetime.timedelta(minutes=5)
        self.assertEqual(badi.prayer_day("medium",inside,TROMSO),day); self.assertEqual(badi.current_window("medium",inside,TROMSO).key,evening.key)

    def test_the_clock_change_day(self):
        # US clocks go forward at 02:00 on 8 March 2026: the window keeps following the sun and its length in real time.
        day=date(2026,3,8); morning,noon,evening=badi.prayer_windows("medium",day,TYLER); sun=badi.place_sun(TYLER,day)
        self.assertEqual(noon.closes,sun.sunset); self.assertEqual(sun.sunrise.utcoffset(),datetime.timedelta(hours=-5))
        self.assertEqual(evening.closes.timestamp()-evening.opens.timestamp(),7200)
        before=badi.place_sun(TYLER,date(2026,3,7))
        self.assertEqual(before.noon.hour,12); self.assertEqual(sun.noon.hour,13)
        # Clocks go back on 1 November: noon by the sun is an hour earlier on the clock.
        self.assertEqual(badi.place_sun(TYLER,date(2026,10,31)).noon.hour,13); self.assertEqual(badi.place_sun(TYLER,date(2026,11,1)).noon.hour,12)

    def test_polar_day_and_night_have_no_windows(self):
        self.assertEqual(badi.prayer_windows("short",date(2026,6,21),TROMSO),[]); self.assertEqual(badi.prayer_windows("medium",date(2026,12,21),TROMSO),[])

    def test_lines_never_say_anything_was_missed(self):
        [window]=badi.prayer_windows("short",date(2026,6,21),HAIFA)
        for moment in (window.opens-datetime.timedelta(hours=1),window.opens,window.closes+datetime.timedelta(hours=1)):
            self.assertNotIn("miss",badi.window_line(window,moment,fmt).casefold())
        self.assertTrue(badi.window_line(window,window.opens,fmt).startswith("Open now, until"))
        self.assertTrue(badi.window_line(window,window.opens-datetime.timedelta(hours=1),fmt).startswith("Opens at"))
        self.assertTrue(badi.window_line(window,window.closes,fmt).startswith("Its time has ended"))

    def test_labels(self):
        short,=badi.prayer_windows("short",date(2026,6,21),HAIFA); parts=badi.prayer_windows("medium",date(2026,6,21),HAIFA)
        self.assertEqual(badi.said_label(short),"Said today"); self.assertEqual([badi.said_label(w) for w in parts],["Said this morning","Said at noon","Said this evening"])

    def test_with_history_off_only_the_current_state_is_kept(self):
        said=["2026-10-01:short:noon","2026-11-01:short:noon","2026-11-02:short:noon"]
        self.assertEqual(badi.prune_said(said,date(2026,11,2),True),said)
        self.assertEqual(badi.prune_said(said,date(2026,11,2),False),said[1:])

class NoLocationTests(unittest.TestCase):
    """Clock times stand in for the sun, on this computer's own zone, including across its own clock change."""
    def setUp(self):
        self.saved=os.environ.get("TZ"); os.environ["TZ"]="America/Chicago"; time.tzset()
    def tearDown(self):
        if self.saved is None: os.environ.pop("TZ",None)
        else: os.environ["TZ"]=self.saved
        time.tzset()
    def test_clock_times(self):
        short,=badi.prayer_windows("short",date(2026,6,21))
        self.assertEqual((short.opens.hour,short.closes.hour),(12,18))
        morning,noon,evening=badi.prayer_windows("medium",date(2026,6,21))
        self.assertEqual((morning.opens.hour,morning.closes.hour,noon.opens.hour,noon.closes.hour,evening.opens.hour,evening.closes.hour),(6,12,12,18,18,20))
    def test_on_the_clock_change_day_they_stay_at_the_same_clock_time(self):
        for day in (date(2026,3,8),date(2026,11,1)):
            short,=badi.prayer_windows("short",day)
            self.assertEqual((short.opens.hour,short.closes.hour),(12,18),day)
        march=badi.prayer_windows("short",date(2026,3,8))[0]; self.assertEqual(march.opens.utcoffset(),datetime.timedelta(hours=-5))
    def test_current_window_without_a_place(self):
        moment=datetime.datetime(2026,6,21,13,tzinfo=ZoneInfo("America/Chicago")).astimezone()
        self.assertEqual(badi.current_window("short",moment).key,"2026-06-21:short:noon")
        self.assertEqual(badi.observed_date(moment),date(2026,6,21))

if __name__=="__main__": unittest.main()

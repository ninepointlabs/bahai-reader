"""Sun times agree with NOAA's calculator, within 2 minutes, and polar days and DST changes are handled (no display needed)."""
import datetime
import unittest
from zoneinfo import ZoneInfo
import badi

PLACES=dict(Tyler=(32.35,-95.30,"America/Chicago"),Haifa=(32.82,34.99,"Asia/Jerusalem"),Tihran=(35.69,51.42,"Asia/Tehran"),Sydney=(-33.87,151.21,"Australia/Sydney"),Tromso=(69.65,18.96,"Europe/Oslo"))
# From NOAA's own Solar Calculator code (https://gml.noaa.gov/grad/solcalc/main.js, calcSunriseSetUTC and calcSolNoon) run for these
# places and dates: local sunrise, solar noon and sunset; None where the sun does not rise or set.
NOAA=[("Tyler",(2026,6,21),"06:14","13:22","20:31"),("Tyler",(2026,12,21),"07:18","12:19","17:20"),
      ("Tyler",(2026,3,8),"07:40","13:32","19:24"),  # US clocks go forward that morning
      ("Tyler",(2026,11,1),"06:38","12:04","17:30"),  # and back
      ("Haifa",(2026,6,21),"05:32","12:41","19:51"),("Haifa",(2026,12,21),"06:38","11:37","16:37"),
      ("Haifa",(2026,3,27),"06:34","12:45","18:56"),  # Israel's clocks go forward
      ("Tihran",(2026,6,21),"04:48","12:06","19:23"),("Tihran",(2026,12,21),"07:10","12:02","16:54"),
      ("Sydney",(2026,6,21),"06:59","11:56","16:53"),("Sydney",(2026,12,21),"05:40","12:52","20:05"),
      ("Sydney",(2026,10,4),"06:28","12:44","18:59"),  # New South Wales clocks go forward
      ("Tromso",(2026,6,21),None,"12:45",None),("Tromso",(2026,12,21),None,"11:41",None),("Tromso",(2026,3,21),"05:39","11:51","18:05")]

class SunTests(unittest.TestCase):
    def test_within_two_minutes_of_noaa(self):
        for name,day,*expected in NOAA:
            date=datetime.date(*day); sun=badi.sun_times(date,*PLACES[name])
            for moment,value in zip((sun.sunrise,sun.noon,sun.sunset),expected):
                with self.subTest(place=name,date=date,expected=value):
                    if value is None: self.assertIsNone(moment); continue
                    wall=datetime.datetime.combine(date,datetime.time.fromisoformat(value))
                    self.assertLessEqual(abs((moment.replace(tzinfo=None)-wall).total_seconds()),120,moment)

    def test_polar_day_and_night(self):
        summer=badi.sun_times(datetime.date(2026,6,21),*PLACES["Tromso"]); winter=badi.sun_times(datetime.date(2026,12,21),*PLACES["Tromso"])
        self.assertEqual((summer.polar,winter.polar),("day","night"))
        fmt=lambda m:m.strftime("%H:%M")
        self.assertEqual(badi.sun_summary(summer,fmt),"Noon 12:45. The sun does not set today.")
        self.assertEqual(badi.sun_summary(winter,fmt),"Noon 11:42. The sun does not rise today.")

    def test_the_clock_change_is_followed(self):
        # The evening of the DST day is an hour later on the clock than it would be without the change.
        before=badi.sun_times(datetime.date(2026,3,7),*PLACES["Tyler"]); after=badi.sun_times(datetime.date(2026,3,8),*PLACES["Tyler"])
        self.assertEqual(before.sunset.utcoffset(),datetime.timedelta(hours=-6)); self.assertEqual(after.sunset.utcoffset(),datetime.timedelta(hours=-5))
        self.assertAlmostEqual((after.sunset.replace(tzinfo=None)-before.sunset.replace(tzinfo=None)-datetime.timedelta(days=1)).total_seconds(),3600,delta=120)

    def test_noon_is_on_the_asked_date_far_from_the_zones_longitude(self):
        # Kiritimati is UTC+14 at 157° W; a plain UTC calculation would give the neighbouring day.
        date=datetime.date(2026,6,21)
        sun=badi.sun_times(date,1.87,-157.4,"Pacific/Kiritimati")
        self.assertEqual((sun.noon.date(),sun.sunrise.date(),sun.sunset.date()),(date,date,date))
        self.assertLess(abs(sun.noon.hour-12),2)

    def test_sunset_after_midnight_belongs_to_the_day_before(self):
        # Just before Tromsø's midnight sun, the sunset of 13 May falls after midnight.
        sun=badi.sun_times(datetime.date(2026,5,13),*PLACES["Tromso"])
        self.assertIsNotNone(sun.sunset); self.assertGreater(sun.sunset,sun.noon); self.assertLess(sun.sunset-sun.noon,datetime.timedelta(hours=13))

    def test_times_are_in_the_places_zone(self):
        sun=badi.sun_times(datetime.date(2026,6,21),*PLACES["Haifa"])
        self.assertEqual(sun.noon.tzinfo,ZoneInfo("Asia/Jerusalem"))

class PlaceTests(unittest.TestCase):
    def test_rounded_to_two_decimals_and_only_known_keys(self):
        self.assertEqual(badi.clean_place({"label":" Haifa,  Israel ","lat":32.81841,"lon":34.9885,"tz":"Asia/Jerusalem","gps":"x"}),{"label":"Haifa, Israel","lat":32.82,"lon":34.99,"tz":"Asia/Jerusalem"})
        self.assertEqual(badi.clean_place({"lat":1,"lon":2,"tz":"UTC"})["label"],"1.0, 2.0")
    def test_invalid_places_are_dropped(self):
        for bad in ("Haifa",[],{"lat":91,"lon":0,"tz":"UTC"},{"lat":0,"lon":181,"tz":"UTC"},{"lat":"1","lon":0,"tz":"UTC"},{"lat":True,"lon":0,"tz":"UTC"},
                    {"lat":float("nan"),"lon":0,"tz":"UTC"},{"lat":0,"lon":0,"tz":"Mars/Olympus"},{"lat":0,"lon":0,"tz":"../etc/passwd"},{"lat":0,"lon":0},{"lat":0,"lon":0,"tz":3}):
            self.assertIsNone(badi.clean_place(bad),bad)
    def test_no_place_no_sun(self):
        self.assertIsNone(badi.place_sun(None,datetime.date(2026,1,1)))

if __name__=="__main__": unittest.main()

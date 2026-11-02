"""The Badí‘ calendar follows the House of Justice's table and rules, and never guesses outside it (no display needed)."""
import datetime
import json
import unittest
from datetime import date
import badi
from badi import BadiDate

class TableTests(unittest.TestCase):
    """Every row of data/badi-dates.json is checked against the rules, using the table's redundant columns to catch a mistyped digit."""
    @classmethod
    def setUpClass(cls):
        cls.data=json.loads(badi.TABLE.read_text()); cls.rows=cls.data["years"]

    def test_covers_172_to_221_with_source_and_credit(self):
        self.assertEqual([r["year"] for r in self.rows],list(range(172,222)))
        self.assertIn("Bahá’í World Centre",self.data["credit"]); self.assertIn("Universal House of Justice",self.data["credit"])
        self.assertIn("11 December 2014",self.data["source"]); self.assertIn("10 July 2014",self.data["source"])
        self.assertIn("bahai-library.com",self.data["source_url"]); self.assertIn("drive.google.com",self.data["checked_against"]["url"])

    def test_naw_ruz_is_on_20_or_21_march_of_the_right_year(self):
        for row in self.rows:
            day=date.fromisoformat(row["naw_ruz"])
            self.assertEqual((day.year,day.month),(row["year"]+1843,3),row["year"]); self.assertIn(day.day,(20,21),row["year"])

    def test_months_and_ayyam_i_ha_make_up_the_year(self):
        for row,following in zip(self.rows,self.rows[1:]):
            length=(date.fromisoformat(following["naw_ruz"])-date.fromisoformat(row["naw_ruz"])).days
            self.assertEqual(19*19+row["ayyam_i_ha_days"],length,row["year"])
        self.assertTrue(all(r["ayyam_i_ha_days"] in (4,5) for r in self.rows))

    def test_ayyam_i_ha_gregorian_column_agrees(self):
        for row in self.rows:
            first=badi.to_gregorian(BadiDate(row["year"],badi.INTERCALARY,1)); last=badi.to_gregorian(BadiDate(row["year"],badi.INTERCALARY,row["ayyam_i_ha_days"]))
            self.assertEqual([first.isoformat(),last.isoformat()],row["ayyam_i_ha_gregorian"],row["year"])

    def test_twin_birthdays_are_consecutive_in_the_allowed_months_and_agree_with_their_gregorian_column(self):
        for row in self.rows:
            first,second=row["birth_bab"],row["birth_bahaullah"]
            for part in (first,second):
                self.assertIn(part["month"],("Mashíyyat","‘Ilm","Qudrat"),row["year"])
                self.assertTrue(1<=part["day"]<=19,row["year"])
                computed=badi.to_gregorian(BadiDate(row["year"],badi.month_number(part["month"]),part["day"]))
                self.assertEqual(computed.isoformat(),part["gregorian"],row["year"])
            self.assertEqual(date.fromisoformat(second["gregorian"])-date.fromisoformat(first["gregorian"]),datetime.timedelta(1),row["year"])

class CalendarTests(unittest.TestCase):
    def test_fixtures(self):
        self.assertEqual(badi.from_gregorian(date(2026,3,21)),BadiDate(183,1,1))
        self.assertEqual(badi.to_gregorian(BadiDate(183,1,1)),date(2026,3,21))
        self.assertEqual(badi.from_gregorian(date(2026,11,10)),BadiDate(183,13,7))
        self.assertEqual(badi.from_gregorian(date(2026,11,11)),BadiDate(183,13,8))
        self.assertEqual(str(BadiDate(183,13,8)),"8 Qudrat 183 B.E.")
        self.assertEqual(BadiDate(183,13,8).meaning,"Power")
        days={e.name:e for e in badi.holy_days(183)}
        self.assertEqual(days["Birth of the Báb"].date,date(2026,11,10)); self.assertEqual(days["Birth of Bahá’u’lláh"].date,date(2026,11,11))

    def test_every_day_round_trips_with_no_gaps(self):
        day=badi.naw_ruz(172); previous=None; last=badi.to_gregorian(BadiDate(221,19,19))
        while day<=last:
            current=badi.from_gregorian(day)
            self.assertIsNotNone(current,day); self.assertEqual(badi.to_gregorian(current),day)
            if previous: self.assertNotEqual(current,previous)
            previous=current; day+=datetime.timedelta(1)

    def test_table_b_dates_in_a_year_starting_on_21_march(self):
        # Table B's own column for Naw-Rúz on 21 March.
        expected={"First day of Riḍván":(4,21),"Ninth day of Riḍván":(4,29),"Twelfth day of Riḍván":(5,2),"Declaration of the Báb":(5,24),"Ascension of Bahá’u’lláh":(5,29),
                  "Martyrdom of the Báb":(7,10),"Day of the Covenant":(11,26),"Ascension of ‘Abdu’l‑Bahá":(11,28)}
        days={e.name:e for e in badi.holy_days(183)}
        for name,(month,day) in expected.items(): self.assertEqual(days[name].date,date(2026,month,day),name)
        feasts=[(e.date.month,e.date.day) for e in badi.feasts(183)]
        self.assertEqual(feasts,[(3,21),(4,9),(4,28),(5,17),(6,5),(6,24),(7,13),(8,1),(8,20),(9,8),(9,27),(10,16),(11,4),(11,23),(12,12),(12,31),(1,19),(2,7),(3,2)])

    def test_table_b_dates_in_a_year_starting_on_20_march(self):
        days={e.name:e for e in badi.holy_days(182)}
        self.assertEqual(days["First day of Riḍván"].date,date(2025,4,20)); self.assertEqual(days["Martyrdom of the Báb"].date,date(2025,7,9))
        self.assertEqual(days["Ascension of ‘Abdu’l‑Bahá"].date,date(2025,11,27)); self.assertEqual(badi.feasts(182)[12].date,date(2025,11,3))

    def test_nine_holy_days_suspend_work(self):
        for year in (172,183,221):
            days=badi.holy_days(year); self.assertEqual(len(days),11)
            self.assertEqual(sum(e.work_suspended for e in days),9)
            self.assertEqual({e.name for e in days if not e.work_suspended},{"Day of the Covenant","Ascension of ‘Abdu’l‑Bahá"})

    def test_every_tagged_holy_day_exists_in_days_of_remembrance(self):
        tags={row["HolyDay"] for row in json.loads((badi.ROOT/"data"/"days.json").read_text())}
        used={e.readings for e in badi.holy_days(183) if e.readings}
        self.assertEqual(used,tags)

    def test_a_day_begins_at_sunset_the_evening_before(self):
        feast=badi.feasts(183)[12]
        self.assertEqual((feast.name,feast.date,feast.begins,feast.meaning),("Feast of Qudrat",date(2026,11,4),date(2026,11,3),"Power"))

    def test_upcoming_spans_the_new_year(self):
        found=badi.upcoming(date(2027,2,1))
        self.assertEqual(found[0].name,"Feast of Mulk"); self.assertEqual([e.date for e in found],sorted(e.date for e in found))
        self.assertIn("Naw-Rúz",[e.name for e in found]); self.assertTrue(all(date(2027,2,1)<=e.date<=date(2028,2,1) for e in found))
        self.assertEqual(badi.next_feast(date(2026,11,1)).name,"Feast of Qudrat")
        self.assertEqual(badi.next_holy_day(date(2026,11,1)).name,"Birth of the Báb")
        self.assertEqual(badi.next_feast(date(2026,11,4)).date,date(2026,11,4))

    def test_year_months_list_nineteen_months_and_ayyam_i_ha(self):
        months=badi.year_months(183)
        self.assertEqual(len(months),20); self.assertEqual(months[18].name,badi.AYYAM_I_HA); self.assertEqual((months[18].first,months[18].last),(date(2027,2,26),date(2027,3,1)))
        self.assertEqual((months[19].name,months[19].first,months[19].last),("‘Alá’",date(2027,3,2),date(2027,3,20)))
        for before,after in zip(months,months[1:]): self.assertEqual(before.last+datetime.timedelta(1),after.first)

    def test_fast(self):
        self.assertEqual(badi.fast_days(183),(date(2027,3,2),date(2027,3,20)))
        self.assertEqual(badi.fast_day(date(2027,3,8)),7); self.assertIsNone(badi.fast_day(date(2027,3,1))); self.assertIsNone(badi.fast_day(date(2027,3,21)))
        self.assertEqual(badi.next_fast(date(2026,11,1)),date(2027,3,2)); self.assertIsNone(badi.next_fast(date(2027,3,8)))

class OutsideTheTableTests(unittest.TestCase):
    """After 221 B.E. and before 172 B.E. nothing is guessed."""
    def test_last_published_day_and_the_day_after(self):
        self.assertEqual(badi.from_gregorian(date(2065,3,19)),BadiDate(221,19,19))
        self.assertIsNone(badi.from_gregorian(date(2065,3,20))); self.assertIsNone(badi.from_gregorian(date(2070,1,1)))
    def test_before_172(self):
        self.assertIsNone(badi.from_gregorian(date(2015,3,20))); self.assertEqual(badi.from_gregorian(date(2015,3,21)),BadiDate(172,1,1))
    def test_lists_are_empty_or_stop_at_the_end(self):
        self.assertEqual((badi.holy_days(222),badi.feasts(222),badi.year_months(222)),([],[],[]))
        self.assertIsNone(badi.fast_days(222)); self.assertIsNone(badi.naw_ruz(171)); self.assertIsNone(badi.to_gregorian(BadiDate(222,1,1)))
        self.assertEqual(badi.upcoming(date(2070,1,1)),[])
        self.assertTrue(all(e.date<=date(2065,3,19) for e in badi.upcoming(date(2065,1,1))))
        self.assertIsNone(badi.next_holy_day(date(2065,1,1)))
    def test_damaged_table_leaves_the_calendar_empty(self):
        saved=badi.TABLE
        try:
            badi.TABLE=badi.ROOT/"no-such-file.json"; badi.table.cache_clear()
            self.assertIsNone(badi.from_gregorian(date(2026,11,1))); self.assertEqual(badi.upcoming(date(2026,11,1)),[])
        finally:
            badi.TABLE=saved; badi.table.cache_clear()

if __name__=="__main__": unittest.main()

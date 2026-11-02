"""The reminder schedule with a fake clock: restarts, suspend and clock changes cannot lose or repeat a reminder (no display needed)."""
import datetime
import os
import tempfile
import unittest
from datetime import timedelta
from pathlib import Path
from zoneinfo import ZoneInfo
import badi
import reader

HAIFA={"label":"Haifa","lat":32.81,"lon":35.0,"tz":"Asia/Jerusalem"}
ZONE=ZoneInfo("Asia/Jerusalem")
fmt=lambda moment:moment.strftime("%H:%M")
SHORT={"prayer":"short","reminders":{"prayer":True}}
MEDIUM={"prayer":"medium","reminders":{"prayer":True}}

def walk(settings,start,end,place=HAIFA,step=30,said=()):
    """Runs the 30-second tick from start to end, as the app does, returning what was sent and when."""
    moment=start; sent=[]; log=[]
    while moment<end:
        due,marked=badi.due_reminders(settings,moment,place,fmt,sent,said)
        sent=sent+marked; log+=[(moment,r) for r in due]; moment+=timedelta(seconds=step)
    return log,sent

class ScheduleTests(unittest.TestCase):
    def setUp(self):
        self.day=datetime.date(2026,11,2); self.sun=badi.place_sun(HAIFA,self.day)
    def at(self,hour,minute=0): return datetime.datetime(2026,11,2,hour,minute,tzinfo=ZONE)

    def test_all_off_by_default(self):
        for settings in ({},{"prayer":"short"},{"prayer":"short","reminders":{}},{"prayer":"short","reminders":{"prayer":False}}):
            self.assertEqual(walk(settings,self.at(0),self.at(23,59),step=600)[0],[])

    def test_short_prayer_opens_and_nudges_each_once(self):
        log,_=walk(SHORT,self.at(0),self.at(23,59))
        self.assertEqual([r.id for _,r in log],["2026-11-02:short:noon:opens","2026-11-02:short:noon:closing"])
        opened,closing=log
        self.assertLess(abs((opened[0]-self.sun.noon).total_seconds()),31)
        self.assertLess(abs((closing[0]-(self.sun.sunset-timedelta(minutes=30))).total_seconds()),31)
        self.assertEqual(closing[1].said,"2026-11-02:short:noon"); self.assertEqual(closing[1].opens,"prayer:short")

    def test_medium_prayer_each_window_in_turn(self):
        log,_=walk(MEDIUM,self.at(0),self.at(23,59))
        self.assertEqual([r.id.split(":",1)[1] for _,r in log],["medium:morning:opens","medium:morning:closing","medium:noon:opens","medium:noon:closing","medium:evening:opens","medium:evening:closing"])

    def test_no_nudge_once_said(self):
        log,_=walk(SHORT,self.at(0),self.at(23,59),said=["2026-11-02:short:noon"])
        self.assertEqual(log,[])

    def test_a_restart_does_not_resend(self):
        first,sent=walk(SHORT,self.at(0),self.sun.noon+timedelta(minutes=5))
        self.assertEqual(len(first),1)
        again,_=badi.due_reminders(SHORT,self.sun.noon+timedelta(minutes=6),HAIFA,fmt,sent,[])
        self.assertEqual(again,[])  # sent is what the settings file kept

    def test_long_suspend_sends_nothing_stale(self):
        # Asleep from before noon until after sunset: the window has closed, so nothing is sent at all.
        before=self.sun.noon-timedelta(hours=1); after=self.sun.sunset+timedelta(minutes=10)
        _,sent=walk(SHORT,before,before+timedelta(minutes=1))
        self.assertEqual(badi.due_reminders(SHORT,after,HAIFA,fmt,sent,[])[0],[])

    def test_waking_inside_the_window_sends_one_not_a_burst(self):
        # Woke during the last half hour: the opening and the nudge are both due, and only the nudge goes out.
        moment=self.sun.sunset-timedelta(minutes=10)
        due,marked=badi.due_reminders(SHORT,moment,HAIFA,fmt,[],[])
        self.assertEqual([r.id for r in due],["2026-11-02:short:noon:closing"]); self.assertEqual(len(marked),2)
        self.assertEqual(badi.due_reminders(SHORT,moment+timedelta(seconds=30),HAIFA,fmt,marked,[])[0],[])
        # Asleep for days: still at most that one, and nothing from the days in between.
        self.assertEqual(len(badi.due_reminders(MEDIUM,moment,HAIFA,fmt,[],[])[0]),1)

    def test_a_clock_set_back_does_not_repeat(self):
        _,sent=walk(SHORT,self.at(0),self.at(23,59))
        self.assertEqual(walk(SHORT,self.at(0),self.at(23,59),step=600)[0] and badi.due_reminders(SHORT,self.sun.noon+timedelta(minutes=1),HAIFA,fmt,sent,[])[0],[])

    def test_a_change_of_time_zone_is_the_same_moment(self):
        moment=self.sun.noon+timedelta(minutes=1)
        here=badi.due_reminders(SHORT,moment,HAIFA,fmt,[],[])[0]; there=badi.due_reminders(SHORT,moment.astimezone(ZoneInfo("Asia/Tokyo")),HAIFA,fmt,[],[])[0]
        self.assertEqual([r.id for r in here],[r.id for r in there])

    def test_long_and_dont_track_send_nothing(self):
        for prayer in ("long","none"):
            self.assertEqual(walk({"prayer":prayer,"reminders":{"prayer":True}},self.at(0),self.at(23,59),step=600)[0],[],prayer)

    def test_the_long_prayer_is_off_by_default_even_with_the_other_prayer_switch_on(self):
        self.assertEqual(walk({"prayer":"long","reminders":{"prayer":True}},self.at(0),self.at(23,59),step=300)[0],[])

    def test_the_long_prayer_nudges_once_before_sunset_unless_marked(self):
        settings={"prayer":"long","reminders":{"long":True}}
        sunset=badi.place_sun(HAIFA,self.at(12).date()).sunset; start=self.at(0); moment=sunset-timedelta(hours=2)
        sent=[r for _,r in walk(settings,start,sunset,step=60)[0]]
        self.assertEqual(len(sent),1); self.assertEqual(sent[0].at.timestamp(),moment.timestamp()); self.assertTrue(sent[0].said)
        self.assertEqual(walk(settings,start,sunset,step=60,said=[sent[0].said])[0],[])

    def test_the_long_prayer_lead_time_can_change(self):
        settings={"prayer":"long","long_lead_hours":5,"reminders":{"long":True}}
        sunset=badi.place_sun(HAIFA,self.at(12).date()).sunset
        self.assertEqual(walk(settings,self.at(0),sunset,step=60)[0][0][1].at.timestamp(),(sunset-timedelta(hours=5)).timestamp())

    def test_rolling_only_nudges_after_it_has_been_said(self):
        settings={"prayer":"long","long_period":"rolling","reminders":{"long":True}}; start=self.at(8)
        self.assertEqual(walk(settings,start,start+timedelta(days=2),step=600)[0],[])
        mark=f"{start.date().isoformat()}:long:at:{int(start.timestamp())}"
        sent=[r for _,r in walk(settings,start,start+timedelta(days=2),step=600,said=[mark])[0]]
        self.assertEqual(len(sent),1); self.assertEqual(sent[0].until.timestamp(),start.timestamp()+86400); self.assertIsNone(sent[0].said)

    def test_polar_days_send_nothing(self):
        tromso={"label":"Tromsø","lat":69.65,"lon":18.96,"tz":"Europe/Oslo"}; start=datetime.datetime(2026,6,21,0,tzinfo=ZoneInfo("Europe/Oslo"))
        self.assertEqual(walk(SHORT,start,start+timedelta(days=1),place=tromso,step=600)[0],[])

    def test_without_a_location_clock_times_are_used(self):
        saved=os.environ.get("TZ"); os.environ["TZ"]="Asia/Jerusalem"; reader.time.tzset()
        try:
            due=badi.due_reminders(SHORT,self.at(12,0).astimezone(),None,fmt,[],[])[0]
            self.assertEqual([r.id for r in due],["2026-11-02:short:noon:opens"]); self.assertIn("until 18:00",due[0].body)
        finally:
            os.environ.pop("TZ",None) if saved is None else os.environ.__setitem__("TZ",saved); reader.time.tzset()

    def test_the_sent_list_stays_short(self):
        self.assertEqual(badi.prune_sent(["2026-10-01:a","2026-10-30:b","2026-11-02:c"],self.day),["2026-10-30:b","2026-11-02:c"])

class EventReminderTests(unittest.TestCase):
    """Feasts, Holy Days and the Fast at the times in the brief, each off until turned on."""
    def day(self,*date,hour=0): return datetime.datetime(*date,hour,tzinfo=ZONE)
    def test_off_by_default(self):
        start=self.day(2026,11,1)
        self.assertEqual(walk({"reminders":{}},start,start+timedelta(days=12),step=900)[0],[])
    def test_a_feast_on_the_afternoon_of_the_day_it_begins(self):
        # Feast of Qudrat: 4 November 2026, begins at sunset on 3 November.
        log,_=walk({"reminders":{"feast":True}},self.day(2026,11,1),self.day(2026,11,5),step=300)
        self.assertEqual([r.title for _,r in log],["Feast of Qudrat (Power)"])
        moment,reminder=log[0]; self.assertEqual((moment.date(),moment.hour),(datetime.date(2026,11,3),15)); self.assertEqual(reminder.body,"Begins at sunset today.")
        self.assertIsNone(reminder.said); self.assertEqual(reminder.opens,"today")
    def test_a_holy_day_the_day_before_and_on_the_day(self):
        log,_=walk({"reminders":{"holy":True}},self.day(2026,11,8),self.day(2026,11,11),step=300)
        self.assertEqual([(m.date().isoformat(),m.hour,r.body) for m,r in log if r.title=="Birth of the Báb"],[("2026-11-09",15,"Begins at sunset today. Work is suspended."),("2026-11-10",9,"Today. Work is suspended.")])
    def test_a_holy_day_without_work_suspended_says_nothing_of_it(self):
        log,_=walk({"reminders":{"holy":True}},self.day(2026,11,24),self.day(2026,11,27),step=300)
        self.assertEqual([r.body for _,r in log if r.title=="Day of the Covenant"],["Begins at sunset today.","Today."])
    def test_the_fast_5_3_and_1_days_before(self):
        log,_=walk({"reminders":{"fast":True}},self.day(2027,2,20),self.day(2027,3,3),step=900)
        self.assertEqual([(m.date().isoformat(),r.body) for m,r in log],[("2027-02-25","The Fast begins at sunrise on 2 March."),("2027-02-27","The Fast begins at sunrise on 2 March."),("2027-03-01","The Fast begins at sunrise tomorrow.")])
    def test_the_fast_each_day_only_if_asked(self):
        self.assertEqual(walk({"reminders":{"fast":True}},self.day(2027,3,8),self.day(2027,3,9),step=300)[0],[])
        log,_=walk({"reminders":{"fast_daily":True}},self.day(2027,3,8),self.day(2027,3,9),step=60)
        self.assertEqual([r.id for _,r in log],["2027-03-08:fast:sunrise","2027-03-08:fast:sunset"])
        sun=badi.place_sun(HAIFA,datetime.date(2027,3,8))
        self.assertLess(abs((log[0][0]-(sun.sunrise-timedelta(minutes=30))).total_seconds()),61); self.assertLess(abs((log[1][0]-sun.sunset).total_seconds()),61)
        self.assertTrue(log[0][1].body.startswith("Day 7 of 19. Sunrise is at"))
        self.assertEqual(walk({"reminders":{"fast_daily":True}},self.day(2027,3,21),self.day(2027,3,22),step=300)[0],[])
    def test_after_a_long_sleep_stale_ones_are_skipped(self):
        # Waking on the evening of the Feast's first day: its afternoon reminder has gone stale at sunset.
        moment=self.day(2026,11,3,20)
        self.assertEqual(badi.due_reminders({"reminders":{"feast":True}},moment,HAIFA,fmt,[],[])[0],[])
        # Holy Day: both due at once is never a burst; only the latest goes out.
        moment=self.day(2026,11,10,15); due,_=badi.due_reminders({"reminders":{"holy":True}},moment,HAIFA,fmt,[],[])
        self.assertEqual([r.body for r in due if r.title=="Birth of the Báb"],["Today. Work is suspended."])
    def test_where_the_sun_sets_early_the_afternoon_comes_earlier(self):
        tromso={"label":"T","lat":69.65,"lon":18.96,"tz":"Europe/Oslo"}
        # Late November, near the polar night, the sun has set by mid afternoon.
        feast=next(e for e in badi.feasts(183) if e.name=="Feast of Qawl")
        reminder=badi.event_reminders(feast,tromso)[0]; self.assertLess(reminder.at.timestamp(),reminder.until.timestamp())
    def test_unpublished_years_send_nothing(self):
        start=self.day(2065,3,20)
        settings={"reminders":{"feast":True,"holy":True,"fast":True,"fast_daily":True}}
        self.assertEqual(walk(settings,start,start+timedelta(days=30),step=3600)[0],[])

class FastStateTests(unittest.TestCase):
    def test_states(self):
        self.assertEqual(badi.fast_state(datetime.date(2027,3,8)),(7,datetime.date(2027,3,8)))
        self.assertEqual(badi.fast_state(datetime.date(2027,2,10)),(None,datetime.date(2027,3,2)))
        self.assertIsNone(badi.fast_state(datetime.date(2026,11,1))); self.assertIsNone(badi.fast_state(datetime.date(2027,3,21)))
        self.assertIsNone(badi.fast_state(datetime.date(2070,1,1)))
        self.assertEqual(badi.fast_state(datetime.date(2027,1,31)),(None,datetime.date(2027,3,2)))  # 30 days ahead
        self.assertIsNone(badi.fast_state(datetime.date(2027,1,30)))

class AutostartTests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        self.saved=reader.AUTOSTART; reader.AUTOSTART=Path(temp.name)/"autostart"/"org.bahai.Reader-reminders.desktop"
        self.addCleanup(lambda:setattr(reader,"AUTOSTART",self.saved))
    def test_entry_is_written_and_removed(self):
        reader.write_autostart()
        text=reader.AUTOSTART.read_text(); self.assertIn("Type=Application",text); self.assertIn(" --background\n",text)
        reader.remove_autostart(); self.assertFalse(reader.AUTOSTART.exists()); reader.remove_autostart()  # removing twice is fine
    def test_quoting_for_desktop_entries(self):
        self.assertEqual(reader.desktop_quote("bahai-reader"),"bahai-reader")
        self.assertEqual(reader.desktop_quote("/home/a b/x.AppImage"),'"/home/a b/x.AppImage"')
        self.assertEqual(reader.desktop_quote('/x/$a"b%c'),'"/x/\\$a\\"b%%c"')
    def test_command_for_each_kind_of_install(self):
        saved=reader.ROOT
        try:
            os.environ["APPIMAGE"]="/home/me/Reader.AppImage"; self.assertEqual(reader.launch_command(),"/home/me/Reader.AppImage"); del os.environ["APPIMAGE"]
            reader.ROOT=Path("/usr/share/bahai-reader"); self.assertEqual(reader.launch_command(),"bahai-reader")
            reader.ROOT=Path("/home/me/bahai-reader"); self.assertEqual(reader.launch_command(),"/home/me/bahai-reader/launch.sh")
        finally:
            reader.ROOT=saved; os.environ.pop("APPIMAGE",None)

class SettingsTests(unittest.TestCase):
    def test_reminder_settings_are_checked_and_off_by_default(self):
        self.assertEqual(reader.clean_settings({"saved":["a"]}),{"saved":["a"]})
        prefs=reader.clean_settings({"reminders":{"prayer":True,"bogus":True,"feast":"yes"},"keep_running":"yes","reminders_sent":["2026-11-02:x",3,"junk"]})
        self.assertEqual(prefs,{"reminders":{"prayer":True},"reminders_sent":["2026-11-02:x"]})
        self.assertEqual(reader.clean_settings({"reminders":"oops"})["reminders"],{})

if __name__=="__main__": unittest.main()

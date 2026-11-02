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

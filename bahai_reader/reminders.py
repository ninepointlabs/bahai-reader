"""The clock tick, reminders and notifications, and running in the background."""
import random
import sys
import time
from gi.repository import Gio, GLib
import badi

from . import config, desktop
from .desktop import clock, remove_autostart, write_autostart
from .settings import SAID_KEY

class RemindersMixin:
    """Reader methods: the clock tick, reminders and notifications, and running in the background."""
    def now(self):
        """The time now at the saved place, or on this computer without one. The computer's own zone may have changed."""
        time.tzset()
        return badi.local_now(self.place(),self.fixed_now)

    def start_ticking(self):
        if self.ticking: return
        self.ticking=True
        GLib.timeout_add_seconds(30,self.tick); GLib.idle_add(lambda:(self.tick(),False)[1])

    def tick(self):
        """The wall clock, every 30 seconds, with a window or without: a long timeout would not survive suspend or a change of
        the clock. Waking from suspend, the next tick catches up; what has gone stale is skipped."""
        self.send_due_reminders()
        if not self.window or not self.window.get_visible(): return True
        if getattr(self,"today_day",None)!=badi.observed_date(self.now(),self.place()) and self.section=="today":
            self.rebuild()
        if self.views.get_visible_child_name()=="today": self.refresh_today()
        if self.views.get_visible_child_name()=="home": self.refresh_home()
        self.show_said()
        return True

    def send_due_reminders(self):
        moment=self.now()
        due,marked=badi.due_reminders(self.prefs,moment,self.place(),clock,self.prefs.get("reminders_sent",[]),self.said_marks())
        if not marked: return
        for reminder in due: self.send_reminder(reminder)
        self.prefs["reminders_sent"]=badi.prune_sent(self.prefs.get("reminders_sent",[])+marked,moment.date()); self.save()

    def send_reminder(self,reminder):
        note=Gio.Notification.new(reminder.title); note.set_body(reminder.body)
        note.set_icon(Gio.ThemedIcon.new("org.bahai.Reader"))
        note.set_default_action_and_target("app.open",GLib.Variant("s",reminder.opens))
        if reminder.said:
            note.add_button_with_target("Said today","app.said",GLib.Variant("s",reminder.said))
        note.add_button_with_target("Open","app.open",GLib.Variant("s",reminder.opens))
        self.send_notification(reminder.group,note)

    def notification_said(self,key):
        """"Said today" on a notification: marked without opening the window."""
        if not SAID_KEY.fullmatch(key): return
        self.mark_said(key,True); self.withdraw_notification(f"prayer:{key.split(':')[1]}")

    def notification_open(self,target):
        self.activate(self)
        chosen=target.split(":",1)[1] if target.startswith("prayer:") else None
        item=self.prayer_item(chosen) if chosen in badi.PRAYERS else None
        if item: self.open_obligatory(item)
        else: self.navigate("today")

    def set_keep_running(self,wanted):
        """The opt-in background mode: an XDG autostart entry, or the Background portal inside Flatpak, whose sandbox cannot write one."""
        self.prefs["keep_running"]=wanted; self.save(); self.apply_keep_running(wanted)
        if desktop.in_flatpak(): self.request_background(wanted); return
        try:
            write_autostart() if wanted else remove_autostart()
            self.running_message("Starts when you log in." if wanted else None)
        except OSError as exc:
            print(f"bahai-reader: could not change {config.AUTOSTART}: {exc}",file=sys.stderr)
            self.running_message(f"The login entry could not be changed ({exc.strerror or exc}). Reminders run only while the app is open.")

    def running_message(self,text):
        label=getattr(self,"keep_running_status",None)
        if label: label.set_text(text or ""); label.set_visible(bool(text))

    def request_background(self,wanted):
        """Asks the XDG Background portal to start the app at login. Some desktops (Hyprland's portal among them) do not offer it, and then the
        settings window says so plainly; the setting still keeps the process alive after closing the window until logout."""
        unavailable="This desktop does not offer the Background portal, so reminders cannot start at login in the Flatpak. They run while the app is open."
        declined="The desktop declined to start the app at login. Reminders run while the app is open."
        bus=self.get_dbus_connection()
        if bus is None: self.running_message(unavailable); return
        token=f"bahai{random.randrange(10**8)}"
        sender=bus.get_unique_name()[1:].replace(".","_")
        path=f"/org/freedesktop/portal/desktop/request/{sender}/{token}"
        state={"source":None}
        def finish(text):
            if state["source"] is not None: bus.signal_unsubscribe(state["source"]); state["source"]=None
            self.running_message(text)
        def responded(_bus,_sender,_path,_interface,_signal,parameters):
            code,results=parameters.unpack()
            if code!=0: finish(declined if wanted else None); return
            if wanted and not results.get("autostart"): finish(declined)
            else: finish("Starts when you log in." if wanted else None)
        state["source"]=bus.signal_subscribe(None,"org.freedesktop.portal.Request","Response",path,None,Gio.DBusSignalFlags.NONE,responded)
        options={"handle_token":GLib.Variant("s",token),"reason":GLib.Variant("s","Keep reminders running when the window is closed"),
                 "autostart":GLib.Variant("b",wanted),"commandline":GLib.Variant("as",["bahai-reader","--background"]),"dbus-activatable":GLib.Variant("b",False)}
        def called(connection,result):
            try: connection.call_finish(result)
            except GLib.Error as exc:
                print(f"bahai-reader: Background portal: {exc.message}",file=sys.stderr); finish(unavailable)
        bus.call("org.freedesktop.portal.Desktop","/org/freedesktop/portal/desktop","org.freedesktop.portal.Background","RequestBackground",
                 GLib.Variant("(sa{sv})",("",options)),GLib.VariantType.new("(o)"),Gio.DBusCallFlags.NONE,30000,None,called)

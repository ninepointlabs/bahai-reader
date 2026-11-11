"""--background then a normal launch, closing the window with and without the option, notifications with actions, and the Background portal.
Run with xvfb-run -a dbus-run-session -- /usr/bin/python3 tests/background_ui.py: it needs its own session bus, which also stands in for the notification server."""
import datetime
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
os.environ["GNOTIFICATION_BACKEND"]="freedesktop"  # what mako and swaync are reached through
temp=tempfile.TemporaryDirectory()
os.environ["XDG_CONFIG_HOME"]=temp.name+"/config"; os.environ["XDG_DATA_HOME"]=temp.name+"/data"; os.environ["XDG_CACHE_HOME"]=temp.name+"/cache"
import reader
from gi.repository import Gio, GLib, Gtk
reader.time.tzset()

NOTIFY_XML="""<node><interface name="org.freedesktop.Notifications">
<method name="Notify"><arg type="s" direction="in"/><arg type="u" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="as" direction="in"/><arg type="a{sv}" direction="in"/><arg type="i" direction="in"/><arg type="u" direction="out"/></method>
<method name="CloseNotification"><arg type="u" direction="in"/></method>
<method name="GetCapabilities"><arg type="as" direction="out"/></method>
<method name="GetServerInformation"><arg type="s" direction="out"/><arg type="s" direction="out"/><arg type="s" direction="out"/><arg type="s" direction="out"/></method>
<signal name="ActionInvoked"><arg type="u"/><arg type="s"/></signal><signal name="NotificationClosed"><arg type="u"/><arg type="u"/></signal>
</interface></node>"""
PORTAL_XML="""<node><interface name="org.freedesktop.portal.Background"><method name="RequestBackground"><arg type="s" direction="in"/><arg type="a{sv}" direction="in"/><arg type="o" direction="out"/></method></interface></node>"""
received=[]; portal_calls=[]; server={}

def notifications(connection,sender,path,interface,method,parameters,invocation):
    if method=="Notify":
        received.append(parameters.unpack()); server["sender"]=sender; invocation.return_value(GLib.Variant("(u)",(len(received),)))
    elif method=="GetCapabilities": invocation.return_value(GLib.Variant("(as)",(["actions","body"],)))
    elif method=="GetServerInformation": invocation.return_value(GLib.Variant("(ssss)",("test","test","1","1.2")))
    else: invocation.return_value(None)

def portal(connection,sender,path,interface,method,parameters,invocation):
    # Like a desktop whose portal has no Background backend, until the test turns it on.
    if not server.get("portal"): invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod","No such interface"); return
    window,options=parameters.unpack(); portal_calls.append(options)
    handle=f"/org/freedesktop/portal/desktop/request/{sender[1:].replace('.','_')}/{options['handle_token']}"
    invocation.return_value(GLib.Variant("(o)",(handle,)))
    connection.emit_signal(sender,handle,"org.freedesktop.portal.Request","Response",GLib.Variant("(ua{sv})",(0,{"background":GLib.Variant("b",True),"autostart":GLib.Variant("b",options["autostart"])})))

bus=Gio.bus_get_sync(Gio.BusType.SESSION,None)
assert "DBUS_SESSION_BUS_ADDRESS" in os.environ
bus.register_object("/org/freedesktop/Notifications",Gio.DBusNodeInfo.new_for_xml(NOTIFY_XML).interfaces[0],notifications)
Gio.bus_own_name_on_connection(bus,"org.freedesktop.Notifications",Gio.BusNameOwnerFlags.NONE,None,None)

# Owned here so the bus never starts a real portal on machines that have one.
bus.register_object("/org/freedesktop/portal/desktop",Gio.DBusNodeInfo.new_for_xml(PORTAL_XML).interfaces[0],portal)
bus.call_sync("org.freedesktop.DBus","/org/freedesktop/DBus","org.freedesktop.DBus","RequestName",GLib.Variant("(su)",("org.freedesktop.portal.Desktop",0)),None,Gio.DBusCallFlags.NONE,5000,None)

def launch(*args):
    """A separate launch of the app, as the desktop would do."""
    return subprocess.Popen([sys.executable,str(ROOT/"reader.py"),*args],env=os.environ)

app=reader.Reader(background=True); app.register(None); assert not app.get_is_remote(), "another instance on this private bus"
errors=[]; passed=[]; steps=[]; UTC=datetime.timezone.utc
def close_dialog(app,name):
    """Closes a settings window and waits until it is gone. In the libadwaita window it is a dialog inside the main window,
    which closes with an animation and holds the window's focus (and its close request) until then."""
    import time as _time
    from gi.repository import GLib as _GLib
    window=getattr(app,name)
    if window is not None: window.close()
    if not hasattr(app.window,"get_visible_dialog"): return  # the classic window: small windows close at once
    end=_time.monotonic()+4
    # Until no dialog shows in the window at all (one closed earlier in the same step may still be on its way out).
    while app.window.get_visible_dialog() is not None and _time.monotonic()<end:
        _GLib.MainContext.default().iteration(False); _time.sleep(0.01)  # the closing animation needs real frame time


def wait(condition,seconds=60,what=""):
    """Runs the main loop until a condition holds."""
    end=time.monotonic()+seconds; context=GLib.MainContext.default()
    while not condition():
        if time.monotonic()>end: raise AssertionError("timed out: "+what)
        context.iteration(False); time.sleep(0.01)
def windows(): return [w for w in app.get_windows()]
def exercise():
    try:
        # --background: no window, and the library is not even loaded.
        assert app.window is None and windows()==[] and app._items is None and app.held
        # A normal launch then opens one window in this process, and exits at once.
        first=launch(); wait(lambda:app.window is not None and first.poll() is not None,what="first launch")
        assert first.returncode==0 and len(windows())==1 and app.window.get_visible()
        # Another launch shows the same window.
        again=launch(); wait(lambda:again.poll() is not None,what="second launch"); assert again.returncode==0 and len(windows())==1
        # --background while running does nothing at all.
        idle=launch("--background"); wait(lambda:idle.poll() is not None,what="background launch"); assert idle.returncode==0 and len(windows())==1 and app.window.get_visible()
        # Started with --background, closing the window leaves the process running; it comes back on the next launch.
        app.window.close(); wait(lambda:not app.window.get_visible(),what="hidden after background launch")
        back=launch(); wait(lambda:app.window.get_visible() and back.poll() is not None,what="back"); assert len(windows())==1
        # The option: writes the login entry; closing then hides the window and the process lives on.
        app.location_dialog(); app.keep_running_check.set_active(True)
        assert reader.AUTOSTART.exists() and "--background" in reader.AUTOSTART.read_text() and app.prefs["keep_running"] is True and app.held
        assert json.loads(reader.STATE.read_text())["keep_running"] is True and app.keep_running_status.get_text()=="Starts when you log in."
        close_dialog(app,"location_window")
        app.window.close(); wait(lambda:not app.window.get_visible(),what="window hidden")
        assert app.window is not None and not app.window.get_visible()
        reopen=launch(); wait(lambda:app.window.get_visible() and reopen.poll() is not None,what="reopen"); assert len(windows())==1
        # Ctrl+Q does what closing does while the option is on.
        assert app.quit_key(None,reader.Gdk.KEY_q,0,reader.Gdk.ModifierType.CONTROL_MASK) and not app.window.get_visible()
        app.activate(app); assert app.window.get_visible()
        # A reminder through the real path: settings, wall clock, notification with actions.
        place={"label":"Haifa","lat":32.81,"lon":35.0,"tz":"Asia/Jerusalem"}
        app.prefs.update(location=place,prayer="short",reminders={"prayer":True}); app.prefs.pop("reminders_sent",None)
        sun=reader.badi.place_sun(place,datetime.date(2026,11,2)); app.fixed_now=sun.noon+datetime.timedelta(minutes=1)
        app.navigate("today"); app.tick(); wait(lambda:received,what="notification")
        _,_,_,title,body,actions,_,_=received[-1]
        assert title=="Short Obligatory Prayer" and body.startswith("Its time is open, until"), received[-1]
        assert "Said today" in actions and "Open" in actions, actions
        count=len(received); app.tick(); reader.GLib.MainContext.default().iteration(False); time.sleep(0.2); assert len(received)==count, "sent twice"
        assert "2026-11-02:short:noon:opens" in json.loads(reader.STATE.read_text())["reminders_sent"]
        # "Said today" on the notification marks it, with the window closed, and the Today card agrees when opened.
        app.window_closing(app.window); assert not app.window.get_visible()
        said=actions[actions.index("Said today")-1]
        bus.emit_signal(server["sender"],"/org/freedesktop/Notifications","org.freedesktop.Notifications","ActionInvoked",GLib.Variant("(us)",(len(received),said)))
        wait(lambda:"2026-11-02:short:noon" in app.said_marks(),what="said action")
        assert not app.window.get_visible(), "Said today must not open the window"
        assert json.loads(reader.STATE.read_text())["records"]["said"]==["2026-11-02:short:noon"]
        # Now said: no nudge before it closes.
        app.fixed_now=sun.sunset-datetime.timedelta(minutes=10); count=len(received); app.tick(); time.sleep(0.2); assert len(received)==count
        # "Open" opens the prayer.
        app.fixed_now=sun.noon+datetime.timedelta(days=1)  # the next day's window
        app.prefs["records"]["said"]=[]; app.tick(); wait(lambda:len(received)>count,what="next notification")
        _,_,_,_,_,actions,_,_=received[-1]; opening=actions[actions.index("Open")-1]
        bus.emit_signal(server["sender"],"/org/freedesktop/Notifications","org.freedesktop.Notifications","ActionInvoked",GLib.Variant("(us)",(len(received),opening)))
        wait(lambda:app.window.get_visible(),what="open action"); assert app.section=="obligatory" and "Short Obligatory Prayer" in app.current["tags"]
        # The Flatpak path: the sandbox has no autostart folder, so the portal is asked instead.
        app.fixed_now=None; reader.remove_autostart(); saved=reader.in_flatpak; reader.in_flatpak=lambda:True
        app.location_dialog(); app.prefs.pop("keep_running",None); app.keep_running_check.set_active(False)
        # No portal on this bus: said plainly, not silently.
        app.keep_running_status.set_text(""); app.keep_running_check.set_active(True); wait(lambda:"does not offer the Background portal" in app.keep_running_status.get_text(),what="no portal message")
        assert not reader.AUTOSTART.exists()
        # With a portal: autostart asked for with the right command.
        app.keep_running_check.set_active(False); wait(lambda:"does not offer" in app.keep_running_status.get_text(),what="second refusal")
        server["portal"]=True
        app.keep_running_check.set_active(True); wait(lambda:app.keep_running_status.get_text()=="Starts when you log in.",what="portal response")
        assert portal_calls[-1]["autostart"] is True and portal_calls[-1]["commandline"]==["bahai-reader","--background"] and not reader.AUTOSTART.exists(), portal_calls[-1]
        reader.in_flatpak=saved; app.keep_running_check.set_active(False); assert not reader.AUTOSTART.exists() and not app.prefs["keep_running"] and not app.held
        close_dialog(app,"location_window")
        # The option off: closing the window ends the process, exactly as before.
        app.window.close(); passed.append("closing"); 
    except Exception as exc:
        errors.append(exc); app.quit()
    return False
GLib.timeout_add(300,exercise)
status=app.run([sys.argv[0]])
if errors: raise errors[0]
assert passed==["closing"], "the test did not finish"
print("Background UI test passed")

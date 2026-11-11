"""Desktop integration: Flatpak detection, autostart for reminders, local clock formatting."""
import os
import re
from pathlib import Path
from gi.repository import GLib

from . import config
def in_flatpak():
    return Path("/.flatpak-info").exists()

def desktop_quote(text):
    """An argument in a desktop entry's Exec line: quoted when it needs to be, with \\ " ` $ escaped and % doubled."""
    text=text.replace("%","%%")
    if not re.search(r"""[\s"'`$\\&;<>|*?()#~=]""",text): return text
    return '"'+re.sub(r'([\\"`$])',r"\\\1",text)+'"'

def launch_command():
    """How to start this copy of the app: the AppImage file, the installed command, or the checkout's launcher."""
    if os.environ.get("APPIMAGE"): return os.environ["APPIMAGE"]
    if str(config.ROOT).startswith(("/usr/","/app/")): return "bahai-reader"
    return str(config.ROOT/"launch.sh")

def autostart_entry():
    return ("[Desktop Entry]\nType=Application\nName=Bahá’í Reader reminders\nComment=Keeps reminders running when the Bahá’í Reader window is closed\n"
            f"Exec={desktop_quote(launch_command())} --background\nIcon=org.bahai.Reader\nTerminal=false\nX-GNOME-Autostart-enabled=true\n")

def write_autostart():
    config.AUTOSTART.parent.mkdir(parents=True,exist_ok=True)
    temp=config.AUTOSTART.with_suffix(".tmp"); temp.write_text(autostart_entry()); temp.replace(config.AUTOSTART)

def remove_autostart():
    config.AUTOSTART.unlink(missing_ok=True)

def clock_style(locale_time,marker):
    """12 when the locale's own time format uses AM/PM, otherwise 24."""
    return 12 if marker and marker in locale_time else 24

def clock(moment):
    """A time at its place, formatted for the user's locale with GLib, as the date-and-time wall clock shows it there."""
    wall=GLib.DateTime.new_utc(moment.year,moment.month,moment.day,moment.hour,moment.minute,moment.second)
    if clock_style(wall.format("%X") or "",wall.format("%p") or "")==12: return " ".join(wall.format("%l:%M %p").split())
    return wall.format("%H:%M")

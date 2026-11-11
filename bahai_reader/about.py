"""About, privacy and keyboard shortcuts windows."""
import os
import sys
from pathlib import Path
import gi
from gi.repository import Gtk, Gdk, GLib, Pango

from . import config
from .config import APP_NAME, COPYRIGHT, CREATED, LICENSE_NAME, ORGANIZATION, SUPPORT_EMAIL, TAGLINE, shipped, version
from .ui import SHORTCUTS

class AboutMixin:
    """Reader methods: about, privacy and keyboard shortcuts windows."""
    def details(self):
        """Version details to paste into a support email."""
        display=Gdk.Display.get_default()
        return (f"{APP_NAME} {version()}\n"
                f"Python {sys.version.split()[0]}, GTK {Gtk.get_major_version()}.{Gtk.get_minor_version()}.{Gtk.get_micro_version()}, PyGObject {gi.__version__}, Pango {Pango.version_string()}\n"
                f"{os.environ.get('XDG_CURRENT_DESKTOP','unknown desktop')}, {type(display).__name__ if display else 'no display'}")

    def privacy(self):
        home=str(Path.home())
        short=lambda path:str(path).replace(home,"~",1) if str(path).startswith(home) else str(path)
        return ("No accounts, no telemetry, no analytics. English is bundled, so starting, reading, searching and switching "
                "to a downloaded language never use the network. The app connects only when you choose Download & use, "
                "Update downloaded content or Check available languages: it then asks bahaiprayers.net over HTTPS for that "
                "language’s texts or the language list. The request carries only the collection, the language number and "
                f"Python’s standard user agent; like any web request, the site sees your IP address. Downloads are saved in {short(config.LIBRARY)}. Settings and saved "
                f"passages stay in {short(config.STATE)} and are never sent anywhere. A location you enter is typed in, never detected, is only used on this computer "
                "to work out the sun’s times, and is never sent anywhere. Reminders are worked out and sent on this computer, and your “Said today” and “Fasted today” records stay here too; "
                "you can turn them off or clear them in Location & reminders.")

    def about_dialog(self,*_):
        if getattr(self,"about_window",None):
            self.about_window.present(); return
        window=Gtk.Window(title="About Bahá’í Reader",transient_for=self.window,modal=True,default_width=560)
        self.about_window=window
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=14)
        for edge in ("top","bottom","start","end"): getattr(box,"set_margin_"+edge)(20)
        scroller=Gtk.ScrolledWindow(propagate_natural_height=True,max_content_height=640,hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroller.set_child(box); window.set_child(scroller)
        top=Gtk.Box(spacing=16); box.append(top)
        icon=shipped("packaging/org.bahai.Reader.svg","icons/hicolor/scalable/apps/org.bahai.Reader.svg")
        image=Gtk.Image.new_from_file(str(icon)) if icon else Gtk.Image.new_from_icon_name("org.bahai.Reader")
        image.set_pixel_size(64); image.set_valign(Gtk.Align.START); top.append(image)
        names=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=2); top.append(names)
        title=Gtk.Label(label=APP_NAME,xalign=0); title.add_css_class("heading"); names.append(title)
        names.append(Gtk.Label(label=TAGLINE,xalign=0,wrap=True,max_width_chars=44))
        about_version=Gtk.Label(label="Version "+version(),xalign=0); about_version.add_css_class("dim-label"); names.append(about_version)
        grid=Gtk.Grid(column_spacing=18,row_spacing=10); box.append(grid)
        def row(name,widget):
            label=Gtk.Label(label=name,xalign=0,valign=Gtk.Align.START); label.add_css_class("dim-label")
            index=len(self.about_rows); self.about_rows[name]=widget
            grid.attach(label,0,index,1,1); grid.attach(widget,1,index,1,1)
        def text(value):
            return Gtk.Label(label=value,xalign=0,wrap=True,max_width_chars=52,hexpand=True)
        def actions(value,*buttons):
            line=Gtk.Box(spacing=10); line.append(Gtk.Label(label=value,xalign=0))
            for name,callback in buttons: line.append(self.button(name,callback))
            return line
        self.about_rows={}
        license_path=shipped("LICENSE","licenses/bahai-reader/LICENSE")
        notice_path=shipped("DATA-NOTICE.md","licenses/bahai-reader/DATA-NOTICE.md")
        license_view=text("\n\n".join(" ".join(p.split()).lstrip("# ") for path in (license_path,notice_path) if path for p in path.read_text().split("\n\n") if p.strip()) or f"{LICENSE_NAME}, {COPYRIGHT}")
        license_view.set_visible(False); self.about_license=license_view
        def toggle_license(button):
            license_view.set_visible(not license_view.get_visible()); button.set_label("Hide" if license_view.get_visible() else "Read it")
        def email(*_):
            uri="mailto:"+SUPPORT_EMAIL+"?subject="+GLib.Uri.escape_string(f"{APP_NAME} {version()}",None,False)+"&body="+GLib.Uri.escape_string("\n\n--\n"+self.details(),None,False)
            if hasattr(Gtk,"UriLauncher"): Gtk.UriLauncher.new(uri).launch(window,None,None)
            else: Gtk.show_uri(window,uri,Gdk.CURRENT_TIME)
        row("Made by",text(ORGANIZATION))
        row("Created",text(CREATED))
        row("License",actions(f"{LICENSE_NAME}, {COPYRIGHT}",("Read it",toggle_license)))
        row("Texts",text("From BahaiPrayers.net, which permits their use in apps. The texts and translations are not covered by the MIT license, and no ownership is claimed (DATA-NOTICE.md). Not an official publication of a Bahá’í institution."))
        row("bahai.org",text("In English, the official text from the Bahá’í Reference Library, bahai.org, wherever it has the passage: the books and most prayers, messages of the Universal House of Justice and works of Shoghi Effendi. Copyright © Bahá’í International Community. Used under the terms at bahai.org/legal; not covered by the MIT license (DATA-NOTICE.md)."))
        row("Places",text("City data © GeoNames (geonames.org), trimmed, under the Creative Commons Attribution 4.0 license (creativecommons.org/licenses/by/4.0)."))
        row("Calendar",text("Badí‘ dates from the Bahá’í World Centre and the Universal House of Justice. Sun times use the public-domain NOAA solar calculation."))
        row("Support",actions(SUPPORT_EMAIL,("Email",email),("Copy",lambda *_: window.get_clipboard().set(SUPPORT_EMAIL))))
        row("Privacy",text(self.privacy()))
        row("Built with",text(f"GTK {Gtk.get_major_version()}.{Gtk.get_minor_version()}.{Gtk.get_micro_version()}, PyGObject {gi.__version__}, Pango {Pango.version_string()}, Python {sys.version.split()[0]}"))
        box.append(license_view)
        buttons=Gtk.Box(spacing=10,halign=Gtk.Align.END); box.append(buttons)
        buttons.append(self.button("Copy version details",lambda *_: window.get_clipboard().set(self.details())))
        close=self.button("Close",lambda *_: window.close()); buttons.append(close)
        keys=Gtk.EventControllerKey()
        keys.connect("key-pressed",lambda _c,key,*_: key==Gdk.KEY_Escape and (window.close() or True))
        window.add_controller(keys)
        keys=Gtk.EventControllerKey(); keys.connect("key-pressed",self.quit_key); window.add_controller(keys)
        def closed(*_):
            self.about_window=None; return False
        window.connect("close-request",closed); window.present(); close.grab_focus()

    def small_window(self,attribute,title,width=520,height=-1):
        """A small window like Languages & offline libraries: Esc closes it, Ctrl+Q still quits, and it scrolls on a small screen."""
        window=Gtk.Window(title=title,transient_for=self.window,modal=True,default_width=width,default_height=height)
        setattr(self,attribute,window)
        keys=Gtk.EventControllerKey(); keys.connect("key-pressed",self.quit_key); window.add_controller(keys)
        keys=Gtk.EventControllerKey(); keys.connect("key-pressed",lambda _c,key,*_: key==Gdk.KEY_Escape and (window.close() or True)); window.add_controller(keys)
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=12)
        for edge in ("top","bottom","start","end"): getattr(box,"set_margin_"+edge)(20)
        scroller=Gtk.ScrolledWindow(propagate_natural_height=True,max_content_height=640,hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroller.set_child(box); window.set_child(scroller)
        def closed(*_):
            setattr(self,attribute,None); return False
        window.connect("close-request",closed)
        return window,box

    def shortcuts_dialog(self,*_):
        if getattr(self,"shortcuts_window",None):
            self.shortcuts_window.present(); return
        window,box=self.small_window("shortcuts_window","Keyboard shortcuts",width=560)
        grid=Gtk.Grid(column_spacing=18,row_spacing=8); box.append(grid)
        for index,(keys,action) in enumerate(SHORTCUTS):
            label=Gtk.Label(label=keys,xalign=0,valign=Gtk.Align.START); label.add_css_class("dim-label"); grid.attach(label,0,index,1,1)
            grid.attach(Gtk.Label(label=action,xalign=0,wrap=True,max_width_chars=44,hexpand=True),1,index,1,1)
        close=self.button("Close",lambda *_: window.close()); close.set_halign(Gtk.Align.END); box.append(close)
        window.present(); close.grab_focus()

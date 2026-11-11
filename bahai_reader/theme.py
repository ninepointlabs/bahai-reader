"""Palettes, contrast checks and the stylesheet; the live Omarchy theme follow."""
import json
import os
import re
import subprocess
import shutil
import tomllib
from pathlib import Path

from .settings import CHROME_FONTS

def luminance(color):
    channels=[int(color[i:i+2],16)/255 for i in (1,3,5)]
    r,g,b=[c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4 for c in channels]
    return 0.2126*r+0.7152*g+0.0722*b

def contrast(first,second):
    # WCAG 2 contrast ratio between two #rrggbb colors.
    light,dark=sorted((luminance(first),luminance(second)),reverse=True)
    return (light+0.05)/(dark+0.05)

def readable(background,*candidates,minimum=4.5):
    # First candidate that meets the minimum on this background, else the strongest one.
    return next((c for c in candidates if contrast(c,background)>=minimum),max(candidates,key=lambda c:contrast(c,background)))

def stylesheet(colors,prefs):
    """The app's CSS for a palette and the reading settings. Plain text, so it can be checked without a display."""
    bg,fg,accent,selection=[colors[k] for k in ("background","foreground","accent","selection")]
    # Some themes (White) use an accent too close to the selection for text on it.
    current=readable(selection,accent,fg); focus=readable(bg,accent,fg,minimum=3); accent_text=readable(bg,accent,fg); current_focus=readable(selection,fg,accent,minimum=3)
    on_accent=readable(accent,bg,fg,"#ffffff","#000000")
    font=str(prefs.get("font","DejaVu Serif")).replace('"','').replace('\\','')
    size=int(prefs.get("size",22))
    chrome=CHROME_FONTS.get(prefs.get("chrome_font","System"))
    # The interface follows the desktop's own (proportional) font unless monospace is asked for; the reading font is set on its own below.
    chrome_rule=f"window, popover, tooltip {{ font-family: {chrome}; }}\n" if chrome else ""
    return chrome_rule+f'''window, textview, textview text {{ background: {bg}; color: {fg}; }}
headerbar, popover contents, list, row, entry, button, combobox {{ background: {bg}; color: {fg}; }}
/* The GTK theme paints .sidebar itself; keep the contents list on the reading palette. */
.sidebar, .sidebar scrolledwindow, .sidebar viewport, .sidebar expander {{ background: {bg}; color: {fg}; }}
/* Soft, quiet controls: small radii, a light fill instead of a box, and one primary style. */
button {{ border: 1px solid transparent; border-radius: 6px; padding: 6px 12px; background: alpha({fg},0.07); box-shadow: none; }}
button:hover {{ background: alpha({fg},0.13); }}
headerbar button, button.flat, .toc-passage {{ background: transparent; }}
headerbar button:hover, button.flat:hover, .toc-passage:hover {{ background: alpha({fg},0.08); }}
button.primary {{ background: {accent}; color: {on_accent}; }}
button.primary:hover {{ background: shade({accent},1.08); }}
button.primary:disabled {{ background: alpha({fg},0.07); color: alpha({fg},0.5); }}
entry {{ border: 1px solid {selection}; border-radius: 6px; box-shadow: none; }}
.toc-passage {{ border: none; padding: 8px; }}
.toc-branch > title {{ min-height: 32px; padding: 6px 0; }}
.toc-passage {{ min-height: 28px; }}
button.current-passage {{ color: {current}; background: {selection}; }}
row:selected, button:checked {{ background: {selection}; }}
button:focus-visible, .toc-branch > title:focus-visible, row:focus-visible {{ outline: 2px solid {focus}; outline-offset: -2px; }}
button.current-passage:focus-visible {{ outline-color: {current_focus}; }}
.switcher, .switcher row {{ background: transparent; }}
.switcher row {{ border-radius: 6px; padding: 7px 8px; min-height: 22px; }}
.switcher row:hover {{ background: alpha({fg},0.08); }}
.switcher row:selected {{ background: {selection}; color: {current}; }}
/* A hairline between the panes, not a bar. */
paned > separator {{ min-width: 1px; margin: 0; padding: 0; border: none; background: {selection}; background-image: none; }}
paned > separator:hover {{ background: {accent}; }}
headerbar {{ border-bottom: 1px solid {selection}; box-shadow: none; }}
.app-title {{ font-weight: bold; }}
.heading {{ color: {accent_text}; font-size: 19px; font-weight: bold; }}
/* Allow room for hinted glyphs and accents at fractional display scales. */
label {{ padding-top: 2px; padding-bottom: 2px; }}
.dim-label {{ opacity: 0.7; font-size: 13px; min-height: 18px; padding-top: 3px; padding-bottom: 3px; }}
.count {{ font-feature-settings: "tnum"; }}
textview {{ font-family: "{font}"; font-size: {size}px; }}
textview text selection {{ background: {selection}; }}
/* The reading footer: a divider, with the text fading out just above it rather than running under it. */
.reading-footer {{ border-top: 1px solid {selection}; padding-top: 10px; }}
.reading-fade {{ background: linear-gradient(to bottom, alpha({bg},0), {bg}); }}
.today-card {{ border: 1px solid {selection}; border-radius: 12px; padding: 16px 18px; }}
.today-large {{ font-family: "{font}"; font-size: {size+4}px; color: {accent_text}; }}
.today-reading {{ font-family: "{font}"; font-size: {max(15,size-4)}px; }}
.toc-date {{ padding: 8px; }}
.today-card flowboxchild {{ padding: 0; }}
.counter-count {{ font-family: "{font}"; font-size: 96px; }}
.counter-done {{ color: {accent_text}; }}
.counter-button {{ padding: 14px 48px; }}
.notice {{ background: {selection}; color: {fg}; padding: 8px 16px; border-bottom: 1px solid {accent}; }}'''


class ThemeMixin:
    """Reader methods: palettes, contrast checks and the stylesheet; the live Omarchy theme follow."""
    def theme_tick(self):
        # A hidden window in the background has nothing to repaint.
        if self.window.get_visible(): self.apply_theme()
        return True

    def apply_theme(self):
        mode=self.prefs.get("theme","Omarchy"); colors={}
        if mode=="Omarchy":
            states=[os.environ.get("HOST_XDG_STATE_HOME"),os.environ.get("XDG_STATE_HOME"),Path.home()/".local/state"]
            paths=[Path(state)/"omarchy/current/theme/colors.toml" for state in states if state]+[Path.home()/".config/omarchy/current/theme/colors.toml"]
            for path in paths:
                try:
                    source=path.read_text()
                    if source != self.palette_source:
                        colors=tomllib.loads(source)
                        if shutil.which("omarchy"):
                            try:
                                resolved=subprocess.run(["omarchy","theme","color","--file",str(path),"--all"],capture_output=True,text=True,timeout=3,check=True)
                                colors.update(dict(line.split("\t",1) for line in resolved.stdout.splitlines() if "\t" in line))
                            except (OSError,subprocess.SubprocessError): pass
                        self.palette_source=source; self.resolved_colors=colors
                    colors=self.resolved_colors
                    break
                except (OSError,ValueError): pass
        base={"background":"#161b19","foreground":"#e6e1d3","accent":"#c9ab70","selection":"#303b35"}
        if mode=="Light": base.update(background="#fafaf7",foreground="#252b27",accent="#45654c",selection="#e2e9df")
        if mode=="Sepia": base.update(background="#f2e9d7",foreground="#463c2f",accent="#7e5d28",selection="#e2d4b9")
        base.update({k:v for k,v in colors.items() if k in base and isinstance(v,str) and re.fullmatch(r"#[0-9a-fA-F]{6}",v)})
        signature=json.dumps([base,self.prefs],sort_keys=True)
        if signature==self.signature:return True
        self.signature=signature; bg,fg,accent,selection=[base[k] for k in ("background","foreground","accent","selection")]
        # Some themes (White) use an accent too close to the selection for text on it.
        self.colors=dict(background=bg,foreground=fg,accent=accent,selection=selection,current=readable(selection,accent,fg))
        self.provider.load_from_data(stylesheet(self.colors,self.prefs).encode())
        for view in (self.reader,self.second):
            view.set_pixels_inside_wrap(int(self.prefs.get("spacing",8))); view.set_pixels_below_lines(14)
        self.fit_margins()
        return True

#!/usr/bin/python3
"""A quiet, native Linux reader for Bahá’í prayers and writings.

The app lives in the bahai_reader package beside this file. This module starts it and keeps the names that tests, packages
and launchers have always used: `import reader` still gives every function, constant and class, and setting a path such as
reader.STATE (as the tests do) changes it for the whole app."""
import sys
import types
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bahai_reader.config import *  # noqa: F401,F403
from bahai_reader.settings import *  # noqa: F401,F403
from bahai_reader.ui import *  # noqa: F401,F403
from bahai_reader.library import *  # noqa: F401,F403
from bahai_reader.search import *  # noqa: F401,F403
from bahai_reader.citations import *  # noqa: F401,F403
from bahai_reader.labels import *  # noqa: F401,F403
from bahai_reader.theme import *  # noqa: F401,F403
from bahai_reader.rendering import *  # noqa: F401,F403
from bahai_reader.desktop import *  # noqa: F401,F403
from bahai_reader.widgets import *  # noqa: F401,F403
from bahai_reader.contents import *  # noqa: F401,F403
from bahai_reader.reading import *  # noqa: F401,F403
from bahai_reader.saved import *  # noqa: F401,F403
from bahai_reader.reminders import *  # noqa: F401,F403
from bahai_reader.counter import *  # noqa: F401,F403
from bahai_reader.today import *  # noqa: F401,F403
from bahai_reader.about import *  # noqa: F401,F403
from bahai_reader.location import *  # noqa: F401,F403
from bahai_reader.languages import *  # noqa: F401,F403
from bahai_reader.app import *  # noqa: F401,F403

_MISSING=object()

class _Facade(types.ModuleType):
    """Setting a name here (reader.STATE=..., or patch.object(reader,"fetch_json",...) in the tests) sets it in every
    bahai_reader module that holds the same object, so the app sees the change wherever it looks the name up."""
    def __setattr__(self,name,value):
        old=self.__dict__.get(name,_MISSING)
        if old is not _MISSING:
            for module in [m for key,m in sys.modules.items() if key.startswith("bahai_reader.")]:
                if module.__dict__.get(name,_MISSING) is old: setattr(module,name,value)
        super().__setattr__(name,value)

sys.modules[__name__].__class__=_Facade

def usage():
    return (f"Usage: bahai-reader [--help | --version | --background]\n\n{TAGLINE}\n"
            "With no options it opens the reader window; a second launch shows the open window.\n\n"
            "Options:\n  -h, --help     Show this help and exit\n  --version      Show the version and exit\n"
            "  --background   Run reminders with no window; a later launch opens the window in the same process\n\n"
            f"Settings and saved passages: {short_path(STATE)}\nDownloaded languages: {short_path(LIBRARY)}\n"
            f"Support: {SUPPORT_EMAIL}")

def main(args):
    if args in (["-h"],["--help"]): print(usage()); return 0
    if args==["--version"]: print(f"{APP_NAME} {version()}"); return 0
    background=args==["--background"]
    if args and not background:
        print(f"bahai-reader: unknown option {args[0]!r}. Try bahai-reader --help.",file=sys.stderr); return 2
    # X11 WM_CLASS comes from the program name; match StartupWMClass and the Wayland app_id.
    GLib.set_prgname("org.bahai.Reader")
    app=Reader(background=background); app.can_restart=True
    if background:
        # Already running: nothing to do, and no window to open.
        try: app.register(None)
        except GLib.Error as exc:
            print(f"bahai-reader: {exc.message}",file=sys.stderr); return 1
        if app.get_is_remote(): return 0
    return app.run([sys.argv[0]])

if __name__=="__main__":
    sys.exit(main(sys.argv[1:]))

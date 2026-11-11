"""End to end: reminders keep the app running in the background, a new version is installed over it, and opening the app
then shows the new version (the same process restarts from the new files) instead of the one still running from before.
Run with xvfb-run -a dbus-run-session -- /usr/bin/python3 tests/update_ui.py (a private session bus: one instance only)."""
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def wait(condition,seconds,what):
    end=time.monotonic()+seconds
    while not condition():
        if time.monotonic()>end: raise AssertionError("timed out: "+what)
        time.sleep(0.2)

def arguments(pid):
    try: return Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")[:-1]
    except OSError: return None

with tempfile.TemporaryDirectory() as temp:
    temp=Path(temp); app=temp/"app"
    # An installed copy of the app, as a package puts it in /usr/share/bahai-reader.
    app.mkdir(); shutil.copytree(ROOT/"bahai_reader",app/"bahai_reader",ignore=shutil.ignore_patterns("__pycache__")); shutil.copytree(ROOT/"data",app/"data")
    for name in ("reader.py","badi.py"): shutil.copy(ROOT/name,app/name)
    (app/"VERSION").write_text("9.9.0\n")
    env=dict(os.environ,XDG_CONFIG_HOME=str(temp/"config"),XDG_DATA_HOME=str(temp/"data"),XDG_CACHE_HOME=str(temp/"cache"),XDG_STATE_HOME=str(temp/"state"))
    (temp/"config/bahai-reader").mkdir(parents=True); (temp/"config/bahai-reader/settings.json").write_text('{"keep_running":true}')
    log=open(temp/"background.log","w")
    background=subprocess.Popen([sys.executable,str(app/"reader.py"),"--background"],env=env,stderr=log,stdout=log)
    try:
        time.sleep(4); assert background.poll() is None, "the background instance did not stay up"
        # The update: new files on disk while it runs.
        (app/"VERSION").write_text("9.9.1\n")
        launch=subprocess.run([sys.executable,str(app/"reader.py")],env=env,timeout=60)
        assert launch.returncode==0, launch.returncode
        # The running instance became the new version, with a window: same process, started again without --background.
        wait(lambda:arguments(background.pid) is not None and b"--background" not in arguments(background.pid),30,"restart as the new version")
        assert background.poll() is None, "the restarted instance exited"
        log.flush(); text=(temp/"background.log").read_text()
        assert "9.9.1 was installed while 9.9.0 was running; restarting." in text, text[-500:]
        version=subprocess.run([sys.executable,str(app/"reader.py"),"--version"],env=env,capture_output=True,text=True).stdout.strip()
        assert version.endswith("9.9.1"), version
        print("Update UI test passed")
    finally:
        background.terminate()
        try: background.wait(10)
        except subprocess.TimeoutExpired: background.kill()

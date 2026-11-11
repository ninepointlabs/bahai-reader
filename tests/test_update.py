"""An update installed while the app runs is picked up: the next launch, or the next reminder tick with the window closed,
restarts the process from the new files. No display needed (os.execv is replaced)."""
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import reader

class Restart(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        for name,value in (("STATE",Path(self.temp.name)/"settings.json"),("LIBRARY",Path(self.temp.name)/"l"),("CACHE",Path(self.temp.name)/"c")):
            patcher=patch.object(reader,name,value); patcher.start(); self.addCleanup(patcher.stop)
        self.app=reader.Reader(); self.app.can_restart=True
    def installed(self,version):
        return patch("bahai_reader.app.version",lambda:version)
    def test_same_version_does_not_restart(self):
        self.assertEqual(self.app.started_version,reader.version())
        self.assertFalse(self.app.updated_on_disk())
    def test_a_new_version_on_disk_is_noticed(self):
        with self.installed("99.0.0"): self.assertTrue(self.app.updated_on_disk())
    def test_tests_and_unknown_versions_never_restart(self):
        with self.installed("99.0.0"):
            self.app.can_restart=False; self.assertFalse(self.app.updated_on_disk())
            self.app.can_restart=True; self.app.started_version="unknown"; self.assertFalse(self.app.updated_on_disk())
    def test_opening_it_again_restarts_with_a_window(self):
        with self.installed("99.0.0"), patch("os.execv") as execv:
            self.app.activate(self.app)
        execv.assert_called_once(); program,argv=execv.call_args[0]
        self.assertEqual(program,sys.executable); self.assertEqual(argv,[sys.executable,str(reader.ROOT/"reader.py")])
        self.assertIsNone(self.app.window, "the old version's window is not built first")
    def test_reminders_alone_restart_in_the_background(self):
        self.app.held=True
        with self.installed("99.0.0"), patch("os.execv") as execv, patch.object(self.app,"send_due_reminders"):
            self.app.tick()
        self.assertEqual(execv.call_args[0][1][-1],"--background")
    def test_without_an_update_nothing_restarts(self):
        self.app.held=True
        with patch("os.execv") as execv, patch.object(self.app,"send_due_reminders"): self.app.tick()
        execv.assert_not_called()

if __name__=="__main__": unittest.main()

"""Settings loading never blocks startup or loses saved passages (no display needed)."""
import contextlib
import io
import json
import os
import tempfile
import unittest
import urllib.error
from pathlib import Path
import reader

class SettingsTests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        self.path=Path(temp.name)/"settings.json"

    def test_missing_file_is_quiet(self):
        self.assertEqual(reader.load_settings(self.path),({},None))

    def test_wrong_types_fall_back_and_keep_the_rest(self):
        self.path.write_text(json.dumps({"size":"abc","spacing":None,"margin":True,"language":"4","theme":"Neon","section":"bogus","saved":["prayers:1",7],"expanded":[],"font":3}))
        prefs,notice=reader.load_settings(self.path)
        self.assertIsNone(notice)
        self.assertEqual(prefs,{"saved":["prayers:1"],"expanded":{}})

    def test_numbers_are_clamped_to_the_sliders(self):
        prefs=reader.clean_settings({"size":900,"spacing":-5,"margin":1e9,"sidebar_width":3,"language":4,"section":"gleanings"})
        self.assertEqual(prefs,{"size":36,"spacing":0,"margin":160,"sidebar_width":220,"language":4,"section":"writings"})
        self.assertEqual(reader.clean_settings({"size":float("nan")}),{})

    def test_not_an_object_is_set_aside(self):
        self.path.write_text("[]")
        prefs,notice=reader.load_settings(self.path)
        self.assertEqual(prefs,{})
        self.assertIn("settings.json.bad",notice)
        self.assertEqual((self.path.parent/"settings.json.bad").read_text(),"[]")

    def test_invalid_json_keeps_saved_passages_in_a_backup(self):
        broken='{"saved":["prayers:258","hidden:1"],"la'
        self.path.write_text(broken)
        prefs,notice=reader.load_settings(self.path)
        self.assertEqual(prefs,{})
        self.assertFalse(self.path.exists())
        self.assertEqual((self.path.parent/"settings.json.bad").read_text(),broken)
        self.assertIn("saved passages",notice)

    @unittest.skipIf(os.geteuid()==0,"root ignores permissions")
    def test_unreadable_file_is_left_alone(self):
        self.enterContext(contextlib.redirect_stderr(io.StringIO()))
        self.path.write_text('{"saved":["prayers:1"]}'); self.path.chmod(0)
        self.addCleanup(self.path.chmod,0o600)
        prefs,notice=reader.load_settings(self.path)
        self.assertEqual(prefs,{})
        self.assertIn("could not be read",notice)
        self.assertTrue(self.path.exists())

    def test_download_problems_are_plain_language(self):
        self.enterContext(contextlib.redirect_stderr(io.StringIO()))
        offline=reader.download_problem(urllib.error.URLError(ConnectionRefusedError(111,"Connection refused")))
        self.assertEqual(offline,"Could not reach bahaiprayers.net. Check your connection and try again.")
        self.assertNotIn("Errno",reader.download_problem(ValueError("Unexpected language or content format")))
        self.assertIn("No space left",reader.download_problem(OSError(28,"No space left on device")))

    def test_command_line(self):
        self.enterContext(contextlib.redirect_stdout(io.StringIO())); self.enterContext(contextlib.redirect_stderr(io.StringIO()))
        self.assertEqual(reader.main(["--version"]),0)
        self.assertEqual(reader.main(["--help"]),0)
        self.assertEqual(reader.main(["--nope"]),2)

if __name__=="__main__": unittest.main()

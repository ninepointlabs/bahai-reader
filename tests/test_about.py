"""The About dialog's facts (no display needed)."""
import unittest
import reader

class AboutTests(unittest.TestCase):
    def test_version_comes_from_version_file(self):
        self.assertEqual(reader.version(),(reader.ROOT/"VERSION").read_text().strip())

    def test_facts_agree_with_the_license(self):
        license_text=(reader.ROOT/"LICENSE").read_text()
        self.assertTrue(license_text.startswith(reader.LICENSE_NAME))
        self.assertIn(reader.COPYRIGHT.replace("©","Copyright (c)"),license_text)
        self.assertEqual(reader.shipped("LICENSE","licenses/bahai-reader/LICENSE"),reader.ROOT/"LICENSE")
        self.assertIsNotNone(reader.shipped("DATA-NOTICE.md"))
        self.assertIsNotNone(reader.shipped("packaging/org.bahai.Reader.svg"))
        self.assertEqual(reader.SUPPORT_EMAIL,"help@ninepointlabs.com")
        self.assertEqual(reader.ORGANIZATION,"Nine Point Labs")

if __name__=="__main__": unittest.main()

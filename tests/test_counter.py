"""The Alláh-u-Abhá counter's rules, and its verse in the bundled Aqdas (no display needed)."""
import unittest
import badi
import reader

class CounterTests(unittest.TestCase):
    def test_counts_up_to_the_target_and_stops(self):
        counter=badi.Counter(3)
        self.assertEqual(str(counter),"0 of 3")
        self.assertTrue(counter.add() and counter.add() and counter.add()); self.assertTrue(counter.done); self.assertEqual(str(counter),"3 of 3")
        self.assertFalse(counter.add()); self.assertEqual(counter.count,3)
    def test_undo_and_reset(self):
        counter=badi.Counter()
        self.assertFalse(counter.undo())
        counter.add(); counter.add(); self.assertTrue(counter.undo()); self.assertEqual(counter.count,1)
        counter.reset(); self.assertEqual(counter.count,0)
    def test_targets(self):
        self.assertEqual(badi.Counter().target,95); self.assertEqual(badi.Counter.PRESETS,(95,19,9))
        counter=badi.Counter()
        self.assertTrue(counter.set_target("19")); self.assertEqual(counter.target,19)
        for bad in ("",0,-1,"abc",True,10000,1.5,None): self.assertFalse(counter.set_target(bad),bad); self.assertEqual(counter.target,19)
        self.assertEqual(badi.Counter("nonsense").target,95)
    def test_lowering_the_target_keeps_the_count_within_it(self):
        counter=badi.Counter(95)
        for _ in range(20): counter.add()
        counter.set_target(9); self.assertEqual(str(counter),"9 of 9")
    def test_milestones_are_every_nineteenth_and_the_target(self):
        counter=badi.Counter(95); spoken=[]
        for _ in range(95):
            counter.add()
            if counter.milestone: spoken.append(counter.count)
        self.assertEqual(spoken,[19,38,57,76,95])
        counter=badi.Counter(9); spoken=[]
        for _ in range(9):
            counter.add()
            if counter.milestone: spoken.append(counter.count)
        self.assertEqual(spoken,[9])
    def test_a_bad_saved_target_is_dropped_and_the_rest_kept(self):
        self.assertEqual(reader.clean_settings({"counter_target":19,"saved":[]}),{"counter_target":19,"saved":[]})
        for bad in ("19",0,True,99999,None): self.assertEqual(reader.clean_settings({"counter_target":bad,"saved":[]}),{"saved":[]},bad)

class VerseTests(unittest.TestCase):
    def test_paragraph_18_is_the_verse_on_ninety_five_times(self):
        item=next(i for i in reader.load_library() if i["id"]=="aqdas:Paragraphs:18")
        self.assertIn("Alláh-u-Abhá",item["text"]); self.assertIn("ninety-five times",item["text"])
        self.assertEqual(item["citation"],"Bahá’u’lláh, The Kitáb-i-Aqdas, ¶18. Copyright © Bahá’í International Community, bahai.org")
        # The counter shows the verse without bahai.org's margin number.
        self.assertTrue(reader.unnumbered(item).startswith("It hath been ordained that every believer in God"))

if __name__=="__main__": unittest.main()

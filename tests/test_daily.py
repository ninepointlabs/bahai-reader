"""Passage of the day and random passages work offline from the loaded library (no display needed)."""
import datetime
import unittest
import reader

class DailyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.items=reader.load_library()
        cls.pool=reader.reflections(cls.items)

    def test_pool_is_short_reflective_passages(self):
        books={b for i in self.pool for b in i["tags"] if i["section"]=="writings"}
        self.assertEqual(books,{reader.BOOKS["gleanings"],reader.BOOKS["meditations"]})
        self.assertTrue({"prayers","hidden"}<={i["section"] for i in self.pool})
        self.assertTrue(all(i["word_count"]<=reader.REFLECTION_WORDS for i in self.pool))
        self.assertGreater(len(self.pool),500)

    def test_same_passage_all_day_and_a_new_one_each_day(self):
        day=datetime.date(2026,10,30)
        today=reader.passage_of_the_day(self.items,day)
        self.assertIs(reader.passage_of_the_day(list(reversed(self.items)),day),today)  # independent of load order
        days=[reader.passage_of_the_day(self.items,day+datetime.timedelta(n)) for n in range(len(self.pool))]
        self.assertTrue(all(a is not b for a,b in zip(days,days[1:])))
        self.assertEqual(len({i["id"] for i in days}),len(self.pool))  # every passage once before any repeats

    def test_known_day_is_stable_across_releases(self):
        # The order must not depend on Python's hash seed or the machine.
        self.assertEqual(reader.passage_of_the_day(self.items,datetime.date(2026,10,30))["id"],EXPECTED)

    def test_empty_library(self):
        self.assertIsNone(reader.passage_of_the_day([],datetime.date.today()))

EXPECTED="prayers:321"

if __name__=="__main__": unittest.main()

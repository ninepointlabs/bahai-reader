"""The reading pane's heading says what the passage is (no display needed)."""
import unittest
import reader

def item(id,title,section="other",tags=()): return {"id":id,"title":title,"section":section,"tags":list(tags)}

class HeadingTests(unittest.TestCase):
    def test_prayers(self):
        self.assertEqual(reader.heading(item("prayers:1","Anything","prayers")),"Prayer")
    def test_hidden_words_by_origin(self):
        self.assertEqual(reader.heading(item("hidden:1","1 · O SON OF SPIRIT!",tags=["From the Arabic"])),"Arabic no. 1")
        self.assertEqual(reader.heading(item("hidden:80","9 · O SON OF DUST!",tags=["From the Persian"])),"Persian no. 9")
    def test_a_library_with_other_tags_is_not_guessed(self):
        self.assertEqual(reader.heading(item("hidden:1","1 · Oh hijo",tags=["Del árabe"])),"1")
    def test_aqdas_parts(self):
        self.assertEqual(reader.heading(item("aqdas:Paragraphs:4","4 · text")),"Paragraph 4")
        self.assertEqual(reader.heading(item("aqdas:QAs:83","83 · text")),"Question and Answer 83")
        self.assertEqual(reader.heading(item("aqdas:Notes:5","5 · text")),"Note 5")
    def test_other_books_keep_their_number(self):
        self.assertEqual(reader.heading(item("gleanings:12","12 · text")),"12")

if __name__=="__main__": unittest.main()

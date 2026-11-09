"""Copying a passage brings its citation along (no display needed)."""
import unittest
import reader

class ClippingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.items={i["id"]:i for i in reader.load_library()}

    def test_hidden_word_names_the_book_and_number(self):
        item=self.items["hidden:1"]
        text=reader.clipping(item)
        self.assertTrue(text.startswith(item["text"]))
        # bahai.org's text, so the notice its terms ask for follows the reference.
        self.assertTrue(text.endswith("\n\n— Bahá’u’lláh, The Hidden Words, Arabic no. 1. Copyright © Bahá’í International Community, bahai.org"),text[-80:])

    def test_aqdas_paragraph_and_gleanings_section(self):
        # bahai.org's text carries its notice after the reference.
        notice=lambda item:". Copyright © Bahá’í International Community, bahai.org" if item.get("official_id") else ""
        aqdas,gleaning=self.items["aqdas:Paragraphs:6"],self.items["gleanings:1"]
        self.assertTrue(reader.clipping(aqdas).endswith("— Bahá’u’lláh, The Kitáb-i-Aqdas, ¶6"+notice(aqdas)))
        self.assertTrue(reader.clipping(gleaning).endswith("— Bahá’u’lláh, Gleanings from the Writings of Bahá’u’lláh, I"+notice(gleaning)))

    def test_prayer_names_author_and_book(self):
        # bahai.org's text names the book it was taken from, then bahai.org's notice.
        self.assertTrue(reader.clipping(self.items["prayers:391"]).endswith("— Bahá’u’lláh, Bahá’í Prayers. Copyright © Bahá’í International Community, bahai.org"))
        self.assertTrue(reader.clipping(self.items["prayers:6344"]).endswith("— Bahá’u’lláh, Gleanings from the Writings of Bahá’u’lláh. Copyright © Bahá’í International Community, bahai.org"))

    def test_prayer_without_official_text_names_author_and_category(self):
        item=self.items["prayers:354"]  # keeps the BahaiPrayers.net copy
        self.assertTrue(reader.clipping(item).endswith("\n\n— Bahá’u’lláh, Prayers, Unity"))

    def test_selection_keeps_the_citation_once(self):
        item=self.items["hidden:1"]
        words=" ".join(item["text"].split()[:4])
        self.assertEqual(reader.clipping(item,words),words+"\n\n— "+item["citation"])
        # Selecting down into the citation line does not repeat it.
        self.assertEqual(reader.clipping(item,item["text"]+"\n\n— "+item["citation"]),reader.clipping(item))
        self.assertEqual(reader.clipping(item,"— "+item["citation"]),reader.clipping(item))

    def test_no_citation_copies_the_text_alone(self):
        item=dict(self.items["hidden:1"],citation="",section="hidden")
        self.assertEqual(reader.clipping(item),item["text"])

if __name__=="__main__": unittest.main()

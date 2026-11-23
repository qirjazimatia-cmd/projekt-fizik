"""Prova për rojën e gjuhës shqipe: `python3 -m unittest Tests/test_check_shqip.py`."""
import pathlib, sys, unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_shqip as c  # noqa: E402


def swift(kod):
    return c.kontrollo_swift(kod, "X.swift", set())


class RojaSwift(unittest.TestCase):
    def test_kap_fjali_angleze(self):
        self.assertTrue(swift('Text("Something went wrong, please try again")'))
        self.assertTrue(swift('let m = "You are not allowed to open this class"'))

    def test_kap_titull_anglisht_ne_buton(self):
        self.assertTrue(swift('Button("Cancel") { }'))
        self.assertTrue(swift('.navigationTitle("Settings")'))

    def test_lejon_shqipen(self):
        self.assertEqual(swift('Text("Diçka shkoi keq, provo përsëri")'), [])
        self.assertEqual(swift('Button("Anulo") { }'), [])
        self.assertEqual(swift('Text("Klasa e \\(emri) është gati")'), [])

    def test_anashkalon_kodin_jo_te_perdoruesit(self):
        self.assertEqual(swift('// Text("This is only a comment for you")'), [])
        self.assertEqual(swift('print("loading the user profile from cache")'), [])
        self.assertEqual(swift('let url = "https://example.com/the/and/for"'), [])
        self.assertEqual(swift('let key = "settings"'), [])  # identifikues, jo titull

    def test_emri_i_produktit(self):
        self.assertTrue(swift('ShareLink(item: "ScienceQuest · kodi")'))
        self.assertTrue(swift('Text("Mirë se erdhe te Don Bosko Connect")'))
        self.assertEqual(swift('Text("Mirë se erdhe te BrainSpark")'), [])

    def test_lista_e_lejimeve(self):
        self.assertEqual(c.kontrollo_swift('let x = "saving new user"', "X.swift", {"saving new user"}), [])


class RojaFaqet(unittest.TestCase):
    def faqe(self, trupi, lang="sq"):
        return c.kontrollo_faqe(f'<!DOCTYPE html><html lang="{lang}"><body>{trupi}</body></html>', "x.html", set())

    def test_kerkon_lang_sq(self):
        self.assertTrue(self.faqe("<p>Mirë se erdhe</p>", lang="en"))

    def test_kap_paragraf_anglisht(self):
        self.assertTrue(self.faqe("<p>Delete your account in the app settings</p>"))

    def test_lejon_pjesen_e_shenuar_lang_en(self):
        self.assertEqual(self.faqe('<div lang="en"><p>Delete your account in the app settings</p></div>'
                                   '<p>Fshi llogarinë · <span lang="en">Delete your account</span></p>'), [])

    def test_anashkalon_skriptin(self):
        self.assertEqual(self.faqe('<script>const m = "Could not send the code to your email";</script><p>Gati</p>'), [])

    def test_marka_jo_emri_github(self):
        self.assertTrue(self.faqe("<footer>qirjazimatia-cmd</footer>"))


class RojaRepo(unittest.TestCase):
    def test_repo_kalon(self):
        self.assertEqual(c.main(), 0)


if __name__ == "__main__":
    unittest.main()

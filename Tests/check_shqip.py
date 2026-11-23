#!/usr/bin/env python3
"""Roja e gjuhës shqipe (kontroll statik, pa rrjet).

BrainSpark është në shqip. Ky kontroll dështon nëse në tekstet që sheh përdoruesi futet
anglisht pa dashje, ose nëse emri i produktit nuk është BrainSpark. Kontrollon:
  1. vargjet në Swift (App/, Watch/, Widgets/) që duken fjali angleze;
  2. faqet publike në docs/ (lang="sq"; privacy.html është anglisht me qëllim, për App Review);
  3. tekstet e lejeve (INFOPLIST_KEY_*Usage*), gjuhën bazë (sq) dhe emrin BrainSpark;
  4. rregullin «Përgjigju gjithmonë në shqip» te Bosko AI.

Përjashtimet e qëllimshme shkruhen te Tests/shqip_lejohen.txt (një varg për rresht).
`python3 Tests/check_shqip.py` → PASS ose lista e gabimeve me skedar:rresht.
"""
import pathlib, re, sys
from html.parser import HTMLParser

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Fjalë angleze që nuk ekzistojnë si fjalë shqipe (për të mos ngatërruar «me», «do», «per», «e»…).
ANGLISHT = set("""the and you your yours please error errors settings loading saving save cancel delete deleted done
close back next continue sign login logout password account invalid failed failure try again search add edit
remove open share welcome start profile message messages send new today week class classes student students teacher
teachers parent parents lesson lessons home friends friend help about privacy policy contact unknown required optional
create update select choose is are was were not with for from this that it to of in on at be have has will can could
should would there their what which when where who how all any some more most other into than then them these those
our we my your our something went wrong retry network connection offline online upload download file files settings
notifications notification allow deny tap here click learn view show hide sorry yet no""".split())
# Fjalë që tregojnë qartë shqip.
SHQIP = set("""dhe të një për me në nuk që është janë ose nga si ju jo po ke kemi do mund ti unë ka kanë
kjo ky këtu tani shih hap mbyll ruaj fshi provo gabim llogari mësim mësimet nxënës mësues prind klasa""".split())
# Fjalë të vetme angleze të zakonshme si titull butoni/ekrani.
UI_TEK = set("""settings cancel delete save done close back next continue search loading error retry share edit
remove open login logout profile home friends lessons help about privacy contact welcome submit send ok""".split())
UI_KONTEKST = re.compile(r"\b(?:Text|Button|Label|navigationTitle|Section|Toggle|TextField|SecureField|Picker|alert|"
                         r"confirmationDialog|ContentUnavailableView|accessibilityLabel|accessibilityHint|help)\s*\(\s*$")
EMRI_I_VJETER = re.compile(r"\b(Don Bosko Connect|ScienceQuest|Science Quest)\b")
ZHVILLUES = re.compile(r"\b(print|debugPrint|fatalError|assert|assertionFailure|precondition|preconditionFailure|"
                       r"Logger|os_log|NSLog)\s*\(")


def lejohen():
    p = ROOT / "Tests/shqip_lejohen.txt"
    if not p.exists():
        return set()
    return {l.strip() for l in p.read_text(encoding="utf-8").splitlines() if l.strip() and not l.startswith("#")}


def vargjet(rresht):
    """Kthen (pozicioni, teksti) për çdo varg "..." në një rresht Swift, pa komentet //."""
    out, i, n = [], 0, len(rresht)
    while i < n:
        c = rresht[i]
        if c == "/" and rresht[i:i + 2] == "//":
            break
        if c == '"':
            if rresht[i:i + 3] == '"""':
                break  # vargjet shumërreshtëshe nuk kontrollohen
            j, buf = i + 1, []
            while j < n and rresht[j] != '"':
                if rresht[j] == "\\" and j + 1 < n:
                    if rresht[j + 1] == "(":  # interpolim \( … )
                        thellesi, j = 1, j + 2
                        while j < n and thellesi:
                            thellesi += {"(": 1, ")": -1}.get(rresht[j], 0)
                            j += 1
                        buf.append(" ")
                        continue
                    buf.append(rresht[j:j + 2]); j += 2; continue
                buf.append(rresht[j]); j += 1
            out.append((i, "".join(buf)))
            i = j + 1
            continue
        i += 1
    return out


def fjalet(tekst):
    return re.findall(r"[a-zëç']+", tekst.lower())


def duket_anglisht(tekst):
    """Fjali: ≥2 fjalë angleze, ≥40% e fjalëve, pa asnjë shenjë shqipe."""
    if re.search(r"[ëçËÇ]", tekst) or "://" in tekst:
        return False
    w = fjalet(tekst)
    if len(w) < 2:
        return False
    en = [x for x in w if x in ANGLISHT]
    return len(en) >= 2 and len(en) / len(w) >= 0.4 and not any(x in SHQIP for x in w)


def kontrollo_swift(tekst, emri, lejo):
    gabime = []
    for nr, rresht in enumerate(tekst.splitlines(), 1):
        if ZHVILLUES.search(rresht):
            continue
        for poz, s in vargjet(rresht):
            if s in lejo:
                continue
            if EMRI_I_VJETER.search(s) and " " in s:
                gabime.append(f"{emri}:{nr}: emri i produktit duhet të jetë BrainSpark: \"{s}\"")
            elif " " in s.strip() and duket_anglisht(s):
                gabime.append(f"{emri}:{nr}: tekst anglisht: \"{s}\"")
            elif s.strip().lower() in UI_TEK and UI_KONTEKST.search(rresht[:poz]):
                gabime.append(f"{emri}:{nr}: titull anglisht: \"{s}\"")
    return gabime


class _Faqja(HTMLParser):
    """Mbledh tekstin e dukshëm; anashkalon <script>, <style> dhe çdo element me lang="en"
    (pjesët angleze të qëllimshme për App Review, të shënuara siç duhet edhe për lexuesit e ekranit)."""
    BOSH = {"br", "img", "input", "meta", "link", "hr", "source", "wbr"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stiva, self.tekste = [], []

    def handle_starttag(self, tag, attrs):
        if tag in self.BOSH:
            return
        a = dict(attrs)
        jashte = tag in ("script", "style") or (tag != "html" and (a.get("lang") or "").lower().startswith("en"))
        self.stiva.append((tag, jashte or (self.stiva[-1][1] if self.stiva else False)))

    def handle_endtag(self, tag):
        for i in range(len(self.stiva) - 1, -1, -1):
            if self.stiva[i][0] == tag:
                del self.stiva[i:]
                break

    def handle_data(self, data):
        if data.strip() and not (self.stiva and self.stiva[-1][1]):
            self.tekste.append(" ".join(data.split()))


def tekst_i_dukshem(faqe):
    f = _Faqja()
    f.feed(faqe)
    return f.tekste


def kontrollo_faqe(faqe, emri, lejo):
    gabime = []
    if not re.search(r'<html[^>]*\blang="sq"', faqe):
        gabime.append(f"{emri}: faqja duhet të ketë <html lang=\"sq\">")
    for t in tekst_i_dukshem(faqe):
        if t in lejo:
            continue
        if duket_anglisht(t):
            gabime.append(f"{emri}: tekst anglisht: \"{t[:80]}\"")
        if "qirjazimatia" in t:
            gabime.append(f"{emri}: emri i përdoruesit GitHub nuk shfaqet si markë: \"{t[:80]}\"")
        if EMRI_I_VJETER.search(t):
            gabime.append(f"{emri}: emri i produktit duhet të jetë BrainSpark: \"{t[:80]}\"")
    return gabime


def main():
    lejo, gabime = lejohen(), []
    for dosja in ("App", "Watch", "Widgets"):
        for p in sorted((ROOT / dosja).glob("*.swift")):
            gabime += kontrollo_swift(p.read_text(encoding="utf-8"), p.relative_to(ROOT), lejo)
    for p in sorted((ROOT / "docs").glob("*.html")):
        if p.name == "privacy.html":  # versioni anglisht i politikës, me qëllim
            continue
        gabime += kontrollo_faqe(p.read_text(encoding="utf-8"), p.relative_to(ROOT), lejo)
    pbx = (ROOT / "ScienceQuest.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    if "developmentRegion = sq;" not in pbx:
        gabime.append("project.pbxproj: gjuha bazë duhet të jetë sq")
    for v in set(re.findall(r"INFOPLIST_KEY_CFBundleDisplayName = \"?([^;\"]+)\"?;", pbx)):
        if v != "BrainSpark":
            gabime.append(f"project.pbxproj: emri i app-it duhet të jetë BrainSpark, jo «{v}»")
    for k, v in set(re.findall(r"(INFOPLIST_KEY_\w*Usage\w*) = \"([^\"]*)\"", pbx)):
        if not (re.search(r"[ëç]", v) or any(x in SHQIP for x in fjalet(v))):
            gabime.append(f"project.pbxproj: {k} duhet të jetë në shqip: \"{v[:80]}\"")
    ai = (ROOT / "Supabase/functions/bosko-ai/index.ts").read_text(encoding="utf-8")
    if "Përgjigju gjithmonë në shqip" not in ai:
        gabime.append("bosko-ai: mungon rregulli «Përgjigju gjithmonë në shqip»")
    if gabime:
        print("\n".join("GABIM: " + g for g in gabime))
        print(f"\n{len(gabime)} probleme. Përkthe tekstin në shqip ose, nëse është i qëllimshëm, shtoje te Tests/shqip_lejohen.txt.")
        return 1
    print("PASS: tekstet e përdoruesit janë në shqip dhe emri është BrainSpark (kontroll statik).")
    return 0


if __name__ == "__main__":
    sys.exit(main())

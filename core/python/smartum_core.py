"""SmartumSwitch core (reference implementation): decides whether a word was typed in the wrong layout.
Data lives in core/data and core/dict; the same rules are implemented in C# (windows/SmartumSwitch.Core)."""
import ctypes, json, math, os, re

CORE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAYOUT = json.load(open(os.path.join(CORE, "data", "layout.json"), encoding="utf-8"))
RULES = json.load(open(os.path.join(CORE, "data", "rules.json"), encoding="utf-8"))
OTHER = {"en": "ru", "ru": "en"}
_LET = re.compile(r"[a-zA-Zа-яёА-ЯЁ]")

def is_letter(c):
    return bool(_LET.fullmatch(c))

def maps():
    L = LAYOUT
    e2r = dict(zip(L["en_lower"] + L["en_upper"], L["ru_lower"] + L["ru_upper"]))
    return e2r, {v: k for k, v in e2r.items()}

E2R, R2E = maps()

def retype(text, frm):
    """What the same keys give in the other layout."""
    m = E2R if frm == "en" else R2E
    return "".join(m.get(c, c) for c in text)

def core_word(s):
    return re.sub(r"^[^a-zA-Zа-яёА-ЯЁ]+|[^a-zA-Zа-яёА-ЯЁ]+$", "", s)

class Speller:
    def __init__(self):
        L = ctypes.CDLL("libhunspell-1.7.so.0")
        L.Hunspell_create.restype = ctypes.c_void_p
        L.Hunspell_create.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
        L.Hunspell_spell.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        d = os.path.join(CORE, "dict")
        self.L = L
        self.h = {lay: L.Hunspell_create(os.path.join(d, f + ".aff").encode(), os.path.join(d, f + ".dic").encode())
                  for lay, f in (("ru", "ru_RU"), ("en", "en_US"))}
    def ok(self, lay, w):
        return bool(self.L.Hunspell_spell(self.h[lay], w.encode()))

class Judge:
    def __init__(self, exceptions=(), words=()):
        self.sp = Speller()
        self.bg = json.load(open(os.path.join(CORE, "data", "bigrams.json"), encoding="utf-8"))
        self.short = {k: set(v) for k, v in RULES["short_words"].items()}
        self.exc = {w.lower() for w in exceptions}
        self.known = {k: set(v) for k, v in RULES["known_words"].items() if not k.startswith("_")}
        for w in words:  # user words (words.txt): valid in the layout of their letters
            w = w.strip().lower()
            if w:
                self.known["ru" if re.search(r"[а-яё]", w) else "en"].add(w)
    def valid(self, lay, w):
        return self.sp.ok(lay, w) or w.lower() in self.known[lay]
    def score(self, w, lay):
        b = self.bg[lay]; tot = b["tot"]; c = b["c"]; sm = RULES["bigram_smoothing"]
        w = "^" + w.lower() + "$"
        s = [math.log((c.get(x + y, 0) + sm) / tot) for x, y in zip(w, w[1:])]
        return sum(s) / len(s), min(s)
    def should_fix(self, disp, other, L, O):
        d, o = core_word(disp), core_word(other)
        if d.lower() in self.exc or o.lower() in self.exc or disp.lower() in self.exc:
            return False, "exception"
        nd = sum(map(is_letter, d)); no = sum(map(is_letter, o))
        if no < RULES["min_letters"] or no < nd:
            return False, "short"
        if not all(map(is_letter, o)):
            return False, "punct"
        if d and self.valid(L, d):
            return False, "valid"
        if no == 2:
            return (o.lower() in self.short[O] and d.lower() not in self.short[L]), "short2"
        if self.valid(O, o):
            return True, "dict"
        if no >= RULES["bigram_min_letters"] and d and all(map(is_letter, d)):
            sd = self.score(d, L); so = self.score(o, O)
            if (so[0] - sd[0] >= RULES["bigram_avg_margin"] and sd[1] <= RULES["bigram_displayed_min_max"]
                    and so[1] >= RULES["bigram_other_min_min"]):
                return True, "bigram"
        return False, "unsure"

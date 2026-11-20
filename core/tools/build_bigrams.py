#!/usr/bin/env python3
"""Build core/data/bigrams.json (letter-pair counts with word boundaries ^ $) from the bundled hunspell .dic stems."""
import collections, json, os, re
here = os.path.dirname(os.path.abspath(__file__)); core = os.path.dirname(here)
res = {}
for lay, fn, alpha in (("ru", "ru_RU.dic", r"[а-яё]+"), ("en", "en_US.dic", r"[a-z]+")):
    c = collections.Counter()
    with open(os.path.join(core, "dict", fn), encoding="utf-8", errors="ignore") as f:
        next(f)
        for l in f:
            w = l.split("/")[0].strip().lower()
            if w and re.fullmatch(alpha, w):
                w = "^" + w + "$"
                for a, b in zip(w, w[1:]):
                    c[a + b] += 1
    res[lay] = {"tot": sum(c.values()), "c": dict(sorted(c.items()))}
json.dump(res, open(os.path.join(core, "data", "bigrams.json"), "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
print({k: (v["tot"], len(v["c"])) for k, v in res.items()})

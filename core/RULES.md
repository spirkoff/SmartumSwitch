# SmartumSwitch core rules (shared by Linux, Windows, macOS)

Input: the keys of one word (physical key index 0..33 from `data/layout.json` + Shift flag), the layout it was
shown in (L = en|ru) and Caps Lock. `shown` = the keys rendered in L, `other` = the same keys rendered in O.

1. Exceptions (`exceptions.txt`, case-insensitive, either form) → keep.
2. Strip non-letters at both ends. If `other` has fewer than 2 letters, or fewer letters than `shown`
   (e.g. `ютуб` → `.ne,`) → keep. If `other` still contains inner non-letters → keep.
3. `shown` is a valid word in L (hunspell, or `known_words[L]`, or the user's `words.txt`) → keep.
4. Exactly 2 letters: fix only if `other` is in `short_words[O]` and `shown` is not in `short_words[L]`.
5. `other` is a valid word in O (hunspell, or `known_words[O]` — brands and IT terms like ChatGPT, GitHub —
   or the user's `words.txt`, compared case-insensitively) → **fix**.
6. ≥4 letters, `shown` letters only: bigram scores (avg and min of log((count+0.1)/total), with ^ $ boundaries).
   Fix if avg(other)−avg(shown) ≥ 1.5 and min(shown) ≤ −9.0 and min(other) ≥ −9.5.
7. Otherwise keep.

Thresholds are in `data/rules.json`; letter-pair counts in `data/bigrams.json` (rebuild: `tools/build_bigrams.py`).
Tests: `tests/cases.json` (182 words), run with `python3 tests/run_tests.py` and
`dotnet run --project windows/SmartumSwitch.Tests`. Every platform must pass all of them.
Privacy rule for all platforms: typed text is never logged or sent; only counters and errors.

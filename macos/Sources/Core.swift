// SmartumSwitch core for macOS (Swift) — same rules as core/RULES.md and core/python/smartum_core.py.
// Copyright (c) 2026 smARTum. MIT License. Foundation only, so it also builds and is tested on Linux.
import Foundation

enum Res {
    /// Folder with data/ and dict/ (inside the .app: Contents/Resources).
    nonisolated(unsafe) static var root: URL = Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
    static func json(_ name: String) -> [String: Any] {
        let url = root.appendingPathComponent("data").appendingPathComponent(name)
        guard let d = try? Data(contentsOf: url), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { fatalError("SmartumSwitch: cannot read \(name)") }
        return o
    }
}

enum RuVariant: String {
    /// "Russian - PC" (Windows JCUKEN): ` -> ё, / -> ., ? -> ,
    case pc
    /// Standard Apple "Russian": \ -> ё, ` -> ], / -> /, ? -> ?
    case mac
}

enum Text {
    static func isCyr(_ c: Character) -> Bool {
        guard let s = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        return (0x430...0x44F).contains(s.value) || (0x410...0x42F).contains(s.value) || s.value == 0x451 || s.value == 0x401
    }
    static func isLat(_ c: Character) -> Bool {
        guard let s = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        return (0x61...0x7A).contains(s.value) || (0x41...0x5A).contains(s.value)
    }
    static func isLetter(_ c: Character) -> Bool { isCyr(c) || isLat(c) }
    /// Strip non-letters at both ends.
    static func core(_ s: String) -> String {
        let a = Array(s)
        guard let f = a.firstIndex(where: isLetter), let l = a.lastIndex(where: isLetter) else { return "" }
        return String(a[f...l])
    }
}

/// The 34 keys that differ between US QWERTY and Russian JCUKEN (plus optional index 34 for Mac standard Russian `\` -> `ё`).
enum Layout {
    static let data = Res.json("layout.json")
    static let enLower = Array(data["en_lower"] as! String), enUpper = Array(data["en_upper"] as! String)
    static let ruLower = Array(data["ru_lower"] as! String), ruUpper = Array(data["ru_upper"] as! String)
    static let extraEn = Array(data["manual_extra_en"] as! String), extraRu = Array(data["manual_extra_ru"] as! String)
    /// macOS virtual key codes (kVK_ANSI_*) for the 34 keys.
    static let macKeyCodes: [Int] = (data["mac_keycodes"] as! [Any]).map { ($0 as! NSNumber).intValue }
    static let macYoIdx = 34
    static let macYoCode = 0x2A

    static func other(_ lay: String) -> String { lay == "en" ? "ru" : "en" }

    static func char(idx: Int, shift: Bool, lay: String, caps: Bool, ruVariant: RuVariant = .pc) -> Character {
        if idx == macYoIdx {
            if lay == "ru" {
                if ruVariant == .mac {
                    let u = caps ? !shift : shift
                    return u ? "Ё" : "ё"
                }
                return shift ? "/" : "\\"
            }
            return shift ? "|" : "\\"
        }
        if lay == "ru" && ruVariant == .mac {
            if idx == 0 { return shift ? "[" : "]" }
            if idx == 33 { return shift ? "?" : "/" }
        }
        let lo = lay == "ru" ? ruLower[idx] : enLower[idx]
        let up = lay == "ru" ? ruUpper[idx] : enUpper[idx]
        var u = shift
        if caps && Text.isLetter(lo) { u.toggle() }
        return u ? up : lo
    }

    static func render(_ keys: [(idx: Int, shift: Bool)], _ lay: String, caps: Bool, ruVariant: RuVariant = .pc) -> String {
        var s = ""
        for k in keys {
            s.append(char(idx: k.idx, shift: k.shift, lay: lay, caps: caps, ruVariant: ruVariant))
        }
        return s
    }

    /// Same keys in the other layout (tests): maps shown text char by char.
    static func retype(_ shown: String, from: String, ruVariant: RuVariant = .pc) -> String {
        var a = from == "en" ? enLower + enUpper : ruLower + ruUpper
        var b = from == "en" ? ruLower + ruUpper : enLower + enUpper
        if ruVariant == .mac {
            if from == "en" {
                let extraA: [Character] = ["\\", "|"]
                let extraB: [Character] = ["ё", "Ё"]
                let macOverride: [Character: Character] = ["`": "]", "~": "[", "/": "/", "?": "?"]
                return String(shown.map { c in
                    if let mc = macOverride[c] { return mc }
                    if let i = extraA.firstIndex(of: c) { return extraB[i] }
                    return a.firstIndex(of: c).map { b[$0] } ?? c
                })
            } else {
                let extraA: [Character] = ["ё", "Ё", "]", "["]
                let extraB: [Character] = ["\\", "|", "`", "~"]
                let macKeep: Set<Character> = ["/", "?"]
                // Map Russian letters/punct back to EN under Apple standard Russian
                var map = [Character: Character]()
                for (i, rc) in a.enumerated() { map[rc] = b[i] }
                for (i, rc) in extraA.enumerated() { map[rc] = extraB[i] }
                for kc in macKeep { map[kc] = kc }
                return String(shown.map { map[$0] ?? $0 })
            }
        }
        a = from == "en" ? enLower + enUpper : ruLower + ruUpper
        b = from == "en" ? ruLower + ruUpper : enLower + enUpper
        return String(shown.map { c in a.firstIndex(of: c).map { b[$0] } ?? c })
    }

    /// Manual fix: convert selected text typed in the wrong layout. Returns text and target layout.
    static func convert(_ text: String) -> (text: String, target: String) {
        let en = enLower + enUpper + extraEn, ru = ruLower + ruUpper + extraRu
        let cyr = text.filter(Text.isCyr).count, lat = text.filter(Text.isLat).count
        let toEn = cyr > lat
        let out = String(text.map { c -> Character in
            if toEn { return ru.firstIndex(of: c).map { en[$0] } ?? c }
            return en.firstIndex(of: c).map { ru[$0] } ?? c
        })
        return (out, toEn ? "en" : "ru")
    }
}

final class Speller {
    private var h: [String: OpaquePointer] = [:]
    init() {
        let dir = Res.root.appendingPathComponent("dict")
        for (lay, f) in [("ru", "ru_RU"), ("en", "en_US")] {
            let aff = dir.appendingPathComponent(f + ".aff").path, dic = dir.appendingPathComponent(f + ".dic").path
            guard FileManager.default.fileExists(atPath: aff), let p = Hunspell_create(aff, dic) else {
                fatalError("SmartumSwitch: cannot load dictionary \(f)")
            }
            h[lay] = p
        }
    }
    func ok(_ lay: String, _ w: String) -> Bool { Hunspell_spell(h[lay], w) != 0 }
}

final class Judge {
    let sp = Speller()
    private var bg: [String: (tot: Double, c: [String: Double])] = [:]
    private var short: [String: Set<String>] = [:]
    private let minLetters, bgMinLetters, margin, shownMinMax, otherMinMin, smooth: Double
    private let commonEn2Keep: Set<String>
    private static let short1Ru: Set<String> = ["и", "а", "в", "к", "с", "у", "о", "я"]
    private static let commonEn1: Set<String> = ["a", "i"]
    var exceptions = Set<String>()   // lower-case

    init() {
        for (lay, v) in Res.json("bigrams.json") {
            let o = v as! [String: Any]
            let c = (o["c"] as! [String: Any]).mapValues { ($0 as! NSNumber).doubleValue }
            bg[lay] = ((o["tot"] as! NSNumber).doubleValue, c)
        }
        let r = Res.json("rules.json")
        func num(_ k: String) -> Double { (r[k] as! NSNumber).doubleValue }
        minLetters = num("min_letters"); bgMinLetters = num("bigram_min_letters"); margin = num("bigram_avg_margin")
        shownMinMax = num("bigram_displayed_min_max"); otherMinMin = num("bigram_other_min_min"); smooth = num("bigram_smoothing")
        for (k, v) in r["short_words"] as! [String: [String]] { short[k] = Set(v) }
        short["ru", default: []].formUnion(["ее", "её"])
        commonEn2Keep = (short["en"] ?? []).union([
            "vs", "vk", "id", "ad", "ai", "tv", "pc", "pm", "uk", "ex", "cd",
            "hr", "ip", "os", "pr", "qa", "ui", "ux", "vr", "mr", "ms", "dr"
        ])
    }

    func valid(_ lay: String, _ w: String) -> Bool { sp.ok(lay, w) }

    func score(_ w: String, _ lay: String) -> (avg: Double, min: Double) {
        let b = bg[lay]!
        let a = Array("^" + w.lowercased() + "$")
        var sum = 0.0, mn = Double.greatestFiniteMagnitude
        for i in 0..<(a.count - 1) {
            let n = b.c[String(a[i]) + String(a[i + 1])] ?? 0
            let s = log((n + smooth) / b.tot); sum += s; mn = Swift.min(mn, s)
        }
        return (sum / Double(a.count - 1), mn)
    }

    func shouldFix(_ shown: String, _ other: String, _ L: String, _ O: String) -> (fix: Bool, why: String) {
        let sChars = Array(shown), oChars = Array(other)
        guard sChars.count == oChars.count else { return (false, "len") }
        let d = Text.core(shown), o = Text.core(other)
        if exceptions.contains(d.lowercased()) || exceptions.contains(o.lowercased())
            || exceptions.contains(shown.lowercased()) || exceptions.contains(other.lowercased()) {
            return (false, "exception")
        }
        if o.isEmpty || !o.allSatisfy(Text.isLetter) { return (false, "punct") }
        let nd = d.filter(Text.isLetter).count, no = o.count
        if nd == 0 || no < nd { return (false, "short") }

        guard let first = oChars.firstIndex(where: Text.isLetter),
              let last = oChars.lastIndex(where: Text.isLetter) else {
            return (false, "short")
        }
        let dRaw = String(sChars[first...last])

        // 1-letter common Russian prepositions/conjunctions/pronouns (en -> ru only, bare single letter)
        if no == 1 {
            if O == "ru" && L == "en" && sChars.count == 1 && nd == 1 {
                if Judge.short1Ru.contains(o.lowercased()) && !Judge.commonEn1.contains(d.lowercased()) {
                    return (true, "short1")
                }
            }
            return (false, "short")
        }

        let hasPunctLetter = !dRaw.allSatisfy(Text.isLetter)
        if hasPunctLetter {
            // Only en -> ru can turn EN punctuation keys (, . ; ' [ ] ` etc.) into RU letters
            guard L == "en" && O == "ru" else { return (false, "punct") }
            if valid("en", dRaw) { return (false, "valid") }
            // Preserve real trailing punctuation after a genuine English word (e.g. he, it. next.)
            if let f = dRaw.first, let l = dRaw.last, Text.isLetter(f), !Text.isLetter(l),
               !d.isEmpty, d.allSatisfy(Text.isLetter) {
                if d.count == 1 && Judge.commonEn1.contains(d.lowercased()) { return (false, "valid") }
                if d.count == 2 && commonEn2Keep.contains(d.lowercased()) { return (false, "valid") }
                if d.count >= 3 && valid("en", d) { return (false, "valid") }
            }
            // Preserve leading apostrophe + English word (e.g. 'he, 'at, 'as, 'a, 'hello)
            if dRaw.hasPrefix("'"), !d.isEmpty, d.allSatisfy(Text.isLetter) {
                if d.count == 1 && Judge.commonEn1.contains(d.lowercased()) { return (false, "valid") }
                if d.count == 2 && commonEn2Keep.contains(d.lowercased()) { return (false, "valid") }
                if d.count >= 3 && valid("en", d) { return (false, "valid") }
            }
            if no == 2 {
                return (short["ru"]!.contains(o.lowercased()), "short2")
            }
            if valid("ru", o) { return (true, "dict") }
            return (false, "unsure")
        }

        // Pure letters in dRaw (dRaw == d)
        if no == 2 {
            if O == "ru" && L == "en" {
                if short["ru"]!.contains(o.lowercased()) {
                    if commonEn2Keep.contains(d.lowercased()) { return (false, "valid") }
                    if d == d.uppercased() && d != d.lowercased() && valid("en", d) { return (false, "valid") }
                    if short["en"]!.contains(d.lowercased()) { return (false, "valid") }
                    return (true, "short2")
                }
                return (false, valid(L, d) ? "valid" : "short2")
            } else {
                if !d.isEmpty && valid(L, d) { return (false, "valid") }
                return (short["en"]!.contains(o.lowercased()) && !short["ru"]!.contains(d.lowercased()), "short2")
            }
        }

        if Double(no) < minLetters { return (false, "short") }
        if !d.isEmpty && valid(L, d) { return (false, "valid") }
        if valid(O, o) { return (true, "dict") }
        if Double(no) >= bgMinLetters && !d.isEmpty && d.allSatisfy(Text.isLetter) {
            let sd = score(d, L), so = score(o, O)
            if so.avg - sd.avg >= margin && sd.min <= shownMinMax && so.min >= otherMinMin { return (true, "bigram") }
        }
        return (false, "unsure")
    }
}

/// Runs macOS-specific tests (1-2 letter whitelist, EN punct-as-RU-letter, Mac vs PC RU layouts, English/code false positives).
func runExtraMacTests(_ j: Judge) -> (passed: Int, total: Int) {
    struct Case { let shown: String; let layout: String; let fix: Bool; let result: String?; let variant: RuVariant }
    func c(_ s: String, _ l: String, _ f: Bool, _ r: String? = nil, _ v: RuVariant = .pc) -> Case {
        Case(shown: s, layout: l, fix: f, result: r, variant: v)
    }

    var cases: [Case] = [
        // User query examples
        c(",jufnfz", "en", true, "богатая"),
        c("chf,fnsdftn", "en", true, "срабатывает"),
        c(",b,kbjntrf", "en", true, "библиотека"),
        c("vjlektq?", "en", true, "модулей,"),
        c("ntrcneh?", "en", true, "текстур,"),
        c("afcfljd", "en", true, "фасадов"),
        c("aehybnehs", "en", true, "фурнитуры"),
        c("yt", "en", true, "не"),
        c("dctulf", "en", true, "всегда"),

        // 1-letter common RU whitelist (en -> ru)
        c("b", "en", true, "и"),
        c("f", "en", true, "а"),
        c("d", "en", true, "в"),
        c("r", "en", true, "к"),
        c("c", "en", true, "с"),
        c("e", "en", true, "у"),
        c("j", "en", true, "о"),
        c("z", "en", true, "я"),
        c("B", "en", true, "И"),
        c("Z", "en", true, "Я"),

        // 2-letter frequent RU whitelist (all 30 incl. punct-containing & hunspell-overlapping non-common EN)
        c("yf", "en", true, "на"),
        c("gj", "en", true, "по"),
        c("pf", "en", true, "за"),
        c("bp", "en", true, "из"),
        c("jn", "en", true, "от"),
        c("lj", "en", true, "до"),
        c("dj", "en", true, "во"),
        c("rj", "en", true, "ко"),
        c(";t", "en", true, "же"),
        c("kb", "en", true, "ли"),
        c(",s", "en", true, "бы"),
        c("nj", "en", true, "то"),
        c("lf", "en", true, "да"),
        c("yj", "en", true, "но"),
        c("ye", "en", true, "ну"),
        c("ds", "en", true, "вы"),
        c("jy", "en", true, "он"),
        c("ns", "en", true, "ты"),
        c("b[", "en", true, "их"),
        c("tq", "en", true, "ей"),
        c("bv", "en", true, "им"),
        c("tt", "en", true, "ее"),
        c("t`", "en", true, "её"),
        c("yb", "en", true, "ни"),
        c("e;", "en", true, "уж"),
        c("cj", "en", true, "со"),
        c("j,", "en", true, "об"),

        // More punct-as-RU-letter tokens (start/middle/end + shifted)
        c(",bk", "en", true, "бил"),
        c(",eh", "en", true, "бур"),
        c(";bk", "en", true, "жил"),
        c("'hf", "en", true, "эра"),
        c("'nj", "en", true, "это"),
        c("gj'njve", "en", true, "поэтому"),
        c("[jhjij", "en", true, "хорошо"),
        c("d[jl", "en", true, "вход"),
        c("c]tcnm", "en", true, "съесть"),
        c("`krf", "en", true, "ёлка"),
        c(";bpym", "en", true, "жизнь"),
        c(":bpym", "en", true, "Жизнь"),
        c("<jufnfz", "en", true, "Богатая"),
        c("\"nj", "en", true, "Это"),
        c("{jhjij", "en", true, "Хорошо"),
        c("k.,jdm", "en", true, "любовь"),
        c("gfhjk.", "en", true, "паролю"),

        // Apple standard "Russian" layout variant (.mac)
        c("\\krf", "en", true, "ёлка", .mac),
        c("t\\", "en", true, "её", .mac),
        c("vjlektq?", "en", true, "модулей?", .mac),
        c(",jufnfz", "en", true, "богатая", .mac),
        c("руддщ?", "ru", true, "hello?", .mac),
        c("еуые/", "ru", true, "test/", .mac),
        c("`krf", "en", false, nil, .mac),

        // Must keep common English 1-2 letter words untouched
        c("in", "en", false), c("to", "en", false), c("on", "en", false), c("at", "en", false),
        c("is", "en", false), c("it", "en", false), c("of", "en", false), c("me", "en", false),
        c("we", "en", false), c("he", "en", false), c("no", "en", false), c("so", "en", false),
        c("do", "en", false), c("go", "en", false), c("up", "en", false), c("my", "en", false),
        c("by", "en", false), c("or", "en", false), c("an", "en", false), c("am", "en", false),
        c("be", "en", false), c("us", "en", false), c("if", "en", false), c("a", "en", false),
        c("I", "en", false), c("vs", "en", false),
        c("KB", "en", false), c("BP", "en", false), c("PF", "en", false),

        // Must preserve English/code/URL/path/email/punctuation untouched (no false positives)
        c("hello,", "en", false),
        c("world.", "en", false),
        c("test;", "en", false),
        c("he,", "en", false),
        c("it.", "en", false),
        c("at.", "en", false),
        c("next.", "en", false),
        c("don't", "en", false),
        c("it's", "en", false),
        c("I'm", "en", false),
        c("you're", "en", false),
        c("e.g.", "en", false),
        c("i.e.", "en", false),
        c("...", "en", false),
        c("3.14", "en", false),
        c("[1]", "en", false),
        c("https://example.com", "en", false),
        c("http://localhost:8080/api", "en", false),
        c("/workspace/smartumswitch/macos", "en", false),
        c("user@example.com", "en", false),
        c("example.com", "en", false),
        c("foo.bar", "en", false),
        c("a,b", "en", false),
        c("b?", "en", false),
        c("c.", "en", false),
        c("ghbdtn,", "en", false),
        c("ghbdtn.", "en", false),
        c("djn.", "en", false),
        c("значит,что", "ru", false),
    ]

    var bad = 0
    for tc in cases {
        let other = Layout.retype(tc.shown, from: tc.layout, ruVariant: tc.variant)
        let r = j.shouldFix(tc.shown, other, tc.layout, Layout.other(tc.layout))
        if r.fix != tc.fix || (tc.fix && other != tc.result) {
            bad += 1
            print("  FAIL extra [\(tc.variant.rawValue)] \(tc.shown) (\(tc.layout)) expected fix=\(tc.fix) result=\(tc.result ?? "-") got \(r.fix) (\(r.why)) other=\(other)")
        }
    }

    // Verify Layout.render for both .pc and .mac
    let yoMacKeys: [(idx: Int, shift: Bool)] = [
        (Layout.macYoIdx, false),
        (Layout.enLower.firstIndex(of: "k")!, false),
        (Layout.enLower.firstIndex(of: "r")!, false),
        (Layout.enLower.firstIndex(of: "f")!, false),
    ]
    let macRendered = Layout.render(yoMacKeys, "ru", caps: false, ruVariant: .mac)
    if macRendered != "ёлка" {
        bad += 1
        print("  FAIL render mac yo: expected ёлка got \(macRendered)")
    }
    cases.append(c("render-mac-yo", "en", false))
    return (cases.count - bad, cases.count)
}

/// Runs core/tests/cases.json (`SmartumSwitch --selftest [cases.json]`). Returns the number of failures.
func runSelfTest(_ path: String) -> Int {
    guard let d = FileManager.default.contents(atPath: path),
          let cases = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else {
        print("selftest: cannot read \(path)"); return 1
    }
    let t0 = Date()
    let j = Judge()
    print(String(format: "dictionaries loaded in %.0f ms", Date().timeIntervalSince(t0) * 1000))
    var bad = 0
    let t1 = Date()
    for c in cases {
        let shown = c["shown"] as! String, L = c["layout"] as! String, exp = c["fix"] as! Bool
        let other = Layout.retype(shown, from: L)
        let r = j.shouldFix(shown, other, L, Layout.other(L))
        if r.fix != exp || (r.fix && other != c["result"] as! String) {
            bad += 1; print("  FAIL \(shown) (\(L)) expected fix=\(exp) got \(r.fix) (\(r.why))")
        }
    }
    print(String(format: "swift-core: %d/%d passed, %.2f ms per word", cases.count - bad, cases.count,
                 Date().timeIntervalSince(t1) * 1000 / Double(max(cases.count, 1))))
    let extra = runExtraMacTests(j)
    print("swift-macos-extra: \(extra.passed)/\(extra.total) passed")
    bad += (extra.total - extra.passed)
    let keys = "ghbdtn".map { (idx: Layout.enLower.firstIndex(of: $0)!, shift: false) }
    let r1 = Layout.render(keys, "ru", caps: false), r2 = Layout.convert("ghbdtn, rfr ltkf?").text
    print("render: \(r1) | convert: \(r2)")
    if r1 != "привет" || r2 != "приветб как дела," { bad += 1 }
    if Layout.macKeyCodes.count != Layout.enLower.count { print("mac_keycodes: wrong length"); bad += 1 }
    return bad
}

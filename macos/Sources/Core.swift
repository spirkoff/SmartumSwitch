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

/// The 34 keys that differ between US QWERTY and Russian JCUKEN (index i is the same physical key everywhere).
enum Layout {
    static let data = Res.json("layout.json")
    static let enLower = Array(data["en_lower"] as! String), enUpper = Array(data["en_upper"] as! String)
    static let ruLower = Array(data["ru_lower"] as! String), ruUpper = Array(data["ru_upper"] as! String)
    static let extraEn = Array(data["manual_extra_en"] as! String), extraRu = Array(data["manual_extra_ru"] as! String)
    /// macOS virtual key codes (kVK_ANSI_*) for the 34 keys.
    static let macKeyCodes: [Int] = (data["mac_keycodes"] as! [Any]).map { ($0 as! NSNumber).intValue }

    static func other(_ lay: String) -> String { lay == "en" ? "ru" : "en" }

    static func render(_ keys: [(idx: Int, shift: Bool)], _ lay: String, caps: Bool) -> String {
        let lo = lay == "ru" ? ruLower : enLower, up = lay == "ru" ? ruUpper : enUpper
        var s = ""
        for k in keys {
            var u = k.shift
            if caps && Text.isLetter(lo[k.idx]) { u.toggle() }
            s.append(u ? up[k.idx] : lo[k.idx])
        }
        return s
    }

    /// Same keys in the other layout (tests): maps shown text char by char.
    static func retype(_ shown: String, from: String) -> String {
        let a = from == "en" ? enLower + enUpper : ruLower + ruUpper
        let b = from == "en" ? ruLower + ruUpper : enLower + enUpper
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
        let d = Text.core(shown), o = Text.core(other)
        if exceptions.contains(d.lowercased()) || exceptions.contains(o.lowercased()) || exceptions.contains(shown.lowercased()) {
            return (false, "exception")
        }
        let nd = Double(d.filter(Text.isLetter).count), no = Double(o.filter(Text.isLetter).count)
        if no < minLetters || no < nd { return (false, "short") }
        if !o.allSatisfy(Text.isLetter) { return (false, "punct") }
        if !d.isEmpty && valid(L, d) { return (false, "valid") }
        if no == 2 {
            return (short[O]!.contains(o.lowercased()) && !short[L]!.contains(d.lowercased()), "short2")
        }
        if valid(O, o) { return (true, "dict") }
        if no >= bgMinLetters && !d.isEmpty && d.allSatisfy(Text.isLetter) {
            let sd = score(d, L), so = score(o, O)
            if so.avg - sd.avg >= margin && sd.min <= shownMinMax && so.min >= otherMinMin { return (true, "bigram") }
        }
        return (false, "unsure")
    }
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
    let keys = "ghbdtn".map { (idx: Layout.enLower.firstIndex(of: $0)!, shift: false) }
    let r1 = Layout.render(keys, "ru", caps: false), r2 = Layout.convert("ghbdtn, rfr ltkf?").text
    print("render: \(r1) | convert: \(r2)")
    if r1 != "привет" || r2 != "приветб как дела," { bad += 1 }
    if Layout.macKeyCodes.count != Layout.enLower.count { print("mac_keycodes: wrong length"); bad += 1 }
    return bad
}

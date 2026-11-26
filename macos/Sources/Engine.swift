// SmartumSwitch for macOS — keyboard engine.
// A CGEventTap (main run loop) watches physical key presses and keeps only the current word (key indices, in memory).
// On Space the shared core decides whether the word was typed in the wrong layout; if so, Space is held back and a
// worker erases the word, switches the layout (TISSelectInputSource) and types the word again. Keys pressed meanwhile
// are held and replayed afterwards. Backspace right after a fix undoes it. Pause (= F15 on Mac) fixes the selection
// or the last word by hand; Shift+Pause turns automatic correction on/off.
// PRIVACY: typed text is never written anywhere; the log contains only counters and errors.
import Cocoa

struct Key { let idx: Int; let shift: Bool; let code: Int; let flags: CGEventFlags }

final class Engine {
    static let shared = Engine()
    let defaults = UserDefaults.standard
    var judge: Judge?                                   // nil while dictionaries load
    var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    var onNotify: ((String) -> Void)?
    var onToggle: (() -> Void)?
    var conflict: String?                               // another switcher is running (Caramba, Punto)
    var enabled: Bool { get { defaults.object(forKey: "Enabled") as? Bool ?? true } set { defaults.set(newValue, forKey: "Enabled") } }
    var hotkey: Int { defaults.object(forKey: "HotkeyKeyCode") as? Int ?? KC.f15 }
    var replayKeys: Bool { defaults.string(forKey: "ReplayMode") == "keys" }
    var switchDelay: UInt32 { UInt32(defaults.object(forKey: "SwitchDelayMs") as? Int ?? 60) * 1000 }
    var blockApps: [String] = []
    var blockTitles: [String] = []

    private let lock = NSRecursiveLock()
    private let queue = DispatchQueue(label: "SmartumSwitch.worker")
    private var keyIndex: [Int: Int] = [:]
    private var ruVariant: RuVariant = .pc
    private var activeRuId: String = ""
    private var word: [Key] = []
    private var dirty = false, busy = false
    private var wordPid: pid_t = 0
    private var wordLayout: String?
    private var wordRuVariant: RuVariant = .pc
    private var last: (keys: [Key], layout: String, pid: pid_t, ruVariant: RuVariant)?
    private var held: [CGEvent] = []
    private var swallowUp = Set<Int>()
    private var sessionIgnore = Set<String>()
    private(set) var stats: [String: Int] = [:]

    func setup() {
        refreshRuLayout(force: true)
        let r = Res.json("rules.json")
        blockApps = (r["block_apps_macos"] as? [String]) ?? []
        blockTitles = (r["block_titles"] as? [String]) ?? []
    }

    private func refreshRuLayout(force: Bool = false) {
        let src = Layouts.activeRuSource()
        let rid = src.map { Layouts.id($0) } ?? ""
        if !force && rid == activeRuId { return }
        activeRuId = rid
        ruVariant = Layouts.ruVariant(src)
        keyIndex = Layouts.keyIndex(ruVariant: ruVariant)
    }

    func count(_ k: String) { lock.lock(); stats[k, default: 0] += 1; lock.unlock() }
    func takeStats() -> [String: Int] { lock.lock(); defer { stats = [:]; lock.unlock() }; return stats }

    // ---------------- tap ----------------
    /// Create (or re-enable) the event tap. Recreates it when Input Monitoring appears after a tap was made with only Accessibility.
    @discardableResult func start() -> Bool {
        if let t = tap {
            if !CGEvent.tapIsEnabled(tap: t) { CGEvent.tapEnable(tap: t, enable: true) }
            return CGEvent.tapIsEnabled(tap: t)
        }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: tapCallback, userInfo: nil) else { return false }
        tap = t
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        tapSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return CGEvent.tapIsEnabled(tap: t)
    }

    /// Tear down the tap so the next `start()` can create a fresh one (needed after Input Monitoring is granted).
    func stopTap() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let src = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil
        tapSource = nil
    }

    var tapEnabled: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func handle(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(e)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            Log.write("tap re-enabled"); return pass
        }
        if e.getIntegerValueField(.eventSourceUserData) == Input.magic { return pass }   // ours
        lock.lock(); defer { lock.unlock() }
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            reset(); last = nil; return pass
        case .flagsChanged:
            if busy { if let c = e.copy() { held.append(c) }; return nil }
            return pass
        case .keyDown, .keyUp:
            let code = Int(e.getIntegerValueField(.keyboardEventKeycode))
            let down = type == .keyDown
            let rep = e.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !down && swallowUp.remove(code) != nil { return nil }
            if busy {
                if !rep, let c = e.copy() { held.append(c) }
                return nil
            }
            if down && onKey(code, e.flags, rep, e) { swallowUp.insert(code); return nil }
            return pass
        default:
            return pass
        }
    }

    private func reset() { word.removeAll(); dirty = false; wordPid = 0; wordLayout = nil }

    /// Under lock, on the main thread — must be fast. Returns true to swallow the key.
    private func onKey(_ code: Int, _ flags: CGEventFlags, _ rep: Bool, _ event: CGEvent) -> Bool {
        let shift = flags.contains(.maskShift)
        stats["keys", default: 0] += 1
        if code == hotkey {
            reset(); last = nil
            if shift { DispatchQueue.main.async { self.onToggle?() } }
            else { busy = true; queue.async { self.manualFix() } }
            return true
        }
        if KC.modifiers.contains(code) { return false }
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            reset(); last = nil; return false
        }
        if !enabled { return false }
        if conflict != nil { return false }
        if judge == nil { return false }
        if rep { reset(); dirty = true; last = nil; return false }

        if let l = last {
            last = nil
            if code == KC.delete && !shift { busy = true; queue.async { self.rollback(l) }; return true }
        }
        if let idx = keyIndex[code] {
            if word.isEmpty {
                refreshRuLayout()
                wordPid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
                wordLayout = Layouts.layout(of: event) ?? Layouts.current()
                wordRuVariant = ruVariant
                if wordLayout == nil { stats["no_layout", default: 0] += 1 }
            }
            word.append(Key(idx: idx, shift: shift, code: code, flags: flags.intersection([.maskShift, .maskAlphaShift])))
            return false
        }
        if code == KC.space || code == KC.enter || code == KC.padEnter {
            return endWord(terminator: code, shift: shift, caps: flags.contains(.maskAlphaShift))
        }
        if code == KC.delete { if !word.isEmpty { word.removeLast() } else { dirty = true }; return false }
        if KC.dirty.contains(code) { dirty = true; return false }
        reset(); last = nil
        return false
    }

    /// Space / Enter ends the word. Logs a reason (never the text). Returns true to swallow the terminator until after a fix.
    private func endWord(terminator: Int, shift: Bool, caps: Bool) -> Bool {
        let app = NSWorkspace.shared.frontmostApplication
        let bid = (app?.bundleIdentifier ?? app?.localizedName ?? "?")
        let pid = app?.processIdentifier ?? 0
        defer { reset() }
        if word.isEmpty { return false }
        if dirty { count("skip_dirty"); return false }
        if shift { return false }
        guard let L = wordLayout else { count("skip_layout"); Log.write("skip layout=nil bundle=\(bid) letters=\(word.count)"); return false }
        guard let j = judge else { count("skip_judge"); return false }
        if pid != wordPid { count("skip_focus"); Log.write("skip focus bundle=\(bid)"); return false }
        let O = Layout.other(L), keys = word, rv = wordRuVariant
        if Layouts.find(O) == nil { count("skip_no_other"); return false }
        if sessionIgnore.contains(Engine.sig(keys)) { count("skip_ignored"); return false }
        let r = j.shouldFix(Engine.render(keys, L, caps, ruVariant: rv), Engine.render(keys, O, caps, ruVariant: rv), L, O)
        stats["checked", default: 0] += 1
        if r.fix {
            busy = true
            Log.write("fix \(r.why) layout=\(L)->\(O) bundle=\(bid) letters=\(keys.count)")
            queue.async { self.fix(keys, L, O, pid, r.why, caps, ruVariant: rv, terminator: terminator) }
            return true
        }
        count("keep_" + r.why)
        return false
    }

    static func sig(_ keys: [Key]) -> String { keys.map { String($0.idx) }.joined(separator: ",") }
    static func render(_ keys: [Key], _ lay: String, _ caps: Bool, ruVariant: RuVariant = .pc) -> String {
        Layout.render(keys.map { (idx: $0.idx, shift: $0.shift) }, lay, caps: caps, ruVariant: ruVariant)
    }

    // ---------------- environment ----------------
    private func envOk(_ pid: pid_t) -> Bool {
        let app = onMain { NSWorkspace.shared.frontmostApplication }
        guard let a = app, a.processIdentifier == pid else { count("skip_focus"); return false }
        let bid = (a.bundleIdentifier ?? a.localizedName ?? "").lowercased()
        if blockApps.contains(where: { bid.contains($0) }) { count("skip_app"); Log.write("skip app bundle=\(bid)"); return false }
        if Focus.passwordLike() { count("skip_password"); Log.write("skip password bundle=\(bid)"); return false }
        let title = Focus.windowTitle(pid).lowercased()
        if blockTitles.contains(where: { title.contains($0) }) { count("skip_title"); Log.write("skip title bundle=\(bid)"); return false }
        return true
    }

    // ---------------- jobs (worker queue) ----------------
    private func retype(_ keys: [Key], _ lay: String, _ caps: Bool, ruVariant: RuVariant = .pc) {
        if replayKeys { for k in keys { Input.tap(k.code, flags: k.flags) }; return }
        let text = Array(Engine.render(keys, lay, caps, ruVariant: ruVariant))
        for (i, k) in keys.enumerated() { Input.type(text[i], code: k.code) }
    }

    private func fix(_ keys: [Key], _ L: String, _ O: String, _ pid: pid_t, _ why: String, _ caps: Bool, ruVariant: RuVariant = .pc, terminator: Int = KC.space) {
        defer { flushHeld() }
        if !envOk(pid) { Input.tap(terminator); return }
        for _ in keys { Input.tap(KC.delete) }
        let switched = onMain { Layouts.select(O) }
        usleep(switchDelay)
        retype(keys, switched ? O : L, caps, ruVariant: ruVariant)   // if switching failed this simply restores the original text
        Input.tap(terminator)
        if switched { lock.lock(); last = (keys, L, pid, ruVariant); lock.unlock(); count("fixed_" + why) } else { count("error_layout") }
    }

    private func rollback(_ l: (keys: [Key], layout: String, pid: pid_t, ruVariant: RuVariant)) {
        defer { flushHeld() }
        if !envOk(l.pid) { Input.tap(KC.delete); return }
        for _ in 0...l.keys.count { Input.tap(KC.delete) }
        onMain { Layouts.select(l.layout) }
        usleep(switchDelay)
        retype(l.keys, l.layout, l.keys.first?.flags.contains(.maskAlphaShift) ?? false, ruVariant: l.ruVariant)
        Input.tap(KC.space)
        lock.lock(); sessionIgnore.insert(Engine.sig(l.keys)); lock.unlock()
        count("rollback")
    }

    private func manualFix() {
        defer { flushHeld() }
        let app = onMain { NSWorkspace.shared.frontmostApplication }
        let bid = (app?.bundleIdentifier ?? "").lowercased()
        if blockApps.contains(where: { bid.contains($0) }) || Focus.passwordLike() {
            notify("В этом окне ручное исправление не работает"); return
        }
        let pb = NSPasteboard.general
        let saved = onMain { Clip.save(pb) }
        var text = copySelection(pb)
        if text == nil {
            Input.tap(KC.left, flags: [.maskAlternate, .maskShift])   // select the previous word
            usleep(40_000)
            text = copySelection(pb)
        }
        guard let t = text, !t.isEmpty else { onMain { Clip.restore(pb, saved) }; return }
        let (fixed, target) = Layout.convert(t)
        text = nil
        onMain { pb.clearContents(); pb.setString(fixed, forType: .string) }
        Input.tap(KC.v, flags: .maskCommand)
        usleep(300_000)
        onMain { Layouts.select(target) }
        onMain { Clip.restore(pb, saved) }
        count("manual")
    }

    private func copySelection(_ pb: NSPasteboard) -> String? {
        let before = onMain { pb.changeCount }
        Input.tap(KC.c, flags: .maskCommand)
        for _ in 0..<25 {
            usleep(20_000)
            if onMain({ pb.changeCount }) != before { usleep(20_000); return onMain { pb.string(forType: .string) } }
        }
        return nil
    }

    private func notify(_ s: String) { DispatchQueue.main.async { self.onNotify?(s) } }

    /// Replays keys the user pressed while we were busy, then releases the hold.
    private func flushHeld() {
        while true {
            lock.lock()
            if held.isEmpty { busy = false; lock.unlock(); return }
            let batch = held; held.removeAll()
            lock.unlock()
            for e in batch {
                let code = Int(e.getIntegerValueField(.keyboardEventKeycode))
                if code == hotkey && e.type != .flagsChanged { continue }
                Input.post(e)
                if e.type == .keyDown { lock.lock(); trackReplayed(code, e.flags); lock.unlock() }
            }
        }
    }

    private func trackReplayed(_ code: Int, _ flags: CGEventFlags) {
        if let idx = keyIndex[code] {
            if word.isEmpty { wordPid = 0; wordLayout = nil }   // layout unknown here: such a word is not checked
            word.append(Key(idx: idx, shift: flags.contains(.maskShift), code: code, flags: flags.intersection([.maskShift, .maskAlphaShift])))
        } else if !KC.modifiers.contains(code) { reset() }
        if code == KC.space { dirty = true }   // words typed during a fix are not checked again
    }
}

/// C callback for the event tap (no captures allowed).
let tapCallback: CGEventTapCallBack = { _, type, event, _ in Engine.shared.handle(type, event) }

enum Clip {
    typealias Saved = [[(NSPasteboard.PasteboardType, Data)]]
    static func save(_ pb: NSPasteboard) -> Saved {
        (pb.pasteboardItems ?? []).map { item in item.types.compactMap { t in item.data(forType: t).map { (t, $0) } } }
    }
    static func restore(_ pb: NSPasteboard, _ s: Saved) {
        pb.clearContents()
        let items = s.map { pairs -> NSPasteboardItem in
            let it = NSPasteboardItem(); for (t, d) in pairs { it.setData(d, forType: t) }; return it
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }
}

enum Log {
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SmartumSwitch")
    private static let io = NSLock()
    static func write(_ msg: String) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(f.string(from: Date())) \(msg)\n"
        let url = dir.appendingPathComponent("smartum-switch.log")
        io.lock(); defer { io.unlock() }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            let h = try FileHandle(forWritingTo: url)
            defer { try? h.close() }
            try h.seekToEnd()
            if let d = line.data(using: .utf8) { try h.write(contentsOf: d) }
        } catch { }
    }
}

// SmartumSwitch for macOS — system helpers: key codes, posting events, input sources (TIS), focus/password checks.
// PRIVACY: nothing here stores or logs typed text.
import Cocoa
import Carbon
import ApplicationServices

enum KC {   // macOS virtual key codes (kVK_*)
    static let delete = 0x33, space = 0x31, enter = 0x24, padEnter = 0x4C, left = 0x7B, c = 0x08, v = 0x09, f15 = 0x71
    static let modifiers: Set<Int> = [0x37, 0x36, 0x38, 0x3C, 0x3A, 0x3D, 0x3B, 0x3E, 0x39, 0x3F]   // cmd shift opt ctrl caps fn
    /// Digits, - = \ and keypad: part of a "dirty" word (not checked), but do not end it.
    static let dirty: Set<Int> = Set([0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D, 0x1B, 0x18, 0x2A, 0x0A])
        .union(0x41...0x5C)
}

enum Input {
    static let magic: Int64 = 0x534D5357   // "SMSW": marks our own events
    static let src = CGEventSource(stateID: .hidSystemState)

    static func post(_ e: CGEvent) {
        e.setIntegerValueField(.eventSourceUserData, value: magic)
        e.post(tap: .cghidEventTap)
        usleep(2500)
    }
    static func key(_ code: Int, down: Bool, flags: CGEventFlags = []) {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: down) else { return }
        e.flags = flags
        post(e)
    }
    static func tap(_ code: Int, flags: CGEventFlags = []) { key(code, down: true, flags: flags); key(code, down: false, flags: flags) }
    /// Types one character regardless of the active layout (Unicode string attached to the key event).
    static func type(_ ch: Character, code: Int) {
        let u = Array(String(ch).utf16)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: down) else { continue }
            e.flags = []
            e.keyboardSetUnicodeString(stringLength: u.count, unicodeString: u)
            post(e)
        }
    }
}

enum Layouts {
    static func lang(_ s: TISInputSource) -> String? {
        guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceLanguages) else { return nil }
        let arr = Unmanaged<CFArray>.fromOpaque(p).takeUnretainedValue() as NSArray
        guard let f = arr.firstObject as? String else { return nil }
        if f.hasPrefix("ru") { return "ru" }
        if f.hasPrefix("en") { return "en" }
        return nil
    }
    static func id(_ s: TISInputSource) -> String {
        guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "?" }
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }
    /// Keyboard layout only (ignores emoji / dictation IMs). Call on the main thread.
    static func current() -> String? {
        if let s = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(), let l = lang(s) { return l }
        if let s = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), let l = lang(s) { return l }
        if let id = UserDefaults(suiteName: "com.apple.HIToolbox")?.string(forKey: "AppleCurrentKeyboardLayoutInputSourceID") {
            let s = id.lowercased()
            if s.contains("russian") || s.contains("russianwin") || s.hasSuffix(".ru") { return "ru" }
            if s.contains(".us") || s.contains("abc") || s.contains("british") || s.contains("english") { return "en" }
        }
        return nil
    }

    /// Layout of the character this key event will insert (letter only); otherwise `current()`.
    static func layout(of event: CGEvent) -> String? {
        var len = 0
        var buf = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &len, unicodeString: &buf)
        if len >= 1, let sc = UnicodeScalar(buf[0]) {
            let ch = Character(sc)
            if Text.isCyr(ch) { return "ru" }
            if Text.isLat(ch) { return "en" }
        }
        return current()
    }
    static func all() -> [TISInputSource] {
        let props: [String: Any] = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
                                    kTISPropertyInputSourceIsSelectCapable as String: true]
        guard let l = TISCreateInputSourceList(props as CFDictionary, false)?.takeRetainedValue() as NSArray? else { return [] }
        return l.map { $0 as! TISInputSource }
    }
    static func find(_ lay: String) -> TISInputSource? { all().first { lang($0) == lay } }
    static func hasBoth() -> Bool { find("en") != nil && find("ru") != nil }
    /// Call on the main thread.
    @discardableResult static func select(_ lay: String) -> Bool {
        if current() == lay { return true }
        guard let s = find(lay) else { return false }
        return TISSelectInputSource(s) == OSStatus(noErr) && current() == lay
    }

    /// Character the key gives in a layout (UCKeyTranslate), nil for dead/none.
    static func char(_ s: TISInputSource, _ code: Int, shift: Bool) -> Character? {
        guard let p = TISGetInputSourceProperty(s, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(p).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        var dead: UInt32 = 0, len = 0
        var buf = [UniChar](repeating: 0, count: 4)
        let mods: UInt32 = shift ? UInt32((shiftKey >> 8) & 0xFF) : 0
        let st = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
            UCKeyTranslate($0, UInt16(code), UInt16(kUCKeyActionDisplay), mods, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, 4, &len, &buf)
        }
        guard st == OSStatus(noErr), len == 1, let sc = UnicodeScalar(buf[0]) else { return nil }
        return Character(sc)
    }

    /// keycode -> index 0..33. Built from the real US layout (handles ISO keyboards), static table as fallback.
    static func keyIndex() -> [Int: Int] {
        var m: [Int: Int] = [:]
        for (i, c) in Layout.macKeyCodes.enumerated() { m[c] = i }
        if let us = find("en") {
            for code in 0..<0x40 where !KC.dirty.contains(code) {
                if let ch = char(us, code, shift: false), let i = Layout.enLower.firstIndex(of: ch) { m[code] = i }
            }
        }
        return m
    }

    /// `--layout-check`: compares the enabled layouts with core/data/layout.json. Returns mismatches.
    static func check() -> Int {
        guard let en = find("en"), let ru = find("ru") else { print("нужны обе раскладки: английская и русская"); return 1 }
        print("en: \(id(en))   ru: \(id(ru))   keyboard type: \(LMGetKbdType())")
        var bad = 0
        let idx = keyIndex()
        for (code, i) in idx.sorted(by: { $0.value < $1.value }) {
            for shift in [false, true] {
                let e = char(en, code, shift: shift), r = char(ru, code, shift: shift)
                let ee = shift ? Layout.enUpper[i] : Layout.enLower[i], rr = shift ? Layout.ruUpper[i] : Layout.ruLower[i]
                let quirk = i == 0 && shift && r == "\u{00CB}"
                let ok = e == ee && (r == rr || quirk)
                if !ok { bad += 1 }
                let tag = quirk ? "ok (macOS U+00CB -> Ё)" : (ok ? "ok" : "MISMATCH")
                print(String(format: "key 0x%02X #%02d %@  en %@/%@  ru %@/%@  %@", code, i, shift ? "shift" : "     ",
                             String(e ?? "-"), String(ee), String(r ?? "-"), String(rr), tag))
            }
        }
        print(bad == 0 ? "layout-check: ok" : "layout-check: \(bad) mismatches")
        return bad
    }
}

enum Focus {
    /// Secure input (password fields, Terminal "Secure Keyboard Entry") or a focused secure text field.
    static func passwordLike() -> Bool {
        if IsSecureEventInputEnabled() { return true }
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.25)
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &v) == .success, let el = v,
              CFGetTypeID(el) == AXUIElementGetTypeID() else { return false }
        var sr: CFTypeRef?
        if AXUIElementCopyAttributeValue(el as! AXUIElement, kAXSubroleAttribute as CFString, &sr) == .success,
           let s = sr as? String, s == (kAXSecureTextFieldSubrole as String) { return true }
        return false
    }
    static func windowTitle(_ pid: pid_t) -> String {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var w: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &w) == .success, let win = w,
              CFGetTypeID(win) == AXUIElementGetTypeID() else { return "" }
        var t: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString, &t) == .success else { return "" }
        return (t as? String) ?? ""
    }
}

@discardableResult func onMain<T>(_ f: () -> T) -> T { Thread.isMainThread ? f() : DispatchQueue.main.sync(execute: f) }

enum Perms {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var listen: Bool { CGPreflightListenEventAccess() }
    static var post: Bool { CGPreflightPostEventAccess() }
    /// Both are required: Accessibility to create a modifying tap, Input Monitoring to actually receive keys.
    static var ready: Bool { accessibility && listen }
    static var summary: String { "ax=\(accessibility ? 1 : 0) listen=\(listen ? 1 : 0) post=\(post ? 1 : 0)" }
    static func request() {
        if !accessibility { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) }
        if !listen { _ = CGRequestListenEventAccess() }
        if !post { _ = CGRequestPostEventAccess() }
    }
}

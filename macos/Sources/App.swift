// SmartumSwitch for macOS — menu-bar app: status, toggle, permissions, exceptions, log.
import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let engine = Engine.shared
    var item: NSStatusItem!
    let statusLine = NSMenuItem(title: "SmartumSwitch: загрузка…", action: nil, keyEquivalent: "")
    let toggleItem = NSMenuItem(title: "Автоисправление", action: #selector(toggle), keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Запускать при входе в систему", action: #selector(toggleLogin), keyEquivalent: "")
    var hud: NSPanel?
    var exceptionsDate: Date?
    static let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/SmartumSwitch")
    static let exceptionsURL = support.appendingPathComponent("exceptions.txt")

    func applicationDidFinishLaunching(_ n: Notification) {
        let me = Bundle.main.bundleIdentifier ?? ""
        if NSRunningApplication.runningApplications(withBundleIdentifier: me).count > 1 { NSApp.terminate(nil); return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu(); menu.delegate = self
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        toggleItem.target = self; menu.addItem(toggleItem)
        menu.addItem(withTitle: "Исключения…", action: #selector(openExceptions), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Журнал (только счётчики)", action: #selector(openLog), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Разрешение «Универсальный доступ»…", action: #selector(openAccessibility), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Разрешение «Мониторинг ввода»…", action: #selector(openInputMonitoring), keyEquivalent: "").target = self
        loginItem.target = self; menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти из SmartumSwitch", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu

        engine.setup()
        engine.onNotify = { [weak self] s in self?.showHud(s) }
        engine.onToggle = { [weak self] in self?.toggle() }
        loadExceptions()
        refreshConflict()
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshConflict() }
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshConflict() }

        DispatchQueue.global(qos: .userInitiated).async {
            let t0 = Date(); let j = Judge()
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            DispatchQueue.main.async {
                j.exceptions = self.pendingExceptions
                self.engine.judge = j
                Log.write("started, dictionaries loaded in \(ms) ms")
                self.update()
            }
        }
        requestPermissionsAndStart()
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.flushStats()
            self?.loadExceptions()
            self?.watchPermissions()
        }
        update()
    }

    func applicationWillTerminate(_ n: Notification) { flushStats(); Log.write("stopped") }

    // ---------- permissions ----------
    /// Keep trying until both Accessibility and Input Monitoring are granted, then (re)create the tap.
    func requestPermissionsAndStart() {
        Perms.request()
        Log.write("perms " + Perms.summary)
        tryStartTap(reason: "launch", prompt: true)
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.watchPermissions() }
    }

    func watchPermissions() {
        if !engine.tapEnabled || !Perms.ready { tryStartTap(reason: "watch", prompt: false) }
        update()
    }

    func tryStartTap(reason: String, prompt: Bool = false) {
        if prompt { Perms.request() }
        let before = Perms.summary + " tap=\(engine.tapEnabled ? 1 : 0)"
        if !Perms.ready {
            // A tap created with only Accessibility may never receive keys — drop it and wait for both.
            if engine.tap != nil && !Perms.listen { engine.stopTap(); Log.write("tap dropped: no input monitoring") }
            update()
            return
        }
        if engine.tap != nil && !engine.tapEnabled { engine.stopTap() }
        if engine.start() {
            if before != Perms.summary + " tap=1" || reason == "launch" {
                Log.write("event tap active (\(reason)) " + Perms.summary)
            }
        } else {
            Log.write("event tap failed (\(reason)) " + Perms.summary)
        }
        update()
    }
    @objc func openAccessibility() { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") }
    @objc func openInputMonitoring() { open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") }
    func open(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }

    // ---------- state ----------
    func refreshConflict() {
        let other = NSWorkspace.shared.runningApplications.first { a in
            let s = ((a.bundleIdentifier ?? "") + " " + (a.localizedName ?? "")).lowercased()
            return s.contains("caramba") || s.contains("punto")
        }
        engine.conflict = other?.localizedName
        update()
    }

    func update() {
        guard item != nil else { return }
        let st: String
        if !Perms.accessibility && !Perms.listen { st = "SmartumSwitch: нужны разрешения (см. ниже)" }
        else if !Perms.accessibility { st = "SmartumSwitch: включите «Универсальный доступ»" }
        else if !Perms.listen { st = "SmartumSwitch: включите «Мониторинг ввода»" }
        else if !engine.tapEnabled { st = "SmartumSwitch: нет доступа к клавиатуре" }
        else if engine.judge == nil { st = "SmartumSwitch: загрузка словарей…" }
        else if let c = engine.conflict { st = "SmartumSwitch: пауза — работает \(c)" }
        else if !Layouts.hasBoth() { st = "SmartumSwitch: включите русскую и английскую раскладки" }
        else { st = engine.enabled ? "SmartumSwitch: включён" : "SmartumSwitch: автоисправление выключено" }
        statusLine.title = st
        toggleItem.state = engine.enabled ? .on : .off
        toggleItem.title = "Автоисправление (Shift+Pause)"
        let active = Perms.ready && engine.tapEnabled && engine.judge != nil && engine.conflict == nil && engine.enabled
        item.button?.title = active ? "S" : "S·"
        item.button?.toolTip = st + "\nPause (F15) — исправить выделенное или последнее слово"
        if #available(macOS 13.0, *) { loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off }
    }

    func menuWillOpen(_ menu: NSMenu) { refreshConflict() }

    @objc func toggle() {
        engine.enabled.toggle()
        Log.write(engine.enabled ? "auto on" : "auto off")
        showHud(engine.enabled ? "SmartumSwitch: автоисправление включено" : "SmartumSwitch: автоисправление выключено")
        update()
    }

    @objc func toggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { Log.write("error: login item \(error.localizedDescription)") }
        update()
    }

    @objc func quit() { NSApp.terminate(nil) }

    // ---------- exceptions / log ----------
    var pendingExceptions = Set<String>()
    func loadExceptions() {
        let fm = FileManager.default
        try? fm.createDirectory(at: AppDelegate.support, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: AppDelegate.exceptionsURL.path) {
            try? "# SmartumSwitch: слова, которые не нужно исправлять (по одному в строке)\n".write(to: AppDelegate.exceptionsURL, atomically: true, encoding: .utf8)
        }
        let mod = (try? fm.attributesOfItem(atPath: AppDelegate.exceptionsURL.path))?[.modificationDate] as? Date
        if mod == exceptionsDate { return }
        exceptionsDate = mod
        let text = (try? String(contentsOf: AppDelegate.exceptionsURL, encoding: .utf8)) ?? ""
        let set = Set(text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") })
        pendingExceptions = set
        engine.judge?.exceptions = set
    }
    @objc func openExceptions() { loadExceptions(); NSWorkspace.shared.open(AppDelegate.exceptionsURL) }
    @objc func openLog() {
        Log.write("log opened"); NSWorkspace.shared.open(Log.dir.appendingPathComponent("smartum-switch.log"))
    }
    func flushStats() {
        let s = engine.takeStats()
        if !s.isEmpty {
            Log.write("stats " + s.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ") + " " + Perms.summary + " tap=\(engine.tapEnabled ? 1 : 0)")
        }
    }

    // ---------- small on-screen message ----------
    func showHud(_ text: String) {
        hud?.close()
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .medium); label.textColor = .white
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 32, height: label.frame.height + 20)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = NSColor.black.withAlphaComponent(0.78); p.level = .statusBar
        p.ignoresMouseEvents = true; p.hasShadow = true
        p.contentView?.wantsLayer = true; p.contentView?.layer?.cornerRadius = 10
        label.frame.origin = NSPoint(x: 16, y: 10); p.contentView?.addSubview(label)
        if let sc = NSScreen.main?.visibleFrame { p.setFrameOrigin(NSPoint(x: sc.maxX - size.width - 20, y: sc.maxY - size.height - 12)) }
        p.orderFrontRegardless(); hud = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self, weak p] in if self?.hud === p { p?.close(); self?.hud = nil } }
    }
}

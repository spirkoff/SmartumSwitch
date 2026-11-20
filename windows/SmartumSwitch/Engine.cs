// SmartumSwitch for Windows — keyboard engine.
// A low-level keyboard hook (on its own thread) watches physical key presses and keeps only the current word
// (as scan codes, in memory). On Space the shared core decides whether the word was typed in the wrong layout;
// if so, Space is held back, a worker erases the word with SendInput, switches the layout and replays the same
// keys. Keys pressed meanwhile are held and replayed afterwards. Backspace right after a fix undoes it.
// PRIVACY: typed text is never written anywhere; the log contains only counters and errors.
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using SmartumSwitch.Core;
using static SmartumSwitch.Native;

namespace SmartumSwitch;

sealed class Engine : IDisposable
{
    static readonly IntPtr Magic = new(0x534D5357); // "SMSW": marks our own SendInput events
    const int VK_BACK = 0x08, VK_SHIFT = 0x10, VK_CONTROL = 0x11, VK_MENU = 0x12, VK_PAUSE = 0x13, VK_CAPITAL = 0x14,
              VK_SPACE = 0x20, VK_LEFT = 0x25, VK_LSHIFT = 0xA0, VK_RSHIFT = 0xA1, VK_LCONTROL = 0xA2, VK_RCONTROL = 0xA3,
              VK_LMENU = 0xA4, VK_RMENU = 0xA5, VK_LWIN = 0x5B, VK_RWIN = 0x5C;
    const ushort SC_BACK = 0x0E, SC_SPACE = 0x39, SC_LSHIFT = 0x2A;

    public volatile bool Enabled = true;
    public Judge? Judge;                       // null while dictionaries load
    public event Action<string>? Notify;
    public event Action? ToggleRequested;
    public readonly ConcurrentDictionary<string, int> Stats = new();

    readonly object gate = new();
    readonly HashSet<uint> physDown = new(), swallowUp = new();
    readonly List<(int idx, bool shift)> word = new();
    bool dirty; IntPtr wordHwnd; string? wordLayout;
    Last? last;
    bool busy;
    readonly List<(KBDLLHOOKSTRUCT k, bool down)> held = new();
    readonly HashSet<string> sessionIgnore = new();
    readonly BlockingCollection<Action> jobs = new();
    readonly HookProc kbProc, msProc;
    IntPtr kbHook, msHook; uint hookTid;
    readonly Thread hookThread, worker;
    readonly bool selfElevated = SelfElevated();
    public static HashSet<string> BlockApps = new(), BlockTitles = new();

    record Last(List<(int idx, bool shift)> Keys, string Layout, IntPtr Hwnd);

    public Engine()
    {
        kbProc = KbHook; msProc = MouseHook;
        worker = new Thread(() => { foreach (var j in jobs.GetConsumingEnumerable()) Safe(j); }) { IsBackground = true, Name = "SmartumSwitch worker" };
        worker.SetApartmentState(ApartmentState.STA); // clipboard
        worker.Start();
        hookThread = new Thread(HookLoop) { IsBackground = true, Name = "SmartumSwitch hook" };
        hookThread.Start();
    }

    void Safe(Action a)
    {
        try { a(); }
        catch (Exception ex) { Log.Write($"error: {ex.GetType().Name}"); lock (gate) { if (busy) { } } FlushHeld(); }
    }

    void HookLoop()
    {
        hookTid = GetCurrentThreadId();
        var mod = GetModuleHandle(null);
        kbHook = SetWindowsHookEx(WH_KEYBOARD_LL, kbProc, mod, 0);
        msHook = SetWindowsHookEx(WH_MOUSE_LL, msProc, mod, 0);
        if (kbHook == IntPtr.Zero) Log.Write($"error: keyboard hook failed {Marshal.GetLastWin32Error()}");
        while (GetMessage(out var m, IntPtr.Zero, 0, 0) > 0) { TranslateMessage(ref m); DispatchMessage(ref m); }
        if (kbHook != IntPtr.Zero) UnhookWindowsHookEx(kbHook);
        if (msHook != IntPtr.Zero) UnhookWindowsHookEx(msHook);
    }

    public void Dispose()
    {
        if (hookTid != 0) PostThreadMessage(hookTid, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
        jobs.CompleteAdding();
    }

    // ---------------- hook ----------------
    IntPtr MouseHook(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int m = (int)wParam;
            if (m is WM_LBUTTONDOWN or WM_RBUTTONDOWN or WM_MBUTTONDOWN or WM_XBUTTONDOWN)
                lock (gate) { Reset(); last = null; }
        }
        return CallNextHookEx(msHook, nCode, wParam, lParam);
    }

    IntPtr KbHook(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < 0) return CallNextHookEx(kbHook, nCode, wParam, lParam);
        var k = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
        if ((k.flags & LLKHF_INJECTED) != 0) return CallNextHookEx(kbHook, nCode, wParam, lParam); // ours or other tools'
        int msg = (int)wParam;
        bool down = msg is WM_KEYDOWN or WM_SYSKEYDOWN;
        lock (gate)
        {
            bool repeat = down && physDown.Contains(k.vkCode);
            if (down) physDown.Add(k.vkCode); else physDown.Remove(k.vkCode);
            if (!down && swallowUp.Remove(k.vkCode)) return (IntPtr)1;
            if (busy)
            {
                if (!repeat) held.Add((k, down));
                return (IntPtr)1;
            }
            if (OnKey(k, down, repeat))
            {
                if (down) swallowUp.Add(k.vkCode);
                return (IntPtr)1;
            }
        }
        return CallNextHookEx(kbHook, nCode, wParam, lParam);
    }

    bool Shift => physDown.Contains(VK_LSHIFT) || physDown.Contains(VK_RSHIFT) || physDown.Contains(VK_SHIFT);
    bool Ctrl => physDown.Contains(VK_LCONTROL) || physDown.Contains(VK_RCONTROL) || physDown.Contains(VK_CONTROL);
    bool Alt => physDown.Contains(VK_LMENU) || physDown.Contains(VK_RMENU) || physDown.Contains(VK_MENU);
    bool Win => physDown.Contains(VK_LWIN) || physDown.Contains(VK_RWIN);
    static bool IsModifier(uint vk) => vk is VK_SHIFT or VK_CONTROL or VK_MENU or (>= VK_LSHIFT and <= VK_RMENU) or VK_LWIN or VK_RWIN;

    void Reset() { word.Clear(); dirty = false; wordHwnd = IntPtr.Zero; wordLayout = null; }

    /// <summary>Returns true to swallow the key. Called under lock on the hook thread — must be fast.</summary>
    bool OnKey(KBDLLHOOKSTRUCT k, bool down, bool repeat)
    {
        if (!down) return false;
        uint vk = k.vkCode;
        if (vk == VK_PAUSE)
        {
            Reset(); last = null;
            if (Shift) ToggleRequested?.Invoke();
            else { busy = true; jobs.Add(ManualFix); }
            return true;
        }
        if (IsModifier(vk) || vk == VK_CAPITAL) return false;
        if (Ctrl || Alt || Win) { Reset(); last = null; return false; }
        if (!Enabled) return false;
        if (repeat) { Reset(); dirty = true; last = null; return false; }

        if (last != null)
        {
            var l = last; last = null;
            if (vk == VK_BACK && !Shift) { busy = true; jobs.Add(() => Rollback(l)); return true; }
        }
        int idx = (k.flags & LLKHF_EXTENDED) == 0 ? Layout.IndexOfScan((int)k.scanCode) : -1;
        if (idx >= 0)
        {
            if (word.Count == 0) { wordHwnd = GetForegroundWindow(); wordLayout = LayoutOf(wordHwnd); }
            word.Add((idx, Shift));
            return false;
        }
        if (vk == VK_SPACE)
        {
            bool swallow = false;
            if (word.Count > 0 && !dirty && !Shift && wordLayout != null && Judge != null && GetForegroundWindow() == wordHwnd)
            {
                string L = wordLayout, O = Judge.Other(L);
                var keys = word.ToList();
                if (FindHkl(O) != IntPtr.Zero && !sessionIgnore.Contains(Key(keys)))
                {
                    bool caps = (GetKeyState(VK_CAPITAL) & 1) != 0;
                    var (fix, why) = Judge.ShouldFix(Layout.Render(keys, L, caps), Layout.Render(keys, O, caps), L, O);
                    Count("checked");
                    if (fix)
                    {
                        var hwnd = wordHwnd; busy = true; swallow = true;
                        jobs.Add(() => Fix(keys, L, O, hwnd, why));
                    }
                }
            }
            Reset();
            return swallow;
        }
        if (vk == VK_BACK) { if (word.Count > 0) word.RemoveAt(word.Count - 1); else dirty = true; return false; }
        if (vk is >= 0x30 and <= 0x39 or 0xBD or 0xBB or 0xDC or 0xE2 or >= 0x60 and <= 0x6F) { dirty = true; return false; }
        Reset(); last = null;
        return false;
    }

    static string Key(List<(int idx, bool shift)> keys) => string.Join(",", keys.Select(k => k.idx));
    void Count(string k) => Stats.AddOrUpdate(k, 1, (_, v) => v + 1);

    // ---------------- layouts ----------------
    static string? LangOf(IntPtr hkl) => ((long)hkl & 0x3FF) switch { 0x09 => "en", 0x19 => "ru", _ => null };

    static string? LayoutOf(IntPtr hwnd) => LangOf(GetKeyboardLayout(GetWindowThreadProcessId(hwnd, out _)));

    public static IntPtr FindHkl(string lay)
    {
        int n = GetKeyboardLayoutList(0, null); var list = new IntPtr[Math.Max(n, 1)];
        GetKeyboardLayoutList(n, list);
        foreach (var h in list) if (LangOf(h) == lay) return h;
        return IntPtr.Zero;
    }

    public static bool HasBothLayouts() => FindHkl("en") != IntPtr.Zero && FindHkl("ru") != IntPtr.Zero;

    static bool SwitchLayout(string lay, IntPtr hwnd)
    {
        var hkl = FindHkl(lay);
        if (hkl == IntPtr.Zero) return false;
        uint tid = GetWindowThreadProcessId(hwnd, out _);
        if (LangOf(GetKeyboardLayout(tid)) == lay) return true;
        var gi = new GUITHREADINFO { cbSize = Marshal.SizeOf<GUITHREADINFO>() };
        IntPtr target = GetGUIThreadInfo(tid, ref gi) && gi.hwndFocus != IntPtr.Zero ? gi.hwndFocus : hwnd;
        PostMessage(target, WM_INPUTLANGCHANGEREQUEST, IntPtr.Zero, hkl);
        for (int i = 0; i < 40; i++)
        {
            Thread.Sleep(10);
            if (LangOf(GetKeyboardLayout(tid)) == lay) return true;
        }
        return false;
    }

    // ---------------- input ----------------
    static INPUT Scan(ushort sc, bool up, bool ext = false) => new()
    {
        type = INPUT_KEYBOARD,
        u = new InputUnion { ki = new KEYBDINPUT { wScan = sc, dwFlags = KEYEVENTF_SCANCODE | (up ? KEYEVENTF_KEYUP : 0) | (ext ? KEYEVENTF_EXTENDEDKEY : 0), dwExtraInfo = Magic } }
    };
    static INPUT Vk(ushort vk, bool up) => new()
    {
        type = INPUT_KEYBOARD,
        u = new InputUnion { ki = new KEYBDINPUT { wVk = vk, dwFlags = up ? KEYEVENTF_KEYUP : 0, dwExtraInfo = Magic } }
    };
    static void Send(params INPUT[] inp) { SendInput((uint)inp.Length, inp, Marshal.SizeOf<INPUT>()); Thread.Sleep(3); }
    static void TapScan(ushort sc, bool shift = false)
    {
        if (shift) Send(Scan(SC_LSHIFT, false));
        Send(Scan(sc, false)); Send(Scan(sc, true));
        if (shift) Send(Scan(SC_LSHIFT, true));
    }
    static void Replay(List<(int idx, bool shift)> keys) { foreach (var (i, s) in keys) TapScan((ushort)Layout.ScanCodes[i], s); }
    static void Combo(params ushort[] vks)
    {
        foreach (var v in vks) Send(Vk(v, false));
        foreach (var v in vks.Reverse()) Send(Vk(v, true));
    }

    /// <summary>Replays keys the user pressed while we were busy, then releases the hold.</summary>
    void FlushHeld()
    {
        while (true)
        {
            List<(KBDLLHOOKSTRUCT k, bool down)> batch;
            lock (gate)
            {
                if (held.Count == 0) { busy = false; return; }
                batch = held.ToList(); held.Clear();
            }
            foreach (var (k, down) in batch)
            {
                if (k.vkCode == VK_PAUSE) continue;
                bool ext = (k.flags & LLKHF_EXTENDED) != 0;
                Send(k.scanCode != 0 ? Scan((ushort)k.scanCode, !down, ext) : Vk((ushort)k.vkCode, !down));
                if (down) lock (gate) TrackReplayed(k);
            }
        }
    }

    void TrackReplayed(KBDLLHOOKSTRUCT k)
    {
        int idx = (k.flags & LLKHF_EXTENDED) == 0 ? Layout.IndexOfScan((int)k.scanCode) : -1;
        if (idx >= 0) { if (word.Count == 0) { wordHwnd = GetForegroundWindow(); wordLayout = LayoutOf(wordHwnd); } word.Add((idx, Shift)); }
        else if (k.vkCode == VK_SPACE || !IsModifier(k.vkCode)) Reset();
        if (k.vkCode == VK_SPACE) dirty = true; // words typed during a fix are not checked again
    }

    // ---------------- environment ----------------
    bool EnvOk(IntPtr hwnd)
    {
        var fg = GetForegroundWindow();
        if (fg != hwnd) { Count("skip_focus"); return false; }
        var cls = ClassName(fg);
        if (cls is "ConsoleWindowClass" or "CASCADIA_HOSTING_WINDOW_CLASS") { Count("skip_terminal"); return false; }
        var (name, elevated) = ProcessInfo(fg);
        if (BlockApps.Contains(name)) { Count("skip_app"); return false; }
        if (elevated == true && !selfElevated) { Count("skip_elevated"); return false; }
        var title = WindowText(fg).ToLowerInvariant();
        if (BlockTitles.Any(title.Contains)) { Count("skip_title"); return false; }
        if (IsPasswordFocused()) { Count("skip_password"); return false; }
        return true;
    }

    static bool IsPasswordFocused()
    {
        try
        {
            var t = Task.Run(() =>
            {
                var el = System.Windows.Automation.AutomationElement.FocusedElement;
                return el != null && el.Current.IsPassword;
            });
            return t.Wait(250) && t.Result;
        }
        catch { return false; }
    }

    // ---------------- jobs (worker thread) ----------------
    void Fix(List<(int idx, bool shift)> keys, string L, string O, IntPtr hwnd, string why)
    {
        try
        {
            if (!EnvOk(hwnd)) { TapScan(SC_SPACE); return; }
            for (int i = 0; i < keys.Count; i++) TapScan(SC_BACK);
            bool switched = SwitchLayout(O, hwnd);
            Replay(keys);          // if switching failed this simply restores the original text
            TapScan(SC_SPACE);
            if (switched) { lock (gate) last = new Last(keys, L, hwnd); Count("fixed_" + why); }
            else Count("error_layout");
        }
        finally { FlushHeld(); }
    }

    void Rollback(Last l)
    {
        try
        {
            if (!EnvOk(l.Hwnd)) { TapScan(SC_BACK); return; }
            for (int i = 0; i < l.Keys.Count + 1; i++) TapScan(SC_BACK);
            SwitchLayout(l.Layout, l.Hwnd);
            Replay(l.Keys);
            TapScan(SC_SPACE);
            lock (gate) sessionIgnore.Add(Key(l.Keys));
            Count("rollback");
        }
        finally { FlushHeld(); }
    }

    void ManualFix()
    {
        try
        {
            var fg = GetForegroundWindow();
            var cls = ClassName(fg);
            if (cls is "ConsoleWindowClass" or "CASCADIA_HOSTING_WINDOW_CLASS" || BlockApps.Contains(ProcessInfo(fg).name))
            { Notify?.Invoke("В этом окне ручное исправление не работает"); return; }
            string? saved = Clip.GetText();
            string? text = CopySelection();
            if (text == null) { Combo(VK_CONTROL, VK_SHIFT, VK_LEFT); Thread.Sleep(30); text = CopySelection(); }
            if (string.IsNullOrEmpty(text)) { Restore(saved); return; }
            var (fixedText, target) = Layout.Convert(text);
            text = null;
            Clip.SetText(fixedText);
            Combo(VK_CONTROL, (ushort)'V');
            Thread.Sleep(300);
            SwitchLayout(target, fg);
            Restore(saved);
            Count("manual");
        }
        finally { FlushHeld(); }
    }

    static void Restore(string? saved) { if (saved != null) Clip.SetText(saved); else Clip.Clear(); }

    static string? CopySelection()
    {
        uint seq = GetClipboardSequenceNumber();
        Combo(VK_CONTROL, (ushort)'C');
        for (int i = 0; i < 25; i++)
        {
            Thread.Sleep(20);
            if (GetClipboardSequenceNumber() != seq) { Thread.Sleep(20); return Clip.GetText(); }
        }
        return null;
    }
}

static class Clip
{
    static T Retry<T>(Func<T> f, T dflt)
    {
        for (int i = 0; i < 10; i++) { try { return f(); } catch { Thread.Sleep(30); } }
        return dflt;
    }
    public static string? GetText() => Retry(() => System.Windows.Forms.Clipboard.ContainsText() ? System.Windows.Forms.Clipboard.GetText() : null, null);
    public static void SetText(string s) => Retry(() => { System.Windows.Forms.Clipboard.SetText(s); return true; }, false);
    public static void Clear() => Retry(() => { System.Windows.Forms.Clipboard.Clear(); return true; }, false);
}

static class Log
{
    public static readonly string Dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SmartumSwitch");
    static readonly object g = new();
    public static void Write(string msg)
    {
        try { lock (g) { Directory.CreateDirectory(Dir); File.AppendAllText(Path.Combine(Dir, "smartum-switch.log"), $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {msg}\r\n"); } }
        catch { }
    }
}

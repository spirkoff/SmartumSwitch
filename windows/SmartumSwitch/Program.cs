// SmartumSwitch for Windows — tray app. Copyright (c) 2026 smARTum. MIT License.
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Text.Json;
using Microsoft.Win32;
using SmartumSwitch.Core;

namespace SmartumSwitch;

static class Program
{
    public static readonly string ConfigDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "SmartumSwitch");
    public static string ExceptionsFile => Path.Combine(ConfigDir, "exceptions.txt");
    static string SettingsFile => Path.Combine(ConfigDir, "settings.json");
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    [STAThread]
    static int Main(string[] args)
    {
        if (args.Contains("--uninstall")) { Uninstall(); return 0; }
        using var mutex = new Mutex(true, @"Local\SmartumSwitch", out bool first);
        if (!first) { MessageBox.Show("SmartumSwitch уже запущен (значок в трее).", "SmartumSwitch"); return 0; }
        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApp());
        return 0;
    }

    public static void Uninstall()
    {
        try { using var k = Registry.CurrentUser.OpenSubKey(RunKey, true); k?.DeleteValue("SmartumSwitch", false); } catch { }
        try { if (Directory.Exists(ConfigDir)) Directory.Delete(ConfigDir, true); } catch { }
        try { if (Directory.Exists(Log.Dir)) Directory.Delete(Log.Dir, true); } catch { }
        MessageBox.Show("Автозапуск и настройки SmartumSwitch удалены. Сам файл SmartumSwitch.exe удалите вручную.", "SmartumSwitch");
    }

    public static bool Autostart
    {
        get { using var k = Registry.CurrentUser.OpenSubKey(RunKey); return k?.GetValue("SmartumSwitch") != null; }
        set
        {
            using var k = Registry.CurrentUser.CreateSubKey(RunKey);
            if (value) k.SetValue("SmartumSwitch", $"\"{Environment.ProcessPath}\"");
            else k.DeleteValue("SmartumSwitch", false);
        }
    }

    public static bool LoadEnabled()
    {
        try { return JsonDocument.Parse(File.ReadAllText(SettingsFile)).RootElement.GetProperty("enabled").GetBoolean(); }
        catch { return true; }
    }
    public static void SaveEnabled(bool on)
    {
        Directory.CreateDirectory(ConfigDir);
        File.WriteAllText(SettingsFile, JsonSerializer.Serialize(new { enabled = on }));
    }
}

sealed class TrayApp : ApplicationContext
{
    readonly NotifyIcon tray;
    readonly Engine engine;
    readonly ToolStripMenuItem miEnabled, miAutostart;
    readonly System.Windows.Forms.Timer timer;
    readonly Control ui = new();
    readonly Icon iconOn, iconOff;
    DateTime excTime = DateTime.MinValue, lastStats = DateTime.Now;

    public TrayApp()
    {
        ui.CreateControl(); _ = ui.Handle;
        Directory.CreateDirectory(Program.ConfigDir);
        if (!File.Exists(Program.ExceptionsFile))
            File.WriteAllText(Program.ExceptionsFile,
                "# Слова, которые SmartumSwitch никогда не исправляет (по одному в строке, любой регистр).\r\n" +
                "# Можно писать как набрано или как было бы после исправления.\r\n", new System.Text.UTF8Encoding(true));
        using (var r = Res.Json("data.rules.json"))
        {
            Engine.BlockApps = r.RootElement.GetProperty("block_apps_windows").EnumerateArray().Select(e => e.GetString()!).ToHashSet();
            Engine.BlockTitles = r.RootElement.GetProperty("block_titles").EnumerateArray().Select(e => e.GetString()!).ToHashSet();
        }
        iconOn = MakeIcon(Color.FromArgb(0, 120, 215)); iconOff = MakeIcon(Color.Gray);
        engine = new Engine { Enabled = Program.LoadEnabled() };
        engine.Notify += m => ui.BeginInvoke(() => Balloon(m));
        engine.ToggleRequested += () => ui.BeginInvoke(Toggle);

        miEnabled = new ToolStripMenuItem("Автоисправление (Shift+Pause)", null, (_, _) => Toggle()) { Checked = engine.Enabled };
        miAutostart = new ToolStripMenuItem("Запускать при входе в Windows", null, (_, _) =>
        { Program.Autostart = !Program.Autostart; miAutostart!.Checked = Program.Autostart; }) { Checked = Program.Autostart };
        var menu = new ContextMenuStrip();
        menu.Items.Add(miEnabled);
        menu.Items.Add(new ToolStripMenuItem("Pause — исправить выделенное или последнее слово") { Enabled = false });
        menu.Items.Add(new ToolStripMenuItem("Исключения…", null, (_, _) =>
            System.Diagnostics.Process.Start("notepad.exe", $"\"{Program.ExceptionsFile}\"")));
        menu.Items.Add(miAutostart);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("О программе", null, (_, _) => MessageBox.Show(
            "SmartumSwitch 0.2 — свободный переключатель раскладки (QWERTY ⇄ ЙЦУКЕН).\n© 2026 smARTum, лицензия MIT.\n\n" +
            "Набранный текст нигде не сохраняется и никуда не отправляется.", "SmartumSwitch")));
        menu.Items.Add(new ToolStripMenuItem("Выход", null, (_, _) => ExitThread()));
        tray = new NotifyIcon { Text = "SmartumSwitch", ContextMenuStrip = menu, Visible = true };
        tray.DoubleClick += (_, _) => Toggle();
        UpdateIcon();

        Task.Run(() =>
        {
            try { var j = new Judge(); j.Exceptions = ReadExceptions(); engine.Judge = j; Log.Write("start: dictionaries loaded"); }
            catch (Exception ex) { Log.Write($"error: dictionaries {ex.GetType().Name}"); }
        });
        if (!Engine.HasBothLayouts())
            Balloon("Нужны раскладки «Английская (США)» и «Русская». Автоисправление заработает, когда обе будут добавлены.");
        else Balloon(engine.Enabled ? "Запущен. Автоисправление включено." : "Запущен. Автоисправление выключено.");

        timer = new System.Windows.Forms.Timer { Interval = 3000 };
        timer.Tick += (_, _) => Tick();
        timer.Start();
    }

    HashSet<string> ReadExceptions()
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            foreach (var l in File.ReadAllLines(Program.ExceptionsFile))
                if (l.Trim() is { Length: > 0 } t && !t.StartsWith('#')) set.Add(t);
            excTime = File.GetLastWriteTimeUtc(Program.ExceptionsFile);
        }
        catch { }
        return set;
    }

    void Tick()
    {
        try
        {
            if (engine.Judge != null && File.Exists(Program.ExceptionsFile) && File.GetLastWriteTimeUtc(Program.ExceptionsFile) != excTime)
                engine.Judge.Exceptions = ReadExceptions();
        }
        catch { }
        if ((DateTime.Now - lastStats).TotalMinutes >= 10) FlushStats();
    }

    void FlushStats()
    {
        lastStats = DateTime.Now;
        if (engine.Stats.IsEmpty) return;
        Log.Write("stats " + JsonSerializer.Serialize(engine.Stats.ToDictionary(k => k.Key, k => k.Value)));
        engine.Stats.Clear();
    }

    void Toggle()
    {
        engine.Enabled = !engine.Enabled;
        Program.SaveEnabled(engine.Enabled);
        miEnabled.Checked = engine.Enabled;
        UpdateIcon();
        Balloon("Автоисправление раскладки: " + (engine.Enabled ? "ВКЛЮЧЕНО" : "ВЫКЛЮЧЕНО"));
        Log.Write($"toggle enabled={engine.Enabled}");
    }

    void UpdateIcon()
    {
        tray.Icon = engine.Enabled ? iconOn : iconOff;
        tray.Text = "SmartumSwitch — " + (engine.Enabled ? "автоисправление вкл." : "автоисправление выкл.");
    }

    void Balloon(string text) => tray.ShowBalloonTip(2500, "SmartumSwitch", text, ToolTipIcon.None);

    static Icon MakeIcon(Color bg)
    {
        using var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            using var path = new GraphicsPath();
            path.AddArc(0, 0, 12, 12, 180, 90); path.AddArc(19, 0, 12, 12, 270, 90);
            path.AddArc(19, 19, 12, 12, 0, 90); path.AddArc(0, 19, 12, 12, 90, 90); path.CloseFigure();
            using var b = new SolidBrush(bg); g.FillPath(b, path);
            using var f = new Font("Segoe UI", 18, FontStyle.Bold, GraphicsUnit.Pixel);
            var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
            g.DrawString("S", f, Brushes.White, new RectangleF(0, 0, 32, 32), sf);
        }
        return (Icon)Icon.FromHandle(bmp.GetHicon()).Clone();
    }

    protected override void ExitThreadCore()
    {
        FlushStats(); Log.Write("stop");
        timer.Stop(); engine.Dispose();
        tray.Visible = false; tray.Dispose();
        base.ExitThreadCore();
    }
}

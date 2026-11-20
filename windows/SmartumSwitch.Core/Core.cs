// SmartumSwitch core for .NET — same rules as core/RULES.md and core/python/smartum_core.py.
// Copyright (c) 2026 smARTum. MIT License.
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;
using WeCantSpell.Hunspell;

namespace SmartumSwitch.Core;

public static class Res
{
    public static Stream Open(string name) =>
        typeof(Res).Assembly.GetManifestResourceStream(name) ?? throw new FileNotFoundException(name);
    public static JsonDocument Json(string name) { using var s = Open(name); return JsonDocument.Parse(s); }
}

/// <summary>The 34 keys that differ between US QWERTY and Russian JCUKEN.</summary>
public static class Layout
{
    public static readonly int[] ScanCodes;
    public static readonly string EnLower, EnUpper, RuLower, RuUpper, ExtraEn, ExtraRu;
    static readonly Dictionary<int, int> ScanToIndex = new();
    static Layout()
    {
        using var d = Res.Json("data.layout.json");
        var r = d.RootElement;
        ScanCodes = r.GetProperty("scancodes_set1").EnumerateArray().Select(e => e.GetInt32()).ToArray();
        EnLower = r.GetProperty("en_lower").GetString()!; EnUpper = r.GetProperty("en_upper").GetString()!;
        RuLower = r.GetProperty("ru_lower").GetString()!; RuUpper = r.GetProperty("ru_upper").GetString()!;
        ExtraEn = r.GetProperty("manual_extra_en").GetString()!; ExtraRu = r.GetProperty("manual_extra_ru").GetString()!;
        for (int i = 0; i < ScanCodes.Length; i++) ScanToIndex[ScanCodes[i]] = i;
    }
    public static int IndexOfScan(int scan) => ScanToIndex.TryGetValue(scan, out var i) ? i : -1;

    public static string Render(IReadOnlyList<(int idx, bool shift)> keys, string lay, bool caps)
    {
        var lo = lay == "ru" ? RuLower : EnLower; var up = lay == "ru" ? RuUpper : EnUpper;
        var sb = new System.Text.StringBuilder();
        foreach (var (idx, shift) in keys)
        {
            bool u = shift;
            if (caps && char.IsLetter(lo[idx])) u = !u;
            sb.Append(u ? up[idx] : lo[idx]);
        }
        return sb.ToString();
    }

    /// <summary>Convert text typed in the wrong layout (manual fix). Returns text and target layout.</summary>
    public static (string text, string target) Convert(string text)
    {
        string en = EnLower + EnUpper + ExtraEn, ru = RuLower + RuUpper + ExtraRu;
        int cyr = text.Count(c => Text.IsCyr(c)), lat = text.Count(c => c is >= 'a' and <= 'z' or >= 'A' and <= 'Z');
        bool toEn = cyr > lat;
        var sb = new System.Text.StringBuilder();
        foreach (var c in text)
        {
            int i = toEn ? ru.IndexOf(c) : en.IndexOf(c);
            sb.Append(i >= 0 ? (toEn ? en[i] : ru[i]) : c);
        }
        return (sb.ToString(), toEn ? "en" : "ru");
    }

    /// <summary>Same keys in the other layout (for tests): maps shown text char by char.</summary>
    public static string Retype(string shown, string from)
    {
        string a = from == "en" ? EnLower + EnUpper : RuLower + RuUpper;
        string b = from == "en" ? RuLower + RuUpper : EnLower + EnUpper;
        return new string(shown.Select(c => { int i = a.IndexOf(c); return i >= 0 ? b[i] : c; }).ToArray());
    }
}

public static class Text
{
    public static bool IsCyr(char c) => c is >= 'а' and <= 'я' or >= 'А' and <= 'Я' or 'ё' or 'Ё';
    public static bool IsLetter(char c) => IsCyr(c) || c is >= 'a' and <= 'z' or >= 'A' and <= 'Z';
    static readonly Regex Edges = new(@"^[^a-zA-Zа-яёА-ЯЁ]+|[^a-zA-Zа-яёА-ЯЁ]+$", RegexOptions.Compiled);
    public static string Core(string s) => Edges.Replace(s, "");
}

public sealed class Judge
{
    readonly Dictionary<string, WordList> dict = new();
    readonly Dictionary<string, (double tot, Dictionary<string, int> c)> bg = new();
    readonly Dictionary<string, HashSet<string>> shortWords = new();
    readonly double minLetters, bgMinLetters, margin, shownMinMax, otherMinMin, smooth;
    public HashSet<string> Exceptions { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public static string Other(string lay) => lay == "en" ? "ru" : "en";

    public Judge()
    {
        foreach (var (lay, f) in new[] { ("ru", "ru_RU"), ("en", "en_US") })
        {
            using var dic = Res.Open($"dict.{f}.dic"); using var aff = Res.Open($"dict.{f}.aff");
            dict[lay] = WordList.CreateFromStreams(dic, aff);
        }
        using (var b = Res.Json("data.bigrams.json"))
            foreach (var p in b.RootElement.EnumerateObject())
                bg[p.Name] = (p.Value.GetProperty("tot").GetDouble(),
                    p.Value.GetProperty("c").EnumerateObject().ToDictionary(x => x.Name, x => x.Value.GetInt32()));
        using var r = Res.Json("data.rules.json"); var R = r.RootElement;
        minLetters = R.GetProperty("min_letters").GetDouble(); bgMinLetters = R.GetProperty("bigram_min_letters").GetDouble();
        margin = R.GetProperty("bigram_avg_margin").GetDouble(); shownMinMax = R.GetProperty("bigram_displayed_min_max").GetDouble();
        otherMinMin = R.GetProperty("bigram_other_min_min").GetDouble(); smooth = R.GetProperty("bigram_smoothing").GetDouble();
        foreach (var p in R.GetProperty("short_words").EnumerateObject())
            shortWords[p.Name] = p.Value.EnumerateArray().Select(e => e.GetString()!).ToHashSet();
        foreach (var p in R.GetProperty("known_words").EnumerateObject())
            if (!p.Name.StartsWith("_"))
                knownWords[p.Name] = p.Value.EnumerateArray().Select(e => e.GetString()!).ToHashSet(StringComparer.OrdinalIgnoreCase);
    }

    readonly Dictionary<string, HashSet<string>> knownWords = new();
    /// <summary>User words (brands, names): valid in the layout of their letters.</summary>
    public void AddWords(IEnumerable<string> words)
    {
        foreach (var raw in words)
        {
            var w = raw.Trim(); if (w.Length == 0 || w.StartsWith("#")) continue;
            var lay = w.Any(ch => (ch >= 'а' && ch <= 'я') || (ch >= 'А' && ch <= 'Я') || ch == 'ё' || ch == 'Ё') ? "ru" : "en";
            knownWords[lay].Add(w);
        }
    }
    bool Known(string lay, string w) => Valid(lay, w) || (knownWords.TryGetValue(lay, out var k) && k.Contains(w));

    public bool Valid(string lay, string w) => dict[lay].Check(w);

    (double avg, double min) Score(string w, string lay)
    {
        var (tot, c) = bg[lay]; w = "^" + w.ToLowerInvariant() + "$";
        double sum = 0, mn = double.MaxValue;
        for (int i = 0; i + 1 < w.Length; i++)
        {
            c.TryGetValue(w.Substring(i, 2), out int n);
            double s = Math.Log((n + smooth) / tot); sum += s; mn = Math.Min(mn, s);
        }
        return (sum / (w.Length - 1), mn);
    }

    public (bool fix, string why) ShouldFix(string shown, string other, string L, string O)
    {
        string d = Text.Core(shown), o = Text.Core(other);
        if (Exceptions.Contains(d) || Exceptions.Contains(o) || Exceptions.Contains(shown)) return (false, "exception");
        int nd = d.Count(Text.IsLetter), no = o.Count(Text.IsLetter);
        if (no < minLetters || no < nd) return (false, "short");
        if (!o.All(Text.IsLetter)) return (false, "punct");
        if (d.Length > 0 && Known(L, d)) return (false, "valid");
        if (no == 2) return (shortWords[O].Contains(o.ToLowerInvariant()) && !shortWords[L].Contains(d.ToLowerInvariant()), "short2");
        if (Known(O, o)) return (true, "dict");
        if (no >= bgMinLetters && d.Length > 0 && d.All(Text.IsLetter))
        {
            var sd = Score(d, L); var so = Score(o, O);
            if (so.avg - sd.avg >= margin && sd.min <= shownMinMax && so.min >= otherMinMin) return (true, "bigram");
        }
        return (false, "unsure");
    }
}

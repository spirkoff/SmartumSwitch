// Runs core/tests/cases.json against the .NET core. Exit code 0 = all passed.
using System.Text.Json;
using SmartumSwitch.Core;

var path = args.Length > 0 ? args[0] : Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "core", "tests", "cases.json");
var cases = JsonDocument.Parse(File.ReadAllText(path)).RootElement;
var sw = System.Diagnostics.Stopwatch.StartNew();
var j = new Judge();
Console.WriteLine($"dictionaries loaded in {sw.ElapsedMilliseconds} ms");
int bad = 0, n = 0; sw.Restart();
foreach (var c in cases.EnumerateArray())
{
    n++;
    string shown = c.GetProperty("shown").GetString()!, L = c.GetProperty("layout").GetString()!;
    bool exp = c.GetProperty("fix").GetBoolean();
    string other = Layout.Retype(shown, L);
    var (fix, why) = j.ShouldFix(shown, other, L, Judge.Other(L));
    bool okRes = !fix || other == c.GetProperty("result").GetString();
    if (fix != exp || !okRes) { bad++; Console.WriteLine($"  FAIL {shown} ({L}) expected fix={exp} got {fix} ({why})"); }
}
Console.WriteLine($"dotnet-core: {n - bad}/{n} passed, {sw.Elapsed.TotalMilliseconds / Math.Max(n, 1):F2} ms per word");
// layout sanity: scan code -> render
var keys = "ghbdtn".Select(ch => (Layout.EnLower.IndexOf(ch), false)).ToList();
var r1 = Layout.Render(keys, "ru", false); var r2 = Layout.Convert("ghbdtn, rfr ltkf?").text;
Console.WriteLine($"render: {r1} | convert: {r2}");
if (r1 != "привет" || r2 != "приветб как дела,") bad++;
return bad == 0 ? 0 : 1;

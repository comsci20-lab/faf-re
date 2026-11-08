using System;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using System.Text;

// Exercises installer behavior only in a unique temporary fixture, without network access.
internal static class BuilderTests
{
    static void Assert(bool condition, string message) { if (!condition) throw new Exception(message); }
    static void FakeEngine(string directory)
    {
        Directory.CreateDirectory(Path.Combine(directory, "fafengine"));
        using (var writer = new BinaryWriter(File.Create(Path.Combine(directory, "main_x64.exe"))))
        {
            writer.Write((ushort)0x5a4d); writer.BaseStream.Position = 0x3c; writer.Write(64);
            writer.BaseStream.Position = 64; writer.Write((uint)0x4550); writer.Write((ushort)0x8664);
        }
        File.WriteAllText(Path.Combine(directory, "init_faf.lua"), "-- init");
    }
    internal static int Run()
    {
        string root = Path.Combine(Path.GetTempPath(), "microchip-builder-test-" + Guid.NewGuid().ToString("N"));
        try
        {
            string data = Path.Combine(root, "FAF Data"), engine = Path.Combine(data, "bin_x64"), custom = Path.Combine(root, "Custom engine");
            Directory.CreateDirectory(Path.Combine(data, "bin"));
            File.WriteAllText(Path.Combine(data, "fa_path.lua"), "-- local path");
            File.WriteAllText(Path.Combine(data, "bin", "init_faf.lua"), "-- local init");
            string prefs = Path.Combine(root, "client.prefs");
            string original = "{\"forgedAlliance\":{\"executionDirectory\":\"\"},\"keep\":123}";
            File.WriteAllText(prefs, original);
            Assert(Setup.Detect(prefs, new[] { engine }).Count == 0, "Unexpected engine detection");
            FakeEngine(custom);
            Setup.Connect(custom, prefs);
            Assert(Setup.Detect(prefs, new[] { engine }).Single() == custom, "Configured engine detection");
            var configured = Setup.ReadSettings(prefs);
            Setup.GameSettings(configured)["executionDirectory"] = "";
            File.WriteAllText(prefs, Setup.Json.Serialize(configured));
            Assert(Setup.Detect(prefs, new[] { engine }).Single() == custom, "Executable command detection");
            File.WriteAllText(prefs, original);
            string output = Path.Combine(root, "output"); FakeEngine(output);
            File.WriteAllBytes(Path.Combine(output, "dxcompiler.dll"), new byte[] { 1, 2, 3 });
            File.WriteAllBytes(Path.Combine(output, "dxil.dll"), new byte[] { 4, 5, 6 });
            string backup = Setup.InstallBuild(data, output, new string('a', 40), false);
            Assert(File.ReadAllText(prefs) == original, "Build modified FAF settings");
            Assert(Setup.IsEngine(engine), "Build did not install engine");
            Assert(File.ReadAllText(Path.Combine(engine, "init_faf.lua")) == "-- local init", "Initialization scripts");
            foreach (string name in Setup.Hooks)
                Assert(File.ReadAllBytes(Path.Combine(engine, "fafengine", "lua", "ui", "lobby", name)).SequenceEqual(Setup.Resource(name)), "Lag Test payload");
            byte[] before = File.ReadAllBytes(Path.Combine(engine, "main_x64.exe"));
            Setup.InstallHooks(engine);
            Assert(File.ReadAllBytes(Path.Combine(engine, "main_x64.exe")).SequenceEqual(before), "Hook install replaced engine");
            Assert(File.ReadAllText(prefs) == original, "Lag Test changed FAF settings");
            Setup.InstallBuild(data, output, new string('b', 40), false, custom);
            Assert(File.Exists(Path.Combine(custom, "microchip-install.json")), "Update ignored the detected custom directory");
            Assert(File.ReadAllText(prefs) == original, "Custom engine update changed FAF settings");
            Assert((string)Setup.Json.Deserialize<Dictionary<string, object>>(File.ReadAllText(Path.Combine(custom, "microchip-install.json")))["revision"] == new string('b', 40), "Selected version was not recorded");
            File.Delete(Path.Combine(output, "dxil.dll"));
            try { Setup.InstallBuild(data, output, new string('c', 40), false); throw new Exception("Accepted incomplete build"); }
            catch (FileNotFoundException) { }
            Assert(File.ReadAllBytes(Path.Combine(engine, "main_x64.exe")).SequenceEqual(before), "Failed build changed installed engine");
            Setup.Connect(engine, prefs);
            var settings = Setup.ReadSettings(prefs); var game = Setup.GameSettings(settings);
            Assert((int)settings["keep"] == 123 && (string)game["executionDirectory"] == engine, "Client preferences");
            Assert(((string)game["executableDecorator"]).Contains("ren_GpuSelectBrackets=0"), "Selection fix missing");
            string oldPrefs = File.ReadAllText(prefs);
            string enginePath = Path.Combine(engine, "main_x64.exe");
            File.WriteAllText(enginePath, "rollback sentinel");
            var writes = new Dictionary<string, byte[]> { { enginePath, new byte[] { 1 } }, { prefs, Encoding.UTF8.GetBytes("changed") } };
            using (var locked = new FileStream(prefs, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                try { Setup.WriteFiles(data, writes); throw new Exception("Expected locked-file failure"); }
                catch (IOException) { }
            }
            Assert(File.ReadAllText(enginePath) == "rollback sentinel" && File.ReadAllText(prefs) == oldPrefs, "Rollback did not preserve files");
            Assert(File.Exists(Path.Combine(backup, "restore-map.json")), "Backup manifest missing");
            Assert(Directory.GetAccessControl(backup).AreAccessRulesProtected, "Backup inherited public permissions");
            Assert(Setup.Quote(@"C:\path with spaces\") == "\"C:\\path with spaces\\\\\"", "Argument quoting");
            return 0;
        }
        catch (Exception error) { File.WriteAllText(Path.Combine(Path.GetTempPath(), "microchip-builder-selftest-error.txt"), error.ToString()); return 1; }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
}

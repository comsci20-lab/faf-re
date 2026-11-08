using System;
using System.IO;
using System.Reflection;
using System.Collections.Generic;
using System.IO.Compression;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: AssemblyTitle("FAF Lag Test Installer")]
[assembly: AssemblyDescription("Installs the lobby Lag Test hook for the rebuilt FAF engine")]
[assembly: AssemblyCompany("Microchip")]
[assembly: AssemblyProduct("FAF Lag Test")]
[assembly: AssemblyCopyright("Author: Microchip")]
[assembly: AssemblyVersion("1.1.0.0")]

internal static class Installer
{
    private static Dictionary<string, byte[]> Payload()
    {
        var files = new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);
        using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("engine.zip"))
        using (var zip = new ZipArchive(stream, ZipArchiveMode.Read))
            foreach (var entry in zip.Entries)
            {
                string name = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                if (Path.IsPathRooted(name) || name.Contains("..") || name.Contains(":"))
                    throw new InvalidDataException("Invalid package path.");
                using (var source = entry.Open())
                using (var buffer = new MemoryStream())
                {
                    source.CopyTo(buffer);
                    if (buffer.Length == 0) throw new InvalidDataException("Empty package file.");
                    files.Add(name, buffer.ToArray());
                }
            }
        foreach (string required in new[] { "main_x64.exe", "dxcompiler.dll", "dxil.dll", @"fafengine\lua\ui\lobby\lobby.lua", @"fafengine\lua\ui\lobby\connectiontest.lua", @"fafengine\lua\ui\lobby\connectionscore.lua" })
            if (!files.ContainsKey(required)) throw new InvalidDataException("Missing " + required);
        return files;
    }

    private static string Install(string root, string prefs)
    {
        if (!Environment.Is64BitOperatingSystem) throw new IOException("64-bit Windows is required.");
        root = Path.GetFullPath(root);
        string source = Path.Combine(root, "bin"), target = Path.Combine(root, "bin_x64");
        if (!File.Exists(Path.Combine(root, "fa_path.lua")) || !File.Exists(Path.Combine(source, "init_faf.lua")))
            throw new IOException("Choose the FAF data folder containing fa_path.lua and bin. Launch a normal FAF game once first.");
        if (!File.Exists(prefs)) throw new IOException("FAF client settings were not found. Open and close the FAF client first.");
        CheckPath(target); CheckPath(Path.GetDirectoryName(prefs));
        var json = new JavaScriptSerializer { MaxJsonLength = 16777216 };
        var settings = json.Deserialize<Dictionary<string, object>>(File.ReadAllText(prefs));
        object value;
        var game = settings.TryGetValue("forgedAlliance", out value) ? value as Dictionary<string, object> : null;
        if (game == null) throw new IOException("The FAF client settings format is unsupported.");
        var files = Payload();
        foreach (string name in new[] { "init.lua", "init_faf.lua", "init_fafbeta.lua", "init_ladder1v1.lua", "init_nonxt.lua", "SupComDataPath.lua", "SupComDataPathFAF.lua" })
        {
            string path = Path.Combine(source, name);
            if (File.Exists(path)) files[name] = File.ReadAllBytes(path);
        }
        var writes = new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);
        foreach (var file in files) writes.Add(Path.Combine(target, file.Key), file.Value);
        game["executionDirectory"] = target;
        game["executableDecorator"] = "\"" + Path.Combine(target, "main_x64.exe") + "\" /con lua_AllowPrecompiledChunks=1;ren_GpuSelectBrackets=0";
        writes.Add(Path.GetFullPath(prefs), System.Text.Encoding.UTF8.GetBytes(json.Serialize(settings)));
        foreach (string path in writes.Keys)
        {
            CheckPath(Path.GetDirectoryName(path));
            if (File.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Cannot replace linked files.");
        }
        string backup = Path.Combine(root, "lag-test-backups", Guid.NewGuid().ToString("N"));
        CheckPath(backup); Directory.CreateDirectory(backup);
        var originals = new Dictionary<string, string>();
        int index = 0;
        foreach (string path in writes.Keys)
        {
            string saved = null;
            if (File.Exists(path)) { saved = Path.Combine(backup, (++index).ToString() + "-" + Path.GetFileName(path)); File.Copy(path, saved); }
            originals.Add(path, saved);
        }
        File.WriteAllText(Path.Combine(backup, "restore-map.json"), json.Serialize(originals));
        var changed = new List<string>();
        try
        {
            foreach (var file in writes)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(file.Key));
                changed.Add(file.Key);
                File.WriteAllBytes(file.Key, file.Value);
            }
        }
        catch
        {
            foreach (string path in changed)
            {
                if (originals[path] == null) File.Delete(path);
                else File.Copy(originals[path], path, true);
            }
            throw;
        }
        return backup;
    }

    private static int SelfTest()
    {
        string root = Path.Combine(Path.GetTempPath(), "faf-installer-test-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(Path.Combine(root, "bin"));
            File.WriteAllText(Path.Combine(root, "fa_path.lua"), "-- test");
            File.WriteAllText(Path.Combine(root, "bin", "init_faf.lua"), "-- local init");
            string prefs = Path.Combine(root, "client.prefs");
            File.WriteAllText(prefs, "{\"forgedAlliance\":{},\"keep\":123}");
            string backup = Install(root, prefs);
            var settings = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(prefs));
            var game = (Dictionary<string, object>)settings["forgedAlliance"];
            if ((int)settings["keep"] != 123 || (string)game["executionDirectory"] != Path.Combine(root, "bin_x64")) return 1;
            foreach (var file in Payload())
                if (!Convert.ToBase64String(File.ReadAllBytes(Path.Combine(root, "bin_x64", file.Key))).Equals(Convert.ToBase64String(file.Value))) return 2;
            if (!File.Exists(Path.Combine(backup, "restore-map.json"))) return 3;
            if (!((string)game["executableDecorator"]).Contains("ren_GpuSelectBrackets=0")) return 4;
            Install(root, prefs); // Updating an existing installation also backs it up.
            string engine = Path.Combine(root, "bin_x64", "main_x64.exe");
            File.WriteAllText(engine, "rollback sentinel");
            using (var locked = new FileStream(prefs, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                try { Install(root, prefs); return 5; }
                catch (IOException) { }
            }
            if (File.ReadAllText(engine) != "rollback sentinel") return 6;
            return 0;
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    private static void CheckPath(string path)
    {
        for (DirectoryInfo directory = new DirectoryInfo(path); directory != null; directory = directory.Parent)
            if (directory.Exists && (directory.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Choose a folder without links or junctions.");
    }

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--verify")
        {
            Payload();
            return 0;
        }
        if (args.Length == 1 && args[0] == "--selftest") return SelfTest();
        Application.EnableVisualStyles();
        using (Form form = new Form())
        {
            form.Text = "FAF Lag Test Setup - Microchip";
            form.ClientSize = new System.Drawing.Size(570, 240);
            form.FormBorderStyle = FormBorderStyle.FixedDialog;
            form.MaximizeBox = false;
            form.StartPosition = FormStartPosition.CenterScreen;
            Label description = new Label { Left = 20, Top = 18, Width = 530, Height = 90,
                Text = "FAF Lag Test\r\nAuthor: Microchip\r\n\r\nInstalls the rebuilt x64 engine and Lag Test, and configures FAF.\r\nSelect the FAF data folder. FAF and Forged Alliance must be installed." };
            TextBox folder = new TextBox { Left = 20, Top = 116, Width = 420,
                Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "FAForever") };
            Button browse = new Button { Left = 450, Top = 113, Width = 100, Text = "Browse..." };
            browse.Click += delegate {
                using (FolderBrowserDialog picker = new FolderBrowserDialog())
                {
                    if (Directory.Exists(folder.Text)) picker.SelectedPath = folder.Text;
                    if (picker.ShowDialog(form) == DialogResult.OK) folder.Text = picker.SelectedPath;
                }
            };
            CheckBox closed = new CheckBox { Left = 20, Top = 153, Width = 530, Text = "I have closed the FAF client and game." };
            Button install = new Button { Left = 340, Top = 180, Width = 100, Text = "Install" };
            Button close = new Button { Left = 450, Top = 180, Width = 100, Text = "Close" };
            close.Click += delegate { form.Close(); };
            install.Click += delegate {
                try
                {
                    if (!closed.Checked) throw new IOException("Close the FAF client and game, then tick the confirmation box.");
                    foreach (string dll in new[] { "d3dx9_43.dll", "X3DAudio1_7.dll" })
                        if (!File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", dll)))
                            throw new IOException("The 64-bit DirectX June 2010 runtime is required (missing " + dll + "). Install Microsoft's DirectX End-User Runtimes, then run setup again.");
                    string prefs = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Forged Alliance Forever", "client.prefs");
                    string backup = Install(folder.Text, prefs);
                    MessageBox.Show(form, "Engine and Lag Test installed. Open FAF to play.\r\n\r\nPrevious files and FAF settings were backed up to:\r\n" + backup,
                        "Installation complete", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    form.Close();
                }
                catch (UnauthorizedAccessException)
                {
                    MessageBox.Show(form, "Windows denied access to that folder. Close setup, then run it as administrator if you trust it.", "Installation failed");
                }
                catch (Exception error) { MessageBox.Show(form, error.Message, "Installation failed"); }
            };
            form.Controls.AddRange(new Control[] { description, folder, browse, closed, install, close });
            Application.Run(form);
        }
        return 0;
    }
}

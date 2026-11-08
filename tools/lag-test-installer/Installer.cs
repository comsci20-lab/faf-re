using System;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("FAF Lag Test Installer")]
[assembly: AssemblyDescription("Installs the lobby Lag Test hook for the rebuilt FAF engine")]
[assembly: AssemblyCompany("Microchip")]
[assembly: AssemblyProduct("FAF Lag Test")]
[assembly: AssemblyCopyright("Author: Microchip")]
[assembly: AssemblyVersion("1.0.0.0")]

internal static class Installer
{
    private static readonly string[] Files = { "lobby.lua", "connectiontest.lua", "connectionscore.lua" };

    private static byte[] Payload(string name)
    {
        using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
        {
            if (stream == null) throw new InvalidDataException("Missing installer file: " + name);
            using (MemoryStream buffer = new MemoryStream())
            {
                stream.CopyTo(buffer);
                return buffer.ToArray();
            }
        }
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
            foreach (string name in Files) if (Payload(name).Length == 0) return 1;
            return 0;
        }
        Application.EnableVisualStyles();
        using (Form form = new Form())
        {
            form.Text = "FAF Lag Test Setup - Microchip";
            form.ClientSize = new System.Drawing.Size(570, 240);
            form.FormBorderStyle = FormBorderStyle.FixedDialog;
            form.MaximizeBox = false;
            form.StartPosition = FormStartPosition.CenterScreen;
            Label description = new Label { Left = 20, Top = 18, Width = 530, Height = 90,
                Text = "FAF Lag Test\r\nAuthor: Microchip\r\n\r\nRequires the rebuilt FAF engine. Close the game before installing.\r\nSelect its main_x64.exe. Every participant needs this hook." };
            TextBox folder = new TextBox { Left = 20, Top = 116, Width = 420,
                Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "FAForever", "bin_x64") };
            Button browse = new Button { Left = 450, Top = 113, Width = 100, Text = "Browse..." };
            browse.Click += delegate {
                using (OpenFileDialog picker = new OpenFileDialog())
                {
                    picker.Filter = "Rebuilt FAF engine (main_x64.exe)|main_x64.exe";
                    if (Directory.Exists(folder.Text)) picker.InitialDirectory = folder.Text;
                    if (picker.ShowDialog(form) == DialogResult.OK) folder.Text = Path.GetDirectoryName(picker.FileName);
                }
            };
            Button install = new Button { Left = 340, Top = 180, Width = 100, Text = "Install" };
            Button close = new Button { Left = 450, Top = 180, Width = 100, Text = "Close" };
            close.Click += delegate { form.Close(); };
            install.Click += delegate {
                try
                {
                    string root = Path.GetFullPath(folder.Text);
                    if (!File.Exists(Path.Combine(root, "main_x64.exe")) || !Directory.Exists(Path.Combine(root, "fafengine")))
                        throw new IOException("Select the folder containing the rebuilt main_x64.exe and its fafengine folder.");
                    string target = Path.Combine(root, "fafengine", "lua", "ui", "lobby");
                    CheckPath(target);
                    foreach (string name in Files)
                    {
                        string path = Path.Combine(target, name);
                        if (File.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                            throw new IOException("Cannot replace linked files.");
                    }
                    string backup = Path.Combine(root, "fafengine", "lag-test-backups", Guid.NewGuid().ToString("N"));
                    CheckPath(backup);
                    Directory.CreateDirectory(backup);
                    Directory.CreateDirectory(target);
                    foreach (string name in Files)
                    {
                        string path = Path.Combine(target, name);
                        if (File.Exists(path)) File.Copy(path, Path.Combine(backup, name));
                    }
                    foreach (string name in Files) File.WriteAllBytes(Path.Combine(target, name), Payload(name));
                    MessageBox.Show(form, "Lag Test installed. Relaunch the game.\r\n\r\nPrevious files, if present, were backed up to:\r\n" + backup,
                        "Installation complete", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    form.Close();
                }
                catch (UnauthorizedAccessException)
                {
                    MessageBox.Show(form, "Windows denied access to that folder. Close setup, then run it as administrator if you trust it.", "Installation failed");
                }
                catch (Exception error) { MessageBox.Show(form, error.Message, "Installation failed"); }
            };
            form.Controls.AddRange(new Control[] { description, folder, browse, install, close });
            Application.Run(form);
        }
        return 0;
    }
}

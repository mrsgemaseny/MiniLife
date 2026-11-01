using System;
using System.Diagnostics;
using System.IO;

namespace PixelArchitect
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            string appDir = AppDomain.CurrentDomain.BaseDirectory;
            string projectDir = Path.Combine(appDir, "tools", "PixelArchitect");
            if (!Directory.Exists(projectDir))
            {
                // In case exe is inside tools/PixelArchitect directly
                projectDir = appDir;
            }

            string godotExe = @"C:\Users\murat\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe";
            if (!File.Exists(godotExe))
            {
                godotExe = @"C:\Users\murat\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe";
            }

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = godotExe;
            psi.Arguments = "--path \"" + projectDir + "\"";
            psi.WorkingDirectory = projectDir;
            psi.UseShellExecute = false;

            Process.Start(psi);
        }
    }
}

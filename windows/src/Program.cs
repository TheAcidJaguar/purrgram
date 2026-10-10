// Purrgram for Windows (Lite) — a little pixel cat that lives on your desktop.
// Click to pet, double-click to shoo, drag to pick up. Keep the bowls full! Everything else is in the tray icon's menu.

using System;
using System.IO;
using System.Threading;
using System.Windows.Forms;

namespace Purrgram
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            using (var one = new Mutex(true, @"Local\Purrgram.SingleInstance", out bool first))
            {
                if (!first) return;   // one cat at a time
                Application.ThreadException += (s, e) => Log(e.Exception);
                AppDomain.CurrentDomain.UnhandledException += (s, e) => Log(e.ExceptionObject as Exception);
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new CatApp());
            }
        }

        /// Problems go to %APPDATA%\Purrgram\errors.log (kept small), so testers can send it over.
        public static void Log(Exception ex)
        {
            try
            {
                var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Purrgram");
                Directory.CreateDirectory(dir);
                var path = Path.Combine(dir, "errors.log");
                if (File.Exists(path) && new FileInfo(path).Length > 200_000) File.Delete(path);
                File.AppendAllText(path, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss}  {ex}\r\n\r\n");
            }
            catch { }
        }
    }
}

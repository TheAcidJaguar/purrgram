// Purrgram for Windows (Lite) — a little pixel cat that lives on your desktop.
// Click to pet, double-click to shoo, drag to pick up. Keep the bowls full! Everything else is in the tray icon's menu.

using System;
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
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new CatApp());
            }
        }
    }
}

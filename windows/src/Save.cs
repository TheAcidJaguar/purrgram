// Purrgram for Windows — saved state, written atomically with a backup copy (%APPDATA%\Purrgram).

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace Purrgram
{
    class SaveState
    {
        public string Name = "Mochi";
        public int Coat = 0;
        public double Belly = 0.8, Hydration = 0.8, Energy = 0.9, Happiness = 0.8;
        public double Food = 0.6, Water = 0.6;
        public int Personality = -1;     // picked at random on first launch
        public bool Named = false;

        static double Unit(double v, double def) => double.IsNaN(v) || double.IsInfinity(v) ? def : Math.Min(1, Math.Max(0, v));

        public void Sanitize()
        {
            Belly = Unit(Belly, 0.8); Hydration = Unit(Hydration, 0.8); Energy = Unit(Energy, 0.9); Happiness = Unit(Happiness, 0.8);
            Food = Unit(Food, 0.6); Water = Unit(Water, 0.6);
            if (Coat < 0 || Coat >= Assets.CoatNames.Length) Coat = 0;
            if (Personality >= Assets.MoodNames.Length) Personality = -1;
            if (string.IsNullOrWhiteSpace(Name)) Name = "Mochi";
            Name = Name.Replace("\n", " ").Replace("\r", " ").Trim();
            if (Name.Length > 40) Name = Name.Substring(0, 40);
        }

        string Serialize()
        {
            var c = CultureInfo.InvariantCulture;
            var sb = new StringBuilder();
            void W(string k, object v) => sb.Append(k).Append('=').Append(Convert.ToString(v, c)).Append('\n');
            W("name", Name); W("coat", Coat); W("belly", Belly); W("hydration", Hydration); W("energy", Energy);
            W("happiness", Happiness); W("food", Food); W("water", Water); W("personality", Personality); W("named", Named);
            return sb.ToString();
        }

        /// Tolerant: unknown or missing keys keep their defaults, so adding fields never resets a cat.
        static SaveState Parse(string text)
        {
            var s = new SaveState();
            var kv = new Dictionary<string, string>();
            foreach (var line in text.Split('\n'))
            {
                int i = line.IndexOf('=');
                if (i > 0) kv[line.Substring(0, i).Trim()] = line.Substring(i + 1).Trim();
            }
            if (kv.Count == 0) return null;
            var c = CultureInfo.InvariantCulture;
            double D(string k, double def) => kv.TryGetValue(k, out var v) && double.TryParse(v, NumberStyles.Float, c, out var d) ? d : def;
            int I(string k, int def) => kv.TryGetValue(k, out var v) && int.TryParse(v, NumberStyles.Integer, c, out var d) ? d : def;
            if (kv.TryGetValue("name", out var n)) s.Name = n;
            s.Coat = I("coat", s.Coat); s.Personality = I("personality", s.Personality);
            s.Belly = D("belly", s.Belly); s.Hydration = D("hydration", s.Hydration); s.Energy = D("energy", s.Energy);
            s.Happiness = D("happiness", s.Happiness); s.Food = D("food", s.Food); s.Water = D("water", s.Water);
            s.Named = kv.TryGetValue("named", out var nm) && nm.Equals("true", StringComparison.OrdinalIgnoreCase);
            s.Sanitize();
            return s;
        }

        static string Dir
        {
            get
            {
                var d = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Purrgram");
                Directory.CreateDirectory(d);
                return d;
            }
        }
        static string MainPath => Path.Combine(Dir, "state.txt");
        static string BackupPath => Path.Combine(Dir, "state.backup.txt");

        public static SaveState Load()
        {
            foreach (var p in new[] { MainPath, BackupPath })
            {
                try { if (File.Exists(p)) { var s = Parse(File.ReadAllText(p, Encoding.UTF8)); if (s != null) return s; } }
                catch { }
            }
            return new SaveState();
        }

        static readonly object saveLock = new object();

        public void Save()
        {
            lock (saveLock) SaveNow();
        }

        void SaveNow()
        {
            try
            {
                Sanitize();
                var tmp = MainPath + ".tmp";
                File.WriteAllText(tmp, Serialize(), Encoding.UTF8);
                if (File.Exists(MainPath))
                {
                    try { if (Parse(File.ReadAllText(MainPath, Encoding.UTF8)) != null) File.Copy(MainPath, BackupPath, true); } catch { }
                    File.Replace(tmp, MainPath, null);
                }
                else File.Move(tmp, MainPath);
            }
            catch { }
        }
    }
}

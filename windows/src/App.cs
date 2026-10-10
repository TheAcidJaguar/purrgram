// Purrgram for Windows — the app: windows, frame loop, mouse handling, the tray menu and saving.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Windows.Forms;
using Microsoft.Win32;

namespace Purrgram
{
    class CatApp : ApplicationContext
    {
        readonly SaveState state;
        readonly Cat cat;
        readonly LayeredWindow catWin = new LayeredWindow(), bowlWin = new LayeredWindow();
        readonly NotifyIcon tray = new NotifyIcon();
        readonly Timer timer = new Timer();
        readonly Stopwatch clock = Stopwatch.StartNew();
        double lastT, saveT, watchT, topT, fullT;
        bool paused, hiddenByUser, hiddenForFullScreen;

        // Screen geometry in device pixels; `scale` = device pixels per art pixel, `U` = device pixels per point.
        Rectangle work;
        int scale = 3;
        double U = 1;

        Bitmap catCanvas, bowlCanvas;
        string lastCatKey = "", lastBowlKey = "";

        // Bowls: the shown fill level eases toward the real one; `bits` are falling kibble/droplets in art pixels.
        double shownFood, shownWater;
        readonly List<(double x, double y, double vy, bool water)> bits = new List<(double, double, double, bool)>();

        public CatApp()
        {
            state = SaveState.Load();
            if (state.Personality < 0) state.Personality = new Random().Next(Assets.MoodNames.Length);
            cat = new Cat(state);
            shownFood = state.Food; shownWater = state.Water;

            Measure();
            cat.X = cat.Right - 260;

            bowlWin.MouseDown += BowlMouseDown;
            catWin.MouseDown += CatMouseDown;
            catWin.MouseMove += CatMouseMove;
            catWin.MouseUp += CatMouseUp;
            bowlWin.Show();
            catWin.Show();   // shown second so it stacks in front of the bowls

            tray.Icon = Assets.AppIcon(SystemInformation.SmallIconSize.Width);
            tray.Text = "Purrgram";
            tray.ContextMenuStrip = new ContextMenuStrip();
            tray.ContextMenuStrip.Opening += (s, e) => { BuildMenu(); e.Cancel = false; };
            BuildMenu();
            tray.MouseClick += (s, e) =>
            {
                if (e.Button == MouseButtons.Left)   // left-click opens the menu too
                    typeof(NotifyIcon).GetMethod("ShowContextMenu", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)?.Invoke(tray, null);
            };
            tray.Visible = true;

            SystemEvents.DisplaySettingsChanged += (s, e) => { Measure(); cat.Reclamp(); lastCatKey = lastBowlKey = ""; };
            SystemEvents.SessionSwitch += (s, e) =>
            {
                if (e.Reason == SessionSwitchReason.SessionLock || e.Reason == SessionSwitchReason.ConsoleDisconnect) Pause(true);
                if (e.Reason == SessionSwitchReason.SessionUnlock || e.Reason == SessionSwitchReason.ConsoleConnect) Pause(false);
            };
            SystemEvents.PowerModeChanged += (s, e) =>
            {
                if (e.Mode == PowerModes.Suspend) Pause(true);
                if (e.Mode == PowerModes.Resume) Pause(false);
            };
            SystemEvents.SessionEnding += (s, e) => state.Save();
            Application.ApplicationExit += (s, e) => Shutdown();

            timer.Interval = 33;
            timer.Tick += (s, e) => Frame();
            timer.Start();
            lastT = clock.Elapsed.TotalSeconds;
        }

        // MARK: geometry

        void Measure()
        {
            var screen = Screen.PrimaryScreen;
            work = screen.WorkingArea;
            double dpi = 96;
            try { using (var g = Graphics.FromHwnd(IntPtr.Zero)) dpi = g.DpiX; } catch { }
            scale = Math.Max(2, (int)Math.Round(3 * dpi / 96));
            U = scale / 3.0;
            cat.Left = work.Left / U; cat.Right = work.Right / U; cat.Height = work.Height / U;
            cat.BowlX = Math.Round(work.Right / U - 150);
            catCanvas?.Dispose(); bowlCanvas?.Dispose();
            catCanvas = new Bitmap(Assets.FrameW * scale, Assets.FrameH * scale, PixelFormat.Format32bppArgb);
            bowlCanvas = new Bitmap(Assets.BowlW * scale, Assets.BowlH * scale, PixelFormat.Format32bppArgb);
        }

        Point CatWindowPos() => new Point((int)Math.Round(cat.X * U) - Assets.OriginX * scale,
                                          work.Bottom - (int)Math.Round(cat.Y * U) - (Assets.FrameH - Assets.OriginY) * scale);
        Point BowlWindowPos() => new Point((int)Math.Round(cat.BowlX * U), work.Bottom - Assets.BowlH * scale);

        /// Cursor in cat coordinates (points; y up from the floor).
        (double x, double y) MousePt()
        {
            var p = Cursor.Position;
            return (p.X / U, (work.Bottom - p.Y) / U);
        }

        // MARK: frame loop

        void Pause(bool on)
        {
            paused = on;
            if (!on) lastT = clock.Elapsed.TotalSeconds;   // the time away doesn't count: stats only change while you're here
            if (on) state.Save();
        }

        void Frame()
        {
            double now = clock.Elapsed.TotalSeconds, dt = Math.Min(0.1, Math.Max(0, now - lastT));
            lastT = now;
            if (paused) return;

            fullT += dt;
            if (fullT > 2) { fullT = 0; hiddenForFullScreen = Native.FullScreenAppActive(); }
            bool visible = !hiddenByUser && !hiddenForFullScreen;
            if (catWin.Visible != visible) { catWin.Visible = visible; bowlWin.Visible = visible; lastCatKey = lastBowlKey = ""; }

            var m = MousePt();
            cat.MouseMoved(m.x, m.y);
            if (pendingPetAt > 0 && now >= pendingPetAt) { pendingPetAt = 0; cat.Pet(); }

            if (visible) cat.Tick(dt);
            watchT += dt;
            if (watchT > 1) { watchT = 0; cat.Watchdog((Control.MouseButtons & MouseButtons.Left) != 0); }
            TickBowls(dt);

            saveT += dt;
            if (saveT > 30) { saveT = 0; state.Save(); }
            topT += dt;
            if (topT > 3 && visible) { topT = 0; bowlWin.KeepOnTop(); catWin.KeepOnTop(); }

            if (visible) { DrawBowls(); DrawCat(); }
            int fps = (int)(dragging || bits.Count > 0 ? 30 : cat.ActivityFps);
            timer.Interval = Math.Max(15, 1000 / fps);
        }

        void TickBowls(double dt)
        {
            double k = Math.Min(1, dt * 3);
            shownFood += (state.Food - shownFood) * k;
            shownWater += (state.Water - shownWater) * k;
            for (int i = bits.Count - 1; i >= 0; i--)
            {
                var b = bits[i];
                double vy = b.vy - 300 * dt, y = b.y + vy * dt;
                if (y < (b.water ? 9 : 10)) bits.RemoveAt(i); else bits[i] = (b.x, y, vy, b.water);
            }
        }

        static int FoodIndex(double lv) => lv <= 0.04 ? 0 : lv <= 0.3 ? 1 : lv <= 0.55 ? 2 : lv <= 0.75 ? 3 : lv <= 0.92 ? 4 : 5;
        static int WaterIndex(double lv) => lv <= 0.04 ? 0 : lv <= 0.3 ? 1 : lv < 0.5 ? 2 : lv <= 0.6 ? 3 : 4;
        bool Drinking => cat.IsEating && cat.Act.Water;

        string WaterImage(bool front)
        {
            int wi = WaterIndex(shownWater);
            if (Drinking && wi > 0) return $"bowl_water{wi}_d{(int)(cat.Time * 13 / Math.PI) % 3}{(front ? "_front" : "")}";
            if (front) return null;
            int s = (int)((Math.Sin(cat.Time * 1.4) + 1) * 2);
            return $"bowl_water{wi}_s{Math.Min(4, Math.Max(0, s))}";
        }
        string FoodImage(bool front) => $"bowl_food{FoodIndex(shownFood)}{(front ? "_front" : "")}";

        void DrawBowls()
        {
            string w = WaterImage(false), f = FoodImage(false);
            string key = f + w + bits.Count + string.Join(",", bits.ConvertAll(b => $"{(int)b.x}:{(int)b.y}"));
            if (key == lastBowlKey) return;
            lastBowlKey = key;
            using (var g = Graphics.FromImage(bowlCanvas))
            {
                g.Clear(Color.Transparent);
                foreach (var n in new[] { f, w })
                {
                    var img = Assets.Image(n + ".png");
                    if (img != null) Assets.Blit(g, img, new Rectangle(0, 0, img.Width, img.Height), 0, 0, scale);
                }
                foreach (var b in bits)
                {
                    var col = b.water ? Color.FromArgb(0x8F, 0xD8, 0xFF) : ((int)b.x % 2 == 0 ? Color.FromArgb(0x8B, 0x5A, 0x2B) : Color.FromArgb(0xC0, 0x84, 0x42));
                    using (var br = new SolidBrush(col))
                        g.FillRectangle(br, (int)Math.Round(b.x) * scale, (Assets.BowlH - 1 - (int)Math.Round(b.y)) * scale, scale, scale);
                }
            }
            var p = BowlWindowPos();
            bowlWin.SetBitmap(bowlCanvas, p.X, p.Y);
        }

        void DrawCat()
        {
            var (clip, frame) = cat.Frame(c => Assets.FrameCount(state.Coat, c));
            bool right = cat.Facing > 0;
            var pos = CatWindowPos();
            string hearts = string.Join(",", cat.Hearts.ConvertAll(h => $"{(int)(h.X / 3)}:{(int)(h.Y / 3)}:{(h.Age > 1.1 && (int)(h.Age * 12) % 2 == 0 ? 0 : 1)}"));
            string front = cat.IsEating ? (cat.Act.Water ? WaterImage(true) : FoodImage(true)) : "";
            string key = $"{state.Coat}|{clip}|{frame}|{right}|{pos}|{hearts}|{front}";
            if (key == lastCatKey) return;
            lastCatKey = key;

            using (var g = Graphics.FromImage(catCanvas))
            {
                g.Clear(Color.Transparent);
                var strip = Assets.Strip(state.Coat, clip, right);
                if (strip != null)
                    Assets.Blit(g, strip, new Rectangle(frame * Assets.FrameW, 0, Assets.FrameW, Assets.FrameH), 0, 0, scale);

                if (cat.IsEating && !string.IsNullOrEmpty(front))
                {   // the bowl's front wall goes over the cat's face, exactly on top of the bowl's own pixels
                    var bp = BowlWindowPos();
                    int ox = bp.X - pos.X, oy = bp.Y - pos.Y;
                    g.CompositingMode = CompositingMode.SourceCopy;
                    using (var clear = new SolidBrush(Color.Transparent))
                        foreach (var r in Assets.UnderBowls)
                            g.FillRectangle(clear, ox + r.X * scale, oy + (Assets.BowlH - r.Y - r.Height) * scale, r.Width * scale, r.Height * scale);
                    g.CompositingMode = CompositingMode.SourceOver;
                    var img = Assets.Image(front + ".png");
                    if (img != null) Assets.Blit(g, img, new Rectangle(0, 0, img.Width, img.Height), ox, oy, scale);
                }

                foreach (var h in cat.Hearts)
                {
                    if (h.Age > 1.1 && (int)(h.Age * 12) % 2 == 0) continue;   // blink out at the end
                    int hx = (int)Math.Round(h.X * U) - pos.X, hy = work.Bottom - (int)Math.Round(h.Y * U) - pos.Y;
                    DrawHeart(g, hx, hy);
                }
            }
            catWin.SetBitmap(catCanvas, pos.X, pos.Y);
        }

        static readonly string[] heartFill = { "##.##", "#####", ".###.", "..#.." };

        /// A little outlined pixel heart centered on (x, y) in canvas pixels, snapped to the art-pixel grid.
        void DrawHeart(Graphics g, int x, int y)
        {
            int rows = heartFill.Length, cols = heartFill[0].Length;
            bool Filled(int c, int r) => r >= 0 && r < rows && c >= 0 && c < cols && heartFill[r][c] == '#';
            int ox = (x / scale) * scale - cols * scale / 2, oy = (y / scale) * scale - rows * scale;
            for (int r = -1; r <= rows; r++)
                for (int c = -1; c <= cols; c++)
                {
                    Color col;
                    if (Filled(c, r)) col = (r == 0 && c == 0) ? Color.FromArgb(0xFF, 0xB3, 0xC9) : Color.FromArgb(0xFF, 0x5C, 0x8A);
                    else if (Filled(c - 1, r) || Filled(c + 1, r) || Filled(c, r - 1) || Filled(c, r + 1)) col = Color.FromArgb(0x5A, 0x1A, 0x2E);
                    else continue;
                    using (var b = new SolidBrush(col)) g.FillRectangle(b, ox + c * scale, oy + r * scale, scale, scale);
                }
        }

        // MARK: mouse

        bool dragging, mouseIsDown;
        Point downAt, lastDrag;
        double lastDragT, dragVx, dragVy, lastUpT = -1, pendingPetAt;

        void CatMouseDown(object s, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;
            double now = clock.Elapsed.TotalSeconds;
            mouseIsDown = true; dragging = false;
            downAt = lastDrag = Cursor.Position; lastDragT = now; dragVx = dragVy = 0;
            if (now - lastUpT < SystemInformation.DoubleClickTime / 1000.0)
            {   // double-click: shoo
                pendingPetAt = 0; lastUpT = -1;
                cat.Nudge(downAt.X / U);
                mouseIsDown = false;
            }
        }

        void CatMouseMove(object s, MouseEventArgs e)
        {
            if (!mouseIsDown) return;
            var m = Cursor.Position;
            if (!dragging && Math.Abs(m.X - downAt.X) + Math.Abs(m.Y - downAt.Y) > 6 * U)
            {
                dragging = true; pendingPetAt = 0; cat.StartCarry();
            }
            if (!dragging) return;
            double now = clock.Elapsed.TotalSeconds, dt = Math.Max(now - lastDragT, 0.001);
            double vx = (m.X - lastDrag.X) / U / dt, vy = -(m.Y - lastDrag.Y) / U / dt;
            dragVx = dragVx * 0.5 + vx * 0.5; dragVy = dragVy * 0.5 + vy * 0.5;
            lastDrag = m; lastDragT = now;
            var p = MousePt();
            cat.Carry(p.x, p.y);
        }

        void CatMouseUp(object s, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left || !mouseIsDown) return;
            mouseIsDown = false;
            if (dragging) { dragging = false; cat.Drop(dragVx, dragVy); return; }
            lastUpT = clock.Elapsed.TotalSeconds;
            pendingPetAt = lastUpT + Math.Min(SystemInformation.DoubleClickTime / 1000.0, 0.3);
        }

        void BowlMouseDown(object s, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;
            double px = e.X / U, py = (Assets.BowlH * scale - e.Y) / U;
            if (Math.Abs(px - Assets.FoodLX) < 26 && py < 36) Fill(false);
            else if (Math.Abs(px - Assets.WaterLX) < 24 && py < 36) Fill(true);
        }

        void Fill(bool water)
        {
            double cx = (water ? Assets.WaterLX : Assets.FoodLX) / 3;
            var r = new Random();
            for (int i = 0; i < (water ? 8 : 12); i++)
                bits.Add((Math.Round(cx + r.NextDouble() * 8 - 4), 15 + r.NextDouble() * 4, -r.NextDouble() * 8, water));
            if (water) state.Water = 1; else state.Food = 1;
            var t = new Timer { Interval = 400 };
            t.Tick += (s, e) => { t.Stop(); t.Dispose(); cat.HeardBowl(water); };
            t.Start();
        }

        // MARK: tray menu

        static Bitmap Bar(double v)
        {
            var b = new Bitmap(84, 10);
            using (var g = Graphics.FromImage(b))
            {
                g.Clear(Color.Transparent);
                using (var bg = new SolidBrush(Color.FromArgb(70, 128, 128, 128))) g.FillRectangle(bg, 0, 1, 84, 8);
                var c = v >= 0.6 ? Color.FromArgb(0x34, 0xC7, 0x59) : v >= 0.3 ? Color.FromArgb(0xFF, 0xC0, 0x2E) : Color.FromArgb(0xFF, 0x45, 0x3A);
                using (var fg = new SolidBrush(c)) g.FillRectangle(fg, 0, 1, (int)Math.Round(84 * Math.Max(0, Math.Min(1, v))), 8);
            }
            return b;
        }

        void BuildMenu()
        {
            var menu = tray.ContextMenuStrip;
            foreach (ToolStripItem old in menu.Items) old.Image?.Dispose();
            menu.Items.Clear();
            var head = new ToolStripMenuItem($"{state.Name} {cat.Mood}") { Enabled = false };
            head.Font = new Font(head.Font, FontStyle.Bold);
            menu.Items.Add(head);
            menu.Items.Add(new ToolStripMenuItem($"Mood: {Assets.MoodNames[cat.Trait]} · {Assets.CoatNames[state.Coat]}") { Enabled = false });
            menu.Items.Add(new ToolStripSeparator());
            foreach (var (label, v) in new[] { ("Fullness", state.Belly), ("Hydration", state.Hydration), ("Energy", state.Energy),
                                               ("Happiness", state.Happiness), ("Food bowl", state.Food), ("Water bowl", state.Water) })
                menu.Items.Add(new ToolStripMenuItem($"{label}  {(int)Math.Round(v * 100)}%", Bar(v)) { Enabled = true, ImageScaling = ToolStripItemImageScaling.None });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(new ToolStripMenuItem(hiddenByUser ? "Show Cat" : "Hide Cat", null, (s, e) => { hiddenByUser = !hiddenByUser; }));
            menu.Items.Add(new ToolStripMenuItem("Fill Food", null, (s, e) => Fill(false)));
            menu.Items.Add(new ToolStripMenuItem("Fill Water", null, (s, e) => Fill(true)));
            menu.Items.Add(new ToolStripMenuItem("Call Over", null, (s, e) => cat.CallOver()));
            menu.Items.Add(new ToolStripSeparator());

            var coat = new ToolStripMenuItem("Coat");
            for (int i = 0; i < Assets.CoatNames.Length; i++)
            {
                int c = i;
                coat.DropDownItems.Add(new ToolStripMenuItem(Assets.CoatNames[i], null, (s, e) =>
                {
                    state.Coat = c; Assets.KeepCoat(c); lastCatKey = ""; state.Save();
                }) { Checked = state.Coat == i });
            }
            menu.Items.Add(coat);
            var mood = new ToolStripMenuItem("Mood");
            for (int i = 0; i < Assets.MoodNames.Length; i++)
            {
                int c = i;
                mood.DropDownItems.Add(new ToolStripMenuItem(Assets.MoodNames[i], null, (s, e) => { state.Personality = c; state.Save(); })
                                       { Checked = cat.Trait == i, ToolTipText = Assets.MoodBlurbs[i] });
            }
            menu.Items.Add(mood);
            menu.Items.Add(new ToolStripMenuItem("Rename…", null, (s, e) => Rename()));
            menu.Items.Add(new ToolStripMenuItem("Start with Windows", null, (s, e) => SetStartup(!StartsWithWindows())) { Checked = StartsWithWindows() });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(new ToolStripMenuItem("Quit Purrgram", null, (s, e) => ExitThread()));
        }

        void Rename()
        {
            using (var f = new Form { Text = "Rename your cat", FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false,
                                      StartPosition = FormStartPosition.CenterScreen, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink,
                                      Padding = new Padding(12), TopMost = true, Icon = Assets.AppIcon(32) })
            {
                var box = new TextBox { Text = state.Name, Width = 240, MaxLength = 40 };
                var ok = new Button { Text = "OK", DialogResult = DialogResult.OK };
                var cancel = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel };
                var row = new FlowLayoutPanel { FlowDirection = FlowDirection.RightToLeft, AutoSize = true, Dock = DockStyle.Fill };
                row.Controls.Add(cancel); row.Controls.Add(ok);
                var col = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true };
                col.Controls.Add(new Label { Text = "Name:", AutoSize = true });
                col.Controls.Add(box); col.Controls.Add(row);
                f.Controls.Add(col);
                f.AcceptButton = ok; f.CancelButton = cancel;
                if (f.ShowDialog() == DialogResult.OK && !string.IsNullOrWhiteSpace(box.Text))
                {
                    state.Name = box.Text.Trim(); state.Named = true; state.Save();
                }
            }
        }

        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

        static bool StartsWithWindows()
        {
            try { using (var k = Registry.CurrentUser.OpenSubKey(RunKey)) return k?.GetValue("Purrgram") != null; } catch { return false; }
        }

        static void SetStartup(bool on)
        {
            try
            {
                using (var k = Registry.CurrentUser.CreateSubKey(RunKey))
                {
                    if (on) k.SetValue("Purrgram", $"\"{Application.ExecutablePath}\"");
                    else k.DeleteValue("Purrgram", false);
                }
            }
            catch { }
        }

        bool shutDown;
        void Shutdown()
        {
            if (shutDown) return;
            shutDown = true;
            timer.Stop();
            state.Save();
            tray.Visible = false;
            tray.Dispose();
        }

        protected override void ExitThreadCore()
        {
            Shutdown();
            catWin.Close(); bowlWin.Close();
            base.ExitThreadCore();
        }
    }
}

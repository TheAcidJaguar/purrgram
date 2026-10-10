// Purrgram for Windows — the pre-rendered frames (made by the Mac app's `--export-frames`) and how to draw them.

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Reflection;

namespace Purrgram
{
    class ClipInfo
    {
        public readonly string Name; public readonly double Fps; public readonly bool Loop;
        public ClipInfo(string name, double fps, bool loop) { Name = name; Fps = fps; Loop = loop; }
    }

    static class Assets
    {
        // Geometry of a cat frame, in art pixels (one art pixel = 3 points on the Mac).
        public const int FrameW = 77, FrameH = 64, OriginX = 38, OriginY = 12;
        public const int BowlW = 40, BowlH = 20;
        public const double FoodLX = 30, WaterLX = 87;            // bowl centers, in points from the bowl window's left
        // The strip under each bowl (art pixels, from the bottom-left): cleared when the cat's face is in a bowl.
        public static readonly Rectangle[] UnderBowls = { new Rectangle(2, 0, 16, 1), new Rectangle(22, 0, 14, 1) };

        // Must match `clips` in Sources/Export.swift (frame counts come from the strip widths).
        public static readonly Dictionary<string, ClipInfo> Clips = new Dictionary<string, ClipInfo>();
        static Assets()
        {
            foreach (var c in new[] {
                new ClipInfo("sit", 10, true), new ClipInfo("lookUp", 10, true), new ClipInfo("loaf", 10, true),
                new ClipInfo("sleep", 8, true), new ClipInfo("groom", 12, true), new ClipInfo("scratch", 20, true),
                new ClipInfo("stretch", 15, false), new ClipInfo("archStretch", 15, false), new ClipInfo("bigArch", 15, false),
                new ClipInfo("legStretch", 15, false), new ClipInfo("yawn", 15, false), new ClipInfo("petted", 15, true),
                new ClipInfo("annoyed", 15, true), new ClipInfo("swat", 20, false), new ClipInfo("crouch", 15, true),
                new ClipInfo("walk", 20, true), new ClipInfo("run", 30, true), new ClipInfo("carried", 10, true),
                new ClipInfo("airUp", 10, true), new ClipInfo("airDown", 10, true), new ClipInfo("land", 30, false),
                new ClipInfo("eatFood", 12, true), new ClipInfo("eatWater", 15, true), new ClipInfo("waitBowl", 12, true) })
                Clips[c.Name] = c;
        }

        public static readonly string[] CoatNames = { "Slate", "Charcoal", "Siamese", "Tan Tabby", "Orange Tabby", "Midnight", "Tuxedo",
                                                      "Cream", "Maine Coon", "British Shorthair", "Bengal", "Sphynx" };
        public static readonly double[] CoatSize = { 1, 1, 1, 1, 1, 1, 1, 1, 1.13, 1.02, 1, 1 };
        public static readonly string[] MoodNames = { "Playful", "Lazy", "Clingy", "Skittish", "Curious" };
        public static readonly string[] MoodBlurbs = { "Zoomies, pounces, and never says no to yarn", "Loafs and naps more than anything",
                                                       "Follows you around and loves pets", "Easily startled and loves to hide",
                                                       "Explores and climbs everything" };

        static readonly Dictionary<string, Bitmap> cache = new Dictionary<string, Bitmap>();

        public static Stream Resource(string name) => Assembly.GetExecutingAssembly().GetManifestResourceStream(name);

        public static Bitmap Image(string name)
        {
            if (cache.TryGetValue(name, out var b)) return b;
            using (var s = Resource(name))
            {
                if (s == null) return null;
                using (var tmp = new Bitmap(s)) b = new Bitmap(tmp);   // copy so the stream can close
            }
            cache[name] = b;
            return b;
        }

        /// Drop every cat strip except the current coat's (switching coats shouldn't keep the old one in memory).
        public static void KeepCoat(int coat)
        {
            var prefix = $"cat_{coat}_";
            foreach (var k in new List<string>(cache.Keys))
                if (k.StartsWith("cat_") && !k.StartsWith(prefix)) { cache[k].Dispose(); cache.Remove(k); }
        }

        public static Bitmap Strip(int coat, string clip, bool right) => Image($"cat_{coat}_{clip}_{(right ? "R" : "L")}.png");

        public static int FrameCount(int coat, string clip) => Math.Max(1, (Strip(coat, clip, true)?.Width ?? FrameW) / FrameW);

        /// Nearest-neighbor blit of art-pixel `src` onto `g` at `scale` device pixels per art pixel.
        public static void Blit(Graphics g, Bitmap img, Rectangle src, int x, int y, int scale)
        {
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = PixelOffsetMode.Half;
            g.DrawImage(img, new Rectangle(x, y, src.Width * scale, src.Height * scale), src, GraphicsUnit.Pixel);
        }

        /// The app icon at `size` pixels, drawn from the embedded 256px PNG (the .NET Framework Icon class can't always
        /// read PNG-compressed .ico entries, so this doesn't rely on it).
        public static Icon AppIcon(int size)
        {
            try
            {
                var src = Image("icon.png");
                if (src == null) return SystemIcons.Application;
                using (var b = new Bitmap(size, size, PixelFormat.Format32bppArgb))
                {
                    using (var g = Graphics.FromImage(b))
                    {
                        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                        g.DrawImage(src, new Rectangle(0, 0, size, size));
                    }
                    return Icon.FromHandle(b.GetHicon());
                }
            }
            catch { return SystemIcons.Application; }
        }
    }
}

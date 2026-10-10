// Purrgram for Windows — the cat: needs, the action machine and how it decides what to do next.
// A port of the Mac app's Cat / CatBrain, trimmed to the Lite feature set (the floor and the bowls, no window jumping).
// Units are the Mac's points; x grows to the right and y is the height above the floor (the top of the taskbar).

using System;
using System.Collections.Generic;
using System.Linq;

namespace Purrgram
{
    enum A { Sit, LookUp, Loaf, Sleep, Groom, Scratch, Stretch, ArchStretch, BigArch, LegStretch, Yawn,
             Petted, Annoyed, Swat, Crouch, Walk, Carried, Hop, Land, Eat, WaitBowl, Face }

    class Act
    {
        public A Kind;
        public double D;            // duration (seconds) for timed actions
        public double X, Speed;     // walk target and speed
        public double Vx, Vy;       // hop velocity
        public bool Water;          // eat / waitBowl
        public double Dir;          // face

        public static Act Of(A k, double d = 0) => new Act { Kind = k, D = d };
        public static Act Walk(double x, double sp) => new Act { Kind = A.Walk, X = x, Speed = sp };
        public static Act Hop(double vx, double vy) => new Act { Kind = A.Hop, Vx = vx, Vy = vy };
        public static Act Eat(bool w) => new Act { Kind = A.Eat, Water = w };
        public static Act WaitBowl(bool w) => new Act { Kind = A.WaitBowl, Water = w };
        public static Act Face(double d) => new Act { Kind = A.Face, Dir = d };
    }

    class Heart { public double X, Y, Age, Sway; }

    class Cat
    {
        public const double Gravity = 1500;
        static readonly Random rng = new Random();
        public static double Rnd(double a, double b) => a + rng.NextDouble() * (b - a);
        public static bool Chance(double p) => rng.NextDouble() < p;
        static double Clamp(double v, double lo, double hi) => Math.Min(Math.Max(v, lo), hi);

        public SaveState S;
        public double X = 400, Y = 0, Facing = 1, Vx, Vy;
        public Act Act = Act.Of(A.Sit, 2);
        public double ActT, Time, WalkClock;
        public List<Act> Queue = new List<Act>();
        public List<Heart> Hearts = new List<Heart>();
        List<double> petTimes = new List<double>();
        public double MouseX, MouseY, LastMouseMove = -10, LastWait = -999;
        public int WatchdogTrips;

        // The world: screen edges (points) and where the bowls are.
        public double Left = 0, Right = 1440, Height = 875, BowlX = 1290;
        public double FoodX => BowlX + Assets.FoodLX;
        public double WaterX => BowlX + Assets.WaterLX;

        public Cat(SaveState s) { S = s; }

        public int Trait => S.Personality < 0 ? 4 : S.Personality;   // playful, lazy, clingy, skittish, curious
        public double Cs => 0.85 * Assets.CoatSize[S.Coat];          // on-screen scale for this breed
        public bool IsSleeping => Act.Kind == A.Sleep;
        public bool IsAirborne => Act.Kind == A.Hop || Act.Kind == A.Carried;
        public bool IsEating => Act.Kind == A.Eat;

        public string Mood
        {
            get
            {
                if (IsSleeping) return "is fast asleep";
                if (S.Hydration < 0.25) return "is very thirsty";
                if (S.Belly < 0.25) return "is very hungry";
                if (S.Hydration < 0.45) return "is a little thirsty";
                if (S.Belly < 0.45) return "is a little hungry";
                if (S.Energy < 0.3) return "is sleepy";
                if (S.Happiness < 0.35) return "wants some attention";
                if (S.Happiness > 0.8) return "is purring contentedly";
                return "is doing cat things";
            }
        }

        /// How often the screen needs redrawing right now: calm poses barely change.
        public double ActivityFps
        {
            get
            {
                switch (Act.Kind)
                {
                    case A.Sleep: case A.Loaf: case A.Sit: case A.WaitBowl: case A.Face: case A.LookUp: return 10;
                    case A.Walk: case A.Hop: case A.Carried: case A.Land: case A.Swat: case A.Crouch: return 30;
                    default: return 15;
                }
            }
        }

        // MARK: animation

        /// Which pre-rendered clip to show and which frame of it.
        public (string clip, int frame) Frame(Func<string, int> frameCount)
        {
            string c; double t = ActT;
            switch (Act.Kind)
            {
                case A.Sit: case A.Face: c = "sit"; t = Time; break;
                case A.LookUp: c = "lookUp"; t = Time; break;
                case A.Loaf: c = "loaf"; t = Time; break;
                case A.Sleep: c = "sleep"; t = Time; break;
                case A.Groom: c = "groom"; break;
                case A.Scratch: c = "scratch"; break;
                case A.Stretch: c = "stretch"; break;
                case A.ArchStretch: c = "archStretch"; break;
                case A.BigArch: c = "bigArch"; break;
                case A.LegStretch: c = "legStretch"; break;
                case A.Yawn: c = "yawn"; break;
                case A.Petted: c = "petted"; break;
                case A.Annoyed: c = "annoyed"; t = Time; break;
                case A.Swat: c = "swat"; break;
                case A.Crouch: c = "crouch"; break;
                case A.Walk: c = Act.Speed > 200 ? "run" : "walk"; t = WalkClock; break;
                case A.Carried: c = "carried"; t = Time; break;
                case A.Hop: c = Vy > 0 ? "airUp" : "airDown"; break;
                case A.Land: c = "land"; break;
                case A.Eat: c = Act.Water ? "eatWater" : "eatFood"; break;
                case A.WaitBowl: c = "waitBowl"; break;
                default: c = "sit"; break;
            }
            var info = Assets.Clips[c];
            int n = frameCount(c), f = (int)(t * info.Fps);
            return (c, info.Loop ? ((f % n) + n) % n : Math.Min(Math.Max(f, 0), n - 1));
        }

        // MARK: tick

        public void Tick(double dt)
        {
            Time += dt; ActT += dt;
            UpdateNeeds(dt);
            foreach (var h in Hearts) { h.Age += dt; h.X += Math.Cos((h.Age + h.Sway) * 5) * 0.5; h.Y += dt * 24; }
            Hearts.RemoveAll(h => h.Age > 1.5);
            if (Act.Kind == A.Petted && (int)(ActT / 0.7) != (int)((ActT - dt) / 0.7)) Heart();
            if ((Act.Kind == A.Sit || Act.Kind == A.LookUp) && Time - LastMouseMove < 1.2
                && Math.Abs(MouseX - X) < 450 && Math.Abs(MouseX - X) > 10)
                Facing = MouseX > X ? 1 : -1;   // cats watch the cursor
            Run(dt);
        }

        public void MouseMoved(double mx, double my)
        {
            if (Math.Abs(mx - MouseX) + Math.Abs(my - MouseY) > 2) { LastMouseMove = Time; MouseX = mx; MouseY = my; }
        }

        void UpdateNeeds(double dt)
        {
            S.Belly = Clamp(S.Belly - dt / (3 * 3600), 0, 1);
            S.Hydration = Clamp(S.Hydration - dt / (2.5 * 3600), 0, 1);
            S.Energy = Clamp(S.Energy + (IsSleeping ? dt / 360 : -dt / (2 * 3600)), 0, 1);
            double rate = (S.Belly < 0.2 || S.Hydration < 0.2) ? 3 : 1;
            S.Happiness = Clamp(S.Happiness - dt * rate / (4 * 3600), 0, 1);
        }

        public void Heart()
        {
            double hx = X + Facing * 30 * Cs, hy = Y + 62 * Cs;
            Hearts.Add(new Heart { X = hx + Rnd(-8, 8), Y = hy + Rnd(0, 6), Sway = Rnd(0, 6) });
        }

        /// Rescue the cat from any state it shouldn't be in (bad numbers, off screen, a stuck action).
        public void Watchdog(bool mouseDown)
        {
            void Rescue() { WatchdogTrips++; Vx = 0; Vy = 0; Y = 0; Interrupt(Act.Of(A.Sit, 1)); }
            if (double.IsNaN(X) || double.IsInfinity(X) || double.IsNaN(Y) || double.IsInfinity(Y)
                || double.IsNaN(Vx) || double.IsInfinity(Vx) || double.IsNaN(Vy) || double.IsInfinity(Vy)) { X = (Left + Right) / 2; Rescue(); return; }
            if (Act.Kind == A.Carried)
            {
                if (ActT > 0.5 && !mouseDown) { WatchdogTrips++; Drop(0, 0); }
                return;
            }
            if (Act.Kind != A.Walk && (X < Left - 60 || X > Right + 60)) { X = Clamp(X, Left + 40, Right - 40); Rescue(); return; }
            if (Y < -4) { Y = 0; if (IsAirborne) Rescue(); return; }
            double limit = Act.Kind == A.Sleep ? 20 * 60 : Act.Kind == A.Loaf ? 10 * 60 : Act.Kind == A.Hop ? 8 : 3 * 60;
            if (ActT > limit) Rescue();
        }

        /// Keep everything sensible after the screen layout changes.
        public void Reclamp()
        {
            X = Clamp(X, Left + 24, Right - 24);
            if (!IsAirborne) Y = 0;
            if (Y > Height - 70) Y = Height - 70;
        }

        // MARK: action machine

        void Next()
        {
            if (Queue.Count == 0) Decide();
            Act = Queue[0]; Queue.RemoveAt(0); ActT = 0;
            Begin();
        }

        public void Interrupt(params Act[] acts) { Queue = acts.ToList(); Next(); }

        (double, double) Range() => (Left + 30, Right - 30);

        void Begin()
        {
            switch (Act.Kind)
            {
                case A.Walk:
                    var r = Range();
                    Act.X = Clamp(Act.X, r.Item1, r.Item2);
                    if (Trait == 1 && Act.Speed < 200) Act.Speed *= 0.8;   // lazy
                    if (Math.Abs(Act.X - X) > 1) Facing = Act.X > X ? 1 : -1;
                    break;
                case A.Face: Facing = Act.Dir; break;
                case A.Hop: Vx = Act.Vx; Vy = Act.Vy; break;
                case A.Eat: Facing = 1; break;
                case A.WaitBowl: Facing = 1; LastWait = Time; break;
            }
        }

        void Run(double dt)
        {
            bool done = false;
            switch (Act.Kind)
            {
                case A.Sit: case A.LookUp: case A.Groom: case A.Scratch: case A.Annoyed: case A.Petted: case A.Crouch:
                    done = ActT >= Act.D; break;
                case A.Loaf:
                    done = ActT >= Act.D;
                    if (done && Chance(0.3)) Queue.Insert(0, Act.Of(A.ArchStretch));
                    break;
                case A.Sleep:
                    done = ActT >= Act.D || (S.Energy >= 0.99 && ActT > 40);
                    if (done) Queue.InsertRange(0, WakeStretches());
                    break;
                case A.Stretch: done = ActT >= 2.6; break;
                case A.ArchStretch: done = ActT >= 2.4; break;
                case A.BigArch: done = ActT >= 3.2; break;
                case A.LegStretch: done = ActT >= 2.0; break;
                case A.Yawn: done = ActT >= 1.6; break;
                case A.Swat: done = ActT >= 0.6; break;
                case A.Land: done = ActT >= 0.22; break;
                case A.Face: done = true; break;
                case A.Walk:
                {
                    var r = Range();
                    double t = Clamp(Act.X, r.Item1, r.Item2), step = Act.Speed * dt;
                    WalkClock += dt * Act.Speed / (Act.Speed > 200 ? 299.2 : 74.8);   // the clips were drawn at these speeds
                    if (Math.Abs(t - X) <= step) { X = t; done = true; }
                    else { X += t > X ? step : -step; Facing = t > X ? 1 : -1; }
                    break;
                }
                case A.Hop: done = Physics(dt); break;
                case A.Eat:
                    if (Act.Water)
                    {
                        S.Water = Math.Max(0, S.Water - 0.045 * dt); S.Hydration = Math.Min(1, S.Hydration + 0.11 * dt);
                        done = S.Water <= 0 || S.Hydration >= 0.99 || ActT > 9;
                    }
                    else
                    {
                        S.Food = Math.Max(0, S.Food - 0.035 * dt); S.Belly = Math.Min(1, S.Belly + 0.09 * dt);
                        done = S.Food <= 0 || S.Belly >= 0.99 || ActT > 10;
                    }
                    if (done)
                    {
                        S.Happiness = Math.Min(1, S.Happiness + 0.05);
                        if ((Act.Water ? S.Water : S.Food) <= 0.01) Queue.Insert(0, WaitBowl(Act.Water));
                        Queue.Add(Act.Of(A.Groom, Rnd(3, 6)));   // cats always wash up after a meal
                    }
                    break;
                case A.WaitBowl:
                    if ((Act.Water ? S.Water : S.Food) > 0.04) { Act = Act.Eat(Act.Water); ActT = 0; Begin(); return; }
                    done = ActT >= 25;
                    break;
                case A.Carried: break;
            }
            if (done) Next();
        }

        static Act WaitBowl(bool w) => Act.WaitBowl(w);

        bool Physics(double dt)
        {
            Vy -= Gravity * dt; X += Vx * dt; Y += Vy * dt;
            if (X < Left + 24) { X = Left + 24; Vx = Math.Abs(Vx) * 0.3; }
            if (X > Right - 24) { X = Right - 24; Vx = -Math.Abs(Vx) * 0.3; }
            if (Y > Height - 70) { Y = Height - 70; Vy = Math.Min(Vy, 0); }
            if (Math.Abs(Vx) > 5) Facing = Vx > 0 ? 1 : -1;
            if (Vy <= 0 && Y <= 0) { Y = 0; Vx = 0; Vy = 0; Queue.Insert(0, Act.Of(A.Land)); return true; }
            return false;
        }

        // MARK: brain

        double M(double lazy, double playful, double clingy, double skittish, double curious)
        {
            switch (Trait) { case 0: return playful; case 1: return lazy; case 2: return clingy; case 3: return skittish; default: return curious; }
        }

        void Decide()
        {
            var plan = new List<Act>();
            bool patient = Time - LastWait > 60 || Chance(0.5);
            if (S.Hydration < 0.4 && (S.Water > 0.03 || patient)) plan = PlanBowl(true);
            else if (S.Belly < 0.4 && (S.Food > 0.03 || patient)) plan = PlanBowl(false);
            else if (S.Energy < 0.22) plan = PlanSleep();
            else if (S.Happiness < 0.3 && Chance(0.4)) plan = PlanAttention();
            else
            {
                var opts = new List<(double w, Func<List<Act>> f)>
                {
                    (18 * M(0.6, 1.2, 1, 0.9, 1.6), Wander),
                    (12 * M(1.3, 0.8, 1, 1, 1), () => L(Act.Of(A.Sit, Rnd(3, 8)))),
                    (10, () => L(Act.Of(A.Groom, Rnd(5, 9)))),
                    (5, () => L(Act.Of(A.Scratch, Rnd(1.5, 3)))),
                    (6 * M(2.5, 0.6, 1, 1, 0.8), () => L(Act.Of(A.Loaf, Rnd(8, 25)))),
                    ((S.Energy < 0.5 ? 12 : 4) * M(2.5, 0.6, 1, 1, 0.8), PlanSleep),
                    (6 * M(1.5, 1, 1, 1, 1), Stretches),
                    (3 * M(1, 1, 2, 0.6, 1), () => L(Act.Of(A.LookUp, 1.4), Act.Of(A.Sit, 2))),
                };
                if (S.Energy > 0.55) opts.Add((2.5 * M(0.2, 3, 1, 1.4, 1.2), PlanZoomies));
                if (S.Happiness < 0.6 || Trait == 2) opts.Add((5 * M(1, 1, 3.5, 0.3, 1), PlanAttention));
                double total = opts.Sum(o => o.w), pick = Rnd(0, total);
                foreach (var o in opts) { if (pick < o.w) { plan = o.f(); break; } pick -= o.w; }
            }
            if (plan.Count == 0) plan = L(Act.Of(A.Sit, Rnd(2, 5)));
            Queue = plan;
        }

        static List<Act> L(params Act[] a) => a.ToList();

        List<Act> Stretches()
        {
            var all = new[] { L(Act.Of(A.Stretch), Act.Of(A.LegStretch)), L(Act.Of(A.ArchStretch)), L(Act.Of(A.Yawn), Act.Of(A.Stretch)),
                              L(Act.Of(A.BigArch)), L(Act.Of(A.BigArch), Act.Of(A.LegStretch)) };
            return all[rng.Next(all.Length)];
        }

        List<Act> WakeStretches()
        {
            var all = new[] { L(Act.Of(A.Yawn), Act.Of(A.Stretch), Act.Of(A.LegStretch)), L(Act.Of(A.Stretch), Act.Of(A.ArchStretch)),
                              L(Act.Of(A.Yawn), Act.Of(A.ArchStretch)), L(Act.Of(A.Stretch)), L(Act.Of(A.Yawn), Act.Of(A.BigArch)),
                              L(Act.Of(A.BigArch), Act.Of(A.Stretch)) };
            return all[rng.Next(all.Length)];
        }

        List<Act> Wander()
        {
            var r = Range();
            if (r.Item2 - r.Item1 <= 40) return new List<Act>();
            double tx = Rnd(r.Item1, r.Item2);
            if (Math.Abs(tx - X) < 60) tx = Clamp(X + (tx > X ? 120 : -120), r.Item1, r.Item2);
            return L(Act.Walk(tx, Rnd(55, 85)), Act.Of(A.Sit, Rnd(1.5, 5)));
        }

        List<Act> PlanZoomies()
        {
            var r = Range();
            if (r.Item2 - r.Item1 <= 200) return new List<Act>();
            var p = L(Act.Of(A.Crouch, 0.4));
            int n = rng.Next(3, 6);
            for (int i = 0; i < n; i++) p.Add(Act.Walk(Rnd(r.Item1, r.Item2), Rnd(260, 320)));
            p.Add(Act.Of(A.Sit, 2));
            return p;
        }

        /// Trot over to the cursor with tail held high and gaze up.
        public List<Act> PlanAttention()
        {
            var r = Range();
            double tx = Clamp(MouseX + (MouseX > X ? -60 : 60), r.Item1, r.Item2);
            return L(Act.Walk(tx, 75), Act.Face(MouseX > tx ? 1 : -1), Act.Of(A.LookUp, Rnd(3, 5)));
        }

        public List<Act> PlanBowl(bool water, bool hurry = false)
        {
            double bx = water ? WaterX : FoodX, level = water ? S.Water : S.Food;
            return L(Act.Walk(bx - 33 * Cs, hurry ? 240 : 90), Act.Face(1), level > 0.03 ? Act.Eat(water) : Act.WaitBowl(water));
        }

        List<Act> PlanSleep()
        {
            var nap = Act.Of(A.Sleep, S.Energy < 0.3 ? Rnd(120, 300) : Rnd(45, 150));
            return L(Act.Of(A.Loaf, Rnd(2, 5)), nap);
        }

        // MARK: interactions

        public void Pet()
        {
            if (IsAirborne) return;
            S.Happiness = Math.Min(1, S.Happiness + 0.06);
            petTimes = petTimes.Where(t => Time - t < 10).ToList();
            petTimes.Add(Time);
            if (petTimes.Count >= (Trait == 2 ? 13 : 8))   // overstimulated: a quick swat, then off they go
            {
                petTimes.Clear();
                double dir = Chance(0.5) ? 1 : -1;
                Interrupt(Act.Of(A.Swat), Act.Hop(dir * 250, 520), Act.Of(A.Annoyed, Rnd(3, 5)), Act.Of(A.Groom, 3));
                return;
            }
            Heart();
            switch (Act.Kind)
            {
                case A.Sleep: case A.Eat: case A.WaitBowl: break;
                case A.Petted: ActT = Math.Min(ActT, 1); break;
                default:
                    if (Math.Abs(MouseX - X) > 4) Facing = MouseX > X ? 1 : -1;
                    Interrupt(Act.Of(A.Petted, 3.2));
                    break;
            }
        }

        public void Nudge(double fromX)
        {
            if (IsAirborne) return;
            double dir = X >= fromX ? 1 : -1;
            S.Happiness = Math.Max(0, S.Happiness - 0.01);
            Interrupt(Act.Hop(dir * Rnd(240, 300), 560), Act.Face(-dir), Act.Of(A.Annoyed, Rnd(2.5, 4)));
        }

        public void StartCarry() { Queue.Clear(); Act = Act.Of(A.Carried); ActT = 0; }

        public void Carry(double mx, double my)
        {
            if (Act.Kind != A.Carried) return;
            X = mx; Y = Math.Max(0, my - 66 * Cs);
        }

        public void Drop(double vx, double vy)
        {
            if (Act.Kind != A.Carried) return;
            Queue = L(Act.Of(A.Sit, 1), Act.Of(A.Groom, Rnd(2, 4)));
            Act = Act.Hop(Clamp(vx * 0.5, -900, 900), Clamp(vy * 0.4, -200, 900)); ActT = 0;
            Begin();
        }

        public void HeardBowl(bool water)
        {
            double need = water ? S.Hydration : S.Belly;
            if (IsAirborne) return;
            if (IsSleeping)
            {
                if (need < 0.6 || Chance(0.35)) { var p = PlanBowl(water, true); p.Insert(0, Act.Of(A.Yawn)); Interrupt(p.ToArray()); }
                return;
            }
            if (need < 0.85) Interrupt(PlanBowl(water, true).ToArray());
        }

        public void CallOver()
        {
            if (IsAirborne) return;
            if (IsSleeping) { var p = PlanAttention(); p.Insert(0, Act.Of(A.Yawn)); Interrupt(p.ToArray()); }
            else Interrupt(PlanAttention().ToArray());
        }
    }
}

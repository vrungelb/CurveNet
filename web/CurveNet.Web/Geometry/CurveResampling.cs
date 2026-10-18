namespace CurveNet.Web.Geometry;

// core/cnResampleArc.m и core/cnPchip.m
public static class CurveResampling
{
    // core/cnResampleArc.m — ресэмплинг нескольких штрихов с сохранением долей длин
    public static List<Point2D[]> ResampleMany(IReadOnlyList<Point2D[]> strokes, int n, string method = "pchip")
    {
        int m = strokes.Count;
        if (m == 0)
            throw new ArgumentException("Список штрихов пуст.");

        var cleaned = new List<Point2D[]>(m);
        var len = new double[m];
        double totalL = 0.0;

        for (int i = 0; i < m; i++)
        {
            var valid = ValidateStroke(strokes[i]);
            var (_, _, l) = ArcLength(valid);
            cleaned.Add(valid);
            len[i] = l;
            totalL += l;
        }

        var cnt = new int[m];
        int sumCnt = 0;
        for (int i = 0; i < m; i++)
        {
            cnt[i] = totalL > 0
                ? Math.Max(2, (int)Math.Round(n * len[i] / totalL, MidpointRounding.AwayFromZero))
                : Math.Max(2, n / m);
            sumCnt += cnt[i];
        }

        int d = n - sumCnt;
        if (d > 0)
        {
            int big = 0;
            for (int i = 1; i < m; i++)
                if (len[i] > len[big]) big = i;
            cnt[big] += d;
        }
        else if (d < 0)
        {
            var ord = Enumerable.Range(0, m).OrderByDescending(i => len[i]).ToArray();
            foreach (int i in ord)
            {
                int take = Math.Min(cnt[i] - 2, -d);
                cnt[i] -= take;
                d += take;
                if (d == 0) break;
            }
        }

        var result = new List<Point2D[]>(m);
        for (int i = 0; i < m; i++)
            result.Add(ResampleOne(cleaned[i], cnt[i], method));
        return result;
    }

    // core/cnResampleArc.m — ресэмплинг одного штриха по длине дуги
    public static Point2D[] ResampleOne(Point2D[] rawStroke, int n, string method = "pchip")
    {
        var p = ValidateStroke(rawStroke);
        var (pts, s, L) = ArcLength(p);

        if (pts.Length < 2)
        {
            var rep = new Point2D[n];
            Array.Fill(rep, pts[0]);
            return rep;
        }

        var st = new double[n];
        for (int i = 0; i < n; i++)
            st[i] = n == 1 ? 0.0 : L * i / (n - 1);

        var xs = new double[pts.Length];
        var ys = new double[pts.Length];
        for (int i = 0; i < pts.Length; i++)
        {
            xs[i] = pts[i].X;
            ys[i] = pts[i].Y;
        }

        double[] qx = method == "linear" ? Interp1Linear(s, xs, st) : Interp1Pchip(s, xs, st);
        double[] qy = method == "linear" ? Interp1Linear(s, ys, st) : Interp1Pchip(s, ys, st);

        var q = new Point2D[n];
        for (int i = 0; i < n; i++)
            q[i] = new Point2D(qx[i], qy[i]);
        return q;
    }

    private static Point2D[] ValidateStroke(Point2D[] p)
    {
        var res = new List<Point2D>(p.Length);
        foreach (var pt in p)
            if (pt.IsFinite) res.Add(pt);
        if (res.Count == 0)
            throw new ArgumentException("После удаления NaN в штрихе не осталось точек.");
        return res.ToArray();
    }

    private static (Point2D[] Pts, double[] S, double L) ArcLength(Point2D[] p)
    {
        var pts = new List<Point2D>(p.Length) { p[0] };
        var s = new List<double>(p.Length) { 0.0 };
        double acc = 0.0;

        for (int i = 1; i < p.Length; i++)
        {
            double dx = p[i].X - p[i - 1].X;
            double dy = p[i].Y - p[i - 1].Y;
            double step = Math.Sqrt(dx * dx + dy * dy);
            if (step > 0.0)
            {
                acc += step;
                pts.Add(p[i]);
                s.Add(acc);
            }
        }

        return (pts.ToArray(), s.ToArray(), acc);
    }

    private static double[] Interp1Linear(double[] x, double[] y, double[] xq)
    {
        var yq = new double[xq.Length];
        int n = x.Length;
        int k = 0;
        for (int i = 0; i < xq.Length; i++)
        {
            double xi = xq[i];
            while (k < n - 2 && x[k + 1] < xi) k++;
            double h = x[k + 1] - x[k];
            double t = h > 0 ? (xi - x[k]) / h : 0.0;
            yq[i] = y[k] + t * (y[k + 1] - y[k]);
        }
        return yq;
    }

    // core/cnPchip.m — алгоритм Фритча — Карлсона
    private static double[] Interp1Pchip(double[] x, double[] y, double[] xq)
    {
        int n = x.Length;
        if (n == 2)
            return Interp1Linear(x, y, xq);

        var h = new double[n - 1];
        var del = new double[n - 1];
        for (int i = 0; i < n - 1; i++)
        {
            h[i] = Math.Max(x[i + 1] - x[i], 1e-12);
            del[i] = (y[i + 1] - y[i]) / h[i];
        }

        var d = new double[n];
        for (int i = 1; i < n - 1; i++)
        {
            if (del[i - 1] * del[i] > 0.0)
            {
                double w1 = 2.0 * h[i] + h[i - 1];
                double w2 = h[i] + 2.0 * h[i - 1];
                double denom = w1 / del[i - 1] + w2 / del[i];
                d[i] = Math.Abs(denom) > 1e-15 ? (w1 + w2) / denom : 0.0;
            }
            else
            {
                d[i] = 0.0;
            }
        }

        d[0] = PchipEndSlope(h[0], h[1], del[0], del[1]);
        d[n - 1] = PchipEndSlope(h[n - 2], h[n - 3], del[n - 2], del[n - 3]);

        var yq = new double[xq.Length];
        int k = 0;
        for (int i = 0; i < xq.Length; i++)
        {
            double xi = xq[i];
            while (k < n - 2 && x[k + 1] < xi) k++;
            double s = xi - x[k];
            double hk = h[k];
            double t = Math.Clamp(s / hk, 0.0, 1.0);
            double t2 = t * t;
            double t3 = t2 * t;

            double h00 = 2.0 * t3 - 3.0 * t2 + 1.0;
            double h10 = t3 - 2.0 * t2 + t;
            double h01 = -2.0 * t3 + 3.0 * t2;
            double h11 = t3 - t2;

            yq[i] = h00 * y[k] + h10 * hk * d[k] + h01 * y[k + 1] + h11 * hk * d[k + 1];
        }
        return yq;
    }

    private static double PchipEndSlope(double h1, double h2, double del1, double del2)
    {
        double denom = h1 + h2;
        if (denom <= 1e-12) return del1;
        double d = ((2.0 * h1 + h2) * del1 - h1 * del2) / denom;
        if (Math.Sign(d) != Math.Sign(del1))
            return 0.0;
        if (Math.Sign(del1) != Math.Sign(del2) && Math.Abs(d) > Math.Abs(3.0 * del1))
            return 3.0 * del1;
        return d;
    }
}

namespace CurveNet.Web.Equations;

// predict/cnCurveResidual.m — расчет ошибки аппроксимации (RMS точек к кривой со scale через PCA)
public static class CurveResidualCalculator
{
    public static double CalculateResidual(
        IReadOnlyList<Point2D> idealPoints,
        IReadOnlyList<Point2D[]> normStrokes,
        NormalizeTransform? tf)
    {
        if (idealPoints.Count == 0 || tf == null || normStrokes.Count == 0)
            return double.NaN;

        var uAll = new List<Point2D>();
        var uFin = new List<Point2D>();
        for (int i = 0; i < normStrokes.Count; i++)
        {
            foreach (var pt in normStrokes[i])
            {
                var w = tf.ToWorld(pt);
                uAll.Add(w);
                if (w.IsFinite) uFin.Add(w);
            }
            if (i + 1 < normStrokes.Count)
                uAll.Add(new Point2D(double.NaN, double.NaN));
        }

        if (uFin.Count < 2)
            return double.NaN;

        double dU2C = PointsToCurveRms(uFin, idealPoints);
        double dC2U = PointsToCurveRms(idealPoints, uAll);
        if (!double.IsFinite(dU2C) || !double.IsFinite(dC2U))
            return double.NaN;

        double dSym = Math.Sqrt((dU2C * dU2C + dC2U * dC2U) / 2.0);

        double meanX = 0.0, meanY = 0.0;
        foreach (var p in uFin)
        {
            meanX += p.X;
            meanY += p.Y;
        }
        meanX /= uFin.Count;
        meanY /= uFin.Count;

        // Ковариационная матрица 2x2
        double cxx = 0.0, cxy = 0.0, cyy = 0.0;
        foreach (var p in uFin)
        {
            double dx = p.X - meanX;
            double dy = p.Y - meanY;
            cxx += dx * dx;
            cxy += dx * dy;
            cyy += dy * dy;
        }

        // Собственные векторы через угол поворота theta
        double theta = 0.5 * Math.Atan2(2.0 * cxy, cxx - cyy);
        double ct = Math.Cos(theta);
        double st = Math.Sin(theta);

        double minR1 = double.PositiveInfinity, maxR1 = double.NegativeInfinity;
        double minR2 = double.PositiveInfinity, maxR2 = double.NegativeInfinity;
        foreach (var p in uFin)
        {
            double dx = p.X - meanX;
            double dy = p.Y - meanY;
            double r1 = dx * ct + dy * st;
            double r2 = -dx * st + dy * ct;
            if (r1 < minR1) minR1 = r1;
            if (r1 > maxR1) maxR1 = r1;
            if (r2 < minR2) minR2 = r2;
            if (r2 > maxR2) maxR2 = r2;
        }

        double span1 = maxR1 - minR1;
        double span2 = maxR2 - minR2;
        double maxSpan = Math.Max(Math.Max(span1, span2), tf.Extent);
        if (!double.IsFinite(maxSpan) || maxSpan <= 0.0)
            return double.NaN;

        span1 = Math.Max(span1, 0.05 * maxSpan);
        span2 = Math.Max(span2, 0.05 * maxSpan);
        double scale = Math.Sqrt(span1 * span2);

        return scale > 0.0 ? dSym / scale : double.NaN;
    }

    private static double PointsToCurveRms(IReadOnlyList<Point2D> P, IReadOnlyList<Point2D> C)
    {
        var pFin = P.Where(pt => pt.IsFinite).ToArray();
        if (pFin.Length == 0 || C.Count < 2)
            return double.NaN;

        var segA = new List<Point2D>(C.Count - 1);
        var segAB = new List<Point2D>(C.Count - 1);
        var segL2 = new List<double>(C.Count - 1);

        for (int j = 0; j < C.Count - 1; j++)
        {
            var a = C[j];
            var b = C[j + 1];
            if (a.IsFinite && b.IsFinite)
            {
                double abx = b.X - a.X;
                double handy = b.Y - a.Y;
                segA.Add(a);
                segAB.Add(new Point2D(abx, handy));
                segL2.Add(Math.Max(abx * abx + handy * handy, 2.220446049250313e-16));
            }
        }

        int m = segA.Count;
        if (m == 0)
            return double.NaN;

        double sumMinD2 = 0.0;
        for (int i = 0; i < pFin.Length; i++)
        {
            double px = pFin[i].X;
            double py = pFin[i].Y;
            double minD2 = double.PositiveInfinity;

            for (int j = 0; j < m; j++)
            {
                double ax = segA[j].X;
                double ay = segA[j].Y;
                double abx = segAB[j].X;
                double aby = segAB[j].Y;

                double t = ((px - ax) * abx + (py - ay) * aby) / segL2[j];
                t = Math.Clamp(t, 0.0, 1.0);
                double dx = px - (ax + t * abx);
                double dy = py - (ay + t * aby);
                double d2 = dx * dx + dy * dy;
                if (d2 < minD2) minD2 = d2;
            }
            sumMinD2 += minD2;
        }

        return Math.Sqrt(sumMinD2 / pFin.Length);
    }
}

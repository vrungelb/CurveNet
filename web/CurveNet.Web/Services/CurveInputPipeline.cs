namespace CurveNet.Web.Services;

// predict/cnPrepareInput.m — фильтрация, ресэмплинг (cnResampleArc.m), нормализация (cnNormalize.m) и растр 160x160 (cnRasterize.m)
public static class CurveInputPipeline
{
    public static (bool Ok, string Message, string Warning, byte[,] Img, List<Point2D[]> Strokes, NormalizeTransform? Tf)
        PrepareInput(double[][][] rawStrokesDto, double canvasSpan)
    {
        var kept = new List<Point2D[]>();
        int totalPoints = 0;
        double minX = double.PositiveInfinity, minY = double.PositiveInfinity;
        double maxX = double.NegativeInfinity, maxY = double.NegativeInfinity;
        bool touchesEdge = false;
        double half = canvasSpan / 2.0;
        double tol = CurveConfig.EdgeTol * canvasSpan;

        if (rawStrokesDto != null)
        {
            const int MaxStrokes = 200;
            const int MaxPointsPerStroke = 20000;
            int strokeCount = Math.Min(rawStrokesDto.Length, MaxStrokes);

            for (int sIdx = 0; sIdx < strokeCount; sIdx++)
            {
                var strokeDto = rawStrokesDto[sIdx];
                if (strokeDto == null) continue;
                int ptLimit = Math.Min(strokeDto.Length, MaxPointsPerStroke);
                var pts = new List<Point2D>(ptLimit);
                for (int pIdx = 0; pIdx < ptLimit; pIdx++)
                {
                    var xy = strokeDto[pIdx];
                    if (xy != null && xy.Length >= 2 && double.IsFinite(xy[0]) && double.IsFinite(xy[1]))
                        pts.Add(new Point2D(xy[0], xy[1]));
                }

                if (pts.Count < CurveConfig.MinStrokePoints)
                    continue;

                double len = 0.0;
                for (int i = 1; i < pts.Count; i++)
                {
                    double dx = pts[i].X - pts[i - 1].X;
                    double dy = pts[i].Y - pts[i - 1].Y;
                    len += Math.Sqrt(dx * dx + dy * dy);
                }

                if (len >= CurveConfig.MinStrokeFrac * canvasSpan)
                {
                    var arr = pts.ToArray();
                    kept.Add(arr);
                    totalPoints += arr.Length;
                    foreach (var p in arr)
                    {
                        if (p.X < minX) minX = p.X;
                        if (p.Y < minY) minY = p.Y;
                        if (p.X > maxX) maxX = p.X;
                        if (p.Y > maxY) maxY = p.Y;
                        if (Math.Abs(p.X) > half - tol || Math.Abs(p.Y) > half - tol)
                            touchesEdge = true;
                    }
                }
            }
        }

        if (kept.Count == 0)
            return (false, "Ничего не нарисовано.", "", new byte[0, 0], [], null);

        if (totalPoints < CurveConfig.MinPoints)
            return (false, "Слишком мало точек.", "", new byte[0, 0], [], null);

        double ext = Math.Max(maxX - minX, maxY - minY);
        double boxFrac = ext / canvasSpan;
        if (!double.IsFinite(boxFrac) || boxFrac < CurveConfig.MinBoxFrac)
            return (false, "Рисунок слишком мелкий.", "", new byte[0, 0], [], null);

        string warning = touchesEdge ? "Рисунок упирается в край." : "";

        var resampled = CurveResampling.ResampleMany(kept, CurveConfig.DefaultNPoints, "pchip");
        var (normStrokes, tf) = CurveRasterizer.Normalize(resampled);
        var img = CurveRasterizer.Rasterize(normStrokes, CurveConfig.DefaultLineWidth, CurveConfig.DefaultSoftenSigma);

        return (true, "", warning, img, normStrokes, tf);
    }
}

namespace CurveNet.Web.Geometry;

// core/cnCurvePoints.m — генерация точек канонических кривых через стратегии ICurveStrategy
public static class CurvePointsGenerator
{
    public static (List<Point2D[]> Strokes, CycloidMeta? Meta) CurvePoints(
        string key,
        IReadOnlyDictionary<string, double> prm,
        int n = 256)
    {
        var strategy = CurveRegistry.Get(key);
        int nd = Math.Max(4000, 12 * n);
        var (raw, meta) = strategy.GeneratePoints(prm, nd);
        var strokes = CurveResampling.ResampleMany(raw, n, "pchip");
        return (strokes, meta);
    }
}

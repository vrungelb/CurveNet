using CurveNet.Web.Curves.Strategies;

namespace CurveNet.Web.Curves;

// Реестр стратегий кривых: доступ по строковому ключу
public static class CurveRegistry
{
    private static readonly Dictionary<string, ICurveStrategy> Strategies = new(StringComparer.Ordinal)
    {
        ["circle"] = new CircleCurveStrategy(),
        ["ellipse"] = new EllipseCurveStrategy(),
        ["parabola"] = new ParabolaCurveStrategy(),
        ["hyperbola"] = new HyperbolaCurveStrategy(),
        ["archSpiral"] = new ArchSpiralCurveStrategy(),
        ["logSpiral"] = new LogSpiralCurveStrategy(),
        ["rose"] = new RoseCurveStrategy(),
        ["lemniscate"] = new LemniscateCurveStrategy(),
        ["cycloid"] = new CycloidCurveStrategy(),
        ["astroid"] = new AstroidCurveStrategy(),
        ["cardioid"] = new CardioidCurveStrategy(),
        ["limacon"] = new LimaconCurveStrategy()
    };

    public static ICurveStrategy Get(string key) =>
        Strategies.TryGetValue(key, out var s)
            ? s
            : throw new InvalidOperationException($"Нет стратегии для класса «{key}».");

    public static bool TryGet(string key, out ICurveStrategy? strategy) =>
        Strategies.TryGetValue(key, out strategy);
}

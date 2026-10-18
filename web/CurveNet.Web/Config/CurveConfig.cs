namespace CurveNet.Web.Config;

// config/cnConfig.m и config/cnClasses.m
public static class CurveConfig
{
    // Растеризация входа 160x160 (cnConfig.m)
    public const int ImgSize = 160;
    public const double ImgPad = 0.08;
    public const double DefaultLineWidth = 2.4;
    public const double DefaultSoftenSigma = 0.65;
    public const double SplatStep = 0.4;
    public const bool LineOnBlack = true;

    public const int DefaultNPoints = 235;

    // Пороги валидации штриха (cnPrepareInput.m)
    public const int MinPoints = 12;
    public const double MinBoxFrac = 0.05;
    public const double MinStrokeFrac = 0.02;
    public const int MinStrokePoints = 5;
    public const double EdgeTol = 0.005;

    public const double MinConfidence = 0.55;

    // Справочник классов (cnClasses.m)
    public static readonly IReadOnlyList<CurveClassSpec> AllClasses =
    [
        new("circle", "Окружность", HasAngle: false, SymDeg: 0, RegAffine: false),
        new("ellipse", "Эллипс", SymDeg: 180, RegAffine: false,
            Shape: [new("elong", 1.4, 5.0, "log")]),
        new("parabola", "Парабола", Closed: false, RegAffine: false,
            Shape: [new("halfLength", 1.0, 4.0)]),
        new("hyperbola", "Гипербола", Closed: false, NStrokes: 2, SymDeg: 180, RegAffine: false,
            Shape: [new("b", 0.40, 1.80), new("uMax", 1.10, 1.80)]),
        new("archSpiral", "Спираль Архимеда", Closed: false, FlipMode: "target",
            Shape: [new("turns", 1.2, 5.0)]),
        new("logSpiral", "Логарифмическая спираль", Closed: false, FlipMode: "target",
            Shape: [new("growth", 0.12, 0.38, "log"), new("turns", 1.15, 2.30)]),
        new("rose", "Роза Гранди", SymDeg: double.NaN, FlipMode: "sym180",
            KValues: [3, 5]),
        new("lemniscate", "Лемниската", SymDeg: 180, RegAffine: false,
            Shape: [new("stretch", 0.42, 2.4, "log")]),
        new("cycloid", "Циклоида", Closed: false, FlipMode: "none",
            Shape: [new("arches", 0.95, 3.20), new("phase", 0, 1)]),
        new("astroid", "Астроида", SymDeg: 90),
        new("cardioid", "Кардиоида", FlipMode: "sym180"),
        new("limacon", "Улитка Паскаля", FlipMode: "sym180",
            Shape: [new("ratio", 1.25, 3.00)]),
        new("scribble", "Не распознано", IsCurve: false, Closed: false, HasAngle: true, RegAffine: false, SymDeg: 0)
    ];

    private static readonly Dictionary<string, CurveClassSpec> ByKey =
        AllClasses.ToDictionary(c => c.Key, StringComparer.Ordinal);

    public static CurveClassSpec GetClass(string key) =>
        ByKey.TryGetValue(key, out var spec)
            ? spec
            : throw new ArgumentException($"Неизвестный класс «{key}».");
}

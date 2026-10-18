namespace CurveNet.Web.Config;

// config/cnClasses.m — диапазоны параметров формы
public sealed record ShapeParamSpec(string Name, double Lo, double Hi, string Scale = "lin");

// config/cnClasses.m — спецификация класса кривой
public sealed record CurveClassSpec(
    string Key,
    string Name,
    bool IsCurve = true,
    bool Closed = true,
    int NStrokes = 1,
    bool HasAngle = true,
    double SymDeg = 360.0,
    bool RegAffine = true,
    string FlipMode = "sym360",
    ShapeParamSpec[]? Shape = null,
    int[]? KValues = null);

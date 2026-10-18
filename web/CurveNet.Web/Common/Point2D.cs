namespace CurveNet.Web.Common;

// 2D-точка для координат штрихов и кривых
public readonly record struct Point2D(double X, double Y)
{
    public bool IsFinite => double.IsFinite(X) && double.IsFinite(Y);
}

// core/cnCurvePoints.m — параметры развёртки циклоиды
public sealed record CycloidMeta(double T0, double T1, double Cx, double Cy, double Hx);

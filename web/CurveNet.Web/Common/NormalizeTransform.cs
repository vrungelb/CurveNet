namespace CurveNet.Web.Common;

// core/cnNormalize.m — структура tf (переход world <-> norm)
public sealed class NormalizeTransform
{
    public Point2D Center { get; init; }
    public double Extent { get; init; }
    public double Pad { get; init; }
    public double Scale { get; init; }
    public Point2D Offset { get; init; }
    public Point2D BoxMin { get; init; }
    public Point2D BoxMax { get; init; }

    public Point2D ToNorm(Point2D p) =>
        new((p.X - Center.X) / Scale + 0.5 + Offset.X,
            (p.Y - Center.Y) / Scale + 0.5 + Offset.Y);

    public Point2D ToWorld(Point2D u) =>
        new((u.X - 0.5 - Offset.X) * Scale + Center.X,
            (u.Y - 0.5 - Offset.Y) * Scale + Center.Y);
}

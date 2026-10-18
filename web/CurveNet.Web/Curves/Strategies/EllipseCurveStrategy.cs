namespace CurveNet.Web.Curves.Strategies;

// Эллипс: x^2 + (elong*y)^2 = R^2
public sealed class EllipseCurveStrategy : ICurveStrategy
{
    public string Key => "ellipse";

    public (List<Point2D[]> RawStrokes, CycloidMeta? Meta) GeneratePoints(IReadOnlyDictionary<string, double> prm, int nd)
    {
        double elong = prm.GetValueOrDefault("elong", 2.0);
        var pts = new Point2D[nd];
        for (int i = 0; i < nd; i++)
        {
            double t = 2.0 * Math.PI * i / (nd - 1);
            pts[i] = new Point2D(Math.Cos(t), Math.Sin(t) / elong);
        }
        return ([pts], null);
    }

    public (string ExactText, string Latex) BuildEquation(CurveEquationContext ctx)
    {
        double elong = Math.Max(1e-4, ctx.Params.GetValueOrDefault("elong", 2.0));
        var f = Polynomial2D.PolyAdd(ctx.UU, Polynomial2D.ScalePoly(ctx.VV, elong * elong));
        f[0, 0] -= ctx.K * ctx.K;
        return (Polynomial2D.PolyText(f) + " = 0", Polynomial2D.PolyLatex3(f) + " = 0");
    }
}

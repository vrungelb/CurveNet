namespace CurveNet.Web.Curves.Strategies;

// Гипербола: x^2 - (y/b)^2 = R^2 (2 ветви)
public sealed class HyperbolaCurveStrategy : ICurveStrategy
{
    public string Key => "hyperbola";

    public (List<Point2D[]> RawStrokes, CycloidMeta? Meta) GeneratePoints(IReadOnlyDictionary<string, double> prm, int nd)
    {
        double uMax = prm.GetValueOrDefault("uMax", 1.4);
        double b = prm.GetValueOrDefault("b", 1.0);
        var p1 = new Point2D[nd];
        var p2 = new Point2D[nd];
        for (int i = 0; i < nd; i++)
        {
            double u = -uMax + 2.0 * uMax * i / (nd - 1);
            double ch = Math.Cosh(u);
            double sh = b * Math.Sinh(u);
            p1[i] = new Point2D(ch, sh);
            p2[i] = new Point2D(-ch, sh);
        }
        return ([p1, p2], null);
    }

    public (string ExactText, string Latex) BuildEquation(CurveEquationContext ctx)
    {
        double b = Math.Max(1e-4, ctx.Params.GetValueOrDefault("b", 1.0));
        var f = Polynomial2D.PolyAdd(ctx.UU, Polynomial2D.ScalePoly(ctx.VV, -1.0 / (b * b)));
        f[0, 0] -= ctx.K * ctx.K;
        return (Polynomial2D.PolyText(f) + " = 0", Polynomial2D.PolyLatex3(f) + " = 0");
    }
}

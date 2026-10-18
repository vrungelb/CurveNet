namespace CurveNet.Web.Curves.Strategies;

// Лемниската Бернулли: (x^2 + y^2)^2 = 2 a^2 (x^2 - y^2)
public sealed class LemniscateCurveStrategy : ICurveStrategy
{
    public string Key => "lemniscate";

    public (List<Point2D[]> RawStrokes, CycloidMeta? Meta) GeneratePoints(IReadOnlyDictionary<string, double> prm, int nd)
    {
        double stretch = prm.GetValueOrDefault("stretch", 1.0);
        var pts = new Point2D[nd];
        for (int i = 0; i < nd; i++)
        {
            double t = 2.0 * Math.PI * i / (nd - 1);
            double st = Math.Sin(t);
            double ct = Math.Cos(t);
            double d = 1.0 + st * st;
            pts[i] = new Point2D(ct / d, stretch * (st * ct) / d);
        }
        return ([pts], null);
    }

    public (string ExactText, string Latex) BuildEquation(CurveEquationContext ctx)
    {
        double st = Math.Max(1e-4, ctx.Params.GetValueOrDefault("stretch", 1.0));
        double st2 = st * st;
        var a = Polynomial2D.PolyAdd(Polynomial2D.ScalePoly(ctx.UU, st2), ctx.VV);
        var b = Polynomial2D.PolyAdd(Polynomial2D.ScalePoly(ctx.UU, st2), Polynomial2D.ScalePoly(ctx.VV, -1.0));
        var f = Polynomial2D.PolyAdd(Polynomial2D.PolyPow(a, 2), Polynomial2D.ScalePoly(b, -ctx.K * ctx.K * st2));
        return (Polynomial2D.PolyText(f) + " = 0", Polynomial2D.PolyLatex3(f) + " = 0");
    }
}

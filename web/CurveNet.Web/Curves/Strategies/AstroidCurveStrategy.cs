namespace CurveNet.Web.Curves.Strategies;

// Астроида: x^(2/3) + y^(2/3) = R^(2/3) -> неявный полином 6-й степени
public sealed class AstroidCurveStrategy : ICurveStrategy
{
    public string Key => "astroid";

    public (List<Point2D[]> RawStrokes, CycloidMeta? Meta) GeneratePoints(IReadOnlyDictionary<string, double> prm, int nd)
    {
        var pts = new Point2D[nd];
        for (int i = 0; i < nd; i++)
        {
            double t = 2.0 * Math.PI * i / (nd - 1);
            double ct = Math.Cos(t);
            double st = Math.Sin(t);
            pts[i] = new Point2D(ct * ct * ct, st * st * st);
        }
        return ([pts], null);
    }

    public (string ExactText, string Latex) BuildEquation(CurveEquationContext ctx)
    {
        var a = (double[,])ctx.R2.Clone();
        a[0, 0] -= ctx.K * ctx.K;
        var f = Polynomial2D.PolyAdd(Polynomial2D.PolyPow(a, 3), Polynomial2D.ScalePoly(Polynomial2D.Conv2(ctx.UU, ctx.VV), 27.0 * ctx.K * ctx.K));
        return (Polynomial2D.PolyText(f) + " = 0", Polynomial2D.PolyLatex3(f) + " = 0");
    }
}

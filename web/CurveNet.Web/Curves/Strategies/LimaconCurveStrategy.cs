namespace CurveNet.Web.Curves.Strategies;

// Улитка Паскаля: r = a * (1 + ratio * cos(theta))
public sealed class LimaconCurveStrategy : ICurveStrategy
{
    public string Key => "limacon";

    public (List<Point2D[]> RawStrokes, CycloidMeta? Meta) GeneratePoints(IReadOnlyDictionary<string, double> prm, int nd)
    {
        double ratio = prm.GetValueOrDefault("ratio", 2.0);
        var pts = new Point2D[nd];
        for (int i = 0; i < nd; i++)
        {
            double th = 2.0 * Math.PI * i / (nd - 1);
            double r = 1.0 + ratio * Math.Cos(th);
            pts[i] = new Point2D(r * Math.Cos(th), r * Math.Sin(th));
        }
        return ([pts], null);
    }

    public (string ExactText, string Latex) BuildEquation(CurveEquationContext ctx)
    {
        double ratio = ctx.Params.GetValueOrDefault("ratio", 2.0);
        var a = Polynomial2D.PolyAdd(ctx.R2, Polynomial2D.ScalePoly(ctx.U, -ratio * ctx.K));
        var f = Polynomial2D.PolyAdd(Polynomial2D.PolyPow(a, 2), Polynomial2D.ScalePoly(ctx.R2, -ctx.K * ctx.K));
        return (Polynomial2D.PolyText(f) + " = 0", Polynomial2D.PolyLatex3(f) + " = 0");
    }
}

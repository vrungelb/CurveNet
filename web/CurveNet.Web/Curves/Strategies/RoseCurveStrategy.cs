namespace CurveNet.Web.Curves.Strategies;

// Роза Гранди: r = a * cos(k * theta)
public sealed class RoseCurveStrategy : ICurveStrategy
{
    public string Key => "rose";

    public (List<Point2D[]> RawStrokes, CycloidMeta? Meta) GeneratePoints(IReadOnlyDictionary<string, double> prm, int nd)
    {
        int k = (int)Math.Round(prm.GetValueOrDefault("k", 3.0));
        double limit = (k % 2 == 0) ? 2.0 * Math.PI : Math.PI;
        var pts = new Point2D[nd];
        for (int i = 0; i < nd; i++)
        {
            double th = limit * i / (nd - 1);
            double r = Math.Cos(k * th);
            pts[i] = new Point2D(r * Math.Cos(th), r * Math.Sin(th));
        }
        return ([pts], null);
    }

    public (string ExactText, string Latex) BuildEquation(CurveEquationContext ctx)
    {
        int kk = Math.Clamp((int)Math.Round(ctx.Params.GetValueOrDefault("k", 3.0)), 2, 7);
        var reZ = Polynomial2D.PolyRoseReal(ctx.U, ctx.V, kk);
        double[,] f;

        if (kk % 2 == 1)
            f = Polynomial2D.PolyAdd(Polynomial2D.PolyPow(ctx.R2, (kk + 1) / 2), Polynomial2D.ScalePoly(reZ, -ctx.K));
        else
            f = Polynomial2D.PolyAdd(Polynomial2D.PolyPow(ctx.R2, kk + 1), Polynomial2D.ScalePoly(Polynomial2D.PolyPow(reZ, 2), -ctx.K * ctx.K));

        return (Polynomial2D.PolyText(f) + " = 0", Polynomial2D.PolyLatex3(f) + " = 0");
    }
}

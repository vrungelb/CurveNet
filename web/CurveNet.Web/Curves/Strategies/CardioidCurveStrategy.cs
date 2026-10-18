namespace CurveNet.Web.Curves.Strategies;

// Кардиоида: r = a * (1 - cos(theta))
public sealed class CardioidCurveStrategy : ICurveStrategy
{
    public string Key => "cardioid";

    public (List<Point2D[]> RawStrokes, CycloidMeta? Meta) GeneratePoints(IReadOnlyDictionary<string, double> prm, int nd)
    {
        var pts = new Point2D[nd];
        for (int i = 0; i < nd; i++)
        {
            double th = 2.0 * Math.PI * i / (nd - 1);
            double r = 1.0 - Math.Cos(th);
            pts[i] = new Point2D(r * Math.Cos(th), r * Math.Sin(th));
        }
        return ([pts], null);
    }

    public (string ExactText, string Latex) BuildEquation(CurveEquationContext ctx)
    {
        var a = Polynomial2D.PolyAdd(ctx.R2, Polynomial2D.ScalePoly(ctx.U, ctx.K));
        var f = Polynomial2D.PolyAdd(Polynomial2D.PolyPow(a, 2), Polynomial2D.ScalePoly(ctx.R2, -ctx.K * ctx.K));
        return (Polynomial2D.PolyText(f) + " = 0", Polynomial2D.PolyLatex3(f) + " = 0");
    }
}

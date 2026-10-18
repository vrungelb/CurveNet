namespace CurveNet.Web.Curves.Strategies;

// Парабола: y = x^2 / (2k)
public sealed class ParabolaCurveStrategy : ICurveStrategy
{
    public string Key => "parabola";

    public (List<Point2D[]> RawStrokes, CycloidMeta? Meta) GeneratePoints(IReadOnlyDictionary<string, double> prm, int nd)
    {
        double hl = prm.GetValueOrDefault("halfLength", 2.0);
        var pts = new Point2D[nd];
        for (int i = 0; i < nd; i++)
        {
            double x = -hl + 2.0 * hl * i / (nd - 1);
            pts[i] = new Point2D(x, 0.5 * x * x);
        }
        return ([pts], null);
    }

    public (string ExactText, string Latex) BuildEquation(CurveEquationContext ctx)
    {
        var f = Polynomial2D.PolyAdd(ctx.UU, Polynomial2D.ScalePoly(ctx.V, -2.0 * ctx.K));
        return (Polynomial2D.PolyText(f) + " = 0", Polynomial2D.PolyLatex3(f) + " = 0");
    }
}

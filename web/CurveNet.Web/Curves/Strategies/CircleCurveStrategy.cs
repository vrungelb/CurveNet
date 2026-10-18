namespace CurveNet.Web.Curves.Strategies;

// Окружность: x^2 + y^2 = R^2
public sealed class CircleCurveStrategy : ICurveStrategy
{
    public string Key => "circle";

    public (List<Point2D[]> RawStrokes, CycloidMeta? Meta) GeneratePoints(IReadOnlyDictionary<string, double> prm, int nd)
    {
        var pts = new Point2D[nd];
        for (int i = 0; i < nd; i++)
        {
            double t = 2.0 * Math.PI * i / (nd - 1);
            pts[i] = new Point2D(Math.Cos(t), Math.Sin(t));
        }
        return ([pts], null);
    }

    public (string ExactText, string Latex) BuildEquation(CurveEquationContext ctx)
    {
        var f = (double[,])ctx.R2.Clone();
        f[0, 0] -= ctx.K * ctx.K;
        return (Polynomial2D.PolyText(f) + " = 0", Polynomial2D.PolyLatex3(f) + " = 0");
    }
}

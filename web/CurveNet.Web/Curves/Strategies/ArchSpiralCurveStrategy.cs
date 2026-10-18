namespace CurveNet.Web.Curves.Strategies;

// Спираль Архимеда: r = a * theta
public sealed class ArchSpiralCurveStrategy : ICurveStrategy
{
    public string Key => "archSpiral";

    public (List<Point2D[]> RawStrokes, CycloidMeta? Meta) GeneratePoints(IReadOnlyDictionary<string, double> prm, int nd)
    {
        double turns = prm.GetValueOrDefault("turns", 2.5);
        var pts = new Point2D[nd];
        for (int i = 0; i < nd; i++)
        {
            double th = 2.0 * Math.PI * turns * i / (nd - 1);
            pts[i] = new Point2D(th * Math.Cos(th), th * Math.Sin(th));
        }
        return ([pts], null);
    }

    public (string ExactText, string Latex) BuildEquation(CurveEquationContext ctx)
    {
        double k00 = ctx.K * ctx.AffineMatrix[0, 0], k01 = ctx.K * ctx.AffineMatrix[0, 1];
        double k10 = ctx.K * ctx.AffineMatrix[1, 0], k11 = ctx.K * ctx.AffineMatrix[1, 1];
        double turns = ctx.Params.GetValueOrDefault("turns", 2.5);

        string exact =
            $"x(θ) = θ*({CurveFormatters.FmtExact(k00)}*cos(θ) + {CurveFormatters.FmtExact(k01)}*sin(θ)) + {CurveFormatters.FmtExact(ctx.X0.X)}\n" +
            $"y(θ) = θ*({CurveFormatters.FmtExact(k10)}*cos(θ) + {CurveFormatters.FmtExact(k11)}*sin(θ)) + {CurveFormatters.FmtExact(ctx.X0.Y)}, " +
            $"θ ∈ [0, {CurveFormatters.FmtExact(2.0 * turns)}π]";

        string latex =
            @"\begin{aligned}" +
            $"x(\\theta) &= \\theta\\,\\left({CurveFormatters.FmtLatex3(k00)}\\cos\\theta {CurveFormatters.FmtSignedTermLatex(k01, "\\sin\\theta")}\\right) {CurveFormatters.FmtSignedConstLatex(ctx.X0.X)} \\\\ " +
            $"y(\\theta) &= \\theta\\,\\left({CurveFormatters.FmtLatex3(k10)}\\cos\\theta {CurveFormatters.FmtSignedTermLatex(k11, "\\sin\\theta")}\\right) {CurveFormatters.FmtSignedConstLatex(ctx.X0.Y)} \\\\ " +
            $"\\theta &\\in [0,\\; {CurveFormatters.FmtLatex3(2.0 * turns)}\\pi]" +
            @"\end{aligned}";

        return (exact, latex);
    }
}

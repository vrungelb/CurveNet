namespace CurveNet.Web.Curves.Strategies;

// Логарифмическая спираль: r = e^(growth * theta)
public sealed class LogSpiralCurveStrategy : ICurveStrategy
{
    public string Key => "logSpiral";

    public (List<Point2D[]> RawStrokes, CycloidMeta? Meta) GeneratePoints(IReadOnlyDictionary<string, double> prm, int nd)
    {
        double turns = prm.GetValueOrDefault("turns", 1.7);
        double growth = prm.GetValueOrDefault("growth", 0.2);
        var pts = new Point2D[nd];
        for (int i = 0; i < nd; i++)
        {
            double th = -2.0 * Math.PI * turns * (nd - 1 - i) / (nd - 1);
            double r = Math.Exp(growth * th);
            pts[i] = new Point2D(r * Math.Cos(th), r * Math.Sin(th));
        }
        return ([pts], null);
    }

    public (string ExactText, string Latex) BuildEquation(CurveEquationContext ctx)
    {
        double k00 = ctx.K * ctx.AffineMatrix[0, 0], k01 = ctx.K * ctx.AffineMatrix[0, 1];
        double k10 = ctx.K * ctx.AffineMatrix[1, 0], k11 = ctx.K * ctx.AffineMatrix[1, 1];
        double gw = ctx.Params.GetValueOrDefault("growth", 0.2);
        double turns = ctx.Params.GetValueOrDefault("turns", 1.7);

        string exact =
            $"x(θ) = e^({CurveFormatters.FmtExact(gw)}*θ)*({CurveFormatters.FmtExact(k00)}*cos(θ) + {CurveFormatters.FmtExact(k01)}*sin(θ)) + {CurveFormatters.FmtExact(ctx.X0.X)}\n" +
            $"y(θ) = e^({CurveFormatters.FmtExact(gw)}*θ)*({CurveFormatters.FmtExact(k10)}*cos(θ) + {CurveFormatters.FmtExact(k11)}*sin(θ)) + {CurveFormatters.FmtExact(ctx.X0.Y)}, " +
            $"θ ∈ [-{CurveFormatters.FmtExact(2.0 * turns)}π, 0]";

        string latex =
            @"\begin{aligned}" +
            $"x(\\theta) &= e^{{{CurveFormatters.FmtLatex3(gw)}\\theta}}\\left({CurveFormatters.FmtLatex3(k00)}\\cos\\theta {CurveFormatters.FmtSignedTermLatex(k01, "\\sin\\theta")}\\right) {CurveFormatters.FmtSignedConstLatex(ctx.X0.X)} \\\\ " +
            $"y(\\theta) &= e^{{{CurveFormatters.FmtLatex3(gw)}\\theta}}\\left({CurveFormatters.FmtLatex3(k10)}\\cos\\theta {CurveFormatters.FmtSignedTermLatex(k11, "\\sin\\theta")}\\right) {CurveFormatters.FmtSignedConstLatex(ctx.X0.Y)} \\\\ " +
            $"\\theta &\\in [-{CurveFormatters.FmtLatex3(2.0 * turns)}\\pi,\\; 0]" +
            @"\end{aligned}";

        return (exact, latex);
    }
}

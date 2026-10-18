namespace CurveNet.Web.Curves.Strategies;

// Циклоида: x = r*(t - sin(t)), y = r*(1 - cos(t))
public sealed class CycloidCurveStrategy : ICurveStrategy
{
    public string Key => "cycloid";

    public (List<Point2D[]> RawStrokes, CycloidMeta? Meta) GeneratePoints(IReadOnlyDictionary<string, double> prm, int nd)
    {
        double ph = prm.GetValueOrDefault("phase", 0.0);
        double arches = prm.GetValueOrDefault("arches", 2.0);
        double tMid = 2.0 * Math.PI * ph;
        double hSpan = Math.PI * arches;
        double t0 = tMid - hSpan;
        double t1 = tMid + hSpan;
        double shift = 2.0 * Math.PI * Math.Ceiling(Math.Max(0.0, -t0 / (2.0 * Math.PI)));
        t0 += shift;
        t1 += shift;

        var xr = new double[nd];
        var yr = new double[nd];
        double minY = double.PositiveInfinity;
        double maxY = double.NegativeInfinity;
        for (int i = 0; i < nd; i++)
        {
            double t = t0 + (t1 - t0) * i / (nd - 1);
            xr[i] = t - Math.Sin(t);
            yr[i] = 1.0 - Math.Cos(t);
            if (yr[i] < minY) minY = yr[i];
            if (yr[i] > maxY) maxY = yr[i];
        }
        double cx = (xr[0] + xr[nd - 1]) / 2.0;
        double cy = (minY + maxY) / 2.0;
        double hx = Math.Max((xr[nd - 1] - xr[0]) / 2.0, 1e-6);

        var pts = new Point2D[nd];
        for (int i = 0; i < nd; i++)
            pts[i] = new Point2D((xr[i] - cx) / hx, (yr[i] - cy) / hx);

        var meta = new CycloidMeta(t0, t1, cx, cy, hx);
        return ([pts], meta);
    }

    public (string ExactText, string Latex) BuildEquation(CurveEquationContext ctx)
    {
        var (_, cyc) = GeneratePoints(ctx.Params, 2);
        double sFactor = ctx.K / Math.Max(cyc!.Hx, 1e-6);
        double k00 = sFactor * ctx.AffineMatrix[0, 0], k01 = sFactor * ctx.AffineMatrix[0, 1];
        double k10 = sFactor * ctx.AffineMatrix[1, 0], k11 = sFactor * ctx.AffineMatrix[1, 1];
        double xeq0 = ctx.X0.X - (cyc.Cx * k00 + cyc.Cy * k01);
        double xeq1 = ctx.X0.Y - (cyc.Cx * k10 + cyc.Cy * k11);

        string exact =
            $"x(t) = {CurveFormatters.FmtExact(k00)}*(t - sin(t)) + {CurveFormatters.FmtExact(k01)}*(1 - cos(t)) + {CurveFormatters.FmtExact(xeq0)}\n" +
            $"y(t) = {CurveFormatters.FmtExact(k10)}*(t - sin(t)) + {CurveFormatters.FmtExact(k11)}*(1 - cos(t)) + {CurveFormatters.FmtExact(xeq1)}, " +
            $"t ∈ [{CurveFormatters.FmtExact(cyc.T0 / Math.PI)}π, {CurveFormatters.FmtExact(cyc.T1 / Math.PI)}π]";

        string latex =
            @"\begin{aligned}" +
            $"x(t) &= {CurveFormatters.FmtLatex3(k00)}(t - \\sin t) {CurveFormatters.FmtSignedTermLatex(k01, "(1 - \\cos t)")} {CurveFormatters.FmtSignedConstLatex(xeq0)} \\\\ " +
            $"y(t) &= {CurveFormatters.FmtLatex3(k10)}(t - \\sin t) {CurveFormatters.FmtSignedTermLatex(k11, "(1 - \\cos t)")} {CurveFormatters.FmtSignedConstLatex(xeq1)} \\\\ " +
            $"t &\\in [{CurveFormatters.FmtLatex3(cyc.T0 / Math.PI)}\\pi,\\; {CurveFormatters.FmtLatex3(cyc.T1 / Math.PI)}\\pi]" +
            @"\end{aligned}";

        return (exact, latex);
    }
}

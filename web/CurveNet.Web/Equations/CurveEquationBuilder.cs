namespace CurveNet.Web.Equations;

// predict/cnEquationText.m — построение уравнений через стратегии ICurveStrategy
public static class CurveEquationBuilder
{
    public static (string ExactText, string Latex) BuildEquations(
        string cls,
        IReadOnlyDictionary<string, double> prm,
        Point2D X0,
        double k,
        double ang,
        double aX,
        double aY,
        double sh,
        bool flip,
        double[,] A_mat)
    {
        if (!CurveRegistry.TryGet(cls, out var strategy) || strategy == null)
            return ("", "");

        double safeAx = Math.Abs(aX) > 1e-8 ? aX : 1.0;
        double safeAy = Math.Abs(aY) > 1e-8 ? aY : 1.0;
        double c = Math.Cos(ang);
        double sn = Math.Sin(ang);

        // Minv = [1/aX, -sh/aX; 0, 1/aY]
        // C = [c, -sn; sn, c] * Minv^T
        double m00 = 1.0 / safeAx;
        double m01 = -sh / safeAx;
        double m11 = 1.0 / safeAy;

        double c00 = c * m00 + (-sn) * m01;
        double c01 = (-sn) * m11;
        double c10 = sn * m00 + c * m01;
        double c11 = c * m11;

        if (flip)
        {
            c00 = -c00;
            c01 = -c01;
        }

        double[,] u = Polynomial2D.PolyLinear(-(c00 * X0.X + c10 * X0.Y), c00, c10);
        double[,] v = Polynomial2D.PolyLinear(-(c01 * X0.X + c11 * X0.Y), c01, c11);

        double[,] uu = Polynomial2D.Conv2(u, u);
        double[,] vv = Polynomial2D.Conv2(v, v);
        double[,] r2 = Polynomial2D.PolyAdd(uu, vv);

        var ctx = new CurveEquationContext(
            Params: prm,
            X0: X0,
            K: k,
            AngleRad: ang,
            AnisoX: aX,
            AnisoY: aY,
            Shear: sh,
            Flip: flip,
            AffineMatrix: A_mat,
            U: u,
            V: v,
            UU: uu,
            VV: vv,
            R2: r2);

        return strategy.BuildEquation(ctx);
    }
}

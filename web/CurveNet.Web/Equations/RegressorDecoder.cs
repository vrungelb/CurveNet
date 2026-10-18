namespace CurveNet.Web.Equations;

// core/cnRegressorTargets.m (ветка decode) — распаковка параметров из [-1, 1] в физические величины
public static class RegressorDecoder
{
    public static Dictionary<string, double> DecodeTargets(
        CurveClassSpec cls,
        RegressorMeta reg,
        double[] predNorm,
        Dictionary<string, double>? existingParams = null)
    {
        var prm = existingParams != null
            ? new Dictionary<string, double>(existingParams, StringComparer.Ordinal)
            : new Dictionary<string, double>(StringComparer.Ordinal);

        if (predNorm.Length != reg.TargetCols.Length)
            throw new InvalidOperationException(
                $"Регрессор вернул {predNorm.Length} чисел, а ожидалось {reg.TargetCols.Length}.");

        for (int i = 0; i < reg.TargetCols.Length; i++)
        {
            string col = reg.TargetCols[i];
            double minV = reg.NormMin[i];
            double maxV = reg.NormMax[i];
            double range = maxV - minV;
            if (range == 0.0) range = 1.0;

            double raw = (predNorm[i] + 1.0) / 2.0 * range + minV;
            if (!col.StartsWith("cos", StringComparison.Ordinal) &&
                !col.StartsWith("sin", StringComparison.Ordinal))
            {
                raw = Math.Clamp(raw, minV, maxV);
            }
            prm[col] = raw;
        }

        if (reg.UnitAniso && prm.TryGetValue("anisoX", out double ax) && prm.TryGetValue("anisoY", out double ay))
        {
            double cPred = Math.Sqrt(Math.Max(1e-8, ax * ay));
            prm["anisoX"] = ax / cPred;
            prm["anisoY"] = ay / cPred;
        }

        if (prm.TryGetValue("growth", out double gw))
        {
            if (reg.LogGrowth)
                prm["growth"] = Math.Exp(gw);
            else if (gw <= 0.0)
                prm["growth"] = 0.001;
        }

        if (prm.TryGetValue("cosp", out double cosp) && prm.TryGetValue("sinp", out double sinp))
        {
            prm["phase"] = CurveAffine.MathMod(Math.Atan2(sinp, cosp) / (2.0 * Math.PI), 1.0);
        }

        if (cls.HasAngle)
        {
            double kVal = double.IsNaN(cls.SymDeg) && prm.TryGetValue("k", out double kv) ? Math.Max(1.0, kv) : 1.0;
            var (mult, sfx) = AngleMultSuffix(cls, kVal);
            double sinV = prm.GetValueOrDefault("sin" + sfx, 0.0);
            double cosV = prm.GetValueOrDefault("cos" + sfx, 1.0);
            double a = (Math.Atan2(sinV, cosV) * 180.0 / Math.PI) / Math.Max(1.0, mult);

            if (cls.SymDeg == 90.0 && prm.TryGetValue("shear", out double sh))
            {
                double lo = -45.0 + (Math.Atan(sh) * 180.0 / Math.PI) / 2.0;
                a = lo + CurveAffine.MathMod(a - lo, 90.0);
            }
            prm["angleDeg"] = CurveAffine.MathMod(a, 360.0);
        }
        else
        {
            prm["angleDeg"] = 0.0;
        }

        if (prm.TryGetValue("turns", out double turns))
        {
            prm["turns"] = Math.Max(0.5, turns);
        }

        return prm;
    }

    private static (double Mult, string Sfx) AngleMultSuffix(CurveClassSpec cls, double kVal)
    {
        if (double.IsNaN(cls.SymDeg))
            return (Math.Max(1.0, kVal), "Ka");
        int mult = Math.Max(1, (int)Math.Round(360.0 / cls.SymDeg));
        string sfx = mult > 1 ? $"{mult}a" : "a";
        return (mult, sfx);
    }
}

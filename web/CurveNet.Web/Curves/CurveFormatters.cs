using System.Globalization;

namespace CurveNet.Web.Curves;

// Форматирование чисел и слагаемых для текстового и LaTeX вывода
public static class CurveFormatters
{
    public static string FmtExact(double v) => v.ToString("G12", CultureInfo.InvariantCulture);

    public static string FmtLatex3(double v)
    {
        if (Math.Abs(v) < 1e-9) return "0";
        double r = Math.Round(v, 3, MidpointRounding.AwayFromZero);
        if (r != 0.0)
            return r.ToString("0.000", CultureInfo.InvariantCulture);
        return v.ToString("G3", CultureInfo.InvariantCulture);
    }

    public static string FmtSignedTermLatex(double coeff, string expr)
    {
        string sign = coeff < 0 ? "-" : "+";
        return $"{sign} {FmtLatex3(Math.Abs(coeff))}{expr}";
    }

    public static string FmtSignedConstLatex(double val)
    {
        string sign = val < 0 ? "-" : "+";
        return $"{sign} {FmtLatex3(Math.Abs(val))}";
    }
}

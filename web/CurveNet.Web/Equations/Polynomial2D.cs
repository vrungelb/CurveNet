using System.Globalization;

namespace CurveNet.Web.Equations;

// predict/cnEquationText.m — полиномиальная 2D-алгебра (conv2, степени, разложение розы)
public static class Polynomial2D
{
    public static double[,] PolyLinear(double a0, double ax, double ay) =>
        new[,] { { a0, ay }, { ax, 0.0 } };

    public static double[,] ScalePoly(double[,] A, double s)
    {
        int r = A.GetLength(0), c = A.GetLength(1);
        var R = new double[r, c];
        for (int i = 0; i < r; i++)
            for (int j = 0; j < c; j++)
                R[i, j] = A[i, j] * s;
        return R;
    }

    public static double[,] PolyAdd(double[,] A, double[,] B)
    {
        int r = Math.Max(A.GetLength(0), B.GetLength(0));
        int c = Math.Max(A.GetLength(1), B.GetLength(1));
        var C = new double[r, c];
        for (int i = 0; i < A.GetLength(0); i++)
            for (int j = 0; j < A.GetLength(1); j++)
                C[i, j] += A[i, j];
        for (int i = 0; i < B.GetLength(0); i++)
            for (int j = 0; j < B.GetLength(1); j++)
                C[i, j] += B[i, j];
        return C;
    }

    // conv2(A, B) в MATLAB
    public static double[,] Conv2(double[,] A, double[,] B)
    {
        int rA = A.GetLength(0), cA = A.GetLength(1);
        int rB = B.GetLength(0), cB = B.GetLength(1);
        var C = new double[rA + rB - 1, cA + cB - 1];
        for (int i1 = 0; i1 < rA; i1++)
            for (int j1 = 0; j1 < cA; j1++)
                for (int i2 = 0; i2 < rB; i2++)
                    for (int j2 = 0; j2 < cB; j2++)
                        C[i1 + i2, j1 + j2] += A[i1, j1] * B[i2, j2];
        return C;
    }

    public static double[,] PolyPow(double[,] P, int n)
    {
        if (n <= 0)
            return new[,] { { 1.0 } };
        double[,] R = (double[,])P.Clone();
        for (int e = 2; e <= n; e++)
            R = Conv2(R, P);
        return R;
    }

    // Re((u + i*v)^k) через биномиальные коэффициенты
    public static double[,] PolyRoseReal(double[,] u, double[,] v, int k)
    {
        double[,] P = new[,] { { 0.0 } };
        for (int j = 0; j <= k; j += 2)
        {
            var T = Conv2(PolyPow(u, k - j), PolyPow(v, j));
            double sign = ((j / 2) % 2 == 0) ? 1.0 : -1.0;
            P = PolyAdd(P, ScalePoly(T, NChooseK(k, j) * sign));
        }
        return P;
    }

    private static double NChooseK(int n, int k)
    {
        if (k < 0 || k > n) return 0.0;
        if (k == 0 || k == n) return 1.0;
        double res = 1.0;
        for (int i = 1; i <= k; i++)
            res = res * (n - i + 1) / i;
        return res;
    }

    public static string PolyText(double[,] F)
    {
        int nx = F.GetLength(0);
        int ny = F.GetLength(1);
        string t = "";

        for (int d = nx + ny - 2; d >= 0; d--)
        {
            for (int i = Math.Min(d, nx - 1); i >= 0; i--)
            {
                int j = d - i;
                if (j > ny - 1) continue;
                double a = F[i, j];
                if (Math.Abs(a) < 1e-9) continue;

                string num = Math.Abs(a).ToString("G12", CultureInfo.InvariantCulture);
                if (num == "1" && (i > 0 || j > 0)) num = "";

                string sg;
                if (t.Length == 0)
                    sg = a < 0 ? "-" : "";
                else
                    sg = a < 0 ? " - " : " + ";

                t += sg + num + Monomial(i, j);
            }
        }

        return t.Length == 0 ? "0" : t;
    }

    public static string PolyLatex3(double[,] F)
    {
        int nx = F.GetLength(0);
        int ny = F.GetLength(1);
        string t = "";

        for (int d = nx + ny - 2; d >= 0; d--)
        {
            for (int i = Math.Min(d, nx - 1); i >= 0; i--)
            {
                int j = d - i;
                if (j > ny - 1) continue;
                double a = F[i, j];
                if (Math.Abs(a) < 1e-9) continue;

                double absA = Math.Abs(a);
                double rounded = Math.Round(absA, 3, MidpointRounding.AwayFromZero);
                if (rounded == 0.0 && absA < 5e-4) continue;

                string num = rounded.ToString("0.000", CultureInfo.InvariantCulture);
                if (num == "1.000" && (i > 0 || j > 0)) num = "";

                string sg;
                if (t.Length == 0)
                    sg = a < 0 ? "-" : "";
                else
                    sg = a < 0 ? @" \allowbreak - " : @" \allowbreak + ";

                t += sg + num + MonomialLatex(i, j);
            }
        }

        return t.Length == 0 ? "0" : t;
    }

    private static string Monomial(int i, int j)
    {
        ReadOnlySpan<string> sup = ["", "", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸"];
        string m = "";
        if (i > 0) m += "x" + sup[i];
        if (j > 0) m += "y" + sup[j];
        return m;
    }

    private static string MonomialLatex(int i, int j)
    {
        string m = "";
        if (i == 1) m += "x";
        else if (i > 1) m += $"x^{{{i}}}";

        if (j == 1) m += "y";
        else if (j > 1) m += $"y^{{{j}}}";
        return m;
    }
}

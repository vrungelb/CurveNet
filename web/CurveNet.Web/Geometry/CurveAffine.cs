namespace CurveNet.Web.Geometry;

// core/cnAffineMatrix.m — аффинные матрицы (поворот, анизотропия, сдвиг, flip)
public static class CurveAffine
{
    public static double MathMod(double a, double m)
    {
        double r = a % m;
        return r < 0 ? r + m : r;
    }

    public static double[,] AffineMatrix(double angleDeg, double anisoX, double anisoY, double shear, bool flip = false)
    {
        double a = angleDeg * Math.PI / 180.0;
        double ca = Math.Cos(a);
        double sa = Math.Sin(a);

        // M = [anisoX, shear*anisoY; 0, anisoY]
        // R = [ca, -sa; sa, ca]
        // A = R * M
        double a00 = ca * anisoX;
        double a01 = ca * (shear * anisoY) - sa * anisoY;
        double a10 = sa * anisoX;
        double a11 = sa * (shear * anisoY) + ca * anisoY;

        if (flip)
        {
            a00 = -a00;
            a01 = -a01;
        }

        return new[,] { { a00, a01 }, { a10, a11 } };
    }
}

namespace CurveNet.Web.Curves;

// Контекст для генерации уравнений кривой
public sealed record CurveEquationContext(
    IReadOnlyDictionary<string, double> Params,
    Point2D X0,
    double K,
    double AngleRad,
    double AnisoX,
    double AnisoY,
    double Shear,
    bool Flip,
    double[,] AffineMatrix,
    double[,] U,
    double[,] V,
    double[,] UU,
    double[,] VV,
    double[,] R2);

// Паттерн Стратегия: поведение конкретного математического семейства кривой
public interface ICurveStrategy
{
    string Key { get; }
    (List<Point2D[]> RawStrokes, CycloidMeta? Meta) GeneratePoints(IReadOnlyDictionary<string, double> prm, int nd);
    (string ExactText, string Latex) BuildEquation(CurveEquationContext ctx);
}

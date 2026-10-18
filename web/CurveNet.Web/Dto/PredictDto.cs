namespace CurveNet.Web.Dto;

public sealed record TopCandidateDto(string Class, string Name, double Probability);

public sealed record PredictRequestDto(
    double[][][] Strokes,
    double CanvasSpan = 20.0,
    string? ForceClass = null);

public sealed class PredictResponseDto
{
    public bool Ok { get; set; }
    public string Message { get; set; } = "";
    public string Warning { get; set; } = "";
    public string Class { get; set; } = "";
    public string Name { get; set; } = "";
    public string DisplayTitle { get; set; } = "";
    public double Confidence { get; set; }
    public bool Reliable { get; set; }
    public List<TopCandidateDto> Top { get; set; } = [];
    public Dictionary<string, double> Params { get; set; } = new();
    public string Equation { get; set; } = "";
    public string EquationLatex { get; set; } = "";
    public double?[][] IdealPoints { get; set; } = [];
    public double? Residual { get; set; }
    public byte[] PreviewPixels { get; set; } = []; // 160*160 построчно
}

public sealed record SaveSampleRequestDto(
    double[][][] Strokes,
    string ClassKey,
    double CanvasSpan = 20.0);

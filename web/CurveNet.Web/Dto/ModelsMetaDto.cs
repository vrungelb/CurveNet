namespace CurveNet.Web.Dto;

public sealed class RegressorMeta
{
    public string[] TargetCols { get; set; } = [];
    public double[] NormMin { get; set; } = [];
    public double[] NormMax { get; set; } = [];
    public bool LogGrowth { get; set; }
    public bool UnitAniso { get; set; }
}

public sealed class ModelsMetaRoot
{
    public string[] ClassifierKeys { get; set; } = [];
    public double[] RoseKValues { get; set; } = [];
    public Dictionary<string, RegressorMeta> Regressors { get; set; } = new(StringComparer.Ordinal);
}

namespace CurveNet.Web.Services;

// Интерфейс запуска нейросетевых моделей
public interface IModelRunner : IDisposable
{
    ModelsMetaRoot Meta { get; }
    bool ModelExists(string modelName);
    float[] Run(string modelName, byte[,] image);
}

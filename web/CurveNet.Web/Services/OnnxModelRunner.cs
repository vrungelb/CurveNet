using System.Collections.Concurrent;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;

namespace CurveNet.Web.Services;

// Запуск ONNX-моделей через ONNX Runtime
public sealed class OnnxModelRunner : IModelRunner
{
    private readonly string _onnxDir;
    private readonly ConcurrentDictionary<string, InferenceSession> _sessions = new(StringComparer.Ordinal);

    public ModelsMetaRoot Meta { get; }

    public OnnxModelRunner(IWebHostEnvironment env)
    {
        string modelsDir = Path.Combine(env.ContentRootPath, "Models");
        _onnxDir = Path.Combine(modelsDir, "onnx");

        string metaPath = Path.Combine(modelsDir, "models_meta.json");
        if (!File.Exists(metaPath))
            throw new FileNotFoundException($"Файл метаданных моделей не найден: {metaPath}");

        string json = File.ReadAllText(metaPath);
        Meta = JsonSerializer.Deserialize<ModelsMetaRoot>(json, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        }) ?? throw new InvalidOperationException("Не удалось прочитать models_meta.json.");
    }

    public bool ModelExists(string modelName) =>
        File.Exists(Path.Combine(_onnxDir, modelName + ".onnx"));

    public float[] Run(string modelName, byte[,] img)
    {
        var session = GetSession(modelName);
        int n = CurveConfig.ImgSize;
        var tensor = new DenseTensor<float>([1, 1, n, n]);

        // В MATLAB свёртки по матрице [row=y, col=x], заполняем NCHW
        for (int y = 0; y < n; y++)
            for (int x = 0; x < n; x++)
                tensor[0, 0, y, x] = img[y, x];

        var inputs = new List<NamedOnnxValue>
        {
            NamedOnnxValue.CreateFromTensor("input", tensor)
        };

        using var results = session.Run(inputs);
        return results.First().AsEnumerable<float>().ToArray();
    }

    private InferenceSession GetSession(string name) =>
        _sessions.GetOrAdd(name, key =>
        {
            string path = Path.Combine(_onnxDir, key + ".onnx");
            if (!File.Exists(path))
                throw new FileNotFoundException($"Не найдена ONNX-модель: {path}");
            return new InferenceSession(path);
        });

    public void Dispose()
    {
        foreach (var s in _sessions.Values)
            s.Dispose();
        _sessions.Clear();
    }
}

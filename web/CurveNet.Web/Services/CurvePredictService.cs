using System.Text.Json;
using Microsoft.AspNetCore.Hosting;

namespace CurveNet.Web.Services;

// predict/cnPredict.m — пайплайн предсказания и координация инференса
public sealed class CurvePredictService
{
    private readonly IModelRunner _runner;
    private readonly string _userTestDir;

    // Ограничение параллельного инференса для защиты CPU
    private static readonly SemaphoreSlim InferenceThrottler = new(Math.Max(2, Environment.ProcessorCount));

    public CurvePredictService(IModelRunner runner, IWebHostEnvironment env)
    {
        _runner = runner;
        _userTestDir = Path.GetFullPath(Path.Combine(env.ContentRootPath, "..", "..", "userTest"));
    }

    public async Task<PredictResponseDto> PredictAsync(PredictRequestDto req, CancellationToken ct = default)
    {
        await InferenceThrottler.WaitAsync(ct);
        try
        {
            return await Task.Run(() => Predict(req), ct);
        }
        finally
        {
            InferenceThrottler.Release();
        }
    }

    // predict/cnPredict.m
    public PredictResponseDto Predict(PredictRequestDto req)
    {
        double span = req.CanvasSpan > 0 && double.IsFinite(req.CanvasSpan) ? req.CanvasSpan : 20.0;
        var prep = CurveInputPipeline.PrepareInput(req.Strokes, span);

        var resp = new PredictResponseDto
        {
            Ok = prep.Ok,
            Message = prep.Message,
            Warning = prep.Warning,
            PreviewPixels = FlattenImage(prep.Img)
        };

        if (!prep.Ok)
            return resp;

        float[] clfScores = _runner.Run("classifier", prep.Img);
        var keys = _runner.Meta.ClassifierKeys;

        for (int i = 0; i < clfScores.Length; i++)
        {
            if (!float.IsFinite(clfScores[i]))
                clfScores[i] = 0f;
        }

        var ord = Enumerable.Range(0, keys.Length)
            .OrderByDescending(i => clfScores[i])
            .ToArray();

        int bestIdx = ord[0];
        string predClass = keys[bestIdx];
        double confidence = Math.Clamp(clfScores[bestIdx], 0.0, 1.0);
        bool reliable = confidence >= CurveConfig.MinConfidence;

        if (!string.IsNullOrWhiteSpace(req.ForceClass))
        {
            int forcedIdx = Array.IndexOf(keys, req.ForceClass);
            if (forcedIdx < 0)
                throw new ArgumentException($"Класса «{req.ForceClass}» нет в классификаторе.");
            predClass = keys[forcedIdx];
            confidence = Math.Clamp(clfScores[forcedIdx], 0.0, 1.0);
            reliable = true;
        }

        var cls = CurveConfig.GetClass(predClass);
        resp.Ok = true;
        resp.Class = predClass;
        resp.Name = cls.Name;
        resp.DisplayTitle = cls.Name;
        resp.Confidence = confidence;
        resp.Reliable = reliable;

        int topN = Math.Min(3, ord.Length);
        for (int i = 0; i < topN; i++)
        {
            int ix = ord[i];
            var cSpec = CurveConfig.GetClass(keys[ix]);
            resp.Top.Add(new TopCandidateDto(keys[ix], cSpec.Name, 100.0 * Math.Clamp(clfScores[ix], 0.0, 1.0)));
        }

        if (!reliable)
            resp.Warning = $"{resp.Warning} Уверенность классификатора ниже порога.".Trim();

        if (cls.IsCurve)
        {
            string regModelName = "regress_" + predClass;
            if (!_runner.Meta.Regressors.TryGetValue(predClass, out var regMeta) || !_runner.ModelExists(regModelName))
            {
                resp.Warning = $"{resp.Warning} Регрессор для «{cls.Name}» не обучен.".Trim();
            }
            else if (cls.KValues is { Length: > 0 } && !_runner.ModelExists("rosek"))
            {
                resp.Warning = $"{resp.Warning} Классификатор числа лепестков не обучен.".Trim();
            }
            else
            {
                try
                {
                    AddIdealCurve(resp, cls, regMeta, prep.Img, prep.Strokes, prep.Tf!);
                }
                catch (Exception ex)
                {
                    resp.Params.Clear();
                    resp.IdealPoints = [];
                    resp.Equation = "";
                    resp.EquationLatex = "";
                    resp.Warning = $"{resp.Warning} Ошибка восстановления кривой: {ex.Message}".Trim();
                }
            }
        }

        return resp;
    }

    private void AddIdealCurve(
        PredictResponseDto resp,
        CurveClassSpec cls,
        RegressorMeta regMeta,
        byte[,] img,
        List<Point2D[]> normStrokes,
        NormalizeTransform tf)
    {
        var initParams = new Dictionary<string, double>(StringComparer.Ordinal);
        if (cls.KValues is { Length: > 0 })
        {
            int kVal = Math.Max(2, (int)Math.Round(PredictRoseK(img)));
            initParams["k"] = kVal;
        }

        float[] predNormF = _runner.Run("regress_" + cls.Key, img);
        double[] predNorm = Array.ConvertAll(predNormF, x => float.IsFinite(x) ? (double)x : 0.0);

        var prm = RegressorDecoder.DecodeTargets(cls, regMeta, predNorm, initParams);
        resp.Params = prm
            .Where(kv => double.IsFinite(kv.Value))
            .ToDictionary(kv => kv.Key, kv => kv.Value, StringComparer.Ordinal);

        if (cls.Key == "rose" && prm.TryGetValue("k", out double rk))
            resp.DisplayTitle = $"{cls.Name} ({PetalWord((int)Math.Round(rk))})";

        var (pRaw, _) = CurvePointsGenerator.CurvePoints(cls.Key, prm, 361);

        double aX = prm.GetValueOrDefault("anisoX", 1.0);
        double aY = prm.GetValueOrDefault("anisoY", 1.0);
        double sh = prm.GetValueOrDefault("shear", 0.0);
        bool flip = prm.TryGetValue("flip", out double fl) && fl > 0.5;
        double angleDeg = prm.GetValueOrDefault("angleDeg", 0.0);

        var A_mat = CurveAffine.AffineMatrix(angleDeg, aX, aY, sh, flip);
        var X0 = tf.ToWorld(new Point2D(prm.GetValueOrDefault("originX", 0.5), prm.GetValueOrDefault("originY", 0.5)));
        double k = Math.Max(1e-6, prm.GetValueOrDefault("normScale", 0.5) * tf.Scale);

        var idealList = new List<Point2D>();
        var idealDto = new List<double?[]>();

        for (int s = 0; s < pRaw.Count; s++)
        {
            if (s > 0)
            {
                idealList.Add(new Point2D(double.NaN, double.NaN));
                idealDto.Add([null, null]);
            }

            foreach (var p in pRaw[s])
            {
                // p_final = (p * A_mat^T) * k + X0
                double fx = (p.X * A_mat[0, 0] + p.Y * A_mat[0, 1]) * k + X0.X;
                double fy = (p.X * A_mat[1, 0] + p.Y * A_mat[1, 1]) * k + X0.Y;
                if (double.IsFinite(fx) && double.IsFinite(fy))
                {
                    idealList.Add(new Point2D(fx, fy));
                    idealDto.Add([fx, fy]);
                }
            }
        }

        resp.IdealPoints = idealDto.ToArray();

        double angRad = angleDeg * Math.PI / 180.0;
        var (exactEq, latexEq) = CurveEquationBuilder.BuildEquations(
            cls.Key, prm, X0, k, angRad, aX, aY, sh, flip, A_mat);
        resp.Equation = exactEq;
        resp.EquationLatex = latexEq;

        double res = CurveResidualCalculator.CalculateResidual(idealList, normStrokes, tf);
        if (double.IsFinite(res))
            resp.Residual = res;
    }

    private double PredictRoseK(byte[,] img)
    {
        float[] scores = _runner.Run("rosek", img);
        int best = 0;
        for (int i = 1; i < scores.Length; i++)
            if (scores[i] > scores[best]) best = i;
        return _runner.Meta.RoseKValues[best];
    }

    private static readonly object SaveLock = new();
    private const int MaxSamplesPerClass = 500;

    public (string FileName, int TotalInClass) SaveSample(SaveSampleRequestDto req)
    {
        var cls = CurveConfig.GetClass(req.ClassKey);
        string dir = Path.Combine(_userTestDir, cls.Key);

        lock (SaveLock)
        {
            Directory.CreateDirectory(dir);

            int total = Directory.GetFiles(dir, "sample_*.*").Length;
            if (total >= MaxSamplesPerClass)
                throw new InvalidOperationException($"Достигнут лимит ({MaxSamplesPerClass}) сохранённых образцов для «{cls.Name}».");

            string stamp = DateTime.Now.ToString("yyyyMMdd_HHmmss_fff");
            string fileName = $"sample_{stamp}.json";
            string fullPath = Path.Combine(dir, fileName);
            if (File.Exists(fullPath))
            {
                fileName = $"sample_{stamp}_{Guid.NewGuid().ToString("N")[..4]}.json";
                fullPath = Path.Combine(dir, fileName);
            }

            double span = req.CanvasSpan > 0 && double.IsFinite(req.CanvasSpan) ? req.CanvasSpan : 20.0;
            var payload = new
            {
                strokes = req.Strokes,
                @class = cls.Key,
                canvasSpan = span,
                limits = new[] { -span / 2.0, span / 2.0 },
                savedAt = DateTime.Now
            };

            File.WriteAllText(fullPath, JsonSerializer.Serialize(payload, new JsonSerializerOptions
            {
                WriteIndented = true
            }));

            return (fileName, total + 1);
        }
    }

    private static byte[] FlattenImage(byte[,] img)
    {
        int h = img.GetLength(0);
        int w = img.GetLength(1);
        if (h == 0 || w == 0) return [];
        var flat = new byte[h * w];
        int k = 0;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                flat[k++] = img[y, x];
        return flat;
    }

    private static string PetalWord(int k)
    {
        int rem10 = k % 10;
        int rem100 = k % 100;
        if (rem100 is >= 11 and <= 14)
            return $"{k} лепестков";
        if (rem10 == 1)
            return $"{k} лепесток";
        if (rem10 is >= 2 and <= 4)
            return $"{k} лепестка";
        return $"{k} лепестков";
    }
}

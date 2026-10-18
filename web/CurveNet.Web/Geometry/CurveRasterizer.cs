using System.Buffers;

namespace CurveNet.Web.Geometry;

// core/cnNormalize.m и core/cnRasterize.m
public static class CurveRasterizer
{
    // core/cnNormalize.m — упаковка в [0, 1] с отступами ImgPad
    public static (List<Point2D[]> NormalizedStrokes, NormalizeTransform Tf) Normalize(IReadOnlyList<Point2D[]> strokes)
    {
        double minX = double.PositiveInfinity, minY = double.PositiveInfinity;
        double maxX = double.NegativeInfinity, maxY = double.NegativeInfinity;
        int count = 0;

        foreach (var s in strokes)
        {
            foreach (var p in s)
            {
                if (!p.IsFinite) continue;
                if (p.X < minX) minX = p.X;
                if (p.Y < minY) minY = p.Y;
                if (p.X > maxX) maxX = p.X;
                if (p.Y > maxY) maxY = p.Y;
                count++;
            }
        }

        if (count < 2)
            throw new InvalidOperationException("Для нормализации нужно хотя бы две конечные точки.");

        var c0 = new Point2D((minX + maxX) / 2.0, (minY + maxY) / 2.0);
        double ext = Math.Max(maxX - minX, maxY - minY);
        if (!double.IsFinite(ext) || ext <= 0.0)
            throw new InvalidOperationException("Габаритная рамка вырождена: фигура схлопнулась в точку.");

        double fill = 1.0 - 2.0 * CurveConfig.ImgPad;
        double scale = ext / fill;

        var tf = new NormalizeTransform
        {
            Center = c0,
            Extent = ext,
            Pad = CurveConfig.ImgPad,
            Scale = scale,
            Offset = new Point2D(0.0, 0.0),
            BoxMin = new Point2D(minX, minY),
            BoxMax = new Point2D(maxX, maxY)
        };

        var q = new List<Point2D[]>(strokes.Count);
        foreach (var s in strokes)
        {
            var ns = new Point2D[s.Length];
            for (int i = 0; i < s.Length; i++)
                ns[i] = tf.ToNorm(s[i]);
            q.Add(ns);
        }

        return (q, tf);
    }

    // core/cnRasterize.m — матрица 160x160 (uint8) с пулингом памяти и Span<T>
    public static byte[,] Rasterize(
        IReadOnlyList<Point2D[]> strokes,
        double lineWidth = CurveConfig.DefaultLineWidth,
        double softenSigma = CurveConfig.DefaultSoftenSigma)
    {
        const int N = CurveConfig.ImgSize;
        const int totalPixels = N * N;

        // Пул буферов для устранения аллокаций в куче (Zero-GC)
        bool[] maskBuffer = ArrayPool<bool>.Shared.Rent(totalPixels);
        float[] distBuffer = ArrayPool<float>.Shared.Rent(totalPixels);
        float[] imgBuffer = ArrayPool<float>.Shared.Rent(totalPixels);

        try
        {
            Array.Clear(maskBuffer, 0, totalPixels);
            bool drawn = false;

            foreach (var raw in strokes)
            {
                var p = raw.Where(pt => pt.IsFinite).ToArray();
                if (p.Length < 2) continue;

                var pix = new Point2D[p.Length];
                double len = 0.0;
                for (int i = 0; i < p.Length; i++)
                {
                    // В MATLAB: cx = p(:,1)*(N-1) + 1; cy = (1 - p(:,2))*(N-1) + 1 (1-based)
                    double cx = p[i].X * (N - 1) + 1.0;
                    double cy = (1.0 - p[i].Y) * (N - 1) + 1.0;
                    pix[i] = new Point2D(cx, cy);
                    if (i > 0)
                    {
                        double dx = cx - pix[i - 1].X;
                        double dy = cy - pix[i - 1].Y;
                        len += Math.Sqrt(dx * dx + dy * dy);
                    }
                }

                int nd = Math.Max(2, (int)Math.Ceiling(len / CurveConfig.SplatStep));
                var d = CurveResampling.ResampleOne(pix, nd, "linear");

                foreach (var pt in d)
                {
                    int xi = (int)Math.Round(pt.X, MidpointRounding.AwayFromZero) - 1;
                    int yi = (int)Math.Round(pt.Y, MidpointRounding.AwayFromZero) - 1;
                    if (xi >= 0 && xi < N && yi >= 0 && yi < N)
                    {
                        maskBuffer[yi * N + xi] = true;
                        drawn = true;
                    }
                }
            }

            if (!drawn)
                return new byte[N, N];

            // 2D Distance Transform с использованием Span<T>
            ComputeEuclideanDistanceTransform(maskBuffer, distBuffer, N);

            float halfLw = (float)(lineWidth / 2.0 + 0.5);
            for (int i = 0; i < totalPixels; i++)
                imgBuffer[i] = Math.Clamp(halfLw - distBuffer[i], 0f, 1f);

            // Разделяемое гауссово сглаживание
            if (softenSigma > 0.0)
            {
                ApplySeparableBlur(imgBuffer, N, softenSigma);
            }

            // Формирование итоговой матрицы байт
            var outBytes = new byte[N, N];
            for (int y = 0; y < N; y++)
            {
                int rowOffset = y * N;
                for (int x = 0; x < N; x++)
                {
                    float v = CurveConfig.LineOnBlack ? imgBuffer[rowOffset + x] : 1f - imgBuffer[rowOffset + x];
                    outBytes[y, x] = (byte)Math.Round(255f * Math.Clamp(v, 0f, 1f), MidpointRounding.AwayFromZero);
                }
            }
            return outBytes;
        }
        finally
        {
            ArrayPool<bool>.Shared.Return(maskBuffer);
            ArrayPool<float>.Shared.Return(distBuffer);
            ArrayPool<float>.Shared.Return(imgBuffer);
        }
    }

    // Точный 2D Euclidean Distance Transform (алгоритм Felzenszwalb & Huttenlocher)
    private static void ComputeEuclideanDistanceTransform(ReadOnlySpan<bool> mask, Span<float> dist, int n)
    {
        const double inf = 1e12;
        int total = n * n;

        double[] f = ArrayPool<double>.Shared.Rent(total);
        double[] d1 = ArrayPool<double>.Shared.Rent(total);

        try
        {
            for (int i = 0; i < total; i++)
                f[i] = mask[i] ? 0.0 : inf;

            // Буферы на стеке (160 элементов ~ 1.2 KB L1-кэша, 0 аллокаций)
            Span<int> v = stackalloc int[n];
            Span<double> z = stackalloc double[n + 1];
            Span<double> line = stackalloc double[n];
            Span<double> res = stackalloc double[n];

            // Проход по столбцам (вдоль Y)
            for (int x = 0; x < n; x++)
            {
                for (int y = 0; y < n; y++)
                    line[y] = f[y * n + x];

                Edt1D(line, res, v, z, n);

                for (int y = 0; y < n; y++)
                    d1[y * n + x] = res[y];
            }

            // Проход по строкам (вдоль X)
            for (int y = 0; y < n; y++)
            {
                int rowOffset = y * n;
                ReadOnlySpan<double> rowSlice = d1.AsSpan(rowOffset, n);

                Edt1D(rowSlice, res, v, z, n);

                for (int x = 0; x < n; x++)
                    dist[rowOffset + x] = (float)Math.Sqrt(res[x]);
            }
        }
        finally
        {
            ArrayPool<double>.Shared.Return(f);
            ArrayPool<double>.Shared.Return(d1);
        }
    }

    private static void Edt1D(ReadOnlySpan<double> f, Span<double> d, Span<int> v, Span<double> z, int n)
    {
        int k = 0;
        v[0] = 0;
        z[0] = double.NegativeInfinity;
        z[1] = double.PositiveInfinity;

        for (int q = 1; q < n; q++)
        {
            double s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.0 * q - 2.0 * v[k]);
            while (s <= z[k])
            {
                k--;
                s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.0 * q - 2.0 * v[k]);
            }
            k++;
            v[k] = q;
            z[k] = s;
            z[k + 1] = double.PositiveInfinity;
        }

        k = 0;
        for (int q = 0; q < n; q++)
        {
            while (z[k + 1] < q) k++;
            double dx = q - v[k];
            d[q] = dx * dx + f[v[k]];
        }
    }

    private static void ApplySeparableBlur(Span<float> img, int n, double sigma)
    {
        int r = Math.Max(1, (int)Math.Ceiling(3.0 * sigma));
        int kLen = 2 * r + 1;

        // Ядро фильтра на стеке
        Span<float> k = stackalloc float[kLen];
        double sum = 0.0;
        for (int i = -r; i <= r; i++)
        {
            double w = Math.Exp(-(i * i) / (2.0 * sigma * sigma));
            k[i + r] = (float)w;
            sum += w;
        }
        for (int i = 0; i < kLen; i++)
            k[i] = (float)(k[i] / sum);

        int total = n * n;
        float[] tmp = ArrayPool<float>.Shared.Rent(total);
        float[] dst = ArrayPool<float>.Shared.Rent(total);

        try
        {
            // Горизонтальная свёртка
            for (int y = 0; y < n; y++)
            {
                int rowOffset = y * n;
                for (int x = 0; x < n; x++)
                {
                    float acc = 0f;
                    int jMin = Math.Max(-r, -x);
                    int jMax = Math.Min(r, n - 1 - x);
                    for (int j = jMin; j <= jMax; j++)
                    {
                        acc += img[rowOffset + x + j] * k[j + r];
                    }
                    tmp[rowOffset + x] = acc;
                }
            }

            // Вертикальная свёртка
            for (int x = 0; x < n; x++)
            {
                for (int y = 0; y < n; y++)
                {
                    float acc = 0f;
                    int jMin = Math.Max(-r, -y);
                    int jMax = Math.Min(r, n - 1 - y);
                    for (int j = jMin; j <= jMax; j++)
                    {
                        acc += tmp[(y + j) * n + x] * k[j + r];
                    }
                    dst[y * n + x] = acc;
                }
            }

            // Нормализация по максимальному значению
            float maxVal = 0f;
            for (int i = 0; i < total; i++)
                if (dst[i] > maxVal) maxVal = dst[i];

            if (maxVal > 0f)
            {
                float inv = 1f / maxVal;
                for (int i = 0; i < total; i++)
                    img[i] = dst[i] * inv;
            }
            else
            {
                dst.AsSpan(0, total).CopyTo(img);
            }
        }
        finally
        {
            ArrayPool<float>.Shared.Return(tmp);
            ArrayPool<float>.Shared.Return(dst);
        }
    }
}

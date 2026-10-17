%CNPREVIEWREGRESSORS  Проверка регрессора: красный рисунок, зелёная идеальная кривая.
function cnPreviewRegressors(className, n, opts)

arguments
    className (1,1) string = "ellipse"
    n         (1,1) double {mustBeInteger, mustBePositive} = 16
    opts.seed   = []
    opts.force  (1,1) logical = false
end

c = cnClasses(className);
if ~c.isCurve
    error("cnPreviewRegressors:notACurve", "Класс «%s» не кривая.", className);
end

if isempty(opts.seed)
    seed = randi([1 2^31-2]);
else
    seed = double(opts.seed);
end

T  = cnSampleParams(className, n, seed);
rs = RandStream("threefry", Seed = seed + 17);

SPAN = 20;
HALF = SPAN / 2;

f = figure(Name = "Тест регрессора: " + className, Color = "w");
f.Position = [100, 100, 950, 950];
t = tiledlayout('flow', TileSpacing = 'compact', Padding = 'tight');

errs = nan(n, 1);

for i = 1:n
    rec = table2struct(T(i,:));

    [~, strokes] = cnRender(className, rec, false);

    allPts = vertcat(strokes{:});
    c0  = (max(allPts, [], 1) + min(allPts, [], 1)) / 2;
    ext = max(max(allPts, [], 1) - min(allPts, [], 1));
    if ext <= 0; ext = 1; end

    targetSize = SPAN * (0.55 + 0.20 * rand(rs));
    scale = targetSize / ext;

    maxShift = (SPAN - targetSize) / 2 * 0.7;
    shift = (rand(rs, 1, 2) - 0.5) * 2 * maxShift;

    rawStrokes = cell(size(strokes));
    for k = 1:numel(strokes)
        rawStrokes{k} = (strokes{k} - c0) * scale + shift;
    end

    args = {};
    if opts.force
        args = {"forceClass", className};
    end
    R = cnPredict(rawStrokes, SPAN, args{:});

    ax = nexttile(t);
    hold(ax, "on");

    for k = 1:numel(rawStrokes)
        p = rawStrokes{k};
        plot(ax, p(:,1), p(:,2), "-", Color = [0.85 0.10 0.10], LineWidth = 1.4);
    end

    if isfield(R, 'idealPoints') && ~isempty(R.idealPoints)
        plot(ax, R.idealPoints(:,1), R.idealPoints(:,2), "-", Color = [0.15 0.70 0.25], LineWidth = 2.0);
    end

    ax.XLim = [-HALF HALF];
    ax.YLim = [-HALF HALF];
    ax.XTick = [];
    ax.YTick = [];
    ax.DataAspectRatio = [1 1 1];
    box(ax, "on");

    ttl = sprintf("%s (%.0f%%)", R.class, R.confidence * 100);
    if isfield(R, 'fit') && isfinite(R.fit.residual)
        errs(i) = R.fit.residual;
        ttl = ttl + sprintf("  невязка %.1f%%", 100 * R.fit.residual);
    end
    ttlColor = [0.2 0.2 0.2];
    if R.class ~= className
        ttlColor = [0.8 0.1 0.1];
    end
    title(ax, ttl, FontSize = 8.5, Color = ttlColor);
end

if any(isfinite(errs))
    fprintf("%s: медианная невязка %.2f%%, худшая %.2f%% (seed %d)\n", ...
        className, 100*median(errs, "omitnan"), 100*max(errs), seed);
end
end

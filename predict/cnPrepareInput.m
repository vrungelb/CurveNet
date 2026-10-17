%CNPREPAREINPUT  Приведение рисунка пользователя к виду обучающих данных.
function [img, info] = cnPrepareInput(strokes, canvasSpan)

arguments
    strokes    cell
    canvasSpan (1,1) double {mustBePositive}
end

cfg = cnConfig();

info = struct( ...
    "ok", false, "message", "", "warning", "", ...
    "strokes", {{}}, "tf", [], ...
    "nStrokes", 0, "nDropped", 0, "boxFrac", 0, "touchesEdge", false);
img = uint8.empty(0,0);

raw = strokes(:);
keep = false(numel(raw),1);
len  = zeros(numel(raw),1);

for i = 1:numel(raw)
    p = raw{i};
    if ~isnumeric(p) || size(p,2) ~= 2
        continue
    end
    p = double(p);
    p = p(all(isfinite(p), 2), :);
    raw{i} = p;

    if size(p,1) < cfg.input.minStrokePoints
        continue
    end
    len(i) = sum(hypot(diff(p(:,1)), diff(p(:,2))));
    keep(i) = len(i) >= cfg.input.minStrokeFrac * canvasSpan;
end

info.nDropped = sum(~keep);
raw = raw(keep);

if isempty(raw)
    info.message = "Ничего не нарисовано.";
    return
end
info.nStrokes = numel(raw);

pts = vertcat(raw{:});
if size(pts,1) < cfg.input.minPoints
    info.message = "Слишком мало точек.";
    return
end

lo  = min(pts, [], 1);
hi  = max(pts, [], 1);
ext = max(hi - lo);
info.boxFrac = ext / canvasSpan;

if info.boxFrac < cfg.input.minBoxFrac
    info.message = "Рисунок слишком мелкий.";
    return
end

half = canvasSpan/2;
tol  = cfg.input.edgeTol * canvasSpan;
if any(abs(pts(:)) > half - tol)
    info.touchesEdge = true;
    info.warning = "Рисунок упирается в край.";
end

nPts = round(mean(cfg.curve.nPoints));
q = cnResampleArc(raw, nPts);

[q, tf] = cnNormalize(q);

lw = mean(cfg.img.lineWidth);
sg = mean(cfg.img.softenSigma);
img = cnRasterize(q, lw, sg);

info.ok      = true;
info.strokes = q;
info.tf      = tf;
end

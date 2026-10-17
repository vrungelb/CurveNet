%CNNORMALIZE  Вписывание штрихов в единый кадр с сохранением пропорций.
function [q, tf] = cnNormalize(strokes, jitter)

arguments
    strokes cell
    jitter        = []
end

if isempty(strokes)
    error("cnNormalize:noStrokes", "Список штрихов пуст.");
end

cfg = cnConfig();

pts = vertcat(strokes{:});
pts = pts(all(isfinite(pts), 2), :);
if size(pts,1) < 2
    error("cnNormalize:tooFewPoints", ...
        "Для нормализации нужно хотя бы две конечные точки.");
end

lo = min(pts, [], 1);
hi = max(pts, [], 1);
c0 = (lo + hi) / 2;

ext = max(hi - lo);
if ~isfinite(ext) || ext <= 0
    error("cnNormalize:degenerate", ...
        "Габаритная рамка вырождена: фигура схлопнулась в точку.");
end

fill  = 1 - 2*cfg.img.pad;
scale = ext / fill;

q = strokes(:);
for i = 1:numel(q)
    q{i} = (q{i} - c0) / scale + 0.5;
end

sj = 1;
off = [0 0];
if ~isempty(jitter)
    if isfield(jitter, "scaleJit"); sj = jitter.scaleJit; end
    if isfield(jitter, "offX") && isfield(jitter, "offY")
        off = [jitter.offX, jitter.offY];
    end
    for i = 1:numel(q)
        q{i} = (q{i} - 0.5) * sj + 0.5 + off;
    end
end

tf = struct( ...
    "center",   c0, ...
    "extent",   ext, ...
    "pad",      cfg.img.pad, ...
    "scale",    scale / sj, ...
    "offset",   off, ...
    "boxMin",   lo, ...
    "boxMax",   hi);
end

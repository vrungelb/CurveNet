%CNHANDDISTORT  Имитация рисования от руки (аугментация).
function [out, pOrig] = cnHandDistort(strokes, rec, closed)

arguments
    strokes cell
    rec     (1,1) struct
    closed  (1,1) logical = false
end

need = ["angleDeg","anisoX","anisoY","shear","warpAmp","tremorAmp","seed"];
missing = need(~isfield(rec, need));
if ~isempty(missing)
    error("cnHandDistort:missingFields", "В рецепте нет полей: %s.", join(missing, ", "));
end
if isempty(strokes)
    error("cnHandDistort:noStrokes", "Список штрихов пуст.");
end

cfg = cnConfig();
rs  = RandStream("threefry", Seed = rec.seed);

pts = vertcat(strokes{:});
c0  = (max(pts,[],1) + min(pts,[],1)) / 2;
for i = 1:numel(strokes)
    strokes{i} = strokes{i} - c0;
end

flip = isfield(rec, 'flip') && rec.flip;
A = cnAffineMatrix(rec.angleDeg, rec.anisoX, rec.anisoY, rec.shear, flip);

for i = 1:numel(strokes)
    strokes{i} = strokes{i} * A.';
end

pts = vertcat(strokes{:});
ext = max(pts,[],1) - min(pts,[],1);
S   = max(min(ext), 0.25*max(ext));
if S <= 0 || ~isfinite(S)
    error("cnHandDistort:degenerate", "Фигура вырождена: нулевой габарит.");
end

cAff = (max(pts,[],1) + min(pts,[],1)) / 2;
for i = 1:numel(strokes)
    strokes{i} = strokes{i} - cAff;
end

pOrig = -c0 * A.' - cAff;

radAmp = 0;
if isfield(rec, "radialAmp")
    radAmp = rec.radialAmp;
end

multi = numel(strokes) > 1;
if multi
    nMax = max(cellfun(@(p) size(p,1), strokes));
    swS  = max(1, nMax / cfg.aug.warpScale);
    sharedX = smoothNoise(rs, nMax, swS, false);
    sharedY = smoothNoise(rs, nMax, swS, false);
    uShared = linspace(0, 1, nMax).';
end
w = cfg.aug.warpShare;

out = strokes;
for i = 1:numel(strokes)
    p = strokes{i};
    n = size(p,1);
    if n < 4
        continue;
    end

    wrap = closed && ~multi;
    sw   = max(1, n / cfg.aug.warpScale);

    wx = smoothNoise(rs, n, sw, wrap);
    wy = smoothNoise(rs, n, sw, wrap);

    if multi
        u  = linspace(0, 1, n).';
        wx = w*interp1(uShared, sharedX, u) + sqrt(1-w^2)*wx;
        wy = w*interp1(uShared, sharedY, u) + sqrt(1-w^2)*wy;
    end

    p = p + rec.warpAmp * S * [wx, wy];

    p = p + rec.tremorAmp * S * ...
        [smoothNoise(rs, n, cfg.aug.tremorSigma, wrap), ...
         smoothNoise(rs, n, cfg.aug.tremorSigma, wrap)];

    if radAmp > 0
        p = p .* (1 + radAmp * smoothNoise(rs, n, sw, wrap));
    end

    out{i} = p;
end
end

function v = smoothNoise(rs, n, sigma, wrap)

sigma = max(sigma, 0.5);
pad   = min(n-1, ceil(3*sigma));

x = randn(rs, n, 1);

k = exp(-(-pad:pad).^2 / (2*sigma^2)).';
k = k / sum(k);

idx = (1:n).' + (-pad:pad);
if wrap
    idx = mod(idx - 1, n) + 1;
else
    idx = min(max(idx, 1), n);
end

v = x(idx) * k;

s = std(v);
if s > 0
    v = v / s;
end
end

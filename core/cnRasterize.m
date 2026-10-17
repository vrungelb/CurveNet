%CNRASTERIZE  Отрисовка штрихов в изображение 160x160.
function img = cnRasterize(strokes, lineWidth, softenSigma)

arguments
    strokes     cell
    lineWidth   (1,1) double {mustBePositive} = 2.2
    softenSigma (1,1) double {mustBeNonnegative} = 0.6
end

cfg = cnConfig();
N   = cfg.img.size;

img = zeros(N, N, "single");
if isempty(strokes)
    img = toUint8(img, cfg);
    return
end

mask = false(N, N);
drawn = false;

for i = 1:numel(strokes)
    p = strokes{i};
    p = p(all(isfinite(p), 2), :);
    if size(p,1) < 2
        continue
    end

    cx = p(:,1) * (N-1) + 1;
    cy = (1 - p(:,2)) * (N-1) + 1;

    L  = sum(hypot(diff(cx), diff(cy)));
    nd = max(2, ceil(L / cfg.img.splatStep));
    d  = cnResampleArc([cx, cy], nd, "linear");

    xi = round(d(:,1));
    yi = round(d(:,2));
    ok = xi >= 1 & xi <= N & yi >= 1 & yi <= N;
    if ~any(ok)
        continue
    end

    mask(sub2ind([N N], yi(ok), xi(ok))) = true;
    drawn = true;
end

if ~drawn
    img = toUint8(img, cfg);
    return
end

D = single(bwdist(mask));

img = min(1, max(0, lineWidth/2 - D + 0.5));

if softenSigma > 0
    img = blurSeparable(img, softenSigma);
    m = max(img(:));
    if m > 0
        img = img / m;
    end
end

img = toUint8(img, cfg);
end

function img = blurSeparable(img, sigma)

r = max(1, ceil(3*sigma));
k = exp(-(-r:r).^2 / (2*sigma^2));
k = single(k / sum(k));

img = conv2(k.', k, img, "same");
end

function img = toUint8(img, cfg)

if ~cfg.img.lineOnBlack
    img = 1 - img;
end
img = uint8(round(255 * min(1, max(0, img))));
end

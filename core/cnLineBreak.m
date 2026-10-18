%CNLINEBREAK  Незамыкание контура и отрывы пера.
function out = cnLineBreak(strokes, rec, closed)

arguments
    strokes cell
    rec     (1,1) struct
    closed  (1,1) logical = false
end

need = ["openGap","nBreaks","seed"];
missing = need(~isfield(rec, need));
if ~isempty(missing)
    error("cnLineBreak:missingFields", ...
        "В рецепте нет полей: %s.", join(missing, ", "));
end

cfg = cnConfig();

rs = RandStream("threefry", Seed = mod(rec.seed + 7919, 2^31-1));

strokes = strokes(:);

if closed
    for i = 1:numel(strokes)
        strokes{i} = openContour(rs, strokes{i}, rec.openGap);
    end
end

out = applyBreaks(rs, strokes, round(rec.nBreaks), cfg);

if isempty(out)

    out = strokes;
end
end

function p = openContour(rs, p, gap)

n = size(p,1);
if n < 8
    return
end

seg = mean(hypot(diff(p(:,1)), diff(p(:,2))));
if hypot(p(end,1)-p(1,1), p(end,2)-p(1,2)) < 0.5*seg
    p(end,:) = [];
    n = n - 1;
end

p = circshift(p, randi(rs, [0 n-1]), 1);

if gap > 0
    cut = min(max(1, round(gap*n)), n-4);
    p(end-cut+1:end, :) = [];
else

    p(end+1,:) = p(1,:);
end
end

function out = applyBreaks(rs, strokes, nBreaks, cfg)

m = numel(strokes);
keep = cell(m,1);
len  = zeros(m,1);
for i = 1:m
    len(i)  = size(strokes{i}, 1);
    keep{i} = true(len(i), 1);
end

for b = 1:nBreaks

    i = pickWeighted(rs, len);
    n = len(i);

    margin = max(2, round(cfg.aug.breakMargin * n));
    L = max(2, round(uni(rs, cfg.aug.breakLen) * n));

    lo = margin + 1;
    hi = n - margin - L;
    if hi < lo
        continue
    end
    s = randi(rs, [lo hi]);
    keep{i}(s : s+L-1) = false;
end

out = {};
for i = 1:m
    minFrag = max(4, round(cfg.aug.minFragment * len(i)));
    seg = runsOfTrue(keep{i});
    for j = 1:size(seg,1)
        a = seg(j,1);
        b = seg(j,2);
        if b - a + 1 >= minFrag
            out{end+1,1} = strokes{i}(a:b, :);
        end
    end
end
end

function seg = runsOfTrue(mask)

d = diff([0; double(mask(:)); 0]);
seg = [find(d == 1), find(d == -1) - 1];
end

function i = pickWeighted(rs, w)

c = cumsum(w(:));
if c(end) <= 0
    i = 1;
    return
end
i = find(rand(rs) * c(end) <= c, 1);
end

function v = uni(rs, range)

v = range(1) + (range(2) - range(1)) * rand(rs);
end

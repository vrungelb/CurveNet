%CNRESAMPLEARC  Пересчёт точек кривой равномерно по длине дуги.
function [out, L] = cnResampleArc(pts, n, method)

arguments
    pts
    n      (1,1) double {mustBeInteger, mustBePositive}
    method (1,1) string = "pchip"
end

if iscell(pts)
    [out, L] = resampleMany(pts, n, method);
else
    [out, L] = resampleOne(pts, n, method);
end
end

function [q, L] = resampleOne(p, n, method)

p = validateStroke(p);
[p, s, L] = arcLength(p);

if size(p,1) < 2

    q = repmat(p(1,:), n, 1);
    return
end

st = linspace(0, L, n).';
q  = [interp1(s, p(:,1), st, method), ...
      interp1(s, p(:,2), st, method)];
end

function [q, L] = resampleMany(c, n, method)

c = c(:);
m = numel(c);
if m == 0
    error("cnResampleArc:noStrokes", "Список штрихов пуст.");
end

len = zeros(m,1);
for i = 1:m
    c{i} = validateStroke(c{i});
    [~, ~, len(i)] = arcLength(c{i});
end
L = sum(len);

if L > 0
    cnt = max(2, round(n * len / L));
else
    cnt = repmat(max(2, floor(n/m)), m, 1);
end

d = n - sum(cnt);
if d > 0
    [~, big] = max(len);
    cnt(big) = cnt(big) + d;
elseif d < 0
    [~, ord] = sort(len, "descend");
    for i = ord(:).'
        take   = min(cnt(i) - 2, -d);
        cnt(i) = cnt(i) - take;
        d      = d + take;
        if d == 0; break; end
    end
end

q = cell(m,1);
for i = 1:m
    q{i} = resampleOne(c{i}, cnt(i), method);
end
end

function p = validateStroke(p)

if ~isnumeric(p) || ~ismatrix(p) || size(p,2) ~= 2
    error("cnResampleArc:badShape", ...
        "Штрих должен быть числовой матрицей размера M x 2.");
end
p = double(p);

p = p(all(isfinite(p), 2), :);

if isempty(p)
    error("cnResampleArc:emptyStroke", ...
        "После удаления NaN в штрихе не осталось точек.");
end
end

function [p, s, L] = arcLength(p)

d = [0; hypot(diff(p(:,1)), diff(p(:,2)))];
s = cumsum(d);

keep = [true; diff(s) > 0];
p = p(keep, :);
s = s(keep);

L = s(end);
end

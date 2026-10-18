%CNCURVERESIDUAL Расчет двусторонней среднеквадратичной невязки между штрихами и идеальной кривой.
function e = cnCurveResidual(idealPoints, info)

arguments
    idealPoints double
    info        struct
end

e = NaN;
if isempty(idealPoints) || ~isfield(info, "tf") || isempty(info.tf) ...
        || ~isfield(info, "strokes") || isempty(info.strokes)
    return
end

tf = info.tf;
nStrokes = numel(info.strokes);
chunks = cell(2 * nStrokes - 1, 1);
for i = 1:nStrokes
    chunks{2*i - 1} = tf.toWorld(info.strokes{i});
    if i < nStrokes
        chunks{2*i} = [NaN, NaN];
    end
end
U = vertcat(chunks{:});

Ufin = U(all(isfinite(U), 2), :);
if size(Ufin, 1) < 2
    return
end

dU2C = pointsToCurveRMS(Ufin, idealPoints);
dC2U = pointsToCurveRMS(idealPoints, U);
if ~isfinite(dU2C) || ~isfinite(dC2U)
    return
end
dSym = hypot(dU2C, dC2U) / sqrt(2);

U0 = Ufin - mean(Ufin, 1);
[V, ~] = eig(U0.' * U0);
Urot = U0 * V;
span = max(Urot, [], 1) - min(Urot, [], 1);

maxSpan = max([span, tf.extent]);
if ~isfinite(maxSpan) || maxSpan <= 0
    return
end
span  = max(span, 0.05 * maxSpan);
scale = sqrt(prod(span));

e = dSym / scale;
end


function e = pointsToCurveRMS(P, C)

e = NaN;
P = P(all(isfinite(P), 2), :);
A = C(1:end-1, :);
B = C(2:end, :);
ok = all(isfinite(A), 2) & all(isfinite(B), 2);
A = A(ok, :);
B = B(ok, :);
if isempty(A) || isempty(P)
    return
end

AB = B - A;
L2 = max(sum(AB.^2, 2), eps);

t = ((P(:,1) - A(:,1).') .* AB(:,1).' + (P(:,2) - A(:,2).') .* AB(:,2).') ./ L2.';
t = min(max(t, 0), 1);
dx = P(:,1) - (A(:,1).' + t .* AB(:,1).');
dy = P(:,2) - (A(:,2).' + t .* AB(:,2).');

e = sqrt(mean(min(dx.^2 + dy.^2, [], 2)));
end
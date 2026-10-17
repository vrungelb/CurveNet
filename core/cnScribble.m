%CNSCRIBBLE Генератор «каракуль» для мусорного класса.
function strokes = cnScribble(rec, n)

arguments
    rec (1,1) struct
    n (1,1) double {mustBeInteger, mustBePositive} = 256
end

if ~isfield(rec, "seed")
    error("cnScribble:missingSeed", "В рецепте нет поля seed.");
end

sub = "fourier";
if isfield(rec, "subtype")
    sub = string(rec.subtype);
end

rs = RandStream("threefry", Seed = mod(rec.seed + 104729, 2^31-1));

nd = max(2000, 8*n);

switch sub
    case "fourier";  raw = fourierBlob(rs, nd);
    case "polyline"; raw = polyLine(rs);
    case "shape";    raw = simpleShape(rs);
    case "walk";     raw = randomWalk(rs, nd);
    otherwise
        error("cnScribble:badSubtype", "Неизвестный вид каракули: «%s».", sub);
end

strokes = cnResampleArc({raw}, n);
end

function p = fourierBlob(rs, nd)

for attempt = 1:20
    ks = pickDistinct(rs, 2:7, randi(rs, [3 4]));
    a = 0.10 + 0.20*rand(rs, numel(ks), 1);
    ph = 2*pi*rand(rs, numel(ks), 1);

    if max(a)/sum(a) <= 0.60 || attempt == 20
        break
    end
end

t = linspace(0, 2*pi, nd).';
r = ones(nd,1);
for i = 1:numel(ks)
    r = r + a(i)*cos(ks(i)*t + ph(i));
end
r = max(r, 0.15);

p = [r.*cos(t), r.*sin(t)];
end

function p = polyLine(rs)

m = randi(rs, [5 8]);

v = zeros(0,2);
guard = 0;
while size(v,1) < m && guard < 500
    guard = guard + 1;
    q = 2*rand(rs, 1, 2) - 1;

    if isempty(v) || min(hypot(v(:,1)-q(1), v(:,2)-q(2))) > 0.25
        v(end+1,:) = q;
    end
end

if size(v,1) < 3
    v = [-1 -1; 1 -0.2; -0.6 0.9];
end

v = v ./ max(max(abs(v)));
p = traceSegments(v, 80);
end

function p = simpleShape(rs)

kinds = ["square","triangle","house","cross","arrow","zigzag"];
k = kinds(randi(rs, [1 numel(kinds)]));

switch k
    case "square"
        v = [-1 -1; 1 -1; 1 1; -1 1; -1 -1];
    case "triangle"
        v = [-1 -0.8; 1 -0.8; 0 1; -1 -0.8];
    case "house"
        v = [-1 -1; 1 -1; 1 0.3; 0 1.1; -1 0.3; -1 -1];
    case "cross"
        v = [-1 1; 1 -1; 0 0; -1 -1; 1 1];
    case "arrow"
        v = [-1 0; 1 0; 0.4 0.5; 1 0; 0.4 -0.5];
    case "zigzag"
        m = randi(rs, [4 7]);
        x = linspace(-1, 1, m).';
        y = repmat([-0.7; 0.7], ceil(m/2), 1);
        v = [x, y(1:m)];
end

p = traceSegments(v, 60);
end

function p = traceSegments(v, nPerSeg)

p = zeros(0,2);
for i = 1:size(v,1)-1
    s = linspace(0, 1, nPerSeg).';
    if i > 1
        s(1) = [];
    end
    p = [p; v(i,:) + s.*(v(i+1,:) - v(i,:))];
end
end

function p = randomWalk(rs, nd)

m = 600;
turn = smooth1(randn(rs, m, 1), 12);
ang = cumsum(turn) * 0.9;

x = cumsum(cos(ang));
y = cumsum(sin(ang));

x = x - mean(x);
y = y - mean(y);
s = max(max(abs(x)), max(abs(y)));
if s > 0
    x = x/s; y = y/s;
end

p = cnResampleArc([x y], nd, "linear");
end

function v = smooth1(x, sigma)

n = numel(x);
pad = min(n-1, ceil(3*sigma));
k = exp(-(-pad:pad).^2 / (2*sigma^2)).';
k = k / sum(k);

idx = (1:n).' + (-pad:pad);
idx = min(max(idx, 1), n);
v = x(idx) * k;
end

function v = pickDistinct(rs, pool, m)

pool = pool(:);
p = randperm(rs, numel(pool));
v = pool(p(1:min(m, numel(pool))));
end
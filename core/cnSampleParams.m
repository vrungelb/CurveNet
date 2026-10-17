%CNSAMPLEPARAMS Розыгрыш параметров для N примеров класса.  
function T = cnSampleParams(key, N, seed)  
  
arguments  
 key (1,1) string  
 N (1,1) double {mustBeInteger, mustBePositive}  
 seed (1,1) double = NaN  
end  
  
cfg = cnConfig();  
c = cnClasses(key);  
  
if isnan(seed)  
 allC = cnClasses();  
 ci = find([allC.key] == key, 1);  
 seed = cfg.data.seed + 1000*ci;  
end  
rs = RandStream("threefry", Seed = seed);  
  
T = table((1:N).', VariableNames = "idx");  
  
for i = 1:numel(c.shape)  
 s = c.shape(i);  
 if s.scale == "log"  
 T.(s.name) = exp(lhs(rs, N, log(s.lo), log(s.hi)));  
 else  
 T.(s.name) = lhs(rs, N, s.lo, s.hi);  
 end  
end  
  
if key == "logSpiral"  
 tIdx = find([c.shape.name] == "turns", 1);  
 turnsMin = c.shape(tIdx).lo;  
 minLnR = 2 * pi * T.growth * turnsMin;  
 lnRmax = max(minLnR, log(40) * (0.60 + 0.40 * rand(rs, N, 1)));  
 T.turns = max(turnsMin, min(T.turns, lnRmax ./ (2 * pi * T.growth)));  
end  
  
if ~isempty(c.kValues)  
 T.k = balanced(rs, N, c.kValues(:));  
end  
  
if ~c.isCurve  
 T.subtype = balanced(rs, N, ["fourier"; "polyline"; "shape"; "walk"]);  
end  
  
if c.hasAngle  
 T.angleDeg = lhs(rs, N, cfg.aug.rotation(1), cfg.aug.rotation(2));  
else  
 T.angleDeg = zeros(N,1);  
end  
  
an = c.aniso;  
if isempty(an)  
 an = cfg.aug.aniso;  
end  
T.anisoX = uni(rs, N, an);  
T.anisoY = uni(rs, N, an);  
  
if key == "cycloid"
    short = T.arches < 1.36;
    if any(short)
        dev = T.phase(short) - round(T.phase(short));
        maxDev = max(0.05, (T.arches(short) - 0.36) / 2);
        T.phase(short) = mod(dev .* (2 * maxDev), 1);
    end
    e = exp(uni(rs, N, log(an)));
    T.anisoX = 1 ./ sqrt(e);
    T.anisoY = sqrt(e);
end

if key == "logSpiral"
 sc = sqrt(T.anisoX .* T.anisoY);
 e = exp(uni(rs, N, log([1 2.5])));
 T.anisoX = sc .* sqrt(e);
 T.anisoY = sc ./ sqrt(e);
end  
  
if key == "lemniscate"  
 w = [0.28 0.12 0.30 0.30];  
 band = [0.420 0.435; 0.435 0.570; 0.570 1.000; 1.000 2.400];  
 cw = cumsum(w);  
 u = rand(rs, N, 1);  
 b = 1 + sum(u > cw(1:end-1), 2);  
 T.stretch = band(b,1) + (band(b,2) - band(b,1)) .* rand(rs, N, 1);  
end  
  
sh = c.shear;  
if isempty(sh)  
 sh = cfg.aug.shear;  
end  
T.shear = uni(rs, N, sh);  
  
if c.flipMode == "none"
    T.flip = zeros(N, 1);
else
    T.flip = randi(rs, [0 1], N, 1);
end  
  
T.warpAmp = c.distort * lhs(rs, N, cfg.aug.warpAmp(1), cfg.aug.warpAmp(2));  
T.tremorAmp = c.distort * lhs(rs, N, cfg.aug.tremorAmp(1), cfg.aug.tremorAmp(2));  
T.radialAmp = c.distort * lhs(rs, N, cfg.aug.radialAmp(1), cfg.aug.radialAmp(2));  
  
if c.closed  
 open = rand(rs, N, 1) < cfg.aug.openProb;  
 T.openGap = open .* uni(rs, N, cfg.aug.openGap);  
else  
 T.openGap = zeros(N,1);  
end  
  
brk = rand(rs, N, 1) < cfg.aug.breakProb;  
T.nBreaks = brk .* randi(rs, cfg.aug.breakCount, N, 1);  
  
T.nPoints = max(40, round(uni(rs, N, cfg.curve.nPoints) .* uni(rs, N, cfg.curve.densityJitter)));  
T.lineWidth = uni(rs, N, cfg.img.lineWidth);  
T.softenSigma = uni(rs, N, cfg.img.softenSigma);  
  
T.scaleJit = uni(rs, N, cfg.aug.scaleJitter);  
T.offX = uni(rs, N, cfg.aug.offsetJitter);  
T.offY = uni(rs, N, cfg.aug.offsetJitter);  
  
T.seed = randi(rs, [1 2^31-2], N, 1);  
  
T.Properties.Description = sprintf("Рецепты класса %s, seed %d", key, seed);  
end  
  
function v = lhs(rs, N, lo, hi)  
p = randperm(rs, N).';  
v = lo + (hi - lo) .* (p - 1 + rand(rs, N, 1)) ./ N;  
end  
  
function v = uni(rs, N, range)  
v = range(1) + (range(2) - range(1)) .* rand(rs, N, 1);  
end  
  
function v = balanced(rs, N, vals)  
reps = ceil(N / numel(vals));  
v = repmat(vals, reps, 1);  
v = v(1:N);  
v = v(randperm(rs, N).');
end
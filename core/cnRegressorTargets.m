%CNREGRESSORTARGETS Кодирование и декодирование целевых параметров регрессора.
function out = cnRegressorTargets(mode, C, varargin)

arguments
    mode (1,1) string {mustBeMember(mode, ["encode", "decode"])}
    C    (1,1) struct
end
arguments (Repeating)
    varargin
end

switch mode
    case "encode"
        out = encodeTargets(C, varargin{:});
    case "decode"
        out = decodeTargets(C, varargin{:});
end
end

function out = encodeTargets(C, Tclass)

targetCols = [string({C.shape.name}), "originX", "originY", "normScale"];
if C.hasAngle
    targetCols = [targetCols, "angleDeg"];
end
if C.regAffine
    targetCols = [targetCols, "anisoX", "anisoY"];
    if isempty(C.shear) || any(C.shear ~= 0)
        targetCols = [targetCols, "shear"];
    end
end
if C.flipMode == "target"
    targetCols = [targetCols, "flip"];
end

if ismember("flip", Tclass.Properties.VariableNames) && C.flipMode ~= "target"
    flipped = Tclass.flip > 0.5;
    baseDeg = 360;
    if C.flipMode == "sym180"; baseDeg = 180; end
    Tclass.angleDeg(flipped) = mod(baseDeg - Tclass.angleDeg(flipped), 360);
    if ismember("shear", targetCols)
        Tclass.shear(flipped) = -Tclass.shear(flipped);
    end
    Tclass.flip(flipped) = 0;
end

unitAniso = C.regAffine && all(ismember(["anisoX", "anisoY"], targetCols));
if unitAniso
    cScale = sqrt(max(1e-8, double(Tclass.anisoX) .* double(Tclass.anisoY)));
    Tclass.normScale = double(Tclass.normScale) .* cScale;
    Tclass.anisoX    = double(Tclass.anisoX) ./ cScale;
    Tclass.anisoY    = double(Tclass.anisoY) ./ cScale;
end

logGrowth = (C.key == "logSpiral");
if logGrowth && ismember("growth", Tclass.Properties.VariableNames)
    Tclass.growth = log(max(1e-4, double(Tclass.growth)));
end

Y_raw = double(Tclass{:, targetCols});

if ismember("phase", targetCols)
    pIdx = find(targetCols == "phase");
    ph = Y_raw(:, pIdx);
    cosp = cos(2 * pi * ph);
    sinp = sin(2 * pi * ph);
    targetCols = [targetCols(1:pIdx-1), "cosp", "sinp", targetCols(pIdx+1:end)];
    Y_raw = [Y_raw(:, 1:pIdx-1), cosp, sinp, Y_raw(:, pIdx+1:end)];
end

if C.hasAngle
    idx = find(targetCols == "angleDeg");
    angles = Y_raw(:, idx);

    if C.symDeg == 90
        axIdx = find(targetCols == "anisoX");
        ayIdx = find(targetCols == "anisoY");
        shIdx = find(targetCols == "shear");

        s  = Y_raw(:, shIdx);
        d  = atand(s);
        lo = shearAngleBound(s);
        a  = lo + mod(angles - lo, 180);

        sw = a >= lo + 90;
        h  = hypot(1, s(sw));
        ax = Y_raw(sw, axIdx);
        ay = Y_raw(sw, ayIdx);

        Y_raw(sw, axIdx) = ay .* h;
        Y_raw(sw, ayIdx) = ax ./ h;
        Y_raw(sw, shIdx) = -s(sw);
        a(sw) = a(sw) - 90 - d(sw);

        angles = a;
    end

    kVal = [];
    if isnan(C.symDeg)
        kVal = double(Tclass.k);
    end
    [mult, sfx] = angleMultSuffix(C, kVal);
    if isnan(C.symDeg)
        angles = mod(angles, 360 ./ mult);
    end

    cosa = cosd(mult .* angles);
    sina = sind(mult .* angles);
    targetCols = [targetCols(1:idx-1), "cos" + sfx, "sin" + sfx, targetCols(idx+1:end)];
    Y_raw = [Y_raw(:, 1:idx-1), cosa, sina, Y_raw(:, idx+1:end)];
end

normMin = min(Y_raw, [], 1);
normMax = max(Y_raw, [], 1);
normRange = normMax - normMin;
normRange(normRange == 0) = 1;
Y_norm = 2 * (Y_raw - normMin) ./ normRange - 1;

out = struct( ...
    "Y_norm",     Y_norm, ...
    "targetCols", targetCols, ...
    "normMin",    normMin, ...
    "normMax",    normMax, ...
    "logGrowth",  logGrowth, ...
    "unitAniso",  unitAniso);
end

function params = decodeTargets(C, reg, predNorm, params)

if nargin < 4 || isempty(params)
    params = struct();
end

predNorm = predNorm(:).';
if numel(predNorm) ~= numel(reg.targetCols)
    error("cnPredict:badRegressor", ...
        "Регрессор вернул %d чисел, а ожидалось %d.", numel(predNorm), numel(reg.targetCols));
end

rangeY = reg.normMax - reg.normMin;
rangeY(rangeY == 0) = 1;
predRaw = (predNorm + 1) / 2 .* rangeY + reg.normMin;

lim = ~startsWith(reg.targetCols, ["cos", "sin"]);
predRaw(lim) = min(max(predRaw(lim), reg.normMin(lim)), reg.normMax(lim));

for i = 1:numel(reg.targetCols)
    params.(reg.targetCols(i)) = predRaw(i);
end

if isfield(reg, "unitAniso") && reg.unitAniso ...
        && isfield(params, "anisoX") && isfield(params, "anisoY")
    cPred = sqrt(max(1e-8, params.anisoX * params.anisoY));
    params.anisoX = params.anisoX / cPred;
    params.anisoY = params.anisoY / cPred;
end

if isfield(params, "growth")
    if isfield(reg, "logGrowth") && reg.logGrowth
        params.growth = exp(params.growth);
    elseif params.growth <= 0
        params.growth = 0.001;
    end
end

if isfield(params, "cosp") && isfield(params, "sinp")
    params.phase = mod(atan2(params.sinp, params.cosp) / (2 * pi), 1);
end

if C.hasAngle
    kVal = [];
    if isnan(C.symDeg)
        kVal = params.k;
    end
    [mult, sfx] = angleMultSuffix(C, kVal);
    a = atan2d(params.("sin" + sfx), params.("cos" + sfx)) / mult;
    if C.symDeg == 90 && isfield(params, "shear")
        lo = shearAngleBound(params.shear);
        a  = lo + mod(a - lo, 90);
    end
    params.angleDeg = mod(a, 360);
else
    params.angleDeg = 0;
end

if isfield(params, "turns")
    params.turns = max(0.5, params.turns);
end
end

function [mult, sfx] = angleMultSuffix(C, kVal)
if isnan(C.symDeg)
    mult = kVal;
    sfx  = "Ka";
else
    mult = round(360 / C.symDeg);
    sfx  = "a";
    if mult > 1; sfx = mult + "a"; end
end
end

function lo = shearAngleBound(shear)
lo = -45 + atand(shear) / 2;
end

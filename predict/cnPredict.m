%CNPREDICT Распознавание кривой и восстановление идеальной формы нейросетью.
function R = cnPredict(input, canvasSpan, opts)

arguments
    input
    canvasSpan (1,1) double {mustBePositive} = 20
    opts.model (1,1) string = "classifier"
    opts.reload (1,1) logical = false
    opts.forceClass (1,1) string = ""
end

R = struct("ok", false, "message", "", "warning", "", ...
    "class", "", "name", "", "confidence", 0, ...
    "top", table(), "reliable", false, ...
    "img", uint8.empty(0,0), "info", [], ...
    "params", struct(), "equation", "", "idealPoints", [], ...
    "fit", struct("residual", NaN));

cfg = cnConfig();
model = loadModel(opts.model, opts.reload);

info = struct();

if iscell(input)
    [img, info] = cnPrepareInput(input, canvasSpan);
    R.info = info;
    R.warning = info.warning;
    if ~info.ok
        R.message = info.message;
        return
    end
else
    img = input;
    if ~ismatrix(img) || size(img,1) ~= cfg.img.size || size(img,2) ~= cfg.img.size
        R.message = sprintf("Ожидалась 2D картинка %dx%d.", cfg.img.size, cfg.img.size);
        return
    end
end
R.img = img;

scores = predict(model.net, single(img));
scores = double(scores(:));

[sorted, ord] = sort(scores, "descend");
keys = model.classKeys(:);

R.ok = true;
R.class = keys(ord(1));
R.confidence = sorted(1);
R.reliable = sorted(1) >= cfg.refine.minConfidence;

if opts.forceClass ~= ""
    ix = find(keys == opts.forceClass, 1);
    if isempty(ix)
        error("cnPredict:badForce", "Класса «%s» нет в классификаторе.", opts.forceClass);
    end
    R.class = keys(ix);
    R.confidence = scores(ix);
    R.reliable = true;
end
cls = cnClasses(R.class);
R.name = cls.name;

n = min(3, numel(sorted));
names = [cnClasses(keys(ord(1:n))).name].';

R.top = table(keys(ord(1:n)), names, 100*sorted(1:n), ...
    VariableNames = ["класс","название","вероятность"]);

if ~R.reliable
    R.warning = strtrim(R.warning + " Уверенность классификатора ниже порога.");
end

if cls.isCurve
    regFile = fullfile(cfg.paths.models, "regress_" + R.class + ".mat");
    if ~isfile(regFile)
        R.warning = strtrim(R.warning + " Регрессор для «" + R.name + "» не обучен.");
    elseif ~isempty(cls.kValues) && ~isfile(fullfile(cfg.paths.models, "rosek.mat"))
        R.warning = strtrim(R.warning + " Классификатор числа лепестков не обучен.");
    else
        try
            R = addIdealCurve(R, cls, img, info, opts.reload);
            R.fit = struct("residual", cnCurveResidual(R.idealPoints, info));
        catch ME
            R.params = struct();
            R.idealPoints = [];
            R.equation = "";
            R.warning = strtrim(R.warning + " Ошибка восстановления кривой.");
            warning("cnPredict:regressorFailed", "%s", ME.message);
        end
    end
end
end

function R = addIdealCurve(R, cls, img, info, reload)

if ~isempty(cls.kValues)
    R.params.k = max(2, round(predictRoseK(img, reload)));
end

reg      = loadModel("regress_" + R.class, reload);
predNorm = double(predict(reg.net, single(img)));
R.params = cnRegressorTargets("decode", cls, reg, predNorm, R.params);

if ~isstruct(info) || ~isfield(info, "tf") || isempty(info.tf)
    return
end
tf = info.tf;

P_raw = cnCurvePoints(R.class, R.params, 361);

aX = 1; aY = 1; sh = 0;
if isfield(R.params, "anisoX"); aX = R.params.anisoX; end
if isfield(R.params, "anisoY"); aY = R.params.anisoY; end
if isfield(R.params, "shear");  sh = R.params.shear;  end
flip = isfield(R.params, "flip") && R.params.flip > 0.5;

A_mat = cnAffineMatrix(R.params.angleDeg, aX, aY, sh, flip);
X0 = tf.toWorld([R.params.originX, R.params.originY]);
k = R.params.normScale * tf.scale;

R.idealPoints = [];
for i = 1:numel(P_raw)
    p_final = (P_raw{i} * A_mat.') * k + X0;
    if i > 1
        R.idealPoints = [R.idealPoints; NaN, NaN];
    end
    R.idealPoints = [R.idealPoints; p_final];
end

ang = deg2rad(R.params.angleDeg);

R.equation = cnEquationText(R.class, R.params, X0, k, ang, aX, aY, sh, flip, A_mat);
end

function kv = predictRoseK(img, reload)
model = loadModel("rosek", reload);
scores = double(predict(model.net, single(img)));
scores = scores(:);
[~, ix] = max(scores);
kv = double(model.classKeys(ix));
end

function model = loadModel(name, reload)
persistent models
if isempty(models)
    models = containers.Map("KeyType", "char", "ValueType", "any");
end
if reload || ~isKey(models, char(name))
    cfg = cnConfig();
    file = fullfile(cfg.paths.models, name + ".mat");
    if ~isfile(file)
        error("cnPredict:noModel", "Не найдена модель %s.", file);
    end
    L = load(file, "model");
    models(char(name)) = L.model;
end
model = models(char(name));
end
%CNTRAINREGRESSOR Обучение регрессора одного класса.
function R = cnTrainRegressor(className, opts)

arguments
    className      (1,1) string
    opts.maxEpochs (1,1) double = 0
    opts.miniBatch (1,1) double = 0
    opts.learnRate (1,1) double = 0
    opts.width     (1,1) double = 32
    opts.depth     (1,1) double = 5
    opts.dropout   (1,1) double = 0.20
    opts.plots     (1,1) logical = true
    opts.seed      (1,1) double = 42
end

rng(opts.seed);

[T, S, cfg] = cnLoadDataset();
opts = cnTrainCommon("defaults", opts, cfg, true);

C = cnClasses(className);

mask = (T.class == className);
Tclass = T(mask, :);
nRows = height(Tclass);
if nRows == 0
    error("cnTrainRegressor:noData", "Нет примеров класса «%s».", className);
end

if ~all(ismember(["originX", "originY", "normScale"], string(Tclass.Properties.VariableNames)))
    fprintf("Вычисление пространственных координат для %d примеров...\n", nRows);
    ox     = zeros(nRows, 1);
    oy     = zeros(nRows, 1);
    nScale = zeros(nRows, 1);
    recs   = table2struct(Tclass);

    if ~isempty(ver("parallel"))
        parfor i = 1:nRows
            [~, ~, tf] = cnRender(className, recs(i), false);
            ox(i)     = tf.origin(1);
            oy(i)     = tf.origin(2);
            nScale(i) = tf.normScale;
        end
    else
        for i = 1:nRows
            [~, ~, tf] = cnRender(className, recs(i), false);
            ox(i)     = tf.origin(1);
            oy(i)     = tf.origin(2);
            nScale(i) = tf.normScale;
        end
    end

    Tclass.originX   = ox;
    Tclass.originY   = oy;
    Tclass.normScale = nScale;
end

enc          = cnRegressorTargets("encode", C, Tclass);
targetCols   = enc.targetCols;
Y_norm       = enc.Y_norm;
normMin      = enc.normMin;
normMax      = enc.normMax;
logGrowth    = enc.logGrowth;
numResponses = numel(targetCols);

fprintf("Обучение регрессора: %s\n", upper(className));
fprintf("Целевые параметры (%d): %s\n\n", numResponses, join(targetCols, ", "));

idxTrainClass = find(ismember(find(mask), S.train));
idxValClass   = find(ismember(find(mask), S.val));
files = fullfile(cfg.paths.images, Tclass.class, Tclass.file);

XTrain = cnTrainCommon("loadImages", files(idxTrainClass), cfg.img.size);
YTrain = single(Y_norm(idxTrainClass, :));
XVal   = cnTrainCommon("loadImages", files(idxValClass), cfg.img.size);
YVal   = single(Y_norm(idxValClass, :));

net = cnNetworkArch(numResponses, width=opts.width, depth=opts.depth, dropout=opts.dropout, isRegressor=true);
options = cnTrainCommon("options", opts, cfg, numel(idxTrainClass), {XVal, YVal}, true);

t0 = tic;
[net, info] = trainnet(XTrain, YTrain, net, "mse", options);
trainTime = toc(t0);

model = struct("className", className, "net", net, "targetCols", targetCols, ...
    "normMin", normMin, "normMax", normMax, "info", info, "options", opts, "trainTime", trainTime, ...
    "logGrowth", logGrowth);
if ~exist(cfg.paths.models, "dir"); mkdir(cfg.paths.models); end
modelFile = fullfile(cfg.paths.models, sprintf("regress_%s.mat", className));
save(modelFile, "model");
fprintf("\nРегрессор сохранен: %s\n", modelFile);
if nargout >= 1; R = model; end
end
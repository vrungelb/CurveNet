%CNTRAINROSEK Обучение дискретного классификатора числа лепестков розы (k).
function R = cnTrainRoseK(opts)

arguments
    opts.maxEpochs (1,1) double  = 0
    opts.miniBatch (1,1) double  = 0
    opts.learnRate (1,1) double  = 0
    opts.width     (1,1) double  = 24
    opts.depth     (1,1) double  = 5
    opts.dropout   (1,1) double  = 0.35
    opts.plots     (1,1) logical = true
    opts.seed      (1,1) double  = 1
    opts.name      (1,1) string  = "rosek"
end

rng(opts.seed);

[T, S, cfg] = cnLoadDataset();
opts = cnTrainCommon("defaults", opts, cfg, false);

if ~ismember("k", string(T.Properties.VariableNames))
    error("cnTrainRoseK:noK", "В метаданных нет столбца k.");
end

idxRose = find(T.class == "rose");
if isempty(idxRose); error("cnTrainRoseK:noData", "В датасете нет примеров розы."); end

kAll    = double(T.k(idxRose));
kValues = unique(kAll);
if numel(kValues) < 2
    error("cnTrainRoseK:oneK", "В датасете только одно значение k (%g).", kValues(1));
end

files  = fullfile(cfg.paths.images, T.class(idxRose), T.file(idxRose));
labels = categorical(kAll);

isTrain = ismember(idxRose, S.train);
isVal   = ismember(idxRose, S.val);
isTest  = ismember(idxRose, S.test);

XTrain = cnTrainCommon("loadImages", files(isTrain), cfg.img.size);
YTrain = labels(isTrain);
XVal   = cnTrainCommon("loadImages", files(isVal),   cfg.img.size);
YVal   = labels(isVal);
XTest  = cnTrainCommon("loadImages", files(isTest),  cfg.img.size);

fprintf("Классификатор числа лепестков: значения k = %s\n", join(string(kValues), ", "));
fprintf("Обучение %d, валидация %d, тест %d\n\n", ...
    numel(YTrain), numel(YVal), size(XTest, 4));

net = cnNetworkArch(numel(kValues), width=opts.width, depth=opts.depth, dropout=opts.dropout);
options = cnTrainCommon("options", opts, cfg, numel(YTrain), {XVal, YVal}, false);

t0 = tic;
[net, info] = trainnet(XTrain, YTrain, net, "crossentropy", options);
trainTime = toc(t0);

scoresVal = minibatchpredict(net, XVal, MiniBatchSize=opts.miniBatch);
[~, ixV]  = max(scoresVal, [], 2);
accVal    = mean(kValues(ixV) == kAll(isVal));

scoresTest = minibatchpredict(net, XTest, MiniBatchSize=opts.miniBatch);
[~, ixT]   = max(scoresTest, [], 2);
accTest    = mean(kValues(ixT) == kAll(isTest));

fprintf("\nТочность k: валидация %.2f%%, тест %.2f%%\n", 100*accVal, 100*accTest);

model = struct("net", net, "classKeys", kValues(:).', "info", info, ...
    "accVal", accVal, "accTest", accTest, "options", opts, ...
    "trainTime", trainTime, "trainedAt", datetime("now"));
if ~exist(cfg.paths.models, "dir"); mkdir(cfg.paths.models); end
modelFile = fullfile(cfg.paths.models, opts.name + ".mat");
save(modelFile, "model");
fprintf("Сохранено: %s\n", modelFile);

if nargout >= 1; R = model; end
end
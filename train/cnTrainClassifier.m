%CNTRAINCLASSIFIER Обучение классификатора.
function R = cnTrainClassifier(opts)

arguments
    opts.maxEpochs    (1,1) double  = 0
    opts.miniBatch    (1,1) double  = 0
    opts.learnRate    (1,1) double  = 0
    opts.width        (1,1) double  = 24
    opts.depth        (1,1) double  = 5
    opts.dropout      (1,1) double  = 0.35
    opts.plots        (1,1) logical = true
    opts.parallelData (1,1) logical = true
    opts.inMemory     (1,1) logical = true
    opts.seed         (1,1) double  = 1
    opts.name         (1,1) string  = "classifier"
end

rng(opts.seed);

[T, S, cfg] = cnLoadDataset();
opts = cnTrainCommon("defaults", opts, cfg, false);

files = fullfile(cfg.paths.images, T.class, T.file);

allKeys   = [cnClasses().key];
present   = unique(T.class);
classKeys = allKeys(ismember(allKeys, present));
labels    = categorical(T.class, classKeys);

nC     = numel(classKeys);
nTrain = numel(S.train);
nVal   = numel(S.val);
nTest  = numel(S.test);

fprintf("Классов: %d\n", nC);
fprintf("Обучение %d, валидация %d, тест %d\n", nTrain, nVal, nTest);

useRAM = opts.inMemory;
if useRAM
    try
        m = memory;
        availRAM = m.MemAvailableAllArrays;
        needRAM  = (nTrain + nVal + nTest) * cfg.img.size^2;
        if availRAM < needRAM * 1.3
            warning("cnTrainClassifier:lowRAM", ...
                "Недостаточно свободной RAM для предзагрузки всего датасета (нужно ~%.1f ГБ, доступно %.1f ГБ). Используется imageDatastore.", ...
                needRAM / 1e9, availRAM / 1e9);
            useRAM = false;
        end
    catch
        % Если memory не поддерживается (non-Windows), продолжаем в RAM
    end
end

if useRAM
    fprintf("Режим: Загрузка датасета в оперативную память (RAM)...\n");
    tLoad = tic;
    XTrain = cnTrainCommon("loadImages", files(S.train), cfg.img.size, "Train");
    YTrain = labels(S.train);
    XVal   = cnTrainCommon("loadImages", files(S.val),   cfg.img.size, "Val");
    YVal   = labels(S.val);
    XTest  = cnTrainCommon("loadImages", files(S.test),  cfg.img.size, "Test");
    YTest  = labels(S.test);
    tLoadTotal = toc(tLoad);
    ramGB = (numel(XTrain) + numel(XVal) + numel(XTest)) / 1e9;
    fprintf("Все изображения загружены в RAM за %.1f сек (~%.2f ГБ).\n\n", tLoadTotal, ramGB);

    trainSource = XTrain;
    trainTarget = YTrain;
    valData     = {XVal, YVal};
else
    fprintf("Режим: Чтение с диска через imageDatastore.\n\n");
    imdsTrain = imageDatastore(files(S.train), Labels = labels(S.train));
    imdsVal   = imageDatastore(files(S.val),   Labels = labels(S.val));
    imdsTest  = imageDatastore(files(S.test),  Labels = labels(S.test));

    trainSource = imdsTrain;
    trainTarget = [];
    valData     = imdsVal;
end

net = cnNetworkArch(nC, ...
    width = opts.width, depth = opts.depth, dropout = opts.dropout);

useParallelPrep = ~useRAM && opts.parallelData ...
    && cfg.train.preprocessing == "parallel" && ~isempty(ver("parallel"));
if useParallelPrep
    fprintf("Подготовка данных: параллельно.\n\n");
end

options = cnTrainCommon("options", opts, cfg, nTrain, valData, false, useParallelPrep);

t0 = tic;
if useRAM
    [net, info] = trainnet(trainSource, trainTarget, net, "crossentropy", options);
else
    [net, info] = trainnet(trainSource, net, "crossentropy", options);
end
trainTime = toc(t0);

fprintf("\nОбучение заняло %.1f мин\n", trainTime/60);

if useRAM
    scoresTest = minibatchpredict(net, XTest, MiniBatchSize = opts.miniBatch);
    predTest   = scores2label(scoresTest, classKeys);
    trueTest   = YTest;

    scoresVal  = minibatchpredict(net, XVal, MiniBatchSize = opts.miniBatch);
    accVal     = mean(scores2label(scoresVal, classKeys) == YVal);
    accTest    = mean(predTest(:) == trueTest(:));
else
    scoresTest = minibatchpredict(net, imdsTest, MiniBatchSize = opts.miniBatch);
    predTest   = scores2label(scoresTest, classKeys);
    trueTest   = imdsTest.Labels;

    accTest = mean(predTest(:) == trueTest(:));

    scoresVal = minibatchpredict(net, imdsVal, MiniBatchSize = opts.miniBatch);
    accVal    = mean(scores2label(scoresVal, classKeys) == imdsVal.Labels(:));
end

fprintf("Точность: валидация %.2f%%, тест %.2f%%\n\n", 100*accVal, 100*accTest);

perClass = zeros(nC,1);
for i = 1:nC
    m = trueTest == classKeys(i);
    perClass(i) = mean(predTest(m) == trueTest(m));
end
[perClassSorted, ord] = sort(perClass);
disp(table(classKeys(ord).', 100*perClassSorted, ...
    VariableNames = ["класс","точность, %"]))

for d = [cfg.paths.models, cfg.paths.results]
    if ~exist(d, "dir"); mkdir(d); end
end

model = struct();
model.net        = net;
model.classKeys  = classKeys;
model.info       = info;
model.accVal     = accVal;
model.accTest    = accTest;
model.perClass   = perClass;
model.options    = opts;
model.imageSize  = cfg.img.size;
model.trainedAt  = datetime("now");
model.trainTime  = trainTime;

modelFile = fullfile(cfg.paths.models, opts.name + ".mat");
save(modelFile, "model", "-v7.3");
fprintf("Сеть сохранена: %s\n", modelFile);

f = figure(Name = "Матрица ошибок", Color = "w", Position = [100 100 900 800]);
confusionchart(trueTest, predTest, ...
    RowSummary = "row-normalized", ...
    Title = sprintf("Тест: %.2f%%", 100*accTest));
exportgraphics(f, fullfile(cfg.paths.results, opts.name + "_confusion.png"), ...
    Resolution = 150);

if nargout >= 1
    R = model;
end
end
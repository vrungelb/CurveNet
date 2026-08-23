function R = cnTrainClassifier(opts)
%CNTRAINCLASSIFIER  Обучение классификатора кривых.
%
%   cnTrainClassifier()                       обучить по настройкам cnConfig
%   cnTrainClassifier(maxEpochs = 8)          короткий пробный прогон
%   cnTrainClassifier(width = 16, depth = 4)  сеть поменьше
%   cnTrainClassifier(plots = false)          без окна прогресса
%   cnTrainClassifier(parallelData = false)   без параллельной подготовки
%   cnTrainClassifier(miniBatch = 256)        крупнее пачка, меньше итераций
%   R = cnTrainClassifier(...)                вернуть результаты
%
%   Читает dataset/meta.mat и dataset/split.mat, обучает сеть и сохраняет
%   её в models/classifier.mat вместе с историей обучения и метриками.
%
%   Почему датастор строится по списку файлов, а не по папкам
%   --------------------------------------------------------
%   imageDatastore умеет сам обойти папки и взять метки из их имён, но тогда
%   он вернёт все картинки одной кучей, и разбиение придётся делать заново.
%   Разбиение уже сделано в CNSPLITDATASET, зафиксировано seed'ом и лежит на
%   диске — именно оно должно быть источником истины. Иначе при каждом
%   запуске обучения состав частей был бы новым, тестовые примеры постепенно
%   просачивались бы в обучающие, и итоговая точность оказалась бы завышена,
%   причём совершенно незаметно.
%
%   Поэтому файлы берутся списком, а метки ставятся явно.
%
%   Порядок классов
%   ---------------
%   Категории задаются в порядке CNCLASSES, а не в алфавитном, который
%   categorical выбрал бы сам. Порядок категорий определяет порядок выходов
%   последнего слоя, и если он поплывёт между обучением и применением, сеть
%   начнёт молча выдавать не те имена классов. Это одна из самых
%   неприятных ошибок в таких задачах: всё работает, точность высокая,
%   а ответы перепутаны.
%
%   Что сохраняется
%   ---------------
%   models/classifier.mat  сеть, имена классов, история обучения, настройки
%   results/               матрица ошибок и сводка по классам
%
%   См. также CNCLASSIFIERARCH, CNSPLITDATASET, CNBUILDDATASET.

arguments
    opts.maxEpochs (1,1) double  = 0
    opts.miniBatch (1,1) double  = 0
    opts.learnRate (1,1) double  = 0
    opts.width     (1,1) double  = 24
    opts.depth     (1,1) double  = 5
    opts.dropout   (1,1) double  = 0.35
    opts.plots     (1,1) logical = true
    opts.parallelData (1,1) logical = true
    opts.seed      (1,1) double  = 1
    opts.name      (1,1) string  = "classifier"
end

cfg = cnConfig();

if opts.maxEpochs == 0; opts.maxEpochs = cfg.train.maxEpochs;       end
if opts.miniBatch == 0; opts.miniBatch = cfg.train.miniBatchSize;   end
if opts.learnRate == 0; opts.learnRate = cfg.train.initialLearnRate; end

% Инициализация весов случайна; фиксируем, чтобы повторный запуск с теми же
% настройками давал тот же результат.
rng(opts.seed);

% =======================================================================
%  Данные
% =======================================================================
if ~isfile(cfg.paths.meta)
    error("cnTrainClassifier:noMeta", ...
        "Нет %s. Сначала cnBuildDataset.", cfg.paths.meta);
end
if ~isfile(cfg.paths.split)
    error("cnTrainClassifier:noSplit", ...
        "Нет %s. Сначала cnSplitDataset.", cfg.paths.split);
end

Lm = load(cfg.paths.meta,  "meta");
Ls = load(cfg.paths.split, "split");
T  = Lm.meta.table;
S  = Ls.split;

if height(T) ~= numel(S.assign)
    error("cnTrainClassifier:mismatch", ...
        ["Разбиение не соответствует датасету: %d строк в meta, %d в split. " ...
         "Похоже, датасет пересобирали без cnSplitDataset."], ...
        height(T), numel(S.assign));
end

% Совпадения высоты мало. Разбиение хранит только номера строк, а имена
% файлов в датасете строятся по индексу, поэтому старый split.mat подойдёт
% к новому датасету и по длине, и по путям — даже если под теми же именами
% лежат уже другие картинки. Молча разъедется только раскладка по классам:
% при изменившемся списке классов или другом N на класс метки поедут
% относительно строк, а обучение об этом никак не сообщит.
if ~isequal(string(S.class), string(T.class)) ...
        || ~isequal(string(S.file), string(T.file))
    error("cnTrainClassifier:splitStale", ...
        ["Разбиение построено для другого датасета: не совпадают классы " ...
         "или имена файлов. Перезапустите cnSplitDataset."]);
end

files = fullfile(cfg.paths.images, T.class, T.file);

% Порядок категорий берём из cnClasses, оставляя только те классы, которые
% реально есть в датасете.
allKeys   = [cnClasses().key];
present   = unique(T.class);
classKeys = allKeys(ismember(allKeys, present));
labels    = categorical(T.class, classKeys);

nC = numel(classKeys);

imdsTrain = imageDatastore(files(S.train), Labels = labels(S.train));
imdsVal   = imageDatastore(files(S.val),   Labels = labels(S.val));
imdsTest  = imageDatastore(files(S.test),  Labels = labels(S.test));

% Проверка, что файлы на месте: список путей строился по таблице, а её
% могли сохранить от другого прогона.
if ~isfile(files(S.train(1)))
    error("cnTrainClassifier:missingImages", ...
        "Файл %s не найден. Датасет и метаданные разошлись.", files(S.train(1)));
end

fprintf("Классов: %d\n", nC);
fprintf("Обучение %d, валидация %d, тест %d\n\n", ...
    numel(imdsTrain.Files), numel(imdsVal.Files), numel(imdsTest.Files));

% =======================================================================
%  Сеть и настройки обучения
% =======================================================================
net = cnClassifierArch(nC, ...
    width = opts.width, depth = opts.depth, dropout = opts.dropout);

% Проверять валидацию имеет смысл несколько раз за эпоху: реже — поздно
% заметим переобучение, чаще — потратим на это заметную долю времени.
itPerEpoch = max(1, floor(numel(imdsTrain.Files) / opts.miniBatch));
valFreq    = max(1, floor(itPerEpoch / 2));

if opts.plots; plt = "training-progress"; else; plt = "none"; end

% Подготовка данных в отдельных процессах. Обучение идёт на видеокарте, а
% чтение и раскодировка PNG по умолчанию выполняются одним потоком главного
% процесса — и пока он читает следующую пачку, видеокарта ждёт. Отдав эту
% работу пулу, обычно выигрываем треть-половину времени эпохи.
%
% Аргумент добавляется в список только если он реально применим: без
% Parallel Computing Toolbox trainingOptions на него ругнётся.
extra = {};
if opts.parallelData && cfg.train.preprocessing == "parallel" ...
        && ~isempty(ver("parallel"))
    extra = {"PreprocessingEnvironment", "parallel"};
    fprintf("Подготовка данных: параллельно.\n\n");
end

% Аргументы собираются в ячейку, а не пишутся через «имя = значение».
% Причина синтаксическая: MATLAB требует, чтобы аргументы в форме
% «имя = значение» шли последними, и раскрытие ячейки extra{:} после них
% недопустимо. В классической форме списка такого ограничения нет.
args = { ...
    "MaxEpochs",            opts.maxEpochs, ...
    "MiniBatchSize",        opts.miniBatch, ...
    "InitialLearnRate",     opts.learnRate, ...
    "LearnRateSchedule",    "piecewise", ...
    "LearnRateDropFactor",  cfg.train.lrDropFactor, ...
    "LearnRateDropPeriod",  cfg.train.lrDropPeriod, ...
    "L2Regularization",     cfg.train.l2Regularization, ...
    "Shuffle",              cfg.train.shuffle, ...
    "ValidationData",       imdsVal, ...
    "ValidationFrequency",  valFreq, ...
    "ValidationPatience",   cfg.train.validationPatience, ...
    "Metrics",              "accuracy", ...
    "ExecutionEnvironment", cfg.train.environment, ...
    "Plots",                plt, ...
    "Verbose",              true, ...
    "VerboseFrequency",     cfg.train.verboseFreq };

options = trainingOptions("adam", args{:}, extra{:});

% =======================================================================
%  Обучение
% =======================================================================
t0 = tic;
[net, info] = trainnet(imdsTrain, net, "crossentropy", options);
trainTime = toc(t0);

fprintf("\nОбучение заняло %.1f мин\n", trainTime/60);

% =======================================================================
%  Оценка на тесте
% =======================================================================
% Тестовая часть до этого момента не использовалась ни разу: ни на
% обучении, ни при подборе настроек. Только поэтому её цифра честная.
scoresTest = minibatchpredict(net, imdsTest, MiniBatchSize = opts.miniBatch);
predTest   = scores2label(scoresTest, classKeys);
trueTest   = imdsTest.Labels;

accTest = mean(predTest(:) == trueTest(:));

scoresVal = minibatchpredict(net, imdsVal, MiniBatchSize = opts.miniBatch);
accVal    = mean(scores2label(scoresVal, classKeys) == imdsVal.Labels(:));

fprintf("Точность: валидация %.2f%%, тест %.2f%%\n\n", 100*accVal, 100*accTest);

% Поклассовая точность: общая цифра прячет то, что один-два класса могут
% проваливаться, а остальные вытягивать среднее.
perClass = zeros(nC,1);
for i = 1:nC
    m = trueTest == classKeys(i);
    perClass(i) = mean(predTest(m) == trueTest(m));
end
[perClassSorted, ord] = sort(perClass);
disp(table(classKeys(ord).', 100*perClassSorted, ...
    VariableNames = ["класс","точность, %"]))

% =======================================================================
%  Сохранение
% =======================================================================
for d = [cfg.paths.models, cfg.paths.results]
    if ~exist(d, "dir"); mkdir(d); end
end

model = struct();
model.net        = net;
model.classKeys  = classKeys;
% Объект deep.TrainingInfo сохранять нельзя: он воскрешает окно прогресса
% обучения при каждом чтении модели. Оставляем только числа.
model.history    = struct( ...
    "trainLoss", double(info.TrainingHistory.Loss), ...
    "iteration", double(info.TrainingHistory.Iteration), ...
    "valLoss",   double(info.ValidationHistory.Loss));
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

% --- матрица ошибок -----------------------------------------------------
f = figure(Name = "Матрица ошибок", Color = "w", Position = [100 100 900 800]);
cm = confusionchart(trueTest, predTest, ...
    RowSummary = "row-normalized", ...
    Title = sprintf("Тест: %.2f%%", 100*accTest));
cm.Normalization = "row-normalized";
exportgraphics(f, fullfile(cfg.paths.results, opts.name + "_confusion.png"), ...
    Resolution = 150);

if nargout >= 1
    R = model;
end
end
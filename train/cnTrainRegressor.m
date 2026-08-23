function model = cnTrainRegressor(key, opts)
%CNTRAINREGRESSOR  Обучение регрессора параметров кривой для одного класса.
%
%   cnTrainRegressor("ellipse")
%   cnTrainRegressor("ellipse", maxEpochs = 5)     короткий пробный прогон
%   model = cnTrainRegressor("ellipse", plots = false)
%
%   Читает dataset/meta.mat и dataset/split.mat, строит цели через
%   CNREGRESSIONTARGETS, обучает сеть и сохраняет её в models/reg_<key>.mat.
%
%   Своя сеть на каждый класс
%   -------------------------
%   Число выходов у классов разное, от трёх у окружности до шести у
%   гиперболы, и смысл выходов тоже разный. Возможны два устройства: одна
%   общая сеть с двенадцатью головами и маскировкой потерь по классу, либо
%   отдельная небольшая сеть на класс.
%
%   Здесь выбрано второе. Общая сеть учит признаки один раз для всех и в
%   пределе требует меньше данных, но её нельзя ни обучать, ни отлаживать по
%   частям: ошибка в разметке одного класса портит общие свёрточные слои и
%   тем самым все остальные. Отдельные сети дороже по суммарному времени, но
%   каждая проверяется и переобучается независимо, а данных у нас столько,
%   сколько сгенерируем. Для проекта, который делается впервые, это важнее
%   экономии.
%
%   Стандартизация целей
%   --------------------
%   Выходы имеют разный масштаб: смещение центра порядка сотых, логарифм
%   вытянутости порядка единицы. Среднеквадратичная ошибка сложит их как
%   есть, и сеть займётся только самым крупным слагаемым, а мелкие оставит
%   как шум.
%
%   Поэтому каждый выход приводится к нулевому среднему и единичному
%   разбросу, а коэффициенты сохраняются вместе с сетью. Считаются они
%   только по обучающей части: взять их по всему датасету значит подсмотреть
%   в тест, пусть и в мелочи.
%
%   Именованные аргументы
%   ---------------------
%   maxEpochs, miniBatch, learnRate, width, depth, dropout, plots
%   Значения по умолчанию берутся из cfg.regress.
%
%   См. также CNREGRESSIONTARGETS, CNREGRESSORARCH, CNTRAINCLASSIFIER.

arguments
    key             (1,1) string
    opts.maxEpochs  (1,1) double  = 0
    opts.miniBatch  (1,1) double  = 0
    opts.learnRate  (1,1) double  = 0
    opts.width      (1,1) double  = 24
    opts.depth      (1,1) double  = 5
    opts.dropout    (1,1) double  = 0.15
    opts.plots      (1,1) logical = true
end

cfg = cnConfig();
c   = cnClasses(key);

if opts.maxEpochs == 0; opts.maxEpochs = cfg.regress.maxEpochs;       end
if opts.miniBatch == 0; opts.miniBatch = cfg.regress.miniBatchSize;   end
if opts.learnRate == 0; opts.learnRate = cfg.regress.initialLearnRate; end

% =======================================================================
%  Данные
% =======================================================================
if ~isfile(cfg.paths.meta)
    error("cnTrainRegressor:noMeta", "Нет %s. Сначала cnBuildDataset.", cfg.paths.meta);
end
if ~isfile(cfg.paths.split)
    error("cnTrainRegressor:noSplit", "Нет %s. Сначала cnSplitDataset.", cfg.paths.split);
end

T = load(cfg.paths.meta,  "meta").meta.table;
S = load(cfg.paths.split, "split").split;

if height(T) ~= numel(S.assign)
    error("cnTrainRegressor:mismatch", ...
        "Разбиение не соответствует датасету: %d строк в meta, %d в split.", ...
        height(T), numel(S.assign));
end
if ~isequal(string(S.class), string(T.class)) || ~isequal(string(S.file), string(T.file))
    error("cnTrainRegressor:splitStale", ...
        "Разбиение построено для другого датасета. Перезапустите cnSplitDataset.");
end

% Строки нужного класса и их места в общем разбиении. Разбиение хранит
% назначения по всей таблице, поэтому индексы класса из неё и берутся —
% так регрессор и классификатор видят одну и ту же тестовую часть, и их
% результаты можно честно сопоставлять.
rows = find(string(T.class) == key);
if isempty(rows)
    error("cnTrainRegressor:noRows", "В датасете нет класса «%s».", key);
end

assign = string(S.assign(rows));
files  = fullfile(cfg.paths.images, key, T.file(rows));

[Y, names] = cnRegressionTargets(key, verbose = true);
Y = single(Y);

iTrain = find(assign == "train");
iVal   = find(assign == "val");
iTest  = find(assign == "test");

fprintf("\nОбучение %d, валидация %d, тест %d\n", ...
    numel(iTrain), numel(iVal), numel(iTest));

if ~isfile(files(iTrain(1)))
    error("cnTrainRegressor:missingImages", ...
        "Файл %s не найден. Датасет и метаданные разошлись.", files(iTrain(1)));
end

% --- стандартизация целей ----------------------------------------------
mu = mean(Y(iTrain,:), 1);
sg = std(Y(iTrain,:), 0, 1);
sg(sg < 1e-6) = 1;              % выход-константа не должен обратиться в NaN
Z  = (Y - mu) ./ sg;

% =======================================================================
%  Хранилища
% =======================================================================
mk = @(idx) combine( ...
    imageDatastore(files(idx)), ...
    arrayDatastore(Z(idx,:), IterationDimension = 1));

dsTrain = mk(iTrain);
dsVal   = mk(iVal);
dsTest  = mk(iTest);

% =======================================================================
%  Сеть и настройки
% =======================================================================
net = cnRegressorArch(c.nReg, ...
    width = opts.width, depth = opts.depth, dropout = opts.dropout);

itPerEpoch = max(1, floor(numel(iTrain) / opts.miniBatch));
valFreq    = max(1, floor(itPerEpoch / 2));

if opts.plots; plt = "training-progress"; else; plt = "none"; end

options = trainingOptions("adam", ...
    "MaxEpochs",            opts.maxEpochs, ...
    "MiniBatchSize",        opts.miniBatch, ...
    "InitialLearnRate",     opts.learnRate, ...
    "LearnRateSchedule",    "piecewise", ...
    "LearnRateDropFactor",  cfg.regress.lrDropFactor, ...
    "LearnRateDropPeriod",  cfg.regress.lrDropPeriod, ...
    "L2Regularization",     cfg.regress.l2Regularization, ...
    "Shuffle",              "every-epoch", ...
    "ValidationData",       dsVal, ...
    "ValidationFrequency",  valFreq, ...
    "ExecutionEnvironment", cfg.regress.environment, ...
    "Plots",                plt, ...
    "Verbose",              true);

% =======================================================================
%  Обучение
% =======================================================================
t0 = tic;
[net, info] = trainnet(dsTrain, net, "mse", options);
trainTime = toc(t0);
fprintf("\nОбучение заняло %.1f мин\n", trainTime/60);

% =======================================================================
%  Оценка
% =======================================================================
% Считается в исходных единицах, а не в стандартизованных: «ошибка 0.31» ни
% о чём не говорит, а «центр промахивается на 0.004 кадра» — говорит.
Zhat = minibatchpredict(net, dsTest, MiniBatchSize = opts.miniBatch);
Yhat = double(Zhat) .* sg + mu;
Ytst = double(Y(iTest,:));

mae  = mean(abs(Yhat - Ytst), 1);
disp(array2table(mae, VariableNames = names, RowNames = "ср. модуль ошибки"));

% Угол отдельно: по косинусу с синусом он восстанавливается с точностью до
% периода симметрии, и ошибку осмысленно мерить в градусах исходного
% поворота, а не в отклонении пары чисел.
if c.hasAngle
    mult = 360 / c.symDeg;
    ang  = @(V) atan2(V(:,end), V(:,end-1)) / mult;
    dAng = rad2deg(angdiff(ang(Ytst)*mult, ang(Yhat)*mult)) / mult;
    fprintf("Угол: средняя ошибка %.2f град, медиана %.2f град\n", ...
        mean(abs(dAng)), median(abs(dAng)));
end

% =======================================================================
%  Сохранение
% =======================================================================
if ~exist(cfg.paths.models, "dir"); mkdir(cfg.paths.models); end
modelFile = fullfile(cfg.paths.models, "reg_" + key + ".mat");

model = struct( ...
    "net",        net, ...
    "key",        key, ...
    "names",      names, ...
    "mu",         mu, ...
    "sigma",      sg, ...
    "nReg",       c.nReg, ...
    "maeTest",    mae, ...
    "trainedAt",  datetime("now"), ...
    "trainTime",  trainTime, ...
    "history",    trainHistory(info));

save(modelFile, "model", "-v7.3");
fprintf("Сохранено: %s\n", modelFile);

if nargout == 0
    clear model
end
end


% =======================================================================
function h = trainHistory(info)
%TRAINHISTORY  Кривые обучения в виде обычных чисел.
%
%   Объект deep.TrainingInfo сохранять в модель нельзя. Он тянет за собой
%   окно прогресса обучения: при каждом чтении файла MATLAB воссоздаёт его
%   интерфейс, и поверх приложения выскакивает график — на ровном месте,
%   просто оттого, что регрессор загрузили для распознавания.
%
%   Оставляем то, ради чего info вообще хранилась: потери по итерациям.

h = struct("trainLoss", [], "valLoss", [], "iteration", []);

try
    h.trainLoss = double(info.TrainingHistory.Loss);
    h.iteration = double(info.TrainingHistory.Iteration);
    if ~isempty(info.ValidationHistory)
        h.valLoss = double(info.ValidationHistory.Loss);
    end
catch
    % Состав полей у разных версий MATLAB разный, и терять из-за этого
    % обученную сеть незачем: история — приятное дополнение, не более.
end
end

%CNTRAINCOMMON Общие утилиты обучения: дефолты, загрузка картинок в RAM, сборка trainingOptions.
function out = cnTrainCommon(mode, varargin)

arguments
    mode (1,1) string {mustBeMember(mode, ["defaults", "loadImages", "options"])}
end
arguments (Repeating)
    varargin
end

switch mode
    case "defaults"
        out = applyDefaults(varargin{:});
    case "loadImages"
        out = loadImages(varargin{:});
    case "options"
        out = buildOptions(varargin{:});
end
end

function opts = applyDefaults(opts, cfg, isRegressor)

arguments
    opts        (1,1) struct
    cfg         (1,1) struct
    isRegressor (1,1) logical = false
end

src = cfg.train;
if isRegressor
    src = cfg.regress;
end

if opts.maxEpochs == 0; opts.maxEpochs = src.maxEpochs;        end
if opts.miniBatch == 0; opts.miniBatch = src.miniBatchSize;    end
if opts.learnRate == 0; opts.learnRate = src.initialLearnRate; end
end

function X = loadImages(files, sz, label)

arguments
    files string
    sz    (1,1) double
    label (1,1) string = ""
end

n = numel(files);
X = zeros(sz, sz, 1, n, "uint8");
step = max(5000, round(n / 10));
t0 = tic;

for i = 1:n
    X(:,:,1,i) = imread(files(i));
    if (mod(i, step) == 0 || i == n) && label ~= ""
        pct = round(100 * i / n);
        fprintf("  [%s] Загружено %d/%d (%d%%) [%.1f с]\n", label, i, n, pct, toc(t0));
    end
end
end

function options = buildOptions(opts, cfg, nTrain, valData, isRegressor, useParallelPrep)

arguments
    opts            (1,1) struct
    cfg             (1,1) struct
    nTrain          (1,1) double
    valData
    isRegressor     (1,1) logical = false
    useParallelPrep (1,1) logical = false
end

src = cfg.train;
if isRegressor
    src = cfg.regress;
end

itPerEpoch = max(1, floor(nTrain / opts.miniBatch));
valFreq    = max(1, floor(itPerEpoch / 2));

if opts.plots
    plt = "training-progress";
else
    plt = "none";
end

args = { ...
    "MaxEpochs",            opts.maxEpochs, ...
    "MiniBatchSize",        opts.miniBatch, ...
    "InitialLearnRate",     opts.learnRate, ...
    "LearnRateSchedule",    "piecewise", ...
    "LearnRateDropFactor",  src.lrDropFactor, ...
    "LearnRateDropPeriod",  src.lrDropPeriod, ...
    "L2Regularization",     src.l2Regularization, ...
    "Shuffle",              cfg.train.shuffle, ...
    "ValidationData",       valData, ...
    "ValidationFrequency",  valFreq, ...
    "ValidationPatience",   cfg.train.validationPatience, ...
    "OutputNetwork",        "best-validation-loss", ...
    "ExecutionEnvironment", cfg.train.environment, ...
    "Plots",                plt, ...
    "Verbose",              true, ...
    "VerboseFrequency",     cfg.train.verboseFreq };

if ~isRegressor
    args = [args, {"Metrics", "accuracy"}];
end

if useParallelPrep
    args = [args, {"PreprocessingEnvironment", "parallel"}];
end

options = trainingOptions("adam", args{:});
end

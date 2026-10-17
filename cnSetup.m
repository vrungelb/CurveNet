%CNSETUP  Подключение папок CurveNet к путям MATLAB.
function cnSetup(opts)

arguments
    opts.save    (1,1) logical = false
    opts.startup (1,1) logical = false
    opts.check   (1,1) logical = true
end

root = fileparts(mfilename("fullpath"));

skip = ["dataset", "models", "results", "userTest", "scratch", ".git"];

p = split(string(genpath(root)), pathsep);
p = p(strlength(p) > 0);

keep = true(size(p));
for i = 1:numel(p)
    parts = split(p(i), filesep);
    if any(ismember(parts, skip))
        keep(i) = false;
    end
end
p = p(keep);

addpath(strjoin(p, pathsep));

fprintf("CurveNet подключён: %s\n", root);
fprintf("Папок на пути: %d\n", numel(p));

if opts.check

    need = [ ...
        "cnConfig", "cnClasses", ...
        "cnResampleArc", "cnCurvePoints", "cnSampleParams", ...
        "cnHandDistort", "cnStrokeBreak", "cnNormalize", "cnRasterize", ...
        "cnScribble", "cnRender", "cnVertcatTables", "cnAffineMatrix", "cnRegressorTargets", ...
        "cnBuildDataset", "cnSplitDataset", "cnPreviewDataset", ...
        "cnPredict", "cnPrepareInput", "cnCanvasApp", "cnPreviewRegressors", ...
        "cnTrainClassifier", "cnTrainRegressor", "cnTrainRoseK", "cnNetworkArch", "cnTrainCommon", ...
        "cnTrainAllRegressors", "cnEquationText", "cnLoadDataset", "cnCurveResidual"];

    missing = need(arrayfun(@(f) exist(f, "file") ~= 2, need));
    if isempty(missing)
        fprintf("Все %d функций на месте.\n", numel(need));
    else
        fprintf(2, "Не найдено: %s\n", join(missing, ", "));
    end
end

if opts.save
    savepath;
    fprintf("Пути сохранены через savepath.\n");
end

if opts.startup
    writeStartup(root);
end
end

function writeStartup(root)

up = userpath;
if isempty(up)
    warning("cnSetup:noUserpath", ...
        "Переменная userpath не задана. Скрипт startup.m создать некуда.");
    return
end

file = fullfile(up, "startup.m");
line = sprintf("run(fullfile('%s','cnSetup.m'));", root);

if isfile(file)
    txt = string(fileread(file));
    if contains(txt, "cnSetup")
        fprintf("В %s вызов cnSetup уже есть.\n", file);
        return
    end
    fid = fopen(file, "a");
else
    fid = fopen(file, "w");
end

if fid < 0
    warning("cnSetup:cannotWrite", "Не удалось открыть %s на запись.", file);
    return
end
fprintf(fid, "\n%% CurveNet\n%s\n", line);
fclose(fid);

fprintf("Добавлено в %s — проект будет подключаться при старте MATLAB.\n", file);
end

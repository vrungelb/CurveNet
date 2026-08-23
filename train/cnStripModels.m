function cnStripModels(opts)
%CNSTRIPMODELS  Убирает из сохранённых моделей объект хода обучения.
%
%   cnStripModels
%   cnStripModels(dryRun = true)     только показать, что будет сделано
%
%   Зачем
%   -----
%   В models/*.mat вместе с сетью лежал объект deep.TrainingInfo — история
%   обучения в том виде, в каком её возвращает trainnet. Выяснилось, что он
%   тянет за собой окно прогресса: при каждом чтении файла MATLAB
%   воссоздаёт его интерфейс, и поверх холста выскакивает график. Просто
%   оттого, что регрессор загрузили, чтобы распознать нарисованную кривую.
%
%   Обучающие функции теперь сохраняют вместо объекта обычные числа. Эта
%   утилита нужна для файлов, обученных раньше: она переписывает их на
%   месте, не трогая ни сеть, ни метрики, ни коэффициенты стандартизации.
%   Переобучать ничего не надо.
%
%   Запускается один раз. Повторный вызов безвреден: файлы без объекта
%   пропускаются.
%
%   См. также CNTRAINREGRESSOR, CNTRAINCLASSIFIER, CNFITCURVE.

arguments
    opts.dryRun (1,1) logical = false
end

cfg = cnConfig();
files = dir(fullfile(cfg.paths.models, "*.mat"));

if isempty(files)
    fprintf("В %s нет моделей.\n", cfg.paths.models);
    return
end

nFixed = 0;

for i = 1:numel(files)
    path = fullfile(files(i).folder, files(i).name);

    S = load(path);
    if ~isfield(S, "model")
        continue
    end
    m = S.model;

    if ~isfield(m, "info") || ~isa(m.info, "deep.TrainingInfo")
        fprintf("  %-20s уже чистый\n", files(i).name);
        continue
    end

    m.history = historyOf(m.info);
    m = rmfield(m, "info");

    if opts.dryRun
        fprintf("  %-20s будет очищен\n", files(i).name);
    else
        model = m; %#ok<NASGU>
        save(path, "model", "-v7.3");
        fprintf("  %-20s очищен\n", files(i).name);
    end
    nFixed = nFixed + 1;
end

% Окно, воскрешённое при чтении старых файлов, надо закрыть здесь же: иначе
% оно останется висеть после того, как утилита отработала.
delete(findall(0, "Tag", "DEEPMONITOR_UIFIGURE"));

if opts.dryRun
    fprintf("\nПробный прогон: изменений не внесено, к очистке %d файлов.\n", nFixed);
else
    fprintf("\nОчищено файлов: %d\n", nFixed);
end
end


% =======================================================================
function h = historyOf(info)
%HISTORYOF  Кривые обучения в виде обычных чисел.

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

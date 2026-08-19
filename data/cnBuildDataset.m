function T = cnBuildDataset(opts)
%CNBUILDDATASET  Генерация всего датасета на диск.
%
%   cnBuildDataset()                       весь датасет по cnConfig
%   cnBuildDataset(perClass = 500)         меньше примеров, для пробы
%   cnBuildDataset(classes = "rose")       только один класс
%   cnBuildDataset(overwrite = true)       перезаписать существующий
%   T = cnBuildDataset(...)                вернуть таблицу метаданных
%
%   Что создаётся
%   -------------
%   В корне проекта появляется папка dataset, внутри неё images, а в ней по
%   папке на каждый класс:
%
%       dataset/images/circle/circle_00001.png
%       dataset/images/circle/circle_00002.png
%       ...
%       dataset/images/scribble/...
%       dataset/meta.mat
%
%   Раскладка по папкам выбрана не случайно: imageDatastore берёт метку
%   класса прямо из имени папки, и обучение классификатора сводится к одной
%   строке создания хранилища.
%
%   meta.mat содержит таблицу со строкой на каждую картинку: класс, имя
%   файла и все параметры, с которыми она была сгенерирована. Эта таблица
%   нужна дважды. Сейчас — чтобы разбирать ошибки классификатора: видно, на
%   каких углах, пропорциях и уровнях искажения он промахивается. Потом —
%   как готовая разметка для регрессоров, генерировать данные второй раз не
%   придётся.
%
%   Именованные аргументы
%   ---------------------
%   perClass   сколько примеров на класс (по умолчанию из cnConfig)
%   classes    какие классы генерировать (по умолчанию все)
%   overwrite  перезаписывать уже существующие папки классов
%   parallel   использовать parfor, если есть Parallel Computing Toolbox
%
%   Скорость
%   --------
%   Растеризация идёт напрямую в матрицу, без figure и print, поэтому одна
%   картинка обходится в единицы миллисекунд. Полный датасет из девяноста
%   с лишним тысяч собирается за считанные минуты, а не за полтора часа.
%
%   Воспроизводимость
%   -----------------
%   Все параметры разыгрываются заранее в CNSAMPLEPARAMS от seed, заданного
%   в cnConfig, а сама генерация детерминирована. Один и тот же конфиг даёт
%   побайтово тот же датасет. Поэтому же безопасен parfor: порядок
%   выполнения на результат не влияет.
%
%   См. также CNSAMPLEPARAMS, CNRENDER, CNPREVIEW, CNSPLITDATASET.

arguments
    % Проверку на положительность нельзя ставить в объявлении: MATLAB
    % проверяет и значение по умолчанию тоже, а ноль здесь означает
    % «взять из cnConfig». Проверка сделана ниже, после подстановки.
    opts.perClass  (1,1) double = 0
    opts.classes         = "all"
    opts.overwrite (1,1) logical = false
    opts.parallel  (1,1) logical = true
end

cfg = cnConfig();
if opts.perClass == 0
    opts.perClass = cfg.data.perClass;
end
N = opts.perClass;

if N < 1 || mod(N,1) ~= 0
    error("cnBuildDataset:badPerClass", ...
        "perClass должно быть целым положительным числом, получено %g.", N);
end

% --- какие классы -------------------------------------------------------
C   = cnClasses();
sel = string(opts.classes);
if isscalar(sel) && sel == "all"
    keys = [C.key];
else
    keys = sel;
    for i = 1:numel(keys)
        cnClasses(keys(i));
    end
end

if any(keys == "scribble") && exist("cnScribble", "file") ~= 2
    warning("cnBuildDataset:noScribble", ...
        "cnScribble не найден — класс scribble пропущен.");
    keys(keys == "scribble") = [];
end

% --- параллельность -----------------------------------------------------
usePar = opts.parallel && ~isempty(ver("parallel"));

% --- папки --------------------------------------------------------------
if ~exist(cfg.paths.images, "dir")
    mkdir(cfg.paths.images);
end

fprintf("Датасет: %d классов по %d примеров, всего %d картинок %dx%d\n", ...
    numel(keys), N, numel(keys)*N, cfg.img.size, cfg.img.size);
fprintf("Папка: %s\n\n", cfg.paths.images);

rows  = cell(numel(keys),1);
tAll  = tic;

for j = 1:numel(keys)
    key = keys(j);
    dir_ = fullfile(cfg.paths.images, key);

    if exist(dir_, "dir") && ~opts.overwrite
        if ~isempty(dir(fullfile(dir_, "*." + cfg.img.format)))
            error("cnBuildDataset:exists", ...
                "Папка класса «%s» уже не пуста. Запустите с overwrite = true.", key);
        end
    end
    if exist(dir_, "dir") && opts.overwrite
        rmdir(dir_, "s");
    end
    mkdir(dir_);

    % --- рецепты на весь класс сразу -----------------------------------
    Tj = cnSampleParams(key, N);

    files = strings(N,1);
    for i = 1:N
        files(i) = sprintf("%s_%05d.%s", key, i, cfg.img.format);
    end

    recs = table2struct(Tj);
    ext  = cfg.img.format;
    t0   = tic;

    if usePar
        parfor i = 1:N
            img = cnRender(key, recs(i));
            imwrite(img, fullfile(dir_, files(i)), ext);
        end
    else
        for i = 1:N
            img = cnRender(key, recs(i));
            imwrite(img, fullfile(dir_, files(i)), ext);
            if mod(i, 500) == 0
                fprintf("  %s: %d / %d\n", key, i, N);
            end
        end
    end

    Tj = addvars(Tj, repmat(key, N, 1), files, ...
        NewVariableNames = ["class","file"], Before = 1);
    rows{j} = Tj;

    fprintf("  %-24s %6d шт.  %6.1f c\n", key, N, toc(t0));
end

% --- метаданные ---------------------------------------------------------
Tbl = vertcatTables(rows);

meta = struct();
meta.table     = Tbl;
meta.perClass  = N;
meta.classes   = keys;
meta.imageSize = cfg.img.size;
meta.builtAt   = datetime("now");
meta.config    = cfg;

save(cfg.paths.meta, "meta");

fprintf("\nГотово за %.1f c. Метаданные: %s\n", toc(tAll), cfg.paths.meta);

% Выход отдаётся только по явному запросу: иначе вызов без точки с запятой
% вывалит таблицу на десятки тысяч строк в консоль.
if nargout >= 1
    T = Tbl;
end
end


% =======================================================================
function T = vertcatTables(rows)
%VERTCATTABLES  Склейка таблиц с разным набором столбцов.
%
%   У разных классов свои параметры формы, поэтому столбцы не совпадают.
%   Недостающие заполняются пропусками подходящего типа: строковый столбец
%   и числовой NaN вертикально склеить нельзя.

rows = rows(~cellfun(@isempty, rows));
if isempty(rows)
    T = table();
    return
end

names = string.empty(1,0);
for i = 1:numel(rows)
    names = union(names, string(rows{i}.Properties.VariableNames), "stable");
end

for i = 1:numel(rows)
    h    = height(rows{i});
    miss = setdiff(names, string(rows{i}.Properties.VariableNames), "stable");
    for m = miss
        if isstring(protoOf(rows, m))
            rows{i}.(m) = repmat(string(missing), h, 1);
        else
            rows{i}.(m) = nan(h, 1);
        end
    end
    rows{i} = rows{i}(:, names);
end
T = vertcat(rows{:});
end


% =======================================================================
function v = protoOf(rows, name)
%PROTOOF  Образец значения столбца из первой таблицы, где он встречается.

v = NaN;
for i = 1:numel(rows)
    if ismember(name, string(rows{i}.Properties.VariableNames))
        v = rows{i}.(name)(1);
        return
    end
end
end
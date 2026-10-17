%CNBUILDDATASET  Генерация датасета на диск.
function T = cnBuildDataset(opts)

arguments

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
        "Число примеров на класс должно быть целым и положительным.");
end

keys = unique([cnClasses(opts.classes).key], "stable");

if any(keys == "scribble") && exist("cnScribble", "file") == 0
    warning("cnBuildDataset:noScribble", ...
        "Файл cnScribble не найден, класс scribble пропущен.");
    keys(keys == "scribble") = [];
end

if isempty(keys)
    error("cnBuildDataset:noClasses", "Нет классов для генерации.");
end

if ~opts.overwrite
    busy = strings(0,1);
    for j = 1:numel(keys)
        d = fullfile(cfg.paths.images, keys(j));
        if exist(d, "dir") && ~isempty(dir(fullfile(d, "*." + cfg.img.format)))
            busy(end+1,1) = keys(j);
        end
    end
    if ~isempty(busy)
        error("cnBuildDataset:exists", ...
            "Папки классов не пусты, используйте overwrite = true. Классы %s.", ...
            join(busy(:).', ", "));
    end
end

usePar = opts.parallel && ~isempty(ver("parallel"));

if ~exist(cfg.paths.images, "dir")
    mkdir(cfg.paths.images);
end

fprintf("Генерация %d классов по %d примеров, всего %d картинок %dx%d\n", ...
    numel(keys), N, numel(keys)*N, cfg.img.size, cfg.img.size);
fprintf("Папка %s\n\n", cfg.paths.images);

rows  = cell(numel(keys),1);
tAll  = tic;

for j = 1:numel(keys)
    key  = keys(j);
    dir_ = fullfile(cfg.paths.images, key);

    if exist(dir_, "dir") && opts.overwrite
        rmdir(dir_, "s");
    end

    if ~exist(dir_, "dir")
        mkdir(dir_);
    end

    Tj = cnSampleParams(key, N);

    files = strings(N,1);
    for i = 1:N
        files(i) = sprintf("%s_%05d.%s", key, i, cfg.img.format);
    end

    recs   = table2struct(Tj);
    ext    = cfg.img.format;
    ox     = zeros(N, 1);
    oy     = zeros(N, 1);
    nScale = zeros(N, 1);
    t0     = tic;

    if usePar
        parfor i = 1:N
            [img, ~, tf] = cnRender(key, recs(i));
            ox(i)     = tf.origin(1);
            oy(i)     = tf.origin(2);
            nScale(i) = tf.normScale;
            imwrite(img, fullfile(dir_, files(i)), ext);
        end
    else
        for i = 1:N
            [img, ~, tf] = cnRender(key, recs(i));
            ox(i)     = tf.origin(1);
            oy(i)     = tf.origin(2);
            nScale(i) = tf.normScale;
            imwrite(img, fullfile(dir_, files(i)), ext);
            if mod(i, 500) == 0
                fprintf("  %s %d из %d\n", key, i, N);
            end
        end
    end

    Tj.originX   = ox;
    Tj.originY   = oy;
    Tj.normScale = nScale;

    Tj = addvars(Tj, repmat(key, N, 1), files, ...
        NewVariableNames = ["class","file"], Before = 1);
    rows{j} = Tj;

    fprintf("  %-24s %6d шт.  %6.1f c\n", key, N, toc(t0));
end

Tbl = cnVertcatTables(rows);

if isfile(cfg.paths.meta)
    old  = load(cfg.paths.meta, "meta");
    keep = ~ismember(old.meta.table.class, keys);
    if any(keep)
        rest = old.meta.table(keep,:);

        cnt = groupcounts(rest, "class");
        if any(cnt.GroupCount ~= N)
            warning("cnBuildDataset:perClassMismatch", ...
                "У остальных классов число примеров не равно %d, классы несбалансированы.", N);
        end

        Tbl = cnVertcatTables({rest; Tbl});
    end
end

[~, pos] = ismember(Tbl.class, [cnClasses().key]);
[~, srt] = sort(pos);
Tbl = Tbl(srt,:);

meta = struct();
meta.table     = Tbl;
meta.perClass  = N;
meta.classes   = unique(Tbl.class, "stable");
meta.imageSize = cfg.img.size;
meta.builtAt   = datetime("now");
meta.config    = cfg;

save(cfg.paths.meta, "meta");

fprintf("\nГотово за %.1f c, метаданные сохранены в %s\n", toc(tAll), cfg.paths.meta);

if isfile(cfg.paths.split)
    fprintf("Разбиение устарело, запустите cnSplitDataset.\n");
end

if nargout >= 1
    T = Tbl;
end
end


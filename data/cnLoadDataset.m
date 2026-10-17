%CNLOADDATASET Загрузка метаданных датасета и разбиения с проверкой целостности.
function [T, S, cfg] = cnLoadDataset()

cfg = cnConfig();

if ~isfile(cfg.paths.meta)
    error("cnLoadDataset:noMeta", ...
        "Файл метаданных %s не найден. Запустите cnBuildDataset.", cfg.paths.meta);
end

if ~isfile(cfg.paths.split)
    error("cnLoadDataset:noSplit", ...
        "Файл разбиения %s не найден. Сначала запустите cnSplitDataset.", cfg.paths.split);
end

Lm = load(cfg.paths.meta,  "meta");
Ls = load(cfg.paths.split, "split");
T  = Lm.meta.table;
S  = Ls.split;

% Проверка на рассинхронизацию между генерацией и разбиением
if height(T) ~= numel(S.assign)
    error("cnLoadDataset:mismatch", ...
        "Разбиение не соответствует датасету: %d строк в meta, %d в split. Перезапустите cnSplitDataset.", ...
        height(T), numel(S.assign));
end

if ~isequal(string(S.class), string(T.class)) || ~isequal(string(S.file), string(T.file))
    error("cnLoadDataset:splitStale", ...
        "Разбиение построено для другого датасета. Перезапустите cnSplitDataset.");
end

% Проверка физического наличия картинок на диске
if height(T) > 0
    firstImg = fullfile(cfg.paths.images, T.class(1), T.file(1));
    if ~isfile(firstImg)
        error("cnLoadDataset:missingImages", ...
            "Файл %s не найден. Датасет и метаданные разошлись.", firstImg);
    end
end
end
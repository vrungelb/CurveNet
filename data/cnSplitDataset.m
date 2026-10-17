%CNSPLITDATASET  Разбиение датасета на train/val/test.
function S = cnSplitDataset(opts)

arguments
    opts.fractions double        = []
    opts.seed      (1,1) double  = NaN
    opts.quiet     (1,1) logical = false
end

cfg = cnConfig();

if isempty(opts.fractions)
    opts.fractions = cfg.data.split;
end
if isnan(opts.seed)
    opts.seed = cfg.data.seed;
end

f = opts.fractions(:).';
if numel(f) ~= 3
    error("cnSplitDataset:badFractions", ...
        "Нужны ровно три доли: обучение, валидация, тест. Получено %d.", numel(f));
end
if any(f <= 0) || abs(sum(f) - 1) > 1e-9
    error("cnSplitDataset:badFractions", ...
        "Доли должны быть положительными и в сумме давать единицу, получено [%g %g %g].", f);
end

if ~isfile(cfg.paths.meta)
    error("cnSplitDataset:noMeta", ...
        "Не найден %s. Сначала выполните cnBuildDataset.", cfg.paths.meta);
end

L = load(cfg.paths.meta, "meta");
T = L.meta.table;
N = height(T);

keys = unique(T.class, "stable");
rs   = RandStream("threefry", Seed = opts.seed);

assign = strings(N,1);

for j = 1:numel(keys)
    idx = find(T.class == keys(j));
    m   = numel(idx);

    idx = idx(randperm(rs, m));

    c = round(cumsum(f) * m);
    c = min(max(c, 0), m);
    c(end) = m;

    assign(idx(1      : c(1))) = "train";
    assign(idx(c(1)+1 : c(2))) = "val";
    assign(idx(c(2)+1 : c(3))) = "test";
end

if any(assign == "")
    error("cnSplitDataset:unassigned", ...
        "%d строк остались без части — проверьте доли.", sum(assign == ""));
end

out           = struct();
out.assign    = categorical(assign, ["train","val","test"]);
out.train     = find(out.assign == "train");
out.val       = find(out.assign == "val");
out.test      = find(out.assign == "test");
out.fractions = f;
out.seed      = opts.seed;
out.class     = T.class;
out.file      = T.file;
out.createdAt = datetime("now");

split = out;
save(cfg.paths.split, "split");

if ~opts.quiet
    cnt = zeros(numel(keys), 3);
    for j = 1:numel(keys)
        m = T.class == keys(j);
        cnt(j,1) = sum(m & out.assign == "train");
        cnt(j,2) = sum(m & out.assign == "val");
        cnt(j,3) = sum(m & out.assign == "test");
    end
    rep = table(keys, cnt(:,1), cnt(:,2), cnt(:,3), sum(cnt,2), ...
        VariableNames = ["класс","обучение","валидация","тест","всего"]);
    disp(rep)
    fprintf("Итого: %d обучение, %d валидация, %d тест.\nСохранено: %s\n", ...
        numel(out.train), numel(out.val), numel(out.test), cfg.paths.split);
end

if nargout >= 1
    S = out;
end
end

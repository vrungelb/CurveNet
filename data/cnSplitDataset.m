function S = cnSplitDataset(opts)
%CNSPLITDATASET  Разбиение датасета на обучение, валидацию и тест.
%
%   cnSplitDataset()                       разбить по долям из cnConfig
%   cnSplitDataset(fractions = [.8 .1 .1]) свои доли
%   cnSplitDataset(seed = 7)               другое разбиение
%   S = cnSplitDataset(...)                вернуть структуру разбиения
%
%   Читает dataset/meta.mat, раскладывает строки по трём частям и
%   сохраняет результат в dataset/split.mat. Сами картинки не трогаются и
%   никуда не копируются — хранятся только номера строк.
%
%   Зачем три части, а не две
%   -------------------------
%   Обучающая — на ней сеть подкручивает веса.
%
%   Валидационная — сеть на ней не учится никогда. Мы прогоняем её по ходу
%   обучения и смотрим, не начала ли сеть зубрить конкретные примеры вместо
%   того, чтобы обобщать. Как только точность на валидации перестала расти,
%   обучение пора останавливать. По ней же подбираются число слоёв, темп
%   обучения и прочие настройки.
%
%   Тестовая — не трогается до самого конца, прогоняется один раз, когда всё
%   готово. Отдельно от валидации она нужна потому, что валидацию мы,
%   подбирая настройки, косвенно подсмотрели, и она начинает завышать
%   оценку. Только тест даёт честную цифру для отчёта.
%
%   Стратификация
%   -------------
%   Каждый класс режется отдельно и в тех же пропорциях. При случайном
%   делении общей кучи могло бы выйти, что в тест попало девятьсот
%   окружностей и двести роз — и тогда итоговая точность отражала бы в
%   основном то, как сеть узнаёт окружности.
%
%   Разбиение детерминировано: тот же seed даёт то же разбиение. Это
%   обязательное условие честности. Если пересобирать его при каждом
%   запуске, тестовые примеры будут постепенно просачиваться в обучение, и
%   итоговая цифра окажется завышенной, причём незаметно.
%
%   См. также CNBUILDDATASET, CNCONFIG.

arguments
    % Размер не проверяем в самом объявлении: MATLAB проверяет и значение по
    % умолчанию тоже, а пустой массив под «вектор из трёх» не подходит.
    % Проверка сделана ниже, после подстановки значения из конфига.
    opts.fractions double  = []
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

% --- метаданные ---------------------------------------------------------
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

    % Границы считаются по накопленной доле, а не по каждой доле отдельно:
    % так сумма трёх частей всегда равна m, без потерянных или задвоенных
    % примеров из-за округления.
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

% --- результат ----------------------------------------------------------
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

split = out; %#ok<NASGU>
save(cfg.paths.split, "split");

% --- отчёт --------------------------------------------------------------
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

% Выход отдаётся только по явному запросу: иначе вызов без точки с запятой
% вывалит всю структуру в консоль.
if nargout >= 1
    S = out;
end
end

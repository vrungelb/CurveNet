function R = cnCheckRegressor(key, opts)
%CNCHECKREGRESSOR  Проверка регрессора: предсказанная кривая поверх картинки.
%
%   cnCheckRegressor("ellipse")                 12 случайных примеров теста
%   cnCheckRegressor("parabola", n = 24)        больше примеров
%   cnCheckRegressor("hyperbola", worst = true) самые неудачные
%   R = cnCheckRegressor(key, show = false)     только таблица ошибок
%
%   Зачем это нужно
%   ---------------
%   Средний модуль ошибки по выходам сети — величина, по которой нельзя
%   принять решение. «Ошибка 0.10 по логарифму вытянутости» не отвечает ни
%   насколько это много, ни как выглядит на картинке, ни одинаково ли плохо
%   везде или всё число делают несколько провальных примеров.
%
%   Поэтому здесь два ответа на один вопрос: таблица в человеческих единицах
%   и картинки с наложенной кривой. Красное — предсказание сети, зелёное —
%   разметка.
%
%   Что считать успехом
%   -------------------
%   Не совпадение до пикселя. Регрессор обязан попасть в правильную
%   окрестность, точные числа даёт подгонка. Красная вдоль линии с
%   отставанием на толщину штриха — хорошо. Красная поперёк или вдвое
%   меньшая — провал, подгонка из такой точки не выберется.
%
%   Зелёная не обязана точно лежать на линии: она гладкая, а линия
%   деформирована, и проходит зелёная как бы сквозь дрожание. Красная местами
%   садится плотнее — сеть усредняет деформацию по тысячам примеров, а
%   разметка строится чисто геометрически. Это признак, что сеть учится.
%
%   Проверка идёт по тестовой части, то есть по картинкам, которых сеть не
%   видела.
%
%   См. также CNTRAINREGRESSOR, CNREGRESSIONTARGETS, CNCURVESHAPE.

arguments
    key        (1,1) string
    opts.n     (1,1) double {mustBeInteger, mustBePositive} = 12
    opts.worst (1,1) logical = false
    opts.show  (1,1) logical = true
end

cfg = cnConfig();
c   = cnClasses(key);
N   = cfg.img.size;

modelFile = fullfile(cfg.paths.models, "reg_" + key + ".mat");
if ~isfile(modelFile)
    error("cnCheckRegressor:noModel", ...
        "Нет %s. Сначала cnTrainRegressor(""%s"").", modelFile, key);
end
M = load(modelFile, "model").model;

T = load(cfg.paths.meta,  "meta").meta.table;
S = load(cfg.paths.split, "split").split;

rows = find(string(T.class) == key);
if isempty(rows)
    error("cnCheckRegressor:noRows", "В датасете нет класса «%s».", key);
end

assign = string(S.assign(rows));
files  = fullfile(cfg.paths.images, key, T.file(rows));
iTest  = find(assign == "test");

Y = cnRegressionTargets(key, verbose = false);

% --- предсказание --------------------------------------------------------
imgs = zeros(N, N, 1, numel(iTest), "single");
for i = 1:numel(iTest)
    imgs(:,:,1,i) = single(imread(files(iTest(i))));
end

Z    = minibatchpredict(M.net, imgs);
Yhat = double(Z) .* M.sigma + M.mu;
Ytru = Y(iTest, :);

% --- ошибки в человеческих единицах --------------------------------------
% Число столбцов у классов разное, поэтому таблица собирается по факту: у
% окружности не бывает ни формы, ни угла, и пустые колонки были бы враньём.
dCenter = hypot(Yhat(:,1) - Ytru(:,1), Yhat(:,2) - Ytru(:,2)) * (N-1);
dScale  = 100 * abs(exp(Yhat(:,3) - Ytru(:,3)) - 1);

R = table(dCenter, dScale, VariableNames = ["центр, пикс", "размер, %"]);

nShape = numel(c.shape);
for i = 1:nShape
    col = 3 + i;
    if c.shape(i).scale == "log"
        e = 100 * abs(exp(Yhat(:,col) - Ytru(:,col)) - 1);
        nm = c.shape(i).name + ", %";
    else
        % Линейный параметр в процентах от истинного значения: абсолютная
        % ошибка halfLength ничего не говорит, пока не знаешь, был он
        % единицей или четвёркой.
        e = 100 * abs(Yhat(:,col) - Ytru(:,col)) ./ max(abs(Ytru(:,col)), eps);
        nm = c.shape(i).name + ", %";
    end
    R.(nm) = e;
end

if c.hasAngle
    mult = 360 / c.symDeg;
    aTru = atan2(Ytru(:,end), Ytru(:,end-1));
    aHat = atan2(Yhat(:,end), Yhat(:,end-1));
    R.("угол, град") = abs(rad2deg(atan2(sin(aHat-aTru), cos(aHat-aTru)))) / mult;
end

fprintf("\nРегрессор «%s», тестовая часть, %d примеров\n", key, numel(iTest));
disp(array2table( ...
    [mean(R{:,:}); median(R{:,:}); prctile(R{:,:}, 90); max(R{:,:})], ...
    VariableNames = R.Properties.VariableNames, ...
    RowNames = ["среднее","медиана","90-й проц","макс"]));

if ~opts.show
    if nargout == 0; clear R; end
    return
end

% --- картинки ------------------------------------------------------------
% Веса в оценке уравнивают величины разной природы: доля кадра, относительная
% ошибка и градусы сами по себе не складываются.
score = dCenter/(N-1)*10 + dScale/100;
for i = 4:width(R)
    score = score + R{:,i}/100;
end

if opts.worst
    [~, ord] = sort(score, "descend");
else
    ord = randperm(numel(iTest));
end
sel = ord(1:min(opts.n, numel(ord)));

figure(Name = "Регрессор: " + key, Color = "w");
t = tiledlayout("flow", TileSpacing = "compact", Padding = "compact");
title(t, key + " — красным предсказание сети, зелёным разметка");

for k = 1:numel(sel)
    i = sel(k);
    nexttile
    imshow(imgs(:,:,1,i), [0 255]); hold on

    drawCurve(key, Ytru(i,:), c, cfg, N, "g");
    drawCurve(key, Yhat(i,:), c, cfg, N, "r");

    txt = sprintf("ц %.1f  р %.0f%%", dCenter(i), dScale(i));
    for j = 4:width(R)
        txt = txt + sprintf("  %.0f%%", R{i,j});
    end
    if c.hasAngle
        txt = txt + sprintf("  у %.1f°", R.("угол, град")(i));
    end
    title(txt, FontSize = 8);
end

if nargout == 0
    clear R
end
end


% =======================================================================
function drawCurve(key, y, c, cfg, N, col)
%DRAWCURVE  Кривая по целевому вектору, в пиксельных координатах.
%
%   Ось y переворачивается: в кадре она вверх, в растре вниз. Тот же перевод
%   делает CNRASTERIZE, и если ошибиться, кривая ляжет зеркально — и вы
%   будете искать несуществующую ошибку в сети.

fill = 1 - 2*cfg.img.pad;

ctr = 0.5 + y(1:2);
ext = fill * exp(y(3));

nShape = numel(c.shape);
shape  = zeros(1, nShape);
for i = 1:nShape
    v = y(3+i);
    if c.shape(i).scale == "log"
        v = exp(v);
    end
    shape(i) = v;
end

if c.hasAngle
    th = atan2(y(end), y(end-1)) / (360 / c.symDeg);
else
    th = 0;
end

S = cnCurveShape(key, ctr, ext, shape, th, nPoints = 400);

for i = 1:numel(S.strokes)
    P = S.strokes{i};
    plot(P(:,1)*(N-1) + 1, (1 - P(:,2))*(N-1) + 1, col, LineWidth = 1.2);
end
end

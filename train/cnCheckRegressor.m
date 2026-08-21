function R = cnCheckRegressor(key, opts)
%CNCHECKREGRESSOR  Проверка регрессора: предсказанная кривая поверх картинки.
%
%   cnCheckRegressor("ellipse")                 12 случайных примеров теста
%   cnCheckRegressor("circle", n = 24)          больше примеров
%   cnCheckRegressor("ellipse", worst = true)   самые неудачные, а не случайные
%   R = cnCheckRegressor("ellipse", show = false)   только таблица ошибок
%
%   Зачем это нужно
%   ---------------
%   Средний модуль ошибки по выходам сети — величина, по которой нельзя
%   принять решение. «Ошибка 0.10 по логарифму вытянутости» не отвечает на
%   вопрос, годится регрессор или нет: непонятно ни насколько это много, ни
%   как оно выглядит на картинке, ни одинаково ли плохо везде или всё число
%   делают несколько провальных примеров.
%
%   Поэтому здесь два разных ответа на один вопрос. Первый — таблица ошибок в
%   человеческих единицах: центр в пикселях, размер и форма в процентах, угол
%   в градусах. Второй — картинки с наложенной кривой, потому что
%   окончательное суждение о геометрии выносится глазом.
%
%   Красным рисуется предсказание сети, зелёным — истинная кривая из
%   разметки. Там, где они расходятся, видно и насколько, и в чём именно:
%   промах по центру, по размеру или по повороту выглядят по-разному.
%
%   Что считать успехом
%   -------------------
%   Не совпадение до пикселя. Регрессор обязан лишь попасть в правильную
%   окрестность, а точные числа потом даёт уточняющая подгонка по самим
%   точкам рисунка. Красная кривая, идущая вдоль линии с небольшим
%   отставанием по толщине штриха, — это хороший результат. Красная кривая,
%   повёрнутая поперёк или вдвое меньшая, — это провал, и никакая подгонка её
%   не спасёт, потому что нелинейный поиск стартует именно отсюда.
%
%   Зелёная кривая не обязана в точности лежать на нарисованной линии. Она
%   гладкая, а линия деформирована, и проходит зелёная как бы сквозь
%   дрожание. Более того, красная местами садится на линию плотнее зелёной:
%   сеть усредняет деформацию по тысячам примеров, а разметка строится чисто
%   геометрически. Это признак того, что сеть учится, а не запоминает.
%
%   Проверка идёт по тестовой части разбиения, то есть по картинкам, которых
%   сеть при обучении не видела.
%
%   См. также CNTRAINREGRESSOR, CNREGRESSIONTARGETS, CNFITCURVE, CNCLASSES.

arguments
    key        (1,1) string
    opts.n     (1,1) double {mustBeInteger, mustBePositive} = 12
    opts.worst (1,1) logical = false
    opts.show  (1,1) logical = true
end

cfg = cnConfig();
c   = cnClasses(key);
N   = cfg.img.size;

% =======================================================================
%  Модель, данные, разбиение
% =======================================================================
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

% =======================================================================
%  Предсказание
% =======================================================================
% Картинки читаются одним куском: тестовая часть невелика, а работать с
% массивом проще, чем с хранилищем, — он нужен и для показа.
imgs = zeros(N, N, 1, numel(iTest), "single");
for i = 1:numel(iTest)
    imgs(:,:,1,i) = single(imread(files(iTest(i))));
end

Z    = minibatchpredict(M.net, imgs);
Yhat = double(Z) .* M.sigma + M.mu;
Ytru = Y(iTest, :);

% =======================================================================
%  Ошибки в человеческих единицах
% =======================================================================
% Число столбцов у разных классов разное, поэтому таблица собирается по
% факту: у окружности не бывает ни формы, ни угла, и печатать для неё пустые
% колонки было бы враньём.
dCenter = hypot(Yhat(:,1) - Ytru(:,1), Yhat(:,2) - Ytru(:,2)) * (N-1);
dScale  = 100 * abs(exp(Yhat(:,3) - Ytru(:,3)) - 1);

R = table(dCenter, dScale, VariableNames = ["центр, пикс", "размер, %"]);

nShape = numel(c.shape);
for i = 1:nShape
    col = 3 + i;
    if c.shape(i).scale == "log"
        e = 100 * abs(exp(Yhat(:,col) - Ytru(:,col)) - 1);
    else
        e = abs(Yhat(:,col) - Ytru(:,col));
    end
    R.(c.shape(i).name) = e;
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

% =======================================================================
%  Картинки
% =======================================================================
if ~opts.show
    if nargout == 0; clear R; end
    return
end

% Показывать среднее по больнице бессмысленно: интересны либо честная
% случайная выборка, либо худшие случаи. Второе полезнее при разборе, потому
% что провалы обычно однотипны и подсказывают причину.
%
% Веса в оценке подобраны так, чтобы величины разной природы стали
% сопоставимы: доля кадра, относительная ошибка и градусы сами по себе
% складываться не могут.
score = dCenter/(N-1)*10 + dScale/100;
for i = 1:nShape
    score = score + R.(c.shape(i).name)/100;
end
if c.hasAngle
    score = score + R.("угол, град")/45;
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

    plotCurve(curveInFrame(key, Ytru(i,:), c, cfg), N, "g", 1.2);
    plotCurve(curveInFrame(key, Yhat(i,:), c, cfg), N, "r", 1.2);

    txt = sprintf("ц %.1f  р %.0f%%", dCenter(i), dScale(i));
    for j = 1:nShape
        txt = txt + sprintf("  ф %.0f%%", R.(c.shape(j).name)(i));
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
function P = curveInFrame(key, y, c, cfg)
%CURVEINFRAME  Точки кривой в координатах кадра по вектору параметров.
%
%   Обратное к тому, что делает CNREGRESSIONTARGETS: там из кривой получали
%   числа, здесь из чисел получаем кривую.

fill = 1 - 2*cfg.img.pad;

ctr = 0.5 + y(1:2);
ext = fill * exp(y(3));

t = linspace(0, 2*pi, 400).';

switch key
    case "circle"
        U = [cos(t), sin(t)];

    case "ellipse"
        elong = exp(y(4));
        th    = atan2(y(end), y(end-1)) / (360 / c.symDeg);
        U  = [cos(t), sin(t)/elong];
        Rm = [cos(th), -sin(th); sin(th), cos(th)];
        U  = U * Rm.';

    otherwise
        error("cnCheckRegressor:notImplemented", ...
            "Нет ветви для класса «%s».", key);
end

% Габаритная рамка повёрнутой кривой не равна её полуосям, поэтому масштаб
% подбирается по фактическому размаху — ровно так же, как ext считался при
% построении целей.
k = ext / max(max(U,[],1) - min(U,[],1));
P = ctr + U * k;
end


% =======================================================================
function plotCurve(P, N, col, lw)
%PLOTCURVE  Кривая из координат кадра в пиксельные и на экран.
%
%   Ось y переворачивается: в кадре она смотрит вверх, в растре вниз. Тот же
%   перевод делает CNRASTERIZE, и если здесь ошибиться, кривая ляжет
%   зеркально и вы будете искать несуществующую ошибку в сети.

x = P(:,1) * (N-1) + 1;
y = (1 - P(:,2)) * (N-1) + 1;
plot(x, y, col, LineWidth = lw);
end

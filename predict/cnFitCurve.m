function F = cnFitCurve(key, img, tf, opts)
%CNFITCURVE  Параметры кривой по картинке: регрессор плюс обратный пересчёт.
%
%   F = CNFITCURVE(key, img, tf)          картинка и преобразование кадра
%   F = CNFITCURVE(..., reload = true)    перечитать сеть с диска
%
%   Аргумент tf — поле info.tf из CNPREPAREINPUT, то самое преобразование,
%   которым рисунок вписывали в кадр. Без него выход регрессора остаётся
%   набором чисел в системе координат сети и на холст его не положить.
%
%   Поля результата
%   ---------------
%   ok, message            удалось ли, и почему нет
%   points, params         кривая и её параметры в координатах холста
%   equation, general      уравнение в двух видах
%   raw                    выход сети после снятия стандартизации
%
%   Две системы координат
%   ---------------------
%   Сеть работает в кадре: начало в левом нижнем углу, сторона равна
%   единице, ось y вверх. Холст — свой. Между ними стоит tf, и переход
%   туда-обратно самое вероятное место ошибки в этом файле. Признак того,
%   что перепутано: кривая ложится зеркально или вчетверо меньше рисунка.
%
%       прямое:   q = (p − tf.center)/tf.scale + 0.5 + tf.offset
%       обратное: p = (q − 0.5 − tf.offset)*tf.scale + tf.center
%
%   Поворота в переходе нет, только сдвиг и равномерное растяжение. Значит
%   угол переносится как есть, а размеры умножаются на tf.scale.
%
%   Про точность
%   ------------
%   Это приближение, а не ответ. Радиус окружности сеть завышает процентов
%   на пять: поправку к раздутой дрожанием габаритной рамке она выдаёт не
%   полностью, потому что среднеквадратичная ошибка вознаграждает
%   осторожную оценку. Уточняет числа CNREFINEFIT.
%
%   См. также CNREFINEFIT, CNCURVESHAPE, CNPREDICT, CNCANVASAPP.

arguments
    key           (1,1) string
    img
    tf            (1,1) struct
    opts.reload   (1,1) logical = false
    opts.nPoints  (1,1) double {mustBeInteger, mustBePositive} = 600
end

F = struct("ok", false, "message", "", ...
           "points", zeros(0,2), "params", struct(), ...
           "equation", "", "general", "", "raw", []);

cfg = cnConfig();
c   = cnClasses(key);

if ~ismember(key, ["circle", "ellipse"])
    F.message = sprintf("Для «%s» регрессор не обучен.", c.name);
    return
end

model = loadRegressor(key, opts.reload);
if isempty(model)
    F.message = "Регрессор не обучен.";
    return
end

% --- выход сети ---------------------------------------------------------
z = predict(model.net, single(img));
y = double(z(:)).' .* model.sigma + model.mu;
F.raw = y;

fill     = 1 - 2*cfg.img.pad;
ctrFrame = 0.5 + y(1:2);
extFrame = fill * exp(y(3));

switch key
    case "circle"
        elong = 1;
        th    = 0;
    case "ellipse"
        elong = exp(y(4));
        th    = atan2(y(end), y(end-1)) / (360 / c.symDeg);
end

% Габаритная рамка повёрнутой кривой не совпадает с полуосями, поэтому
% масштаб берётся по фактическому размаху — так же, как extFrame считался
% при построении целей. Иначе кривая выйдет систематически крупнее.
t = linspace(0, 2*pi, 720).';
U = [cos(t), sin(t)/elong] * [cos(th), sin(th); -sin(th), cos(th)];
k = extFrame / max(max(U,[],1) - min(U,[],1));

% --- перенос на холст ----------------------------------------------------
off = [0 0];
if isfield(tf, "offset"); off = tf.offset; end

ctr = (ctrFrame - 0.5 - off) * tf.scale + tf.center;
a   = k * tf.scale;
b   = a / elong;

S = cnCurveShape(key, ctr, a, b, th, nPoints = opts.nPoints);

F.points   = S.points;
F.params   = S.params;
F.equation = S.equation;
F.general  = S.general;
F.ok       = true;
end


% =======================================================================
function model = loadRegressor(key, reload)
%LOADREGRESSOR  Чтение регрессора с кэшированием.
%
%   Чтение с диска дольше самого предсказания, а на холсте ответ должен
%   быть мгновенным. Отсутствие файла ошибкой не считается: регрессор
%   обучен не для всех классов.

persistent cache cacheKey

if reload || isempty(cacheKey) || cacheKey ~= key
    cfg  = cnConfig();
    file = fullfile(cfg.paths.models, "reg_" + key + ".mat");
    if ~isfile(file)
        model = [];
        return
    end
    cache    = load(file, "model").model;
    cacheKey = key;
end
model = cache;
end

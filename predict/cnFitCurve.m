function F = cnFitCurve(key, img, tf, opts)
%CNFITCURVE  Параметры кривой по картинке: регрессор плюс обратный пересчёт.
%
%   F = CNFITCURVE(key, img, tf)
%   F = CNFITCURVE(..., reload = true)
%
%   tf — поле info.tf из CNPREPAREINPUT, преобразование, которым рисунок
%   вписывали в кадр. Без него выход регрессора остаётся набором чисел в
%   системе координат сети.
%
%   Поля результата
%   ---------------
%   ok, message         удалось ли, и почему нет
%   strokes, points     кривая в координатах холста
%   params              производные величины: полуоси, фокальный параметр, угол
%   equation, general   уравнение в двух видах
%   frame               центр, размер, форма и угол в координатах кадра —
%                       начальная точка для CNREFINEFIT
%   raw                 выход сети после снятия стандартизации
%
%   Две системы координат
%   ---------------------
%   Сеть работает в кадре: начало в левом нижнем углу, сторона единица, ось y
%   вверх. Холст свой. Между ними tf, и переход туда-обратно — самое
%   вероятное место ошибки. Признак, что перепутано: кривая ложится зеркально
%   или вчетверо меньше рисунка.
%
%       прямое:   q = (p − tf.center)/tf.scale + 0.5 + tf.offset
%       обратное: p = (q − 0.5 − tf.offset)·tf.scale + tf.center
%
%   Поворота в переходе нет, только сдвиг и равномерное растяжение: угол
%   переносится как есть, размеры умножаются на tf.scale.
%
%   Про точность
%   ------------
%   Это приближение, а не ответ. Радиус окружности сеть завышает процентов на
%   пять: поправку к раздутой дрожанием рамке она выдаёт не полностью, потому
%   что среднеквадратичная ошибка вознаграждает осторожную оценку. Уточняет
%   числа CNREFINEFIT.
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
           "strokes", {{}}, "points", zeros(0,2), "params", struct(), ...
           "equation", "", "general", "", "frame", struct(), "raw", []);

cfg = cnConfig();
c   = cnClasses(key);

model = loadRegressor(key, opts.reload);
if isempty(model)
    F.message = sprintf("Для «%s» регрессор не обучен.", c.name);
    return
end

% --- выход сети ---------------------------------------------------------
z = predict(model.net, single(img));
y = double(z(:)).' .* model.sigma + model.mu;
F.raw = y;

% --- разбор вектора -----------------------------------------------------
fill     = 1 - 2*cfg.img.pad;
ctrFrame = 0.5 + y(1:2);
extFrame = fill * exp(y(3));

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

% --- перенос на холст ----------------------------------------------------
off = [0 0];
if isfield(tf, "offset"); off = tf.offset; end

ctr = (ctrFrame - 0.5 - off) * tf.scale + tf.center;
ext = extFrame * tf.scale;

S = cnCurveShape(key, ctr, ext, shape, th, nPoints = opts.nPoints);

F.strokes  = S.strokes;
F.points   = S.points;
F.params   = S.params;
F.equation = S.equation;
F.general  = S.general;

% Начальная точка для подгонки отдаётся в координатах холста: подгонка
% работает с точками рисунка, а они тоже холстовые.
F.frame = struct("center", ctr, "ext", ext, "shape", shape, "th", th);
F.ok    = true;
end


% =======================================================================
function model = loadRegressor(key, reload)
%LOADREGRESSOR  Чтение регрессора с кэшированием.
%
%   Чтение с диска дольше самого предсказания, а на холсте ответ должен быть
%   мгновенным. Отсутствие файла ошибкой не считается: регрессор обучен не
%   для всех классов.

persistent cache cacheKey

if reload || isempty(cacheKey) || cacheKey ~= key
    cfg  = cnConfig();
    file = fullfile(cfg.paths.models, "reg_" + key + ".mat");
    if ~isfile(file)
        model = [];
        cacheKey = "";
        return
    end
    cache    = load(file, "model").model;
    cacheKey = key;
end
model = cache;
end

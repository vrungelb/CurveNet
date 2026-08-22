function F = cnRefineFit(key, strokes, opts)
%CNREFINEFIT  Уточнение параметров кривой по точкам рисунка.
%
%   F = CNREFINEFIT("ellipse", strokes, init = params)
%   F = CNREFINEFIT("circle", strokes)
%
%   strokes   штрихи в координатах холста
%   opts.init структура params из CNFITCURVE — начальное приближение от
%             сети. Для параболы и гиперболы обязательна.
%
%   Поля результата
%   ---------------
%   ok, status, message   удалось ли; "ok", "warn" или "reject"
%   strokes, points       кривая в координатах холста
%   params                производные величины
%   equation, general     уравнение в двух видах
%   residual              средняя невязка, доля размера кривой
%   moved                 насколько ушли от начального приближения
%   iters, nUsed          итераций и точек в окончательной подгонке
%
%   Что минимизируется
%   ------------------
%   Сумма квадратов расстояний от точек рисунка до кривой — та величина,
%   которую человек оценивает на глаз, глядя, легла кривая на линию или нет.
%
%   Есть более простой путь: алгебраический МНК, где минимизируют значение
%   многочлена, а не расстояние. Он решается напрямую, без итераций, но
%   систематически смещён — многочлен растёт быстрее там, где кривая круче, и
%   такие участки получают незаслуженный вес. У вытянутого эллипса это видно
%   глазом: концы притягивают кривую сильнее боков.
%
%   Геометрический МНК этого не имеет, но он нелинейный и требует начальной
%   точки. Её и даёт регрессор. Для окружности с эллипсом есть запасной
%   алгебраический старт, для параболы с гиперболой — нет: там без сети не
%   обойтись.
%
%   Ровно эта связка понадобится спиралям и розам, где алгебраического
%   решения не существует вовсе.
%
%   Как решается
%   ------------
%   Левенберг — Марквардт с численным якобианом. Параметров от трёх до пяти,
%   точек несколько сотен, поэтому численные производные дешевле
%   аналитических по трудозатратам и не проигрывают по времени.
%
%   Размеры оптимизируются в логарифме: это держит их положительными без
%   явных ограничений и делает шаг соразмерным величине.
%
%   Расстояние берётся в приближении Сэмпсона — значение многочлена, делённое
%   на модуль градиента. Точное расстояние до коники требует корней уравнения
%   четвёртой степени на каждую точку, а вблизи кривой приближение совпадает
%   с ним до второго порядка. Для окружности расстояние точное, приближать
%   нечего.
%
%   Отсев выбросов
%   --------------
%   После первого решения точки дальше утроенной медианной невязки
%   отбрасываются, и решение повторяется. МНК штрафует квадратично, и один
%   хвост от соскочившей руки перетягивает кривую сильнее сотни нормальных
%   точек.
%
%   Размах ветвей
%   -------------
%   У параболы и гиперболы подгоняется сама кривая, а не длина нарисованного
%   куска: длина ветвей на форму не влияет и в невязку не входит. Поэтому
%   halfLength и uMax после подгонки берутся не из оптимизации, а прямым
%   измерением — проекцией точек на собственные оси найденной кривой.
%
%   См. также CNFITCURVE, CNCURVESHAPE, CNPREDICT.

arguments
    key          (1,1) string
    strokes      cell
    opts.init    struct = struct.empty
    opts.nPoints (1,1) double {mustBeInteger, mustBePositive} = 600
end

F = struct("ok", false, "status", "reject", "message", "", ...
           "strokes", {{}}, "points", zeros(0,2), "params", struct(), ...
           "equation", "", "general", "", ...
           "residual", NaN, "moved", NaN, "iters", 0, "nUsed", 0);

cfg = cnConfig();

if ~ismember(key, ["circle", "ellipse", "parabola", "hyperbola"])
    F.message = "Подгонка для этого класса не реализована.";
    return
end

% --- точки ---------------------------------------------------------------
P = vertcat(strokes{:});
P = P(all(isfinite(P), 2), :);
if size(P,1) < 8
    F.message = "Слишком мало точек.";
    return
end

% Центрируем и нормируем: шаги по всем параметрам становятся соразмерны, а
% численные производные не теряют значащих цифр.
c0 = mean(P, 1);
s0 = sqrt(mean(sum((P - c0).^2, 2)));
if s0 < eps
    F.message = "Рисунок вырожден.";
    return
end
Q = (P - c0) / s0;

% --- начальное приближение -----------------------------------------------
fromNet = ~isempty(opts.init);
if fromNet
    p0 = packInit(key, opts.init, c0, s0);
else
    p0 = seedAlgebraic(key, Q);
    if isempty(p0)
        F.message = "Нужна оценка сети как начальное приближение.";
        return
    end
end

% --- две итерации с отсевом между ними -----------------------------------
use = true(size(Q,1), 1);
p   = p0;
it  = 0;

for pass = 1:2
    [p, k] = lmFit(key, Q(use,:), p, cfg.refine.maxIterations, cfg.refine.tolerance);
    it = it + k;

    if pass == 1
        d   = abs(residuals(key, Q, p));
        thr = 3 * median(d);
        if thr > 0
            keep = d <= thr;
            if sum(keep) >= 8
                use = keep;
            end
        end
    end
end

% --- параметры формы по точкам -------------------------------------------
shape = measureShape(key, Q(use,:), p);

% --- обратно в координаты холста -----------------------------------------
[ctr, sz, th] = unpack(key, p);
ctr = ctr * s0 + c0;
sz  = sz * s0;

% Вырожденное решение видно по размеру: в нормированных координатах
% характерный размер рисунка равен единице, и кривая на порядки крупнее или
% мельче — это не подгонка, а расхождение. Парабола, натянутая на
% окружность, уезжает именно так: фокальный параметр к нулю, ветви в тысячи
% единиц, и от кривой остаётся почти прямая.
switch key
    case {"circle", "parabola"}
        szQ = exp(p(3));
    otherwise
        szQ = exp(p(3:4));
end
if any(szQ > 50) || any(szQ < 1e-3)
    F.message = "Подгонка разошлась.";
    return
end

if ~all(isfinite([ctr sz th shape])) || any(sz <= 0)
    F.message = "Подгонка разошлась.";
    return
end

% CNCURVESHAPE принимает габаритную рамку, а подгонка знает натуральный
% размер: радиус, большую полуось, фокальный параметр. Связывает их
% внутренний множитель построителя, поэтому он и спрашивается пробным
% вызовом с единичной рамкой.
probe = cnCurveShape(key, [0 0], 1, shape, th, nPoints = 200);
ext   = sz(1) / probe.params.scale;

S = cnCurveShape(key, ctr, ext, shape, th, nPoints = opts.nPoints);

F.strokes  = S.strokes;
F.points   = S.points;
F.params   = S.params;
F.equation = S.equation;
F.general  = S.general;
F.iters    = it;
F.nUsed    = sum(use);

% --- невязка и смещение от начальной точки -------------------------------
% Невязка считается прямо в нормированных координатах: там единица — это
% характерный размер рисунка. Делить на размер найденной кривой нельзя —
% разошедшаяся подгонка раздувает его и прячет собственную негодность.
F.residual = mean(abs(residuals(key, Q(use,:), p)));

if fromNet
    F.moved = norm(ctr - opts.init.center) / s0;
end

if F.residual > cfg.refine.residualReject
    F.status  = "reject";
    F.message = "Линия далека от кривой.";
else
    F.ok = true;
    if F.residual > cfg.refine.residualWarn
        F.status = "warn";
    else
        F.status = "ok";
    end
end
end


% =======================================================================
%  Упаковка параметров
% =======================================================================
% Вектор параметров по классам:
%   circle     [x0 y0 log r]
%   ellipse    [x0 y0 log a log b th]
%   parabola   [x0 y0 log p th]        p — фокальный параметр
%   hyperbola  [x0 y0 log a log b th]  a действительная, b мнимая полуось
%
% Логарифм размеров держит их положительными без ограничений и делает шаг
% относительным, а не абсолютным.

function p = packInit(key, init, c0, s0)
ctr = (init.center - c0) / s0;
th  = deg2rad(init.angleDeg);

switch key
    case "circle"
        p = [ctr, log(init.semiMajor/s0)];
    case "ellipse"
        p = [ctr, log(init.semiMajor/s0), log(init.semiMinor/s0), th];
    case "parabola"
        p = [ctr, log(init.focal/s0), th];
    case "hyperbola"
        p = [ctr, log(init.semiReal/s0), log(init.semiImag/s0), th];
end
end


function [ctr, sz, th] = unpack(key, p)
ctr = p(1:2);
switch key
    case "circle"
        sz = exp(p(3));           th = 0;
    case "ellipse"
        sz = exp(p(3:4));         th = p(5);
    case "parabola"
        sz = exp(p(3));           th = p(4);
    case "hyperbola"
        sz = exp(p(3:4));         th = p(5);
end
end


% =======================================================================
function shape = measureShape(key, Q, p)
%MEASURESHAPE  Параметры формы по точкам.
%
%   Длина ветвей у параболы и гиперболы в подгонке не участвует: на форму
%   кривой она не влияет и в невязку не входит, поэтому градиент по ней
%   нулевой. Мерить её приходится отдельно — проекцией точек на собственные
%   оси уже найденной кривой.

[ctr, sz, th] = unpack(key, p);
R = [cos(th), sin(th); -sin(th), cos(th)];
Z = (Q - ctr) * R.';

switch key
    case "circle"
        shape = zeros(1,0);

    case "ellipse"
        shape = sz(1)/sz(2);

    case "parabola"
        % Каноническая x пересчитывается из локальной: x' = p·x.
        shape = max(abs(Z(:,1) / sz(1)));

    case "hyperbola"
        % sh(u) = y'/b, отсюда параметр u для каждой точки.
        shape = [sz(2)/sz(1), max(abs(asinh(Z(:,2) / sz(2))))];
end
end


% =======================================================================
function p = seedAlgebraic(key, Q)
%SEEDALGEBRAIC  Запасной старт для окружности и эллипса.
%
%   Алгебраический МНК: линейный для окружности, метод Фицгиббона для
%   эллипса — ограничение 4AC − B² = 1 не даёт решению соскользнуть в
%   гиперболу. Как окончательный ответ смещён, как старт годится.
%
%   Для параболы и гиперболы запасного варианта нет намеренно: их начальную
%   точку даёт сеть, и это ровно та архитектура, к которой мы идём.

p = [];
x = Q(:,1); y = Q(:,2);

switch key
    case "circle"
        A = [x, y, ones(numel(x),1)];
        w = A \ (-(x.^2 + y.^2));
        cx = -w(1)/2; cy = -w(2)/2;
        r2 = cx^2 + cy^2 - w(3);
        if ~isfinite(r2) || r2 <= 0; return; end
        p = [cx, cy, log(sqrt(r2))];

    case "ellipse"
        D1 = [x.^2, x.*y, y.^2];
        D2 = [x, y, ones(numel(x),1)];
        S1 = D1.'*D1;  S2 = D1.'*D2;  S3 = D2.'*D2;
        if rcond(S3) < 1e-12; return; end

        T = -(S3 \ S2.');
        M = S1 + S2*T;
        M = [M(3,:)/2; -M(2,:); M(1,:)/2];   % умножение на обратную матрицу
                                             % ограничения, выписанное явно
        [V, ~] = eig(M);
        k = find(4*V(1,:).*V(3,:) - V(2,:).^2 > 0, 1);
        if isempty(k); return; end
        w = real([V(:,k); T*V(:,k)]);

        M2 = [w(1), w(2)/2; w(2)/2, w(3)];
        if det(M2) <= eps; return; end
        ctr = -M2 \ [w(4)/2; w(5)/2];
        Fc  = w(6) + [w(4)/2, w(5)/2]*ctr;
        if Fc >= 0; return; end

        [Vv, L] = eig(M2);
        lam = diag(L);
        if any(lam <= 0); return; end
        ax = sqrt(-Fc ./ lam);
        [~, i1] = max(ax);
        i2 = 3 - i1;

        p = [ctr.', log(ax(i1)), log(ax(i2)), atan2(Vv(2,i1), Vv(1,i1))];
end
end


% =======================================================================
function [p, it] = lmFit(key, Q, p, maxIter, tol)
%LMFIT  Левенберг — Марквардт с численным якобианом.
%
%   Демпфирование растёт при неудачном шаге и падает при удачном: метод ведёт
%   себя как градиентный спуск вдали от решения и как Гаусс — Ньютон вблизи.

lambda = 1e-3;
r = residuals(key, Q, p);
S = sum(r.^2);
it = 0;

for it = 1:maxIter
    J = jacobian(key, Q, p);
    H = J.'*J;
    g = J.'*r;

    stepped = false;
    for tryStep = 1:8
        dp = -(H + lambda*diag(max(diag(H), 1e-12))) \ g;
        pNew = p + dp.';
        rNew = residuals(key, Q, pNew);
        SNew = sum(rNew.^2);

        if isfinite(SNew) && SNew < S
            p = pNew; r = rNew;
            lambda = max(lambda/3, 1e-9);
            stepped = true;
            break
        end
        lambda = lambda * 5;
    end

    SPrev = S;
    S = sum(r.^2);
    if ~stepped || abs(SPrev - S) < tol * max(S, eps)
        break
    end
end
end


% =======================================================================
function J = jacobian(key, Q, p)
%JACOBIAN  Численный якобиан центральными разностями.

n = numel(p);
J = zeros(size(Q,1), n);
for i = 1:n
    h = 1e-6 * max(abs(p(i)), 1);
    pp = p; pp(i) = pp(i) + h;
    pm = p; pm(i) = pm(i) - h;
    J(:,i) = (residuals(key, Q, pp) - residuals(key, Q, pm)) / (2*h);
end
end


% =======================================================================
function r = residuals(key, Q, p)
%RESIDUALS  Знаковое расстояние от точек до кривой.
%
%   Знак сохраняется намеренно: для наименьших квадратов знаковая невязка
%   гладкая, а модуль имеет излом на нуле и портит сходимость.

[ctr, sz, th] = unpack(key, p);

if key == "circle"
    r = vecnorm(Q - ctr, 2, 2) - sz(1);
    return
end

R = [cos(th), sin(th); -sin(th), cos(th)];
Z = (Q - ctr) * R.';
zx = Z(:,1);
zy = Z(:,2);

switch key
    case "ellipse"
        a = sz(1); b = sz(2);
        val  = (zx/a).^2 + (zy/b).^2 - 1;
        grad = 2*hypot(zx/a^2, zy/b^2);

    case "hyperbola"
        a = sz(1); b = sz(2);
        val  = (zx/a).^2 - (zy/b).^2 - 1;
        grad = 2*hypot(zx/a^2, zy/b^2);

    case "parabola"
        % x'² − 2p·y' = 0, где p — фокальный параметр.
        pf   = sz(1);
        val  = zx.^2 - 2*pf*zy;
        grad = 2*hypot(zx, pf);
end

grad(grad < eps) = eps;
r = val ./ grad;
end

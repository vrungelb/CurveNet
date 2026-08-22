function S = cnCurveShape(key, ctr, ext, shape, th, opts)
%CNCURVESHAPE  Кривая и её уравнение по параметрам в форме целевого вектора.
%
%   S = CNCURVESHAPE("ellipse", ctr, ext, elong, th)
%   S = CNCURVESHAPE("hyperbola", ctr, ext, [b uMax], th)
%   S = CNCURVESHAPE(..., nPoints = 600)
%
%   ctr    опорная точка: центр у окружности, эллипса и гиперболы,
%          вершина у параболы
%   ext    наибольший размах габаритной рамки кривой
%   shape  параметры формы класса, в том же порядке, что в CNCLASSES;
%          пустой массив у окружности
%   th     угол поворота канонической кривой, радианы
%
%   Поля результата
%   ---------------
%   strokes   штрихи кривой (у гиперболы их два)
%   points    все точки подряд, для простой отрисовки
%   params    производные величины: полуоси, фокальный параметр, угол
%   equation  уравнение в координатах холста
%   general   то же в общем виде второй степени
%
%   Почему аргументы именно такие
%   -----------------------------
%   Ровно эти величины стоят в целевом векторе регрессора: смещение центра,
%   размер, параметры формы, угол. Значит одна и та же функция строит кривую
%   и по разметке, и по ответу сети, и по результату подгонки — и все трое
%   гарантированно понимают параметры одинаково. Раньше построение было
%   размазано по трём файлам, и любое расхождение в соглашениях всплывало бы
%   как необъяснимо плохая точность.
%
%   Опорная точка у всех классов — образ начала канонических координат. У
%   параболы это вершина, у остальных центр. Так реконструкция и разметка
%   сходятся без оговорок.
%
%   Размер задаётся размахом рамки, а не полуосью. Причина в том, что у
%   параболы и гиперболы полуось вообще не определяет видимый размер: его
%   задаёт то, насколько далеко уведены ветви. Рамка же осмысленна для всех
%   четырёх.
%
%   См. также CNREGRESSIONTARGETS, CNFITCURVE, CNREFINEFIT, CNCLASSES.

arguments
    key          (1,1) string
    ctr          (1,2) double
    ext          (1,1) double {mustBePositive}
    shape        (1,:) double
    th           (1,1) double
    opts.nPoints (1,1) double {mustBeInteger, mustBePositive} = 600
end

n = opts.nPoints;

% --- каноническая кривая -------------------------------------------------
% Единичный масштаб: окружность радиуса единица, гипербола с действительной
% полуосью единица, парабола y = x²/2. Общий множитель подбирается ниже.
switch key
    case "circle"
        t = linspace(0, 2*pi, n).';
        U = {[cos(t), sin(t)]};

    case "ellipse"
        elong = shape(1);
        t = linspace(0, 2*pi, n).';
        U = {[cos(t), sin(t)/elong]};

    case "parabola"
        L = shape(1);
        x = linspace(-L, L, n).';
        U = {[x, 0.5*x.^2]};

    case "hyperbola"
        b = shape(1);
        uMax = shape(2);
        u = linspace(-uMax, uMax, n).';
        U = {[cosh(u), b*sinh(u)], [-cosh(u), b*sinh(u)]};

    otherwise
        error("cnCurveShape:notImplemented", ...
            "Нет ветви для класса «%s».", key);
end

% --- поворот и подгонка размера ------------------------------------------
Rm = [cos(th), -sin(th); sin(th), cos(th)];
U  = cellfun(@(P) P * Rm.', U, UniformOutput = false);

all_ = vertcat(U{:});
span = max(max(all_,[],1) - min(all_,[],1));
k    = ext / span;                 % общий множитель

S.strokes = cellfun(@(P) ctr + P*k, U, UniformOutput = false);
S.points  = vertcat(S.strokes{:});

% --- производные величины -------------------------------------------------
% Множитель k и есть натуральный размер: у окружности радиус, у гиперболы
% действительная полуось, у параболы фокальный параметр. Проверяется прямо:
% канонические x' = k·x, y' = k·x²/2 дают y' = x'²/(2k).
P = struct("center", ctr, "angleDeg", mod(rad2deg(th), 180), "scale", k);

switch key
    case "circle"
        P.semiMajor = k;  P.semiMinor = k;  P.elong = 1;
    case "ellipse"
        P.semiMajor = k;  P.semiMinor = k/shape(1);  P.elong = shape(1);
    case "parabola"
        P.focal = k;  P.halfLength = shape(1);
        P.angleDeg = mod(rad2deg(th), 360);   % у параболы важно, куда ветви
    case "hyperbola"
        P.semiReal = k;  P.semiImag = k*shape(1);  P.uMax = shape(2);
end
S.params = P;

[S.equation, S.general] = writeEquation(key, ctr, th, P);
end


% =======================================================================
function [eq, gen] = writeEquation(key, ctr, th, P)
%WRITEEQUATION  Уравнение в координатах холста.
%
%   Если оси кривой совпали с осями холста, пишем обычную форму со сдвигом.
%   Иначе — форму в собственных осях x′, y′ с началом в опорной точке:
%   раскрытие в холстовые координаты даёт шесть коэффициентов, читать
%   которые невозможно. Полный вид всегда лежит в general.

x0 = ctr(1);
y0 = ctr(2);

% Парабола несимметрична относительно поворота на 180 градусов: ветви вверх
% и ветви вниз — разные кривые. Остальным хватает полуоборота.
if key == "parabola"
    aligned = abs(mod(rad2deg(th), 360)) < 0.5 || abs(mod(rad2deg(th), 360) - 360) < 0.5;
else
    d = mod(rad2deg(th), 180);
    aligned = d < 0.5 || d > 179.5;
end

switch key
    case "circle"
        eq = sprintf("%s² + %s² = %.2f", term("x",x0), term("y",y0), P.semiMajor^2);

    case "ellipse"
        if aligned
            eq = sprintf("%s²/%.2f + %s²/%.2f = 1", ...
                term("x",x0), P.semiMajor^2, term("y",y0), P.semiMinor^2);
        else
            eq = sprintf("x′²/%.2f + y′²/%.2f = 1", P.semiMajor^2, P.semiMinor^2);
        end

    case "parabola"
        if aligned
            eq = sprintf("%s² = %.2f·%s", term("x",x0), 2*P.focal, term("y",y0));
        else
            eq = sprintf("x′² = %.2f·y′", 2*P.focal);
        end

    case "hyperbola"
        if aligned
            eq = sprintf("%s²/%.2f − %s²/%.2f = 1", ...
                term("x",x0), P.semiReal^2, term("y",y0), P.semiImag^2);
        else
            eq = sprintf("x′²/%.2f − y′²/%.2f = 1", P.semiReal^2, P.semiImag^2);
        end
end

gen = generalConic(key, ctr, th, P);
end


% =======================================================================
function s = term(v, c)
%TERM  Скобка вида (x − 6.60). Отдельно из-за знака: «(x − -6.60)» нелепо.

if abs(c) < 5e-3
    s = v;
elseif c > 0
    s = sprintf("(%s − %.2f)", v, c);
else
    s = sprintf("(%s + %.2f)", v, -c);
end
end


% =======================================================================
function s = generalConic(key, ctr, th, P)
%GENERALCONIC  Раскрытие в многочлен второй степени.
%
%   Кривая записана как (p − c)ᵀ A (p − c) + bᵀ (p − c) + c₀ = 0. У коник с
%   центром линейной части нет, у параболы нет свободного члена — общая
%   форма покрывает всех.

R = [cos(th), -sin(th); sin(th), cos(th)];

switch key
    case {"circle", "ellipse"}
        A = R * diag([1/P.semiMajor^2, 1/P.semiMinor^2]) * R.';
        bl = [0; 0];  c0 = -1;
    case "hyperbola"
        A = R * diag([1/P.semiReal^2, -1/P.semiImag^2]) * R.';
        bl = [0; 0];  c0 = -1;
    case "parabola"
        % x′² − 2p·y′ = 0, где y′ — координата вдоль оси кривой.
        A  = R * diag([1, 0]) * R.';
        bl = -2*P.focal * (R * [0; 1]);
        c0 = 0;
end

x0 = ctr(1); y0 = ctr(2);

Ax = A(1,1);
Bx = 2*A(1,2);
Cx = A(2,2);
Dx = bl(1) - 2*(A(1,1)*x0 + A(1,2)*y0);
Ex = bl(2) - 2*(A(1,2)*x0 + A(2,2)*y0);
Gx = A(1,1)*x0^2 + 2*A(1,2)*x0*y0 + A(2,2)*y0^2 - bl(1)*x0 - bl(2)*y0 + c0;

% Нормируем на наибольший по модулю коэффициент квадратичной части: общий
% множитель на кривую не влияет, а у параболы Ax может обратиться в ноль.
q = max(abs([Ax Bx Cx]));
if q < eps; q = 1; end
k = [Ax Bx Cx Dx Ex Gx] / q;

s = sprintf("%s x² %s xy %s y² %s x %s y %s = 0", ...
    lead(k(1)), signed(k(2)), signed(k(3)), signed(k(4)), signed(k(5)), signed(k(6)));
end


function s = lead(v)
if abs(v - 1) < 5e-4
    s = "";
elseif abs(v + 1) < 5e-4
    s = "−";
else
    s = sprintf("%.3g", v);
end
end


function s = signed(v)
if abs(v) < 5e-4
    s = "+ 0";
elseif v >= 0
    s = sprintf("+ %.3g", v);
else
    s = sprintf("− %.3g", -v);
end
end

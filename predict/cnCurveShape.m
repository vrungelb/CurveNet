function S = cnCurveShape(key, ctr, a, b, th, opts)
%CNCURVESHAPE  Кривая и её уравнение по геометрическим параметрам.
%
%   S = CNCURVESHAPE("ellipse", [x0 y0], a, b, th)
%   S = CNCURVESHAPE(..., nPoints = 600)
%
%   ctr  центр в координатах холста
%   a    большая полуось
%   b    малая полуось
%   th   наклон большой оси, радианы
%
%   Поля результата
%   ---------------
%   points    точки кривой для отрисовки
%   params    те же параметры, собранные в структуру
%   equation  уравнение в координатах холста
%   general   то же в общем виде второй степени
%
%   Отдельный файл нужен, потому что кривую строят двое: CNFITCURVE по
%   выходу сети и CNREFINEFIT по результату подгонки. Раньше это был
%   один и тот же код в двух местах, и правка уравнения в одном из них
%   молча расходилась с другим.
%
%   Про запись уравнения
%   --------------------
%   Уравнение выписывается в координатах холста, а не в канонических.
%   «x² + y² = 4.27» описывает окружность в начале координат, а нарисована
%   она может быть где угодно — такая запись бесполезна. Правильная форма
%   со сдвигом: «(x − 6.60)² + (y − 6.20)² = 4.27».
%
%   С повёрнутым эллипсом честная запись в осях холста — многочлен второй
%   степени с шестью коэффициентами, читать его невозможно. Поэтому
%   основной остаётся форма со сдвигом в повёрнутых осях, а полный вид
%   всегда лежит в поле general.
%
%   См. также CNFITCURVE, CNREFINEFIT.

arguments
    key          (1,1) string
    ctr          (1,2) double
    a            (1,1) double {mustBePositive}
    b            (1,1) double {mustBePositive}
    th           (1,1) double
    opts.nPoints (1,1) double {mustBeInteger, mustBePositive} = 600
end

t  = linspace(0, 2*pi, opts.nPoints).';
U  = [a*cos(t), b*sin(t)];
Rm = [cos(th), -sin(th); sin(th), cos(th)];

S.points = ctr + U * Rm.';

S.params = struct( ...
    "center",    ctr, ...
    "semiMajor", a, ...
    "semiMinor", b, ...
    "elong",     a/b, ...
    "angleDeg",  mod(rad2deg(th), 180));

[S.equation, S.general] = writeEquation(key, ctr, a, b, th);
end


% =======================================================================
function [eq, gen] = writeEquation(key, ctr, a, b, th)

x0 = ctr(1);
y0 = ctr(2);
deg = mod(rad2deg(th), 180);

switch key
    case "circle"
        eq = sprintf("%s² + %s² = %.2f", term("x", x0), term("y", y0), a^2);

    otherwise
        if deg < 0.5 || deg > 179.5
            % Оси эллипса совпали с осями холста — обычная запись со сдвигом.
            eq = sprintf("%s²/%.2f + %s²/%.2f = 1", ...
                term("x", x0), a^2, term("y", y0), b^2);
        else
            % Оси повёрнуты: x′ и y′ — оси кривой с началом в её центре.
            eq = sprintf("x′²/%.2f + y′²/%.2f = 1", a^2, b^2);
        end
end

gen = generalConic(x0, y0, a, b, th);
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
function s = generalConic(x0, y0, a, b, th)
%GENERALCONIC  Раскрытие (p − c)' M (p − c) = 1 в многочлен второй степени.

R = [cos(th), -sin(th); sin(th), cos(th)];
M = R * diag([1/a^2, 1/b^2]) * R.';

A = M(1,1);
B = 2*M(1,2);
C = M(2,2);
D = -2*(M(1,1)*x0 + M(1,2)*y0);
E = -2*(M(1,2)*x0 + M(2,2)*y0);
G =  M(1,1)*x0^2 + 2*M(1,2)*x0*y0 + M(2,2)*y0^2 - 1;

% Нормируем на первый коэффициент: общий множитель на кривую не влияет.
k = [B C D E G] / A;

s = sprintf("x² %s xy %s y² %s x %s y %s = 0", ...
    signed(k(1)), signed(k(2)), signed(k(3)), signed(k(4)), signed(k(5)));
end


% =======================================================================
function s = signed(v)

if v >= 0
    s = sprintf("+ %.3g", v);
else
    s = sprintf("− %.3g", -v);
end
end

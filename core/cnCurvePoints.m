%CNCURVEPOINTS  Канонические точки идеальной кривой класса.
function [strokes, meta] = cnCurvePoints(key, prm, n)

arguments
    key (1,1) string
    prm (1,1) struct
    n   (1,1) double {mustBeInteger, mustBePositive} = 256
end

c = cnClasses(key);
if ~c.isCurve
    error("cnCurvePoints:notACurve", "Класс «%s» — это не кривая (см. cnScribble).", key);
end
checkParams(c, prm);

nd = max(4000, 12*n);
meta = struct();

switch key

    case "circle"

        t = linspace(0, 2*pi, nd).';
        raw = {[cos(t), sin(t)]};

    case "ellipse"

        t = linspace(0, 2*pi, nd).';
        raw = {[cos(t), sin(t)/prm.elong]};

    case "parabola"

        x = linspace(-prm.halfLength, prm.halfLength, nd).';
        raw = {[x, 0.5*x.^2]};

    case "hyperbola"

        u  = linspace(-prm.uMax, prm.uMax, nd).';
        ch = cosh(u);
        sh = prm.b*sinh(u);
        raw = {[ch, sh], [-ch, sh]};

    case "archSpiral"

        th  = linspace(0, 2*pi*prm.turns, nd).';
        raw = {[th.*cos(th), th.*sin(th)]};

    case "logSpiral"

        th  = linspace(-2*pi*prm.turns, 0, nd).';
        r   = exp(prm.growth*th);
        raw = {[r.*cos(th), r.*sin(th)]};

    case "rose"

        k = prm.k;
        limit = pi;
        if mod(k,2) == 0; limit = 2*pi; end
        th = linspace(0, limit, nd).';
        r  = cos(k*th);
        raw = {[r.*cos(th), r.*sin(th)]};

    case "lemniscate"

        t = linspace(0, 2*pi, nd).';
        d = 1 + sin(t).^2;
        raw = {[cos(t)./d, prm.stretch .* (sin(t).*cos(t))./d]};

    case "cycloid"

        ph = 0;
        if isfield(prm, "phase")
            ph = prm.phase;
        end
        tMid  = 2 * pi * ph;
        hSpan = pi * prm.arches;
        t0    = tMid - hSpan;
        t1    = tMid + hSpan;
        shift = 2 * pi * ceil(max(0, -t0 / (2 * pi)));
        t0    = t0 + shift;
        t1    = t1 + shift;
        t     = linspace(t0, t1, nd).';
        xr    = t - sin(t);
        yr    = 1 - cos(t);
        cx    = (xr(1) + xr(end)) / 2;
        cy    = (min(yr) + max(yr)) / 2;
        hx    = max((xr(end) - xr(1)) / 2, 1e-6);
        raw   = {[(xr - cx) / hx, (yr - cy) / hx]};
        meta  = struct("t0", t0, "t1", t1, "cx", cx, "cy", cy, "hx", hx);

    case "astroid"

        t   = linspace(0, 2*pi, nd).';
        raw = {[cos(t).^3, sin(t).^3]};

    case "cardioid"

        th  = linspace(0, 2*pi, nd).';
        r   = 1 - cos(th);
        raw = {[r.*cos(th), r.*sin(th)]};

    case "limacon"

        th  = linspace(0, 2*pi, nd).';
        r   = 1 + prm.ratio*cos(th);
        raw = {[r.*cos(th), r.*sin(th)]};

    otherwise
        error("cnCurvePoints:unhandled", "Для класса «%s» не задана формула.", key);
end

if numel(raw) ~= c.nStrokes
    error("cnCurvePoints:strokeMismatch", ...
        "Класс «%s» требует %d штриха(ов), а сгенерировано %d.", ...
        key, c.nStrokes, numel(raw));
end

strokes = cnResampleArc(raw, n);
end

function checkParams(c, prm)

need = strings(0,1);
if ~isempty(c.shape)
    need = [c.shape.name].';
end
if ~isempty(c.kValues)
    need(end+1) = "k";
end

if c.key == "cycloid" && ~isfield(prm, "phase")
    need(need == "phase") = [];
end

missing = need(~isfield(prm, need));
if ~isempty(missing)
    error("cnCurvePoints:missingParams", ...
        "Для класса «%s» не заданы параметры: %s.", c.key, join(missing, ", "));
end

for i = 1:numel(need)
    v = prm.(need(i));
    if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v)
        error("cnCurvePoints:badParam", "Параметр «%s» должен быть конечным числом.", need(i));
    end
end

if ~isempty(c.kValues)
    if mod(prm.k,1) ~= 0 || prm.k < 2
        error("cnCurvePoints:badK", "Число лепестков (k) должно быть целым >= 2, получено %g.", prm.k);
    end
end
end

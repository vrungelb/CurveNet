%CNEQUATIONTEXT Построение аналитического/параметрического уравнения кривой в виде текста.
function s = cnEquationText(cls, prm, X0, k, ang, aX, aY, sh, flip, A_mat)

c = cos(ang);
sn = sin(ang);
Minv = [1/aX, -sh/aX; 0, 1/aY];
C = [c, -sn; sn, c] * Minv.';
if flip; C(1,:) = -C(1,:); end

u = polyLinear(-(C(1,1)*X0(1) + C(2,1)*X0(2)), C(1,1), C(2,1));
v = polyLinear(-(C(1,2)*X0(1) + C(2,2)*X0(2)), C(1,2), C(2,2));

uu = conv2(u, u);
vv = conv2(v, v);
r2 = polyAdd(uu, vv);

switch cls
    case "circle"
        F = r2;
        F(1,1) = F(1,1) - k^2;
    case "ellipse"
        F = polyAdd(uu, prm.elong^2 * vv);
        F(1,1) = F(1,1) - k^2;
    case "parabola"
        F = polyAdd(uu, -2*k * v);
    case "hyperbola"
        F = polyAdd(uu, -vv / prm.b^2);
        F(1,1) = F(1,1) - k^2;
    case "cardioid"
        A = polyAdd(r2, k * u);
        F = polyAdd(polyPow(A, 2), -k^2 * r2);
    case "limacon"
        A = polyAdd(r2, -prm.ratio * k * u);
        F = polyAdd(polyPow(A, 2), -k^2 * r2);
    case "lemniscate"
        st = prm.stretch;
        A = polyAdd(st^2 * uu, vv);
        B = polyAdd(st^2 * uu, -vv);
        F = polyAdd(polyPow(A, 2), -k^2 * st^2 * B);
    case "astroid"
        A = r2;
        A(1,1) = A(1,1) - k^2;
        F = polyAdd(polyPow(A, 3), 27 * k^2 * conv2(uu, vv));
    case "rose"
        kk = prm.k;
        ReZ = polyRoseReal(u, v, kk);
        if mod(kk, 2) == 1
            F = polyAdd(polyPow(r2, (kk + 1)/2), -k * ReZ);
        else
            F = polyAdd(polyPow(r2, kk + 1), -k^2 * polyPow(ReZ, 2));
        end
    case "cycloid"
        [~, cyc] = cnCurvePoints("cycloid", prm, 2);
        K     = (k / cyc.hx) * A_mat;
        Xeq   = X0 - [cyc.cx, cyc.cy] * K.';
        s = string(sprintf( ...
            "x(t) = %.3g*(t - sin(t)) + %.3g*(1 - cos(t)) + %.3g\n" + ...
            "y(t) = %.3g*(t - sin(t)) + %.3g*(1 - cos(t)) + %.3g, t ∈ [%.3gπ, %.3gπ]", ...
            K(1,1), K(1,2), Xeq(1), ...
            K(2,1), K(2,2), Xeq(2), cyc.t0/pi, cyc.t1/pi));
        return
    case "archSpiral"
        K = k * A_mat;
        s = string(sprintf( ...
            "x(θ) = θ*(%.3g*cos(θ) + %.3g*sin(θ)) + %.3g\n" + ...
            "y(θ) = θ*(%.3g*cos(θ) + %.3g*sin(θ)) + %.3g, θ ∈ [0, %.3gπ]", ...
            K(1,1), K(1,2), X0(1), ...
            K(2,1), K(2,2), X0(2), 2 * prm.turns));
        return
    case "logSpiral"
        K = k * A_mat;
        gw = prm.growth;
        s = string(sprintf( ...
            "x(θ) = e^(%.3g*θ)*(%.3g*cos(θ) + %.3g*sin(θ)) + %.3g\n" + ...
            "y(θ) = e^(%.3g*θ)*(%.3g*cos(θ) + %.3g*sin(θ)) + %.3g, θ ∈ [-%.3gπ, 0]", ...
            gw, K(1,1), K(1,2), X0(1), ...
            gw, K(2,1), K(2,2), X0(2), 2 * prm.turns));
        return
end

s = polyText(F) + " = 0";
end

function P = polyLinear(a0, ax, ay)
P = [a0, ay; ax, 0];
end

function C = polyAdd(A, B)
sz = max(size(A), size(B));
C = zeros(sz);
C(1:size(A,1), 1:size(A,2)) = A;
C(1:size(B,1), 1:size(B,2)) = C(1:size(B,1), 1:size(B,2)) + B;
end

function R = polyPow(P, n)
if n <= 0
    R = 1;
    return
end
R = P;
for e = 2:n
    R = conv2(R, P);
end
end

function P = polyRoseReal(u, v, k)
P = zeros(1, 1);
for j = 0:2:k
    T = conv2(polyPow(u, k - j), polyPow(v, j));
    P = polyAdd(P, nchoosek(k, j) * (-1)^(j/2) * T);
end
end

function t = polyText(F)
F(abs(F) < 1e-9) = 0;
[nx, ny] = size(F);
t = "";
for d = (nx + ny - 2) : -1 : 0
    for i = min(d, nx-1) : -1 : 0
        j = d - i;
        if j > ny - 1; continue; end
        a = F(i+1, j+1);
        if a == 0; continue; end
        num = sprintf("%.12g", abs(a));
        if num == "1" && (i > 0 || j > 0); num = ""; end
        if t == ""
            if a < 0; sg = "-"; else; sg = ""; end
        else
            if a < 0; sg = " - "; else; sg = " + "; end
        end
        t = t + sg + num + monomial(i, j);
    end
end
if t == ""; t = "0"; end
end

function m = monomial(i, j)
sup = ["", "", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸"];
m = "";
if i > 0; m = m + "x" + sup(i+1); end
if j > 0; m = m + "y" + sup(j+1); end
end
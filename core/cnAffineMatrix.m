%CNAFFINEMATRIX  Матрица преобразования канонической кривой: поворот, масштаб, скос, зеркало.
function A = cnAffineMatrix(angleDeg, anisoX, anisoY, shear, flip)

arguments
    angleDeg (1,1) double
    anisoX   (1,1) double
    anisoY   (1,1) double
    shear    (1,1) double
    flip     (1,1) logical = false
end

a = deg2rad(angleDeg);
M = [anisoX, shear*anisoY;
     0,       anisoY];
R = [cos(a), -sin(a);
     sin(a),  cos(a)];

A = R*M;

if flip
    A(1,:) = -A(1,:);
end
end

function [imgs, T] = cnPreview(what, n, opts)
%CNPREVIEW  Быстро сгенерировать и посмотреть примеры любого класса.
%
%   CNPREVIEW("all")                 по 6 примеров каждого класса
%   CNPREVIEW("rose", 40)            40 роз квадратной сеткой
%   CNPREVIEW(["rose","astroid"], 8)
%   CNPREVIEW("all", 8, info = true) с подписями параметров
%   CNPREVIEW("all", 6, seed = 42)   воспроизводимо
%
%   [imgs, T] = CNPREVIEW(...)       забрать картинки и рецепты
%
%   what  ключ класса, массив ключей, либо "all" — все классы разом
%   n     сколько примеров на класс (по умолчанию 6)
%
%   Именованные аргументы
%   ---------------------
%   seed    задать seed розыгрыша; по умолчанию каждый вызов даёт новые
%           примеры, что и нужно при беглом просмотре
%   show    рисовать фигуру (по умолчанию true)
%   info    подписывать примеры значениями параметров формы
%   width   ширина мозаики в пикселях (по умолчанию 1600)
%
%   Ничего не печатает в консоль: выходные значения возвращаются, только
%   если их явно запросили. Вызов без точки с запятой не вываливает на
%   экран матрицу из миллионов чисел.
%
%   Все картинки склеиваются в одно изображение, а не раскладываются по
%   отдельным осям. Тысяча осей в одной фигуре заставляет MATLAB еле
%   шевелиться, а мозаика рисуется мгновенно независимо от числа плиток.
%
%   Зачем это нужно
%   ---------------
%   Просмотр глазами — самая дешёвая и самая полезная проверка генератора.
%   Половина ошибок в аугментации видна сразу: класс, разрушенный
%   деформацией, слипшиеся лепестки, кривая, выродившаяся в закорючку. На
%   цифрах точности те же ошибки выглядят как загадочная «сеть плохо
%   различает такие-то классы», и докопаться до причины уже трудно.
%
%   См. также CNRENDER, CNSAMPLEPARAMS, CNBUILDDATASET.

arguments
    what        = "all"
    n    (1,1) double {mustBeInteger, mustBePositive} = 6
    opts.seed   = []
    opts.show  (1,1) logical = true
    opts.info  (1,1) logical = false
    opts.width (1,1) double  = 1600
end

% --- какие классы -------------------------------------------------------
C    = cnClasses();
what = string(what);
if isscalar(what) && what == "all"
    keys = [C.key];
else
    keys = what;
    for i = 1:numel(keys)
        cnClasses(keys(i));     % проверка, что ключ существует
    end
end

if any(keys == "scribble") && exist("cnScribble", "file") ~= 2
    keys(keys == "scribble") = [];
end

nk  = numel(keys);
cfg = cnConfig();
S   = cfg.img.size;

stack = zeros(S, S, 1, nk*n, "uint8");
rows  = cell(nk,1);

% --- генерация ----------------------------------------------------------
for j = 1:nk
    key = keys(j);

    % Без явного seed каждый вызов должен давать новые примеры, иначе
    % просмотр после правки показывал бы ровно те же самые картинки.
    if isempty(opts.seed)
        s = randi([1 2^31-2]);
    else
        s = opts.seed + 1000*j;
    end

    Tj = cnSampleParams(key, n, s);
    Tj = addvars(Tj, repmat(key, n, 1), NewVariableNames = "class", Before = 1);
    rows{j} = Tj;

    for i = 1:n
        stack(:,:,1,(j-1)*n + i) = cnRender(key, table2struct(Tj(i,:)));
    end
end

% --- показ --------------------------------------------------------------
if opts.show
    if nk == 1
        nc = ceil(sqrt(n));
        nr = ceil(n / nc);
    else
        nr = nk;
        nc = n;
    end
    showMosaic(stack, keys, nr, nc, n, nk, rows, opts);
end

% --- выходы только по запросу -------------------------------------------
% Иначе вызов без точки с запятой печатает всю стопку картинок в консоль.
if nargout >= 1
    imgs = stack;
end
if nargout >= 2
    T = vertcatTables(rows);
end
end


% =======================================================================
function showMosaic(stack, keys, nr, nc, n, nk, rows, opts)
%SHOWMOSAIC  Склейка всех картинок в одно изображение и его показ.

S = size(stack,1);

% Плитки уменьшаются так, чтобы мозаика влезла в заданную ширину. Иначе
% при сотне картинок в ряд получилось бы изображение в 16000 пикселей.
cell_ = floor(min(S, (opts.width - (nc+1)*4) / nc));
cell_ = max(cell_, 24);
gap   = 4;

Hm = nr*(cell_+gap) + gap;
Wm = nc*(cell_+gap) + gap;
mos = zeros(Hm, Wm, "uint8") + uint8(28);   % фон мозаики темнее чёрного кадра

for j = 1:nk
    for i = 1:n
        if nk == 1
            rr = ceil(i/nc);
            cc = i - (rr-1)*nc;
        else
            rr = j;
            cc = i;
        end
        tile = stack(:,:,1,(j-1)*n + i);
        if cell_ ~= S
            tile = imresize(tile, [cell_ cell_]);
        end
        y0 = gap + (rr-1)*(cell_+gap);
        x0 = gap + (cc-1)*(cell_+gap);
        mos(y0+(1:cell_), x0+(1:cell_)) = tile;
    end
end

f = figure(Name = "cnPreview", Color = [0.12 0.12 0.12], NumberTitle = "off");
scale = min(1, 1500/Wm);
f.Position = [80 80 min(1500,Wm*scale+220) min(900, Hm*scale+70)];

ax = axes(f, Position = [0.135 0.02 0.855 0.93]);
imshow(mos, Parent = ax);
ax.Clipping = "off";

% Подписи классов слева от мозаики.
if nk > 1
    for j = 1:nk
        yc = gap + (j-1)*(cell_+gap) + cell_/2;
        text(ax, -8, yc, cnClasses(keys(j)).name, ...
            HorizontalAlignment = "right", VerticalAlignment = "middle", ...
            Color = "w", FontSize = 9);
    end
end

% Подписи параметров поверх плиток.
if opts.info
    for j = 1:nk
        for i = 1:n
            if nk == 1
                rr = ceil(i/nc); cc = i - (rr-1)*nc;
            else
                rr = j; cc = i;
            end
            y0 = gap + (rr-1)*(cell_+gap);
            x0 = gap + (cc-1)*(cell_+gap);
            text(ax, x0+3, y0+9, shapeText(rows{j}(i,:), keys(j)), ...
                Color = [1 0.85 0.3], FontSize = 7, Interpreter = "none");
        end
    end
end

title(ax, sprintf("%d прим. на класс", n), Color = "w", FontWeight = "normal");
end


% =======================================================================
function T = vertcatTables(rows)
%VERTCATTABLES  Склейка таблиц с разным набором столбцов.
%
%   У разных классов свои параметры формы, поэтому столбцы не совпадают.
%   Недостающие заполняются пропусками нужного типа: строковый столбец и
%   числовой NaN вертикально склеить нельзя, vertcat откажется.

rows = rows(~cellfun(@isempty, rows));
if isempty(rows)
    T = table();
    return
end

names = string.empty(1,0);
for i = 1:numel(rows)
    names = union(names, string(rows{i}.Properties.VariableNames), "stable");
end

for i = 1:numel(rows)
    h    = height(rows{i});
    miss = setdiff(names, string(rows{i}.Properties.VariableNames), "stable");
    for m = miss
        if isstring(protoOf(rows, m))
            rows{i}.(m) = repmat(string(missing), h, 1);
        else
            rows{i}.(m) = nan(h, 1);
        end
    end
    rows{i} = rows{i}(:, names);
end
T = vertcat(rows{:});
end


% =======================================================================
function v = protoOf(rows, name)
%PROTOOF  Образец значения столбца из первой таблицы, где он встречается.

v = NaN;
for i = 1:numel(rows)
    if ismember(name, string(rows{i}.Properties.VariableNames))
        v = rows{i}.(name)(1);
        return
    end
end
end


% =======================================================================
function s = shapeText(row, key)
%SHAPETEXT  Короткая подпись со значениями параметров формы.

c = cnClasses(key);
parts = string.empty(1,0);
for i = 1:numel(c.shape)
    parts(end+1) = sprintf("%s=%.2f", c.shape(i).name, row.(c.shape(i).name)); %#ok<AGROW>
end
if ~isempty(c.kValues)
    parts(end+1) = sprintf("k=%d", row.k); %#ok<AGROW>
end
parts(end+1) = sprintf("%.0f deg", row.angleDeg); %#ok<AGROW>
s = join(parts, "  ");
end

%CNPREVIEWDATASET  Мозаика примеров датасета.
function [imgs, T] = cnPreviewDataset(what, n, opts)

arguments
    what        = "all"
    n    (1,1) double {mustBeInteger, mustBePositive} = 6
    opts.seed   = []
    opts.show  (1,1) logical = true
    opts.info  (1,1) logical = false
    opts.width (1,1) double  = 1600
end

keys = [cnClasses(what).key];

if any(keys == "scribble") && exist("cnScribble", "file") == 0
    keys(keys == "scribble") = [];
end

nk  = numel(keys);
cfg = cnConfig();
S   = cfg.img.size;

stack = zeros(S, S, 1, nk*n, "uint8");
rows  = cell(nk,1);

for j = 1:nk
    key = keys(j);

    if isempty(opts.seed)
        s = randi([1 2^31-2]);
    else
        s = double(opts.seed) + 1000*j;
    end

    Tj = cnSampleParams(key, n, s);
    Tj = addvars(Tj, repmat(key, n, 1), NewVariableNames = "class", Before = 1);
    rows{j} = Tj;

    for i = 1:n
        stack(:,:,1,(j-1)*n + i) = cnRender(key, table2struct(Tj(i,:)));
    end
end

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

if nargout >= 1
    imgs = stack;
end
if nargout >= 2
    T = cnVertcatTables(rows);
end
end

function showMosaic(stack, keys, nr, nc, n, nk, rows, opts)

S = size(stack,1);

cell_ = floor(min(S, (opts.width - (nc+1)*4) / nc));
cell_ = max(cell_, 24);
gap   = 4;

Hm = nr*(cell_+gap) + gap;
Wm = nc*(cell_+gap) + gap;
mos = zeros(Hm, Wm, "uint8") + uint8(28);

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

f = figure(Name = "cnPreviewDataset", Color = [0.12 0.12 0.12], NumberTitle = "off");
scale = min(1, 1500/Wm);
f.Position = [80 80 min(1500,Wm*scale+220) min(900, Hm*scale+70)];

ax = axes(f, Position = [0.135 0.02 0.855 0.93]);
imshow(mos, Parent = ax);
ax.Clipping = "off";

if nk > 1
    for j = 1:nk
        yc = gap + (j-1)*(cell_+gap) + cell_/2;
        text(ax, -8, yc, cnClasses(keys(j)).name, ...
            HorizontalAlignment = "right", VerticalAlignment = "middle", ...
            Color = "w", FontSize = 9);
    end
end

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

function s = shapeText(row, key)

c = cnClasses(key);
parts = string.empty(1,0);
for i = 1:numel(c.shape)
    parts(end+1) = sprintf("%s=%.2f", c.shape(i).name, row.(c.shape(i).name));
end
if ~isempty(c.kValues)
    parts(end+1) = sprintf("k=%d", row.k);
end
parts(end+1) = sprintf("%.0f deg", row.angleDeg);
s = join(parts, "  ");
end

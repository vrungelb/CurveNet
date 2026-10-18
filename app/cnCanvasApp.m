%CNCANVASAPP  Холст: рисуете кривую - получаете класс и зелёную идеальную кривую.
function cnCanvasApp

cfg  = cnConfig();
LIM  = [-10 10];
SPAN = LIM(2) - LIM(1);

C     = cnClasses();
names = [C.name];
keys  = [C.key];

strokes = {};
cur     = zeros(0,2);
hLines  = gobjects(0);
hCur    = gobjects(1);
hIdeal  = gobjects(1);
drawing = false;

fig = uifigure(Name = "CurveNet — распознавание кривых", ...
    Position = [100 80 1280 800], Color = [0.96 0.96 0.97]);

g = uigridlayout(fig, [1 2], ColumnWidth = {'1x', 400}, ...
    Padding = 12, ColumnSpacing = 12);

ax = uiaxes(g);
ax.Layout.Row = 1; ax.Layout.Column = 1;
ax.XLim = LIM; ax.YLim = LIM;
ax.DataAspectRatio = [1 1 1];
ax.XGrid = "on"; ax.YGrid = "on";
ax.GridColor = [0.6 0.6 0.6];
ax.GridAlpha = 0.25;
ax.XTick = LIM(1):2:LIM(2);
ax.YTick = LIM(1):2:LIM(2);
ax.Box = "on";
ax.Title.String = "Рисуйте левой кнопкой мыши";
ax.Title.FontWeight = "normal";
ax.Title.FontSize = 14;
hold(ax, "on");
xline(ax, 0, "-", Color = [0.3 0.3 0.3], LineWidth = 1.2);
yline(ax, 0, "-", Color = [0.3 0.3 0.3], LineWidth = 1.2);

disableDefaultInteractivity(ax);
ax.Toolbar.Visible = "off";
ax.Interactions = [];

right = uigridlayout(g, [8 1], ...
    RowHeight = {50, 36, 120, 100, 24, 150, 100, '1x'}, ...
    RowSpacing = 10, Padding = 0);
right.Layout.Row = 1; right.Layout.Column = 2;

uibutton(right, Text = "Распознать", ...
    FontSize = 16, FontWeight = "bold", ...
    BackgroundColor = [0.18 0.45 0.85], FontColor = "w", ...
    ButtonPushedFcn = @(~,~) doRecognize());

rowBtn = uigridlayout(right, [1 2], Padding = 0, ColumnSpacing = 10);
uibutton(rowBtn, Text = "Отменить штрих", ...
    BackgroundColor = [0.9 0.9 0.92], FontColor = [0.2 0.2 0.2], ...
    ButtonPushedFcn = @(~,~) doUndo());
uibutton(rowBtn, Text = "Очистить", ...
    BackgroundColor = [0.9 0.9 0.92], FontColor = [0.2 0.2 0.2], ...
    ButtonPushedFcn = @(~,~) doClear());

pnlAns = uipanel(right, Title = "Ответ", ...
    BackgroundColor = "w", BorderType = "line", HighlightColor = [0.8 0.8 0.8]);
gAns   = uigridlayout(pnlAns, [3 1], RowHeight = {30, 20, '1x'}, ...
    RowSpacing = 2, Padding = [10 8 10 8]);
lblAns  = uilabel(gAns, Text = "—", FontSize = 22, FontWeight = "bold", ...
    WordWrap = "on", VerticalAlignment = "center");
lblConf = uilabel(gAns, Text = "", FontSize = 13, FontColor = [0.4 0.4 0.4]);
lblStatus = uilabel(gAns, Text = "", WordWrap = "on", ...
    FontColor = [0.75 0.35 0.10], VerticalAlignment = "top", FontSize = 12);

tbl = uitable(right, Data = table(strings(0,1), strings(0,1), ...
    VariableNames = ["Кандидаты","%"]), ColumnWidth = {'1x', 65}, ...
    RowStriping = "off");

uilabel(right, Text = "Вход сети (160×160):", ...
    FontColor = [0.35 0.35 0.35], VerticalAlignment = "bottom");

axPrev = uiaxes(right);
axPrev.XTick = []; axPrev.YTick = [];
axPrev.Box = "on";
axPrev.XColor = [0.6 0.6 0.6]; axPrev.YColor = [0.6 0.6 0.6];
disableDefaultInteractivity(axPrev);
axPrev.Toolbar.Visible = "off";
colormap(axPrev, gray(256));

pnlSave = uipanel(right, Title = "Тестовый набор", ...
    BackgroundColor = "w", BorderType = "line", HighlightColor = [0.8 0.8 0.8]);
gSave   = uigridlayout(pnlSave, [2 2], RowHeight = {30, 30}, ...
    ColumnWidth = {'1x', 110}, Padding = 10, ColumnSpacing = 10);
ddClass = uidropdown(gSave, Items = names, Value = names(1));
uibutton(gSave, Text = "Сохранить", ...
    ButtonPushedFcn = @(~,~) doSave());
lblSaved = uilabel(gSave, Text = "", FontColor = [0.2 0.5 0.2]);
lblSaved.Layout.Row = 2; lblSaved.Layout.Column = [1 2];

pnlEq = uipanel(right, Title = "Уравнение", ...
    BackgroundColor = "w", BorderType = "line", HighlightColor = [0.8 0.8 0.8]);
gEq   = uigridlayout(pnlEq, [1 1], Padding = 6);
taEq  = uitextarea(gEq, Editable = "off", FontSize = 13, Value = {''});

fig.WindowButtonDownFcn   = @onDown;
fig.WindowButtonMotionFcn = @onMove;
fig.WindowButtonUpFcn     = @onUp;

showPreview(zeros(cfg.img.size, "uint8"));

    function onDown(~,~)
        p = pointer();
        if isempty(p); return; end
        clearAnswer();
        drawing = true;
        cur = p;
        if isgraphics(hCur); delete(hCur); end
        hCur = plot(ax, cur(:,1), cur(:,2), "-", ...
            Color = [0.85 0.10 0.10], LineWidth = 2.5);
    end

    function onMove(~,~)
        if ~drawing; return; end
        p = pointer();
        if isempty(p); return; end

        if hypot(p(1)-cur(end,1), p(2)-cur(end,2)) < 1e-6; return; end
        cur(end+1,:) = p;
        set(hCur, XData = cur(:,1), YData = cur(:,2));
        drawnow limitrate
    end

    function onUp(~,~)
        if ~drawing; return; end
        drawing = false;
        if size(cur,1) >= 2
            strokes{end+1} = cur;
            hLines(end+1)  = hCur;
            hCur = gobjects(1);
        else
            if isgraphics(hCur); delete(hCur); end
            hCur = gobjects(1);
        end
        cur = zeros(0,2);
    end

    function p = pointer()
        p = [];

        cp = fig.CurrentPoint;
        axPos = getpixelposition(ax, true);

        inAx = cp(1) >= axPos(1) && cp(1) <= (axPos(1) + axPos(3)) && ...
               cp(2) >= axPos(2) && cp(2) <= (axPos(2) + axPos(4));
        if ~inAx
            return;
        end

        c = ax.CurrentPoint;
        pt = c(1,1:2);
        if pt(1) >= LIM(1) && pt(1) <= LIM(2) && pt(2) >= LIM(1) && pt(2) <= LIM(2)
            p = pt;
        end
    end

    function doUndo()
        if isempty(strokes); return; end
        if isgraphics(hLines(end)); delete(hLines(end)); end
        hLines(end) = [];
        strokes(end) = [];
        clearAnswer();
    end

    function doClear()
        delete(hLines(isgraphics(hLines)));
        if isgraphics(hCur); delete(hCur); end
        hLines  = gobjects(0);
        hCur    = gobjects(1);
        strokes = {};
        cur     = zeros(0,2);
        drawing = false;
        clearAnswer();
        showPreview(zeros(cfg.img.size, "uint8"));
    end

    function clearAnswer()
        lblAns.Text  = "—";
        lblAns.FontColor = [0.10 0.10 0.10];
        lblConf.Text = "";
        tbl.Data = table(strings(0,1), strings(0,1), VariableNames = ["Кандидаты","%"]);
        lblStatus.Text = "";
        lblSaved.Text  = "";
        taEq.Value = {''};
        delete(hIdeal(isgraphics(hIdeal)));
        hIdeal = gobjects(1);
    end

    function doRecognize()
        if isempty(strokes)
            lblStatus.Text = "Нарисуйте фигуру.";
            return
        end

        clearAnswer();

        try
            R = cnPredict(strokes, SPAN);
        catch ME
            lblAns.Text    = "Ошибка";
            lblStatus.Text = "Внутренняя ошибка распознавания.";
            warning("cnCanvasApp:predictFailed", "%s", ME.message);
            return
        end

        if ~isempty(R.img); showPreview(R.img); end

        if ~R.ok
            lblAns.Text    = "Не распознано";
            lblStatus.Text = R.message;
            return
        end

        if R.class == "rose" && isfield(R.params, "k")
            lblAns.Text = sprintf("%s (%s)", R.name, petalWord(R.params.k));
        else
            lblAns.Text = R.name;
        end

        confStr = sprintf("Уверенность: %.1f%%", 100*R.confidence);
        if isfield(R, "fit") && isfield(R.fit, "residual") && isfinite(R.fit.residual)
            lblConf.Text = sprintf("%s  •  Невязка: %.1f%%", confStr, 100*R.fit.residual);
        else
            lblConf.Text = confStr;
        end

        tbl.Data = table(R.top.("название"), compose("%.1f", R.top.("вероятность")), ...
            VariableNames = ["Кандидаты","%"]);

        if R.class == "scribble"
            lblAns.FontColor = [0.75 0.25 0.10];
        else
            lblAns.FontColor = [0.10 0.10 0.10];
        end

        lblStatus.Text = strtrim(R.warning);

        if ~isempty(R.idealPoints)
            hIdeal = plot(ax, R.idealPoints(:,1), R.idealPoints(:,2), ...
                "-", Color = [0.15 0.70 0.25], LineWidth = 3.5);
        end

        if R.equation ~= ""
            taEq.Value = cellstr(splitlines(R.equation));
        end
    end

    function doSave()
        if isempty(strokes)
            lblSaved.Text = "Холст пуст.";
            return
        end
        key = keys(names == string(ddClass.Value));
        dir_ = fullfile(cfg.paths.userTest, key);
        if ~exist(dir_, "dir"); mkdir(dir_); end

        stamp = string(datetime("now", Format = "yyyyMMdd_HHmmss_SSS"));
        sample = struct("strokes", {strokes}, "class", key, ...
            "canvasSpan", SPAN, "limits", LIM, "savedAt", datetime("now"));

        save(fullfile(dir_, "sample_" + stamp + ".mat"), "sample");
        n = numel(dir(fullfile(dir_, "*.mat")));
        lblSaved.Text = sprintf("Сохранено: %s (%d)", ddClass.Value, n);
    end

    function showPreview(img)
        cla(axPrev);
        image(axPrev, img, CDataMapping = "scaled");
        axPrev.CLim = [0 255];
        axPrev.DataAspectRatio = [1 1 1];
        axPrev.XTick = []; axPrev.YTick = [];
        axPrev.XLim = [0.5 size(img,2)+0.5];
        axPrev.YLim = [0.5 size(img,1)+0.5];
    end

    function s = petalWord(k)
        rem10 = mod(k, 10);
        rem100 = mod(k, 100);
        if rem100 >= 11 && rem100 <= 14
            s = sprintf("%d лепестков", k);
        elseif rem10 == 1
            s = sprintf("%d лепесток", k);
        elseif rem10 >= 2 && rem10 <= 4
            s = sprintf("%d лепестка", k);
        else
            s = sprintf("%d лепестков", k);
        end
    end
end

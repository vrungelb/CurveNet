function cnCanvasApp
%CNCANVASAPP  Холст для рисования и распознавания кривых.
%
%   cnCanvasApp
%
%   Штрихов может быть сколько угодно: отпустил кнопку — штрих закончился,
%   нажал снова — начался новый. Гипербола так и рисуется, двумя движениями.
%
%   Кнопка «Сохранить» кладёт в userTest не картинку, а координаты штрихов.
%   Тогда при смене нормализации или размера кадра набор не придётся
%   пересобирать — достаточно прогнать заново.
%
%   Как получается кривая
%   ---------------------
%   Сначала классификатор называет класс. Затем регрессор оценивает по
%   картинке центр, размер и наклон. Затем подгонка берёт эту оценку как
%   начальную точку и доводит её по самим точкам рисунка, минимизируя
%   расстояние от них до кривой.
%
%   Две галочки
%   -----------
%   «Уточнять подгонкой» — включить последний шаг. Без неё показывается
%   голая оценка сети, которая завышает радиус процентов на пять.
%
%   «Показать оценку сети» — нарисовать заодно и начальную точку, серым
%   пунктиром. Когда результат плох, сразу видно, чья вина: сеть рядом, а
%   подгонка уехала — виноват МНК или выброс; сеть мимо, подгонка вытащила —
%   регрессор недоучен, но система работает.
%
%   См. также CNPREDICT, CNFITCURVE, CNREFINEFIT, CNCLASSES.

cfg  = cnConfig();
LIM  = [-10 10];
SPAN = LIM(2) - LIM(1);

C     = cnClasses();
names = [C.name];
keys  = [C.key];

COL = struct( ...
    "ink",    [0.13 0.14 0.17], ...
    "fit",    [0.83 0.16 0.22], ...
    "net",    [0.55 0.57 0.62], ...
    "accent", [0.16 0.38 0.72], ...
    "muted",  [0.46 0.48 0.53], ...
    "good",   [0.15 0.50 0.28], ...
    "warn",   [0.72 0.48 0.08], ...
    "bad",    [0.72 0.24 0.12], ...
    "panel",  [1.00 1.00 1.00], ...
    "back",   [0.955 0.957 0.965], ...
    "line",   [0.87 0.88 0.90]);

% --- состояние ----------------------------------------------------------
strokes = {};
cur     = zeros(0,2);
hLines  = gobjects(0);
hCur    = gobjects(1);
hFit    = gobjects(1);
hNet    = gobjects(1);
drawing = false;
panning = false;           % перетаскивание вида правой кнопкой
panFrom = zeros(1,2);      % схваченная точка в координатах холста
lastR   = [];      % последний ответ cnPredict, чтобы не гонять сеть заново

% =======================================================================
%  Окно
% =======================================================================
fig = uifigure(Name = "CurveNet", ...
    Position = [80 60 1280 820], Color = COL.back);

g = uigridlayout(fig, [1 2], ColumnWidth = {'1x', 360}, ...
    Padding = 16, ColumnSpacing = 16, BackgroundColor = COL.back);

% --- холст --------------------------------------------------------------
pnlCanvas = uipanel(g, BorderType = "line", ...
    BorderColor = COL.line, BackgroundColor = COL.panel);
pnlCanvas.Layout.Row = 1; pnlCanvas.Layout.Column = 1;

gc = uigridlayout(pnlCanvas, [1 1], Padding = 8, BackgroundColor = COL.panel);
ax = uiaxes(gc);
ax.XLim = LIM; ax.YLim = LIM;
ax.DataAspectRatio = [1 1 1];
ax.Box = "on";
ax.XColor = [0.35 0.36 0.40];
ax.YColor = [0.35 0.36 0.40];
ax.FontSize = 10;

ax.XGrid = "on"; ax.YGrid = "on";
ax.GridAlpha = 0.16;

ax.XAxis.MinorTick = "on";
ax.YAxis.MinorTick = "on";
ax.XMinorGrid = "on"; ax.YMinorGrid = "on";
ax.MinorGridAlpha = 0.07;
ax.MinorGridLineStyle = "-";

% Шаг сетки подбирается под текущий масштаб: при постоянном шаге после
% приближения подписи разъезжаются, а после отдаления сливаются в кашу.
applyTicks();

hold(ax, "on");
xline(ax, 0, "-", Color = [0.55 0.57 0.60], LineWidth = 1);
yline(ax, 0, "-", Color = [0.55 0.57 0.60], LineWidth = 1);

% Иначе перетаскивание мыши будет двигать оси вместо рисования.
disableDefaultInteractivity(ax);
ax.Toolbar.Visible = "off";
ax.Interactions = [];

% --- правая колонка -----------------------------------------------------
right = uigridlayout(g, [8 1], ...
    RowHeight = {52, 36, 8, 104, 116, 56, '1x', 104}, ...
    RowSpacing = 10, Padding = 0, BackgroundColor = COL.back);
right.Layout.Row = 1; right.Layout.Column = 2;

uibutton(right, Text = "Распознать", ...
    FontSize = 15, FontWeight = "bold", ...
    BackgroundColor = COL.accent, FontColor = "w", ...
    ButtonPushedFcn = @(~,~) doRecognize());

rowBtn = uigridlayout(right, [1 2], Padding = 0, ColumnSpacing = 8, ...
    BackgroundColor = COL.back);
uibutton(rowBtn, Text = "Отменить", ButtonPushedFcn = @(~,~) doUndo());
uibutton(rowBtn, Text = "Сбросить", ButtonPushedFcn = @(~,~) doReset());

uilabel(right, Text = "");     % воздух перед блоком ответа

% --- ответ --------------------------------------------------------------
pnlAns = uipanel(right, BorderType = "line", ...
    BorderColor = COL.line, BackgroundColor = COL.panel);
gAns = uigridlayout(pnlAns, [2 1], RowHeight = {'1x', 22}, ...
    RowSpacing = 2, Padding = [16 12 16 10], BackgroundColor = COL.panel);
lblAns = uilabel(gAns, Text = "—", FontSize = 22, FontWeight = "bold", ...
    WordWrap = "on", VerticalAlignment = "bottom", FontColor = COL.ink);
lblConf = uilabel(gAns, Text = "", FontSize = 12, FontColor = COL.muted);

% --- уравнение ----------------------------------------------------------
pnlEq = uipanel(right, BorderType = "line", ...
    BorderColor = COL.line, BackgroundColor = COL.panel);
gEq = uigridlayout(pnlEq, [3 1], RowHeight = {28, '1x', 18}, ...
    RowSpacing = 2, Padding = [16 10 16 8], BackgroundColor = COL.panel);
lblEq = uilabel(gEq, Text = "", FontSize = 15, FontColor = COL.ink, ...
    WordWrap = "on");
% Перенос по словам обязателен: у параболы в подписи четыре величины, и в
% одну строку они не помещаются — хвост просто обрезался многоточием.
lblEqInfo = uilabel(gEq, Text = "", FontSize = 11, FontColor = COL.muted, ...
    WordWrap = "on", VerticalAlignment = "top");
lblFitInfo = uilabel(gEq, Text = "", FontSize = 11, FontColor = COL.muted);

% --- переключатели ------------------------------------------------------
gChk = uigridlayout(right, [2 1], RowHeight = {24, 24}, ...
    RowSpacing = 2, Padding = [2 0 2 0], BackgroundColor = COL.back);
chkRefine = uicheckbox(gChk, Text = "Уточнять подгонкой", Value = true, ...
    FontColor = COL.ink, ValueChangedFcn = @(~,~) redoFit());
chkNet = uicheckbox(gChk, Text = "Показать оценку сети", Value = false, ...
    FontColor = COL.muted, ValueChangedFcn = @(~,~) redoFit());

% --- подробности --------------------------------------------------------
gMore = uigridlayout(right, [2 1], RowHeight = {24, '1x'}, ...
    RowSpacing = 6, Padding = 0, BackgroundColor = COL.back);
chkDebug = uicheckbox(gMore, Text = "Подробности", ...
    FontColor = COL.muted, ValueChangedFcn = @(~,~) toggleDebug());

pnlDbg = uipanel(gMore, BorderType = "none", ...
    BackgroundColor = COL.back, Visible = "off");
gDbg = uigridlayout(pnlDbg, [4 1], RowHeight = {104, 32, 18, '1x'}, ...
    RowSpacing = 6, Padding = 0, BackgroundColor = COL.back);

tbl = uitable(gDbg, Data = emptyTop(), ColumnWidth = {'1x', 58});
lblGen = uilabel(gDbg, Text = "", FontSize = 10, ...
    FontColor = COL.muted, WordWrap = "on");
uilabel(gDbg, Text = "Вход сети, 160×160", FontSize = 10, FontColor = COL.muted);

axPrev = uiaxes(gDbg);
axPrev.XTick = []; axPrev.YTick = [];
axPrev.Box = "on";
disableDefaultInteractivity(axPrev);
axPrev.Toolbar.Visible = "off";
colormap(axPrev, gray(256));

% --- сохранение ---------------------------------------------------------
pnlSave = uipanel(right, Title = "Тестовый набор", ...
    BorderType = "line", BorderColor = COL.line, ...
    BackgroundColor = COL.panel, ForegroundColor = COL.muted);
gSave = uigridlayout(pnlSave, [2 2], RowHeight = {30, 20}, ...
    ColumnWidth = {'1x', 108}, Padding = 12, ColumnSpacing = 8, ...
    BackgroundColor = COL.panel);
ddClass = uidropdown(gSave, Items = names, Value = names(1));
uibutton(gSave, Text = "Сохранить", ButtonPushedFcn = @(~,~) doSave());
lblSaved = uilabel(gSave, Text = "", FontSize = 11, FontColor = COL.muted);
lblSaved.Layout.Row = 2; lblSaved.Layout.Column = [1 2];

% --- мышь ---------------------------------------------------------------
fig.WindowButtonDownFcn   = @onDown;
fig.WindowButtonMotionFcn = @onMove;
fig.WindowButtonUpFcn     = @onUp;
fig.WindowScrollWheelFcn  = @onScroll;

showPreview(zeros(cfg.img.size, "uint8"));

% =======================================================================
%  Рисование
% =======================================================================
    function onDown(~,~)
        % Правая кнопка и двойной щелчок отданы навигации: левая нужна для
        % рисования и отбирать её нельзя.
        switch fig.SelectionType
            case "alt"                     % правая кнопка — перетаскивание
                a = raw();
                if isempty(a); return; end
                panning = true;
                panFrom = a;
                return
            case "open"                    % двойной щелчок — вернуть вид
                resetView();
                return
        end

        p = pointer();
        if isempty(p); return; end
        drawing = true;
        cur = p;
        hCur = plot(ax, cur(:,1), cur(:,2), "-", ...
            Color = COL.ink, LineWidth = 2.2);
    end

    function onMove(~,~)
        if panning
            % Точка под курсором должна остаться на месте, поэтому пределы
            % сдвигаются на разность между схваченной точкой и текущей.
            a = raw();
            if isempty(a); return; end
            d = panFrom - a;
            ax.XLim = ax.XLim + d(1);
            ax.YLim = ax.YLim + d(2);
            applyTicks();
            drawnow limitrate
            return
        end

        if ~drawing; return; end
        p = pointer();
        if isempty(p); return; end

        % Повторную точку не добавляем: нулевой отрезок ломает счёт длины дуги.
        if hypot(p(1)-cur(end,1), p(2)-cur(end,2)) < 1e-6
            return
        end
        cur(end+1,:) = p; %#ok<AGROW>
        set(hCur, XData = cur(:,1), YData = cur(:,2));
        drawnow limitrate
    end

    function onUp(~,~)
        panning = false;
        if ~drawing; return; end
        drawing = false;
        if size(cur,1) >= 2
            strokes{end+1} = cur; %#ok<AGROW>
            hLines(end+1)  = hCur; %#ok<AGROW>
        else
            delete(hCur);
        end
        cur = zeros(0,2);
    end

    function onScroll(~, ev)
        a = raw();
        if isempty(a); return; end

        % Колесо вверх даёт отрицательный счётчик, значит показатель степени
        % берётся как есть: вверх — приближение.
        f = 1.2 ^ ev.VerticalScrollCount;

        span = diff(ax.XLim) * f;
        if span < 0.5 || span > 4*(LIM(2)-LIM(1))
            return
        end

        % Приближаем к курсору, а не к центру: иначе интересующее место
        % уезжает за край и его приходится догонять перетаскиванием.
        ax.XLim = a(1) + (ax.XLim - a(1)) * f;
        ax.YLim = a(2) + (ax.YLim - a(2)) * f;
        applyTicks();
    end

    function resetView()
        ax.XLim = LIM;
        ax.YLim = LIM;
        applyTicks();
    end

    function p = raw()
        % Координаты курсора без проверки границ: для навигации выход за
        % пределы холста законен.
        c = ax.CurrentPoint;
        p = c(1,1:2);
        if ~all(isfinite(p)); p = []; end
    end

    function p = pointer()
        % Рисовать можно только в пределах логического холста, каким бы ни
        % был текущий масштаб: сохранённые штрихи должны оставаться
        % сопоставимыми между собой.
        p = raw();
        if isempty(p); return; end
        if p(1) < LIM(1) || p(1) > LIM(2) || p(2) < LIM(1) || p(2) > LIM(2)
            p = [];
        end
    end

    function applyTicks()
        % Шаг выбирается из ряда 1, 2, 5 и их десятичных кратных так, чтобы
        % на оси оказалось около десяти подписей. Мелкая сетка — впятеро
        % чаще, если её линии не сходятся вплотную.
        step = niceStep(diff(ax.XLim) / 10);

        ax.XTick = ticksFor(ax.XLim, step);
        ax.YTick = ticksFor(ax.YLim, step);

        minor = step / 5;
        ax.XAxis.MinorTickValues = ticksFor(ax.XLim, minor);
        ax.YAxis.MinorTickValues = ticksFor(ax.YLim, minor);
    end

    function v = ticksFor(lim, step)
        v = ceil(lim(1)/step)*step : step : lim(2);
    end

    function s = niceStep(raw_)
        e = floor(log10(max(raw_, eps)));
        m = raw_ / 10^e;
        if     m < 1.5; s = 1;
        elseif m < 3.5; s = 2;
        elseif m < 7.5; s = 5;
        else;           s = 10;
        end
        s = s * 10^e;
    end

% =======================================================================
%  Кнопки
% =======================================================================
    function doUndo()
        if isempty(strokes); return; end
        delete(hLines(end));
        hLines(end) = [];
        strokes(end) = [];
        clearAnswer();
    end

    function doReset()
        % Возвращает холст в исходное состояние целиком: и штрихи, и масштаб.
        % Разделять на две кнопки незачем — после приближения к мелкой детали
        % всё равно хочется начать с чистого листа и обычного вида.
        delete(hLines(isgraphics(hLines)));
        hLines  = gobjects(0);
        strokes = {};
        cur     = zeros(0,2);
        clearAnswer();
        resetView();
        showPreview(zeros(cfg.img.size, "uint8"));
    end

    function clearAnswer()
        lblAns.Text = "—";
        lblAns.FontColor = COL.ink;
        lblConf.Text    = "";
        lblEq.Text      = "";
        lblEqInfo.Text  = "";
        lblFitInfo.Text = "";
        lblGen.Text     = "";
        lblSaved.Text   = "";
        tbl.Data = emptyTop();
        lastR = [];
        clearCurves();
    end

    function clearCurves()
        delete(hFit(isgraphics(hFit)));
        delete(hNet(isgraphics(hNet)));
        hFit = gobjects(1);
        hNet = gobjects(1);
    end

    function doRecognize()
        if isempty(strokes); return; end

        clearCurves();
        lblEq.Text = ""; lblEqInfo.Text = ""; lblFitInfo.Text = ""; lblGen.Text = "";
        lastR = [];

        R = cnPredict(strokes, SPAN);

        if ~isempty(R.img)
            showPreview(R.img);
        end

        if ~R.ok
            lblAns.Text = "Не распознано";
            lblAns.FontColor = COL.bad;
            lblConf.Text = "";
            tbl.Data = emptyTop();
            return
        end

        tbl.Data = table(R.top.("название"), ...
            compose("%.0f", R.top.("вероятность %")), ...
            VariableNames = ["вариант","%"]);

        % Название класса, в котором сеть не уверена, лучше не показывать:
        % запомнится оно, а не оговорка.
        if ~R.reliable
            lblAns.Text = "Неуверенный ответ";
            lblAns.FontColor = COL.bad;
            lblConf.Text = "";
            return
        end

        lblAns.Text = R.name;
        lblAns.FontColor = COL.ink;
        lblConf.Text = sprintf("%.0f%%", 100*R.confidence);

        if R.class == "scribble"
            lblAns.FontColor = COL.bad;
            lblConf.Text = "";
            return
        end

        lastR = R;
        redoFit();
    end

    function redoFit()
        % Переключение галочек не гоняет сеть заново: класс и картинка уже
        % посчитаны, меняется только способ получить числа.
        if isempty(lastR); return; end

        clearCurves();
        lblFitInfo.Text = "";

        Fnet  = cnFitCurve(lastR.class, lastR.img, lastR.info.tf);
        shown = [];

        if chkRefine.Value
            % Оценка сети идёт в подгонку начальной точкой. Если её нет,
            % подгонка посчитает начальное приближение сама, алгебраически.
            if Fnet.ok
                Fref = cnRefineFit(lastR.class, strokes, init = Fnet.params);
            else
                Fref = cnRefineFit(lastR.class, strokes);
            end

            if Fref.ok
                shown = Fref;
                % Проценты отклонения нужны при отладке, а не человеку,
                % который просто нарисовал кривую. Ему хватает того, точно
                % легла или приблизительно.
                if Fref.status == "warn"
                    lblFitInfo.Text = "приблизительно";
                    lblFitInfo.FontColor = COL.warn;
                else
                    lblFitInfo.Text = "точно";
                    lblFitInfo.FontColor = COL.good;
                end
                if chkDebug.Value
                    lblFitInfo.Text = lblFitInfo.Text + ...
                        sprintf(" · отклонение %.1f%%", 100*Fref.residual);
                end
            elseif Fnet.ok
                shown = Fnet;
                lblFitInfo.Text = "приблизительно";
                lblFitInfo.FontColor = COL.warn;
            end
        elseif Fnet.ok
            shown = Fnet;
            lblFitInfo.Text = "";
        end

        % Начальную точку рисуем бледнее и пунктиром, чтобы не спорила с
        % результатом за внимание.
        if chkNet.Value && Fnet.ok
            hNet = gobjects(1, numel(Fnet.strokes));
            for i = 1:numel(Fnet.strokes)
                P = Fnet.strokes{i};
                hNet(i) = plot(ax, P(:,1), P(:,2), "--", ...
                    Color = COL.net, LineWidth = 1.2);
            end
        end

        if isempty(shown); return; end

        % Штрихи рисуются по отдельности: у гиперболы их два, и склеенные в
        % один вектор точки дали бы отрезок через пустоту между ветвями.
        hFit = gobjects(1, numel(shown.strokes));
        for i = 1:numel(shown.strokes)
            P = shown.strokes{i};
            hFit(i) = plot(ax, P(:,1), P(:,2), "-", ...
                Color = COL.fit, LineWidth = 2);
        end

        lblEq.Text  = shown.equation;
        lblGen.Text = shown.general;

        lblEqInfo.Text = describe(lastR.class, shown.params);
    end

    function s = describe(key, P)
        % Подпись под уравнением: только то, чего в нём не видно. Набор
        % величин у классов разный — у параболы нет полуосей, у гиперболы
        % они называются иначе, — поэтому текст собирается по классу, а не
        % по общему шаблону.
        switch key
            case "circle"
                s = sprintf("радиус %.2f", P.semiMajor);

            case "ellipse"
                s = sprintf("полуоси %.2f и %.2f", P.semiMajor, P.semiMinor);

            case "parabola"
                s = sprintf("фокальный параметр %.2f, ветви до %.2f", ...
                    P.focal, P.halfLength);

            case "hyperbola"
                s = sprintf("полуоси %.2f и %.2f, ветви до %.2f", ...
                    P.semiReal, P.semiImag, P.uMax);

            otherwise
                s = "";
        end

        % Центр стоит в самом уравнении, пока оси не повёрнуты. Как только
        % запись переходит в штрихованные координаты, его надо назвать.
        turned = P.angleDeg > 0.5 && P.angleDeg < 179.5;
        if key == "parabola"
            turned = mod(P.angleDeg, 360) > 0.5;
        end
        if turned
            s = s + sprintf(", поворот %.0f°, центр (%.2f, %.2f)", ...
                P.angleDeg, P.center(1), P.center(2));
        end
    end

    function doSave()
        if isempty(strokes); return; end

        key  = keys(names == string(ddClass.Value));
        dir_ = fullfile(cfg.paths.userTest, key);
        if ~exist(dir_, "dir"); mkdir(dir_); end

        stamp = string(datetime("now", Format = "yyyyMMdd_HHmmss_SSS"));
        sample = struct( ...
            "strokes",    {strokes}, ...
            "class",      key, ...
            "canvasSpan", SPAN, ...
            "limits",     LIM, ...
            "savedAt",    datetime("now")); %#ok<NASGU>

        save(fullfile(dir_, "sample_" + stamp + ".mat"), "sample");

        n = numel(dir(fullfile(dir_, "*.mat")));
        lblSaved.Text = sprintf("%s — %d", ddClass.Value, n);
    end

% =======================================================================
    function toggleDebug()
        redoFit();          % строка под уравнением зависит от подробностей
        if chkDebug.Value
            pnlDbg.Visible = "on";
        else
            pnlDbg.Visible = "off";
        end
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

    function T = emptyTop()
        T = table(strings(0,1), strings(0,1), ...
            VariableNames = ["вариант","%"]);
    end
end

function cnCanvasApp
%CNCANVASAPP  Холст для рисования и распознавания кривых.
%
%   cnCanvasApp
%
%   Рисование левой кнопкой мыши. Штрихов может быть сколько угодно: отпустил
%   кнопку — штрих закончился, нажал снова — начался новый. Гипербола так и
%   рисуется, двумя движениями.
%
%   Кнопки
%   ------
%   Распознать      прогнать нарисованное через сеть
%   Отменить штрих  убрать последний штрих
%   Очистить        стереть всё
%   Сохранить       положить рисунок в тестовый набор с указанным классом
%
%   Про тестовый набор
%   ------------------
%   Кнопка «Сохранить» кладёт в userTest не картинку, а сами координаты
%   штрихов. Это принципиально: если мы потом поменяем нормализацию,
%   толщину линии или размер кадра, набор останется пригодным — достаточно
%   прогнать его заново. Сохранённые картинки пришлось бы выбросить.
%
%   Наберите по десятку примеров на класс, и получите честную оценку
%   точности на реальном вводе. Синтетический тест всегда врёт в плюс, и
%   только этот набор покажет, насколько наш генератор угадал с тем, как
%   рисует человек.
%
%   Окно предпросмотра
%   ------------------
%   Справа внизу показано то, что реально ушло в сеть после нормализации.
%   Если ответ выглядит странным, смотреть надо туда: часто видно, что в
%   кадр попал случайный штрих или кривая ужалась в угол.
%
%   См. также CNPREDICT, CNPREPAREINPUT, CNCLASSES.

cfg  = cnConfig();
LIM  = [-10 10];
SPAN = LIM(2) - LIM(1);

C     = cnClasses();
names = [C.name];
keys  = [C.key];

% --- состояние ----------------------------------------------------------
strokes = {};              % завершённые штрихи, координаты холста
cur     = zeros(0,2);      % текущий штрих
hLines  = gobjects(0);     % линии на холсте, по одной на штрих
hCur    = gobjects(1);     % линия текущего штриха
drawing = false;

% =======================================================================
%  Интерфейс
% =======================================================================
fig = uifigure(Name = "CurveNet — распознавание кривых", ...
    Position = [80 80 1240 760], Color = [0.97 0.97 0.98]);

g = uigridlayout(fig, [1 2], ColumnWidth = {'1x', 380}, ...
    Padding = 10, ColumnSpacing = 10);

% --- холст --------------------------------------------------------------
ax = uiaxes(g);
ax.Layout.Row = 1; ax.Layout.Column = 1;
ax.XLim = LIM; ax.YLim = LIM;
ax.DataAspectRatio = [1 1 1];
ax.XGrid = "on"; ax.YGrid = "on";
ax.GridAlpha = 0.15;
ax.XTick = LIM(1):2:LIM(2);
ax.YTick = LIM(1):2:LIM(2);
ax.Box = "on";
ax.Title.String = "Рисуйте левой кнопкой мыши";
hold(ax, "on");
xline(ax, 0, "k-", LineWidth = 1);
yline(ax, 0, "k-", LineWidth = 1);

% Штатные взаимодействия мешают рисованию: без этого перетаскивание мыши
% начинает панорамировать оси вместо того, чтобы вести линию.
disableDefaultInteractivity(ax);
ax.Toolbar.Visible = "off";
ax.Interactions = [];

% --- правая колонка -----------------------------------------------------
right = uigridlayout(g, [8 1], ...
    RowHeight = {46, 36, 106, 128, 24, 176, 96, '1x'}, ...
    RowSpacing = 8, Padding = 0);
right.Layout.Row = 1; right.Layout.Column = 2;

btnRec = uibutton(right, Text = "Распознать", ...
    FontSize = 16, FontWeight = "bold", ...
    BackgroundColor = [0.20 0.45 0.85], FontColor = "w", ...
    ButtonPushedFcn = @(~,~) doRecognize());

rowBtn = uigridlayout(right, [1 2], Padding = 0, ColumnSpacing = 8);
uibutton(rowBtn, Text = "Отменить штрих", ButtonPushedFcn = @(~,~) doUndo());
uibutton(rowBtn, Text = "Очистить",       ButtonPushedFcn = @(~,~) doClear());

pnlAns = uipanel(right, Title = "Ответ");
gAns   = uigridlayout(pnlAns, [2 1], RowHeight = {'1x', 20}, ...
    RowSpacing = 2, Padding = [8 6 8 6]);
lblAns  = uilabel(gAns, Text = "—", FontSize = 18, FontWeight = "bold", ...
    WordWrap = "on", VerticalAlignment = "center");
lblConf = uilabel(gAns, Text = "", FontSize = 12, FontColor = [0.35 0.35 0.35]);

tbl = uitable(right, Data = table(strings(0,1), strings(0,1), ...
    VariableNames = ["вариант","%"]), ColumnWidth = {'1x', 62});

lblPrev = uilabel(right, Text = "Что видит сеть (160×160):", ...
    FontColor = [0.35 0.35 0.35]);

axPrev = uiaxes(right);
axPrev.XTick = []; axPrev.YTick = [];
axPrev.Box = "on";
disableDefaultInteractivity(axPrev);
axPrev.Toolbar.Visible = "off";
colormap(axPrev, gray(256));

pnlSave = uipanel(right, Title = "Тестовый набор");
gSave   = uigridlayout(pnlSave, [2 2], RowHeight = {28, 28}, ...
    ColumnWidth = {'1x', 110}, Padding = 8, ColumnSpacing = 6);
ddClass = uidropdown(gSave, Items = names, Value = names(1));
btnSave = uibutton(gSave, Text = "Сохранить", ...
    ButtonPushedFcn = @(~,~) doSave());
lblSaved = uilabel(gSave, Text = "", FontColor = [0.2 0.5 0.2]);
lblSaved.Layout.Row = 2; lblSaved.Layout.Column = [1 2];

lblStatus = uilabel(right, Text = "", WordWrap = "on", ...
    FontColor = [0.65 0.35 0.05], VerticalAlignment = "top");

% --- события мыши -------------------------------------------------------
fig.WindowButtonDownFcn   = @onDown;
fig.WindowButtonMotionFcn = @onMove;
fig.WindowButtonUpFcn     = @onUp;

showPreview(zeros(cfg.img.size, "uint8"));

% =======================================================================
%  Рисование
% =======================================================================
    function onDown(~,~)
        p = pointer();
        if isempty(p); return; end
        drawing = true;
        cur = p;
        hCur = plot(ax, cur(:,1), cur(:,2), "-", ...
            Color = [0.85 0.10 0.10], LineWidth = 2);
    end

    function onMove(~,~)
        if ~drawing; return; end
        p = pointer();
        if isempty(p); return; end

        % Точки, совпавшие с предыдущей, не добавляем: они дают нулевые
        % отрезки, а по ним нельзя считать длину дуги.
        if hypot(p(1)-cur(end,1), p(2)-cur(end,2)) < 1e-6
            return
        end
        cur(end+1,:) = p; %#ok<AGROW>
        set(hCur, XData = cur(:,1), YData = cur(:,2));
        drawnow limitrate
    end

    function onUp(~,~)
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

    function p = pointer()
        c = ax.CurrentPoint;
        p = c(1,1:2);
        if p(1) < LIM(1) || p(1) > LIM(2) || p(2) < LIM(1) || p(2) > LIM(2)
            p = [];
        end
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

    function doClear()
        delete(hLines(isgraphics(hLines)));
        hLines  = gobjects(0);
        strokes = {};
        cur     = zeros(0,2);
        clearAnswer();
        showPreview(zeros(cfg.img.size, "uint8"));
    end

    function clearAnswer()
        lblAns.Text  = "—";
        lblConf.Text = "";
        tbl.Data = table(strings(0,1), strings(0,1), ...
            VariableNames = ["вариант","%"]);
        lblStatus.Text = "";
        lblSaved.Text  = "";
    end

    function doRecognize()
        if isempty(strokes)
            lblStatus.Text = "Сначала нарисуйте кривую.";
            return
        end

        R = cnPredict(strokes, SPAN);

        if ~isempty(R.img)
            showPreview(R.img);
        end

        if ~R.ok
            lblAns.Text  = "не распознано";
            lblConf.Text = "";
            lblStatus.Text = R.message;
            return
        end

        lblAns.Text  = R.name;
        lblConf.Text = sprintf("уверенность %.1f%%", 100*R.confidence);

        tbl.Data = table(R.top.("название"), ...
            compose("%.1f", R.top.("вероятность %")), ...
            VariableNames = ["вариант","%"]);

        lblStatus.Text = strtrim(R.warning);

        % Класс-отказ подсвечиваем явно: это не ошибка сети, а её честный
        % ответ, что нарисованное не похоже ни на одну из кривых.
        if R.class == "scribble"
            lblAns.FontColor = [0.75 0.25 0.10];
        else
            lblAns.FontColor = [0.10 0.10 0.10];
        end
    end

    function doSave()
        if isempty(strokes)
            lblSaved.Text = "Нечего сохранять.";
            return
        end
        key = keys(names == string(ddClass.Value));
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
        lblSaved.Text = sprintf("Сохранено. Всего «%s»: %d", ddClass.Value, n);
    end

% =======================================================================
    function showPreview(img)
        cla(axPrev);
        image(axPrev, img, CDataMapping = "scaled");
        axPrev.CLim = [0 255];
        axPrev.DataAspectRatio = [1 1 1];
        axPrev.XTick = []; axPrev.YTick = [];
        axPrev.XLim = [0.5 size(img,2)+0.5];
        axPrev.YLim = [0.5 size(img,1)+0.5];
    end
end

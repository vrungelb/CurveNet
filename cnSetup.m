function cnSetup(opts)
%CNSETUP  Подключение проекта CurveNet к путям MATLAB.
%
%   cnSetup                    добавить пути на текущую сессию
%   cnSetup(save = true)       запомнить пути между запусками MATLAB
%   cnSetup(startup = true)    запускать автоматически при старте MATLAB
%   cnSetup(check = false)     без проверки состава файлов
%
%   Достаточно один раз перейти в папку проекта и выполнить cnSetup.
%
%   Почему не просто addpath(genpath(...))
%   --------------------------------------
%   genpath добавляет вообще все подпапки, включая dataset с тринадцатью
%   папками по семь тысяч картинок в каждой. MATLAB держит список файлов
%   каждой папки на пути и перечитывает его; от девяноста тысяч лишних
%   файлов он заметно тупеет, а любая опечатка в имени функции начинает
%   искаться по всему этому добру.
%
%   Поэтому папки с данными и результатами исключаются явно.
%
%   Три способа подключения
%   -----------------------
%   Без аргументов пути живут до закрытия MATLAB. Это самый безопасный
%   вариант: ничего в системе не меняется.
%
%   save = true вызывает savepath — пути записываются в общий список MATLAB
%   и переживают перезапуск. Минус в том, что если папку проекта потом
%   переместить или удалить, MATLAB будет ругаться на несуществующий путь
%   при каждом запуске, пока не почистишь.
%
%   startup = true дописывает вызов в startup.m в пользовательской папке.
%   MATLAB выполняет этот файл при каждом запуске, так что проект будет
%   подключаться сам. Аккуратнее savepath: правка видна в одном файле, и её
%   легко отменить.
%
%   См. также CNCONFIG, CNBUILDDATASET, CNPREVIEW.

arguments
    opts.save    (1,1) logical = false
    opts.startup (1,1) logical = false
    opts.check   (1,1) logical = true
end

root = fileparts(mfilename("fullpath"));

% Папки с данными и результатами на путь не идут: там нет кода, зато очень
% много файлов.
skip = ["dataset", "models", "results", "userTest", ".git"];

p = split(string(genpath(root)), pathsep);
p = p(strlength(p) > 0);

keep = true(size(p));
for i = 1:numel(p)
    parts = split(p(i), filesep);
    if any(ismember(parts, skip))
        keep(i) = false;
    end
end
p = p(keep);

addpath(strjoin(p, pathsep));

fprintf("CurveNet подключён: %s\n", root);
fprintf("Папок на пути: %d\n", numel(p));

% --- проверка состава ---------------------------------------------------
if opts.check
    need = [ ...
        "cnConfig", "cnClasses", ...
        "cnResampleArc", "cnCurvePoints", "cnSampleParams", ...
        "cnHandDistort", "cnStrokeBreak", "cnNormalize", "cnRasterize", ...
        "cnScribble", "cnRender", ...
        "cnBuildDataset", "cnSplitDataset", "cnPreview"];

    missing = need(arrayfun(@(f) exist(f, "file") ~= 2, need));
    if isempty(missing)
        fprintf("Все %d функций на месте.\n", numel(need));
    else
        fprintf(2, "Не найдено: %s\n", join(missing, ", "));
    end
end

% --- запомнить между запусками ------------------------------------------
if opts.save
    savepath;
    fprintf("Пути сохранены (savepath).\n");
end

if opts.startup
    writeStartup(root);
end
end


% =======================================================================
function writeStartup(root)
%WRITESTARTUP  Дописать вызов cnSetup в пользовательский startup.m.

up = userpath;
if isempty(up)
    warning("cnSetup:noUserpath", ...
        "userpath не задан, startup.m создать некуда.");
    return
end

file = fullfile(up, "startup.m");
line = sprintf("run(fullfile('%s','cnSetup.m'));", root);

if isfile(file)
    txt = string(fileread(file));
    if contains(txt, "cnSetup")
        fprintf("В %s вызов cnSetup уже есть.\n", file);
        return
    end
    fid = fopen(file, "a");
else
    fid = fopen(file, "w");
end

if fid < 0
    warning("cnSetup:cannotWrite", "Не удалось открыть %s на запись.", file);
    return
end
fprintf(fid, "\n%% CurveNet\n%s\n", line);
fclose(fid);

fprintf("Добавлено в %s — проект будет подключаться при старте MATLAB.\n", file);
end

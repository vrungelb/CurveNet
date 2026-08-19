function R = cnPredict(input, canvasSpan, opts)
%CNPREDICT  Распознавание нарисованной кривой.
%
%   R = CNPREDICT(strokes, canvasSpan)      штрихи с холста
%   R = CNPREDICT(img)                      готовая картинка 160x160
%   R = CNPREDICT(..., model = "classifier")
%   R = CNPREDICT(..., reload = true)       перечитать сеть с диска
%
%   Поля результата
%   ---------------
%   ok          удалось ли распознать
%   message     объяснение, если не удалось
%   warning     предупреждение, не мешающее распознаванию
%   class       ключ класса латиницей
%   name        название для показа пользователю
%   confidence  уверенность в ответе, от 0 до 1
%   top         таблица трёх лучших вариантов с вероятностями
%   reliable    прошла ли уверенность порог из cnConfig
%   img         картинка, которая ушла в сеть
%   info        результат проверок из CNPREPAREINPUT
%
%   Про уверенность
%   ---------------
%   Softmax на выходе даёт вероятности, но верить им буквально нельзя: сети
%   систематически переоценивают себя на данных, не похожих на обучающие.
%   Поэтому уверенность здесь — вспомогательный признак, а не приговор.
%   Гораздо надёжнее два других: наличие класса-отказа scribble, который
%   сеть может выбрать явно, и невязка после подгонки кривой, которая
%   появится на следующем этапе.
%
%   Тройка лучших вариантов полезнее одной цифры. Ответ «эллипс 62%,
%   окружность 35%» сразу объясняет, что произошло, а «эллипс» с
%   уверенностью 62% не объясняет ничего.
%
%   Сеть кэшируется в persistent-переменной: загрузка с диска занимает
%   заметное время, а распознавание должно быть мгновенным. Чтобы
%   подхватить переобученную сеть, вызовите с reload = true.
%
%   См. также CNPREPAREINPUT, CNTRAINCLASSIFIER, CNCANVASAPP.

arguments
    input
    canvasSpan (1,1) double {mustBePositive} = 20
    opts.model  (1,1) string  = "classifier"
    opts.reload (1,1) logical = false
end

R = struct("ok", false, "message", "", "warning", "", ...
           "class", "", "name", "", "confidence", 0, ...
           "top", table(), "reliable", false, ...
           "img", uint8.empty(0,0), "info", []);

cfg   = cnConfig();
model = loadModel(opts.model, opts.reload);

% --- подготовка ---------------------------------------------------------
if iscell(input)
    [img, info] = cnPrepareInput(input, canvasSpan);
    R.info    = info;
    R.warning = info.warning;
    if ~info.ok
        R.message = info.message;
        return
    end
else
    img = input;
    if size(img,1) ~= cfg.img.size || size(img,2) ~= cfg.img.size
        R.message = sprintf("Ожидалась картинка %dx%d.", cfg.img.size, cfg.img.size);
        return
    end
end
R.img = img;

% --- распознавание ------------------------------------------------------
scores = predict(model.net, single(img));
scores = double(scores(:));

[sorted, ord] = sort(scores, "descend");
keys = model.classKeys(:);

R.ok         = true;
R.class      = keys(ord(1));
R.name       = cnClasses(R.class).name;
R.confidence = sorted(1);
R.reliable   = sorted(1) >= cfg.refine.minConfidence;

n = min(3, numel(sorted));
names = strings(n,1);
for i = 1:n
    names(i) = cnClasses(keys(ord(i))).name;
end
R.top = table(keys(ord(1:n)), names, 100*sorted(1:n), ...
    VariableNames = ["класс","название","вероятность %"]);

if ~R.reliable
    R.warning = strtrim(R.warning + " Низкая уверенность — ответ ненадёжен.");
end
end


% =======================================================================
function model = loadModel(name, reload)
%LOADMODEL  Чтение обученной сети с кэшированием.

persistent cache cacheName

if reload || isempty(cache) || cacheName ~= name
    cfg  = cnConfig();
    file = fullfile(cfg.paths.models, name + ".mat");
    if ~isfile(file)
        error("cnPredict:noModel", ...
            "Не найдена обученная сеть %s. Сначала выполните cnTrainClassifier.", file);
    end
    L = load(file, "model");
    cache     = L.model;
    cacheName = name;
end
model = cache;
end

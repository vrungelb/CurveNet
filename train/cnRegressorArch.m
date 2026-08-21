function net = cnRegressorArch(nReg, opts)
%CNREGRESSORARCH  Архитектура свёрточного регрессора параметров кривой.
%
%   net = CNREGRESSORARCH(nReg)
%   net = CNREGRESSORARCH(nReg, width = 20, depth = 5)
%   net = CNREGRESSORARCH(..., dropout = 0.15)
%
%   Возвращает dlnetwork, готовую к обучению через trainnet со среднеквад-
%   ратичной функцией потерь.
%
%   Чем отличается от классификатора
%   --------------------------------
%   Свёрточная часть та же: пять ступеней по две свёртки 3x3, признаки для
%   формы кривой нужны те же самые. Различия в трёх местах, и каждое
%   существенно.
%
%   Голова. Вместо софтмакса — линейный выход на nReg чисел без всякой
%   нелинейности. Ограничивать его нечем: смещение центра может быть любого
%   знака, логарифм масштаба тоже.
%
%   Дропаут ослаблен с 0.35 до 0.15. У классификатора он гасит цепляние за
%   артефакты растеризации, и потеря части признаков там безболезненна:
%   решение всё равно принимается по совокупности. Регрессору же надо выдать
%   точное число, и случайное отключение половины признаков перед последним
%   слоем вносит в это число прямой шум. Совсем убирать не стоит — данных
%   много, но и переобучение никто не отменял.
%
%   Усреднение по пространству оставлено, хотя соблазн его убрать есть:
%   кажется, что раз мы предсказываем в том числе положение центра, то
%   пространственную информацию терять нельзя. На деле она не теряется:
%   каналы после пяти ступеней уже кодируют не «что», а «что и где»
%   относительно кадра, и усреднение снимает лишь абсолютные пиксельные
%   координаты, которые нам и не нужны — центр предсказывается в долях
%   кадра, а кадр у всех примеров один.
%
%   Про масштаб выходов
%   -------------------
%   Выходы имеют разный порядок: смещение центра гуляет в сотых, логарифм
%   вытянутости — в единицах. Среднеквадратичная ошибка складывает их без
%   разбора, и без выравнивания сеть занялась бы только самым крупным из
%   них. Поэтому цели стандартизуются в CNTRAINREGRESSOR перед обучением, а
%   сама сеть работает с величинами около нуля и единичного разброса. Здесь
%   про это знать не нужно, но помнить стоит: выход сети — не параметры
%   кривой, а их стандартизованный вид.
%
%   См. также CNCLASSIFIERARCH, CNTRAINREGRESSOR, CNREGRESSIONTARGETS.

arguments
    nReg         (1,1) double {mustBeInteger, mustBePositive}
    opts.width   (1,1) double {mustBeInteger, mustBePositive} = 24
    opts.depth   (1,1) double {mustBeInteger, mustBePositive} = 5
    opts.dropout (1,1) double {mustBeInRange(opts.dropout, 0, 0.9)} = 0.15
end

cfg = cnConfig();
S   = cfg.img.size;

layers = imageInputLayer([S S 1], ...
    Normalization = "rescale-zero-one", ...
    Name = "input");

ch = opts.width;
for k = 1:opts.depth
    layers = [layers; stage(k, ch)]; %#ok<AGROW>
    ch = min(ch*2, 512);
end

layers = [layers
    globalAveragePooling2dLayer(Name = "gap")
    dropoutLayer(opts.dropout, Name = "drop")
    fullyConnectedLayer(nReg, Name = "out")];

net = dlnetwork(layers);
end


% =======================================================================
function L = stage(k, ch)
%STAGE  Одна ступень: две свёртки 3x3 и прореживание вдвое.

p = sprintf("s%d_", k);
L = [
    convolution2dLayer(3, ch, Padding = "same", Name = p + "conv1")
    batchNormalizationLayer(Name = p + "bn1")
    reluLayer(Name = p + "relu1")

    convolution2dLayer(3, ch, Padding = "same", Name = p + "conv2")
    batchNormalizationLayer(Name = p + "bn2")
    reluLayer(Name = p + "relu2")

    maxPooling2dLayer(2, Stride = 2, Name = p + "pool")];
end

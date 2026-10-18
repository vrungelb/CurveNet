%CNEXPORTWEBMODELS Экспорт обученных моделей CurveNet в формат ONNX и метаданных в JSON для веб-приложения (C#).
function cnExportWebModels(outDir)

arguments
    outDir (1,1) string = ""
end

cfg = cnConfig();
if outDir == ""
    root = fileparts(cfg.paths.models);
    outDir = fullfile(root, "web", "CurveNet.Web", "Models");
end

onnxDir = fullfile(outDir, "onnx");
if ~exist(onnxDir, "dir")
    mkdir(onnxDir);
end

fprintf("Экспорт моделей в %s ...\n", onnxDir);

meta = struct();

% 1. Основной классификатор
clfPath = fullfile(cfg.paths.models, "classifier.mat");
L = load(clfPath, "model");
exportDlnetToOnnx(L.model.net, fullfile(onnxDir, "classifier.onnx"));
meta.classifierKeys = cellstr(string(L.model.classKeys(:)));
fprintf("  [OK] classifier.onnx (%d классов)\n", numel(meta.classifierKeys));

% 2. Классификатор числа лепестков розы (rosek)
rkPath = fullfile(cfg.paths.models, "rosek.mat");
Lrk = load(rkPath, "model");
exportDlnetToOnnx(Lrk.model.net, fullfile(onnxDir, "rosek.onnx"));
meta.roseKValues = double(Lrk.model.classKeys(:));
fprintf("  [OK] rosek.onnx (k = %s)\n", join(string(meta.roseKValues), ", "));

% 3. Регрессоры для всех 12 классов кривых
curves = cnClasses("curves");
meta.regressors = struct();

for i = 1:numel(curves)
    key = curves(i).key;
    regPath = fullfile(cfg.paths.models, "regress_" + key + ".mat");
    if ~isfile(regPath)
        warning("cnExportWebModels:missingRegressor", "Пропущен %s (файл не найден).", regPath);
        continue
    end
    Lr = load(regPath, "model");
    m = Lr.model;
    exportDlnetToOnnx(m.net, fullfile(onnxDir, "regress_" + key + ".onnx"));

    regMeta = struct();
    regMeta.targetCols = cellstr(string(m.targetCols(:)));
    regMeta.normMin    = double(m.normMin(:));
    regMeta.normMax    = double(m.normMax(:));
    regMeta.logGrowth  = logical(isfield(m, "logGrowth") && m.logGrowth);
    regMeta.unitAniso  = logical(isfield(m, "unitAniso") && m.unitAniso);

    meta.regressors.(key) = regMeta;
    fprintf("  [OK] regress_%s.onnx (%d выходов)\n", key, numel(regMeta.targetCols));
end

metaFile = fullfile(outDir, "models_meta.json");
writeJson(metaFile, meta);
fprintf("Метаданные сохранены: %s\n", metaFile);

% 4. Контрольный пример для сверки C# и MATLAB
T = cnSampleParams("ellipse", 1, 12345);
rec = table2struct(T(1,:));
[~, strokes] = cnRender("ellipse", rec, false);
rawStrokes = {(strokes{1} - 0.5) * 12};
R = cnPredict(rawStrokes, 20);
ver = struct( ...
    "strokes", {rawStrokes}, ...
    "canvasSpan", 20, ...
    "predClass", R.class, ...
    "confidence", R.confidence, ...
    "params", R.params, ...
    "residual", R.fit.residual, ...
    "equation", R.equation, ...
    "idealPoints", R.idealPoints);
writeJson(fullfile(outDir, "verification.json"), ver);
fprintf("Контрольный пример сохранён: %s\n", fullfile(outDir, "verification.json"));

end

function writeJson(file, data)
jsonTxt = jsonencode(data, PrettyPrint = true);
fid = fopen(file, "w", "n", "UTF-8");
fwrite(fid, jsonTxt, "char");
fclose(fid);
end

% =========================================================================
% Прямая сериализация dlnetwork CurveNet в ONNX (Protobuf Opset 13)
% со слиянием Conv2D + BatchNorm и точным согласованием раскладки NCHW
% =========================================================================
function exportDlnetToOnnx(net, filename)

layers = net.Layers;
nL = numel(layers);

inLayer = layers(1);
H = inLayer.InputSize(1);
W = inLayer.InputSize(2);
C = inLayer.InputSize(3);
rescaleInput = (string(inLayer.Normalization) == "rescale-zero-one");

initializers = {};
nodes = {};
curTensor = "input";
curH = H;
curW = W;
curC = C;
firstConv = true;

i = 2;
while i <= nL
    L = layers(i);
    cls = class(L);

    if cls == "nnet.cnn.layer.Convolution2DLayer"
        w = single(L.Weights); % [kH, kW, Cin, Cout]
        b = single(L.Bias(:)); % [Cout, 1]
        kH = size(w, 1);
        kW = size(w, 2);
        cOut = size(w, 4);

        if firstConv && rescaleInput
            w = w / single(255.0);
            firstConv = false;
        end

        % Слияние со следующим BatchNormalizationLayer, если он идёт следом
        if i + 1 <= nL && class(layers(i+1)) == "nnet.cnn.layer.BatchNormalizationLayer"
            bn = layers(i+1);
            meanVal = single(bn.TrainedMean(:));
            varVal  = single(bn.TrainedVariance(:));
            scale   = single(bn.Scale(:));
            offset  = single(bn.Offset(:));
            epsVal  = single(bn.Epsilon);

            factor = scale ./ sqrt(varVal + epsVal);
            w = w .* reshape(factor, 1, 1, 1, cOut);
            b = (b - meanVal) .* factor + offset;
            i = i + 1;
        end

        % Перевод весов из MATLAB column-major [kH, kW, Cin, Cout]
        % в ONNX C-order [Cout, Cin, kH, kW] (в памяти первыми идут kW, kH, Cin, Cout)
        wOnnx = permute(w, [2, 1, 3, 4]);
        wName = string(L.Name) + "_W";
        bName = string(L.Name) + "_B";
        outName = string(L.Name) + "_out";

        initializers{end+1} = pbTensorFloat(wName, [cOut, curC, kH, kW], wOnnx(:)); %#ok<AGROW>
        initializers{end+1} = pbTensorFloat(bName, cOut, b(:)); %#ok<AGROW>

        padH = floor(kH / 2);
        padW = floor(kW / 2);
        attrs = [ ...
            pbAttrInts("kernel_shape", [kH, kW]), ...
            pbAttrInts("strides", [L.Stride(1), L.Stride(2)]), ...
            pbAttrInts("pads", [padH, padW, padH, padW])];

        nodes{end+1} = pbNode("Conv", string(L.Name), [curTensor, wName, bName], outName, attrs); %#ok<AGROW>
        curTensor = outName;
        curC = cOut;

    elseif cls == "nnet.cnn.layer.ReLULayer"
        outName = string(L.Name) + "_out";
        nodes{end+1} = pbNode("Relu", string(L.Name), curTensor, outName, uint8.empty(1,0)); %#ok<AGROW>
        curTensor = outName;

    elseif cls == "nnet.cnn.layer.MaxPooling2DLayer"
        outName = string(L.Name) + "_out";
        pH = L.PoolSize(1);
        pW = L.PoolSize(2);
        sH = L.Stride(1);
        sW = L.Stride(2);
        attrs = [ ...
            pbAttrInts("kernel_shape", [pH, pW]), ...
            pbAttrInts("strides", [sH, sW]), ...
            pbAttrInts("pads", [0, 0, 0, 0])];
        nodes{end+1} = pbNode("MaxPool", string(L.Name), curTensor, outName, attrs); %#ok<AGROW>
        curTensor = outName;
        curH = floor(curH / sH);
        curW = floor(curW / sW);

    elseif cls == "nnet.cnn.layer.FlattenLayer"
        outName = string(L.Name) + "_out";
        attrs = pbAttrInt("axis", 1);
        nodes{end+1} = pbNode("Flatten", string(L.Name), curTensor, outName, attrs); %#ok<AGROW>
        curTensor = outName;

    elseif cls == "nnet.cnn.layer.DropoutLayer"
        % На инференсе Dropout является тождественным оператором

    elseif cls == "nnet.cnn.layer.FullyConnectedLayer"
        w = single(L.Weights); % [Out, In]
        b = single(L.Bias(:)); % [Out, 1]
        nOut = size(w, 1);
        nIn  = size(w, 2);

        % Если вход пришёл из Flatten после свёрток [curH, curW, curC],
        % согласуем порядок признаков MATLAB [H, W, C] с ONNX NCHW [C, H, W]
        if nIn == curH * curW * curC && curC > 1
            w4 = reshape(w, [nOut, curH, curW, curC]);
            % В ONNX NCHW после Flatten быстрее всего бежит W, затем H, затем C
            wOnnx = permute(w4, [3, 2, 4, 1]); % [W, H, C, Out] -> в памяти C-order [Out, C*H*W]
            curH = 1; curW = 1; curC = nOut;
        else
            % Обычный FC: для C-order [Out, In] первым в памяти должен бежать In
            wOnnx = permute(w, [2, 1]); % [In, Out]
        end

        wName = string(L.Name) + "_W";
        bName = string(L.Name) + "_B";
        outName = string(L.Name) + "_out";

        initializers{end+1} = pbTensorFloat(wName, [nOut, nIn], wOnnx(:)); %#ok<AGROW>
        initializers{end+1} = pbTensorFloat(bName, nOut, b(:)); %#ok<AGROW>

        attrs = [pbAttrInt("transB", 1), pbAttrFloat("alpha", 1.0), pbAttrFloat("beta", 1.0)];
        nodes{end+1} = pbNode("Gemm", string(L.Name), [curTensor, wName, bName], outName, attrs); %#ok<AGROW>
        curTensor = outName;
        outDim = nOut;

    elseif cls == "nnet.cnn.layer.SoftmaxLayer"
        outName = "output";
        attrs = pbAttrInt("axis", 1);
        nodes{end+1} = pbNode("Softmax", string(L.Name), curTensor, outName, attrs); %#ok<AGROW>
        curTensor = outName;
    end

    i = i + 1;
end

% Переименуем последний выход в "output", если он ещё не "output"
if curTensor ~= "output"
    nodes{end} = pbNodeReplaceOutput(nodes{end}, curTensor, "output");
end

inputInfo  = pbValueInfo("input",  [1, C, H, W]);
outputInfo = pbValueInfo("output", [1, outDim]);

graphBytes = [ ...
    horzcat(nodes{:}), ...
    pbFieldBytes(2, unicode2native("CurveNet", "UTF-8")), ...
    horzcat(initializers{:}), ...
    pbFieldBytes(11, inputInfo), ...
    pbFieldBytes(12, outputInfo)];

opsetBytes = [ ...
    pbFieldBytes(1, uint8.empty(1,0)), ...
    pbFieldVarint(2, 13)];

modelBytes = [ ...
    pbFieldVarint(1, 7), ...
    pbFieldBytes(7, graphBytes), ...
    pbFieldBytes(8, opsetBytes)];

fid = fopen(filename, "w");
fwrite(fid, modelBytes, "uint8");
fclose(fid);
end

function b = pbNode(opType, name, inputs, output, attrs)
b = uint8.empty(1,0);
for k = 1:numel(inputs)
    b = [b, pbFieldString(1, inputs(k))]; %#ok<AGROW>
end
b = [b, pbFieldString(2, output)];
b = [b, pbFieldString(3, name)];
b = [b, pbFieldString(4, opType)];
b = [b, attrs];
b = pbFieldBytes(1, b);
end

function b = pbNodeReplaceOutput(nodeFieldBytes, oldOut, newOut)
oldBytes = pbFieldString(2, oldOut);
newBytes = pbFieldString(2, newOut);
raw = nodeFieldBytes;
% Находим payload внутри внешнего поля 1 (NodeProto)
[~, hdrLen] = pbReadVarint(raw(2:end));
inner = raw(2 + hdrLen : end);
idx = strfind(inner, oldBytes);
if ~isempty(idx)
    k = idx(1);
    inner = [inner(1:k-1), newBytes, inner(k+numel(oldBytes):end)];
end
b = pbFieldBytes(1, inner);
end

function b = pbTensorFloat(name, dims, dataSingle)
b = uint8.empty(1,0);
for d = dims(:).'
    b = [b, pbFieldVarint(1, d)]; %#ok<AGROW>
end
b = [b, pbFieldVarint(2, 1)]; % FLOAT = 1
b = [b, pbFieldString(8, name)];
rawBytes = typecast(single(dataSingle(:)).', "uint8");
b = [b, pbFieldBytes(9, rawBytes)];
b = pbFieldBytes(5, b); % GraphProto.initializer = 5
end

function b = pbValueInfo(name, dims)
dimBytes = uint8.empty(1,0);
for d = dims(:).'
    dimBytes = [dimBytes, pbFieldBytes(1, pbFieldVarint(1, d))]; %#ok<AGROW>
end
shapeBytes  = pbFieldBytes(2, dimBytes);
tensorBytes = [pbFieldVarint(1, 1), shapeBytes];
typeBytes   = pbFieldBytes(1, tensorBytes);
b = [pbFieldString(1, name), pbFieldBytes(2, typeBytes)];
end

function b = pbAttrInt(name, val)
inner = [ ...
    pbFieldString(1, name), ...
    pbFieldVarint(3, val), ...
    pbFieldVarint(20, 2)]; % INT = 2
b = pbFieldBytes(5, inner);
end

function b = pbAttrFloat(name, val)
fBytes = typecast(single(val), "uint8");
inner = [ ...
    pbFieldString(1, name), ...
     uint8(2*8 + 5), fBytes, ...
    pbFieldVarint(20, 1)]; % FLOAT = 1
b = pbFieldBytes(5, inner);
end

function b = pbAttrInts(name, vals)
inner = pbFieldString(1, name);
for v = vals(:).'
    inner = [inner, pbFieldVarint(8, v)]; %#ok<AGROW>
end
inner = [inner, pbFieldVarint(20, 7)]; % INTS = 7
b = pbFieldBytes(5, inner);
end

function b = pbFieldString(fieldNum, str)
b = pbFieldBytes(fieldNum, unicode2native(char(str), "UTF-8"));
end

function b = pbFieldBytes(fieldNum, payload)
tag = pbVarint(uint64(fieldNum * 8 + 2));
len = pbVarint(uint64(numel(payload)));
b = [tag, len, uint8(payload(:).')];
end

function b = pbFieldVarint(fieldNum, val)
tag = pbVarint(uint64(fieldNum * 8 + 0));
v   = pbVarint(uint64(val));
b = [tag, v];
end

function out = pbVarint(v)
v = uint64(v);
out = uint8.empty(1,0);
while v >= 128
    out(end+1) = uint8(bitor(bitand(v, 127), 128)); %#ok<AGROW>
    v = bitshift(v, -7);
end
out(end+1) = uint8(v);
end

function [val, len] = pbReadVarint(bytes)
val = uint64(0);
shift = 0;
len = 0;
for i = 1:numel(bytes)
    len = len + 1;
    b = uint64(bytes(i));
    val = bitor(val, bitshift(bitand(b, 127), shift));
    if bitand(b, 128) == 0
        return
    end
    shift = shift + 7;
end
end

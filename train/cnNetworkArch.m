%CNNETWORKARCH Свёрточная архитектура нейросети CurveNet (классификатор и регрессор).
function net = cnNetworkArch(numOutputs, opts)

arguments
    numOutputs (1,1) double {mustBeInteger, mustBePositive}
    opts.width (1,1) double {mustBeInteger, mustBePositive} = 24
    opts.depth (1,1) double {mustBeInteger, mustBePositive} = 5
    opts.dropout (1,1) double {mustBeInRange(opts.dropout, 0, 0.9)} = 0.35
    opts.isRegressor (1,1) logical = false
end

cfg = cnConfig();
S = cfg.img.size;

layers = imageInputLayer([S S 1], ...
    Normalization = "rescale-zero-one", ...
    Name = "input");

ch = opts.width;
stagesCell = cell(opts.depth, 1);
for k = 1:opts.depth
    stagesCell{k} = stage(k, ch);
    ch = min(ch*2, 512);
end
layers = [layers; vertcat(stagesCell{:})];

layers = [layers
    convolution2dLayer(1, 32, Name = "feat_compress")
    batchNormalizationLayer(Name = "feat_bn")
    reluLayer(Name = "feat_relu")
    flattenLayer(Name = "flatten")
    dropoutLayer(opts.dropout, Name = "drop")
    fullyConnectedLayer(256, Name = "fc_hidden")
    reluLayer(Name = "fc_relu")];

if opts.isRegressor
    layers = [layers
        fullyConnectedLayer(numOutputs, Name = "fc_regress")];
else
    layers = [layers
        fullyConnectedLayer(numOutputs, Name = "fc")
        softmaxLayer(Name = "softmax")];
end

net = dlnetwork(layers);
end

function L = stage(k, ch)

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

%CNCONFIG  Единый центр настроек и путей проекта.
function cfg = cnConfig()

persistent CFG
if ~isempty(CFG)
    cfg = CFG;
    return
end

here = fileparts(mfilename("fullpath"));
root = fileparts(here);

cfg.paths.images   = fullfile(root, "dataset", "images");
cfg.paths.meta     = fullfile(root, "dataset", "meta.mat");
cfg.paths.split    = fullfile(root, "dataset", "split.mat");
cfg.paths.models   = fullfile(root, "models");
cfg.paths.results  = fullfile(root, "results");
cfg.paths.userTest = fullfile(root, "userTest");

cfg.img.size        = 160;
cfg.img.pad         = 0.08;
cfg.img.lineWidth   = [1.6 3.2];
cfg.img.softenSigma = [0.4 0.9];
cfg.img.format      = "png";
cfg.img.splatStep   = 0.4;
cfg.img.lineOnBlack = true;

cfg.curve.nPoints       = [150 320];
cfg.curve.densityJitter = [0.7 1.3];

cfg.data.perClass = 9000;
cfg.data.split    = [0.70 0.15 0.15];
cfg.data.seed     = 20260818;

cfg.aug.warpAmp   = [0.015 0.050];
cfg.aug.warpScale = 7;
cfg.aug.warpShare = 0.65;

cfg.aug.radialAmp = [0 0.06];

cfg.aug.tremorAmp   = [0.003 0.010];
cfg.aug.tremorSigma = 2.5;

cfg.aug.openProb    = 0.60;
cfg.aug.openGap     = [0.01 0.05];
cfg.aug.breakProb   = 0.22;
cfg.aug.breakCount  = [1 2];
cfg.aug.breakLen    = [0.02 0.06];
cfg.aug.breakMargin = 0.08;
cfg.aug.minFragment = 0.03;

cfg.aug.rotation = [0 360];
cfg.aug.aniso    = [0.85 1.15];
cfg.aug.shear    = [-0.12 0.12];

cfg.aug.scaleJitter  = [0.92 1.08];
cfg.aug.offsetJitter = [-0.03 0.03];

cfg.input.minPoints       = 12;
cfg.input.minBoxFrac      = 0.05;
cfg.input.minStrokeFrac   = 0.02;
cfg.input.minStrokePoints = 5;
cfg.input.edgeTol         = 0.005;

cfg.train.miniBatchSize      = 256;
cfg.train.maxEpochs          = 30;
cfg.train.initialLearnRate   = 1e-3;
cfg.train.lrDropFactor       = 0.2;
cfg.train.lrDropPeriod       = 6;
cfg.train.l2Regularization   = 1e-4;
cfg.train.validationPatience = 14;
cfg.train.shuffle            = "every-epoch";
cfg.train.environment        = "auto";
cfg.train.preprocessing      = "parallel";
cfg.train.verboseFreq        = 50;

cfg.regress.miniBatchSize    = 256;
cfg.regress.maxEpochs        = 35;
cfg.regress.initialLearnRate = 1e-3;
cfg.regress.lrDropFactor     = 0.2;
cfg.regress.lrDropPeriod     = 18;
cfg.regress.l2Regularization = 1e-4;

cfg.refine.minConfidence = 0.55;

CFG = cfg;
end

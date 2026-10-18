%CNRENDER
function [img, strokes, tf] = cnRender(key, rec, doRaster)

arguments
    key (1,1) string
    rec (1,1) struct
    doRaster (1,1) logical = true
end

c = cnClasses(key);

if c.isCurve
    strokes = cnCurvePoints(key, rec, rec.nPoints);
else
    if exist("cnScribble", "file") == 0
        error("cnRender:noScribble", ...
            "Класс «%s» требует cnScribble, а его нет на пути.", key);
    end
    strokes = cnScribble(rec, rec.nPoints);
end

[strokes, pOrig] = cnHandDistort(strokes, rec, c.closed);
strokes = cnLineBreak(strokes, rec, c.closed);

[strokes, tf] = cnNormalize(strokes, rec);
tf.origin    = tf.toNorm(pOrig);
tf.normScale = 1 / tf.scale;

if doRaster
    img = cnRasterize(strokes, rec.lineWidth, rec.softenSigma);
else
    img = uint8.empty(0,0);
end
end
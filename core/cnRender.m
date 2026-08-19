function [img, strokes, tf] = cnRender(key, rec)
%CNRENDER  Полная цепочка от рецепта до картинки.
%
%   img                 = CNRENDER(key, rec)
%   [img, strokes]      = CNRENDER(key, rec)
%   [img, strokes, tf]  = CNRENDER(key, rec)
%
%   key  ключ класса из CNCLASSES
%   rec  строка рецепта из CNSAMPLEPARAMS в виде структуры:
%        rec = table2struct(T(i,:))
%
%   img      изображение uint8 размера cfg.img.size
%   strokes  штрихи в нормализованном кадре, как они ушли в растр
%   tf       преобразование в исходные координаты (понадобится регрессорам)
%
%   Здесь собран весь конвейер: идеальная кривая, искажение руки, отрывы
%   пера, нормализация, растеризация. Держать его в одном месте важно —
%   этой же функцией пользуется и генератор датасета, и просмотрщик, и
%   любые проверки. Иначе неизбежно возникнут две слегка разошедшиеся
%   версии цепочки, и расхождение вылезет там, где его меньше всего ждёшь.
%
%   Функция полностью детерминирована: один и тот же рецепт всегда даёт
%   одну и ту же картинку. Вся случайность разыграна раньше, в
%   CNSAMPLEPARAMS, и записана в рецепт, включая seed для мелких деталей.
%
%   См. также CNSAMPLEPARAMS, CNCURVEPOINTS, CNHANDDISTORT, CNSTROKEBREAK,
%   CNNORMALIZE, CNRASTERIZE, CNBUILDDATASET.

arguments
    key (1,1) string
    rec (1,1) struct
end

c = cnClasses(key);

% --- идеальная кривая или каракуля --------------------------------------
if c.isCurve
    strokes = cnCurvePoints(key, rec, rec.nPoints);
else
    if exist("cnScribble", "file") ~= 2
        error("cnRender:noScribble", ...
            "Класс «%s» требует cnScribble, а его нет на пути.", key);
    end
    strokes = cnScribble(rec, rec.nPoints);
end

% --- рука ---------------------------------------------------------------
strokes = cnHandDistort(strokes, rec, c.closed);
strokes = cnStrokeBreak(strokes, rec, c.closed);

% --- кадр и растр -------------------------------------------------------
[strokes, tf] = cnNormalize(strokes, rec);
img = cnRasterize(strokes, rec.lineWidth, rec.softenSigma);
end

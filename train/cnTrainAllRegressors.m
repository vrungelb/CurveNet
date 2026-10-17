%CNTRAINALLREGRESSORS Последовательное обучение регрессоров всех кривых.
function cnTrainAllRegressors(opts)

arguments
    opts.plots (1,1) logical = false
end

classes = [cnClasses("curves").key];
fprintf("Обучение %d регрессоров...\n", numel(classes));

if any(classes == "rose")
    fprintf("\n>>> Обучение классификатора лепестков розы (rosek) <<<\n");
    cnTrainRoseK(plots = opts.plots);
end

for c = classes
    fprintf("\n>>> Обучение регрессора для: %s <<<\n", c);
    cnTrainRegressor(c, plots = opts.plots);
end

fprintf("\nВсе регрессоры успешно обучены!\n");
end
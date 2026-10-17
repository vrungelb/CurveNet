%CNVERTCATTABLES  Вертикальная склейка таблиц с разным набором столбцов.
function T = cnVertcatTables(rows)

rows = rows(~cellfun(@isempty, rows));
if isempty(rows)
    T = table();
    return
end

names = string.empty(1,0);
for i = 1:numel(rows)
    names = union(names, string(rows{i}.Properties.VariableNames), "stable");
end

for i = 1:numel(rows)
    h    = height(rows{i});
    miss = setdiff(names, string(rows{i}.Properties.VariableNames), "stable");

    for m = miss
        p = protoOf(rows, m);

        if isstring(p)
            rows{i}.(m) = repmat(string(missing), h, 1);
        elseif iscategorical(p)
            rows{i}.(m) = repmat(categorical(missing), h, 1);
        elseif islogical(p)
            rows{i}.(m) = false(h, 1);
        elseif iscell(p)
            rows{i}.(m) = repmat({missing}, h, 1);
        elseif isnumeric(p)
            rows{i}.(m) = cast(nan(h, 1), class(p));
        else
            error("cnVertcatTables:unsupportedType", ...
                "Столбец %s имеет неподдерживаемый тип %s.", m, class(p));
        end
    end
    rows{i} = rows{i}(:, names);
end
T = vertcat(rows{:});
end

function v = protoOf(rows, name)
v = NaN;
for i = 1:numel(rows)
    if ismember(name, string(rows{i}.Properties.VariableNames))
        v = rows{i}.(name)(1);
        return
    end
end
end

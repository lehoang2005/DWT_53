function kv = dwt53_read_key_value_file(path)
%DWT53_READ_KEY_VALUE_FILE  Read deterministic "key = value" metadata.

    text = fileread(path);
    lines = regexp(text, '\r\n|\n|\r', 'split');
    kv = struct();
    for i = 1:numel(lines)
        line = strtrim(lines{i});
        if isempty(line) || line(1) == '#'
            continue;
        end
        token = regexp(line, '^([A-Za-z][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$', ...
            'tokens', 'once');
        if isempty(token)
            error('dwt53_read_key_value_file:badLine', ...
                'Malformed metadata line %d in %s: %s', i, path, line);
        end
        key = lower(token{1});
        if isfield(kv, key)
            error('dwt53_read_key_value_file:duplicateKey', ...
                'Duplicate key %s in %s.', key, path);
        end
        kv.(key) = token{2};
    end
end

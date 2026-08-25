function values = dwt53_read_dec_vector(path, expected_count)
%DWT53_READ_DEC_VECTOR  Strict reader for one-decimal-integer-per-line files.

    fid = fopen(path, 'r');
    if fid < 0
        error('dwt53_read_dec_vector:fileOpen', 'Could not open %s.', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    % A scalar Inf requests all remaining values and is supported across
    % MATLAB releases.  [Inf, 1] is rejected as an invalid matrix size by
    % some releases because the first fscanf dimension must be finite.
    parsed = fscanf(fid, '%f', Inf);
    parsed = parsed(:);
    remainder = fread(fid, Inf, '*char').';
    clear cleaner;

    if any(~isspace(remainder))
        error('dwt53_read_dec_vector:malformed', ...
            'Non-numeric content remains in %s.', path);
    end
    if nargin >= 2 && ~isempty(expected_count) && numel(parsed) ~= expected_count
        error('dwt53_read_dec_vector:wrongCount', ...
            '%s contains %d values; expected %d.', path, numel(parsed), expected_count);
    end
    if any(~isfinite(parsed)) || any(mod(parsed, 1) ~= 0)
        error('dwt53_read_dec_vector:notInteger', ...
            '%s contains a non-integer value.', path);
    end
    values = int64(parsed);
end

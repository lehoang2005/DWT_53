function values = dwt53_read_hex_vector(path, bits, is_signed, expected_count)
%DWT53_READ_HEX_VECTOR  Strict fixed-width HEX reader with exact line count.

    validateattributes(bits, {'numeric'}, ...
        {'scalar','positive','integer','<=',32}, mfilename, 'bits');
    if mod(bits, 4) ~= 0
        error('dwt53_read_hex_vector:badBits', 'bits must be a multiple of four.');
    end
    validateattributes(expected_count, {'numeric'}, ...
        {'scalar','nonnegative','integer'}, mfilename, 'expected_count');

    fid = fopen(path, 'rb');
    if fid < 0
        error('dwt53_read_hex_vector:fileOpen', 'Could not open %s.', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    raw = fread(fid, Inf, '*uint8');
    clear cleaner;
    raw(raw == 13) = [];  % Accept either LF or CRLF working trees.

    digits_per_line = bits / 4;
    record_bytes = digits_per_line + 1;
    expected_bytes = expected_count * record_bytes;
    if numel(raw) ~= expected_bytes
        error('dwt53_read_hex_vector:wrongSize', ...
            ['%s has %d normalized bytes; expected %d (%d records of ' ...
             '%d hex digits plus LF).'], ...
            path, numel(raw), expected_bytes, expected_count, digits_per_line);
    end
    if expected_count == 0
        values = int64([]);
        return;
    end

    records = reshape(raw, record_bytes, expected_count);
    if any(records(end, :) ~= 10)
        error('dwt53_read_hex_vector:missingNewline', ...
            'Every fixed-width record in %s must end in LF.', path);
    end
    digits = records(1:digits_per_line, :);
    is_digit = digits >= uint8('0') & digits <= uint8('9');
    is_upper = digits >= uint8('A') & digits <= uint8('F');
    is_lower = digits >= uint8('a') & digits <= uint8('f');
    if any(~(is_digit(:) | is_upper(:) | is_lower(:)))
        error('dwt53_read_hex_vector:badDigit', ...
            '%s contains a non-hex character.', path);
    end

    unsigned_values = double(hex2dec(char(digits.')));
    if is_signed
        values = int64(unsigned_values);
        negative = unsigned_values >= 2^(bits - 1);
        values(negative) = int64(unsigned_values(negative) - 2^bits);
    else
        values = int64(unsigned_values);
    end
    values = values(:);
end

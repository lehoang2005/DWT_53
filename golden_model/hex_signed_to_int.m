function vals = hex_signed_to_int(hex_strs, bits)
%HEX_SIGNED_TO_INT  Decode fixed-width two's-complement hex to signed integers.
%
%   vals = HEX_SIGNED_TO_INT(hex_strs, bits) is the exact inverse of
%   int_to_hex_signed.m. hex_strs is a char matrix (one hex string per
%   row, BITS/4 hex digits each); returns an int64 column vector.
%
%   INPUT
%       hex_strs - char matrix, one hex string per row
%       bits     - positive integer, multiple of 4, matching the width
%                  used by int_to_hex_signed.m
%
%   OUTPUT
%       vals - int64 column vector, numel = size(hex_strs,1)

    validateattributes(bits, {'numeric'}, {'scalar','positive','integer'}, mfilename, 'bits');
    if mod(bits, 4) ~= 0
        error('hex_signed_to_int:badBits', 'bits must be a multiple of 4 (got %d).', bits);
    end

    u = double(hex2dec(hex_strs));    % unsigned value(s), vectorized over rows
    half = 2^(bits-1);
    full = 2^bits;

    vals = int64(u);
    is_negative = (u >= half);
    vals(is_negative) = int64(u(is_negative) - full);
end

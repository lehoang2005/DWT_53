function hex_matrix = int_to_hex_signed(vals, bits)
%INT_TO_HEX_SIGNED  Encode signed integers as fixed-width two's-complement hex.
%
%   hex_matrix = INT_TO_HEX_SIGNED(vals, bits) converts every element of
%   integer-valued array VALS into its BITS-bit signed two's-complement
%   representation, printed as uppercase hex with exactly BITS/4 digits
%   (BITS must be a multiple of 4). Output is a char matrix: one row per
%   input element, in the same linear order as VALS(:) -- i.e. row k
%   corresponds to vals(k) when vals is treated column-major, so callers
%   must flatten with their own row-major convention BEFORE calling this
%   (see export_golden_vectors.m, which uses reshape(A.',[],1)).
%
%   This is the single chokepoint used by export_golden_vectors.m to
%   avoid re-deriving two's-complement wraparound ad hoc at each call
%   site (algorithm_spec_v0.1 / project brief Section 6: "Đối với
%   coefficient âm trong file hex: khóa bit width, xuất signed
%   two's-complement đúng bit width").
%
%   INPUT
%       vals - integer-valued numeric array (any shape; flattened
%              internally via vals(:))
%       bits - positive integer, multiple of 4 (e.g. 8 for Y8 pixels,
%              16 for the frozen coefficient storage baseline,
%              spec Section 5.2)
%
%   OUTPUT
%       hex_matrix - numel(vals) x (bits/4) char matrix of hex digits
%
%   Values must lie within the representable signed range
%   [-2^(bits-1), 2^(bits-1)-1]; out-of-range values raise an error
%   rather than silently wrapping or saturating (no silent clipping is
%   allowed anywhere in this project).

    validateattributes(bits, {'numeric'}, {'scalar','positive','integer'}, mfilename, 'bits');
    if mod(bits, 4) ~= 0
        error('int_to_hex_signed:badBits', 'bits must be a multiple of 4 (got %d).', bits);
    end

    v = double(vals(:));
    if any(~isfinite(v)) || any(mod(v, 1) ~= 0)
        error('int_to_hex_signed:notInteger', 'vals must contain only finite integer values.');
    end

    lo = -(2^(bits-1));
    hi = 2^(bits-1) - 1;
    if any(v < lo) || any(v > hi)
        error('int_to_hex_signed:outOfRange', ...
            'value(s) outside representable %d-bit signed range [%d, %d] (min=%d, max=%d).', ...
            bits, lo, hi, min(v), max(v));
    end

    twos = mod(v, 2^bits);            % wraps negatives to unsigned two's-complement form
    ndigits = bits / 4;
    hex_matrix = dec2hex(twos, ndigits);
end

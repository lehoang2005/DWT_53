function [LL, HL, LH, HH] = dwt53_unpack_2d(packed)
%DWT53_UNPACK_2D  Split a canonically-packed 2D coefficient matrix.
%
%   [LL, HL, LH, HH] = DWT53_UNPACK_2D(packed) is the exact inverse of
%   dwt53_pack_2d.m. packed must be (2R)x(2C); quadrants are extracted as
%
%       LL = packed(1:R,     1:C)          HL = packed(1:R,     C+1:2C)
%       LH = packed(R+1:2R,  1:C)          HH = packed(R+1:2R,  C+1:2C)
%
%   per algorithm_spec_v0.1 Section 8.2.

    if isempty(packed)
        error('dwt53_unpack_2d:emptyInput', 'packed must not be empty.');
    end
    [rows, cols] = size(packed);
    if mod(rows, 2) ~= 0 || mod(cols, 2) ~= 0
        error('dwt53_unpack_2d:oddDimension', ...
            'packed matrix dimensions must both be even (got %dx%d).', rows, cols);
    end
    if any(~isfinite(packed(:))) || any(mod(packed(:), 1) ~= 0)
        error('dwt53_unpack_2d:notInteger', 'packed must contain only finite integer values.');
    end

    R = rows / 2;
    C = cols / 2;
    packed = int64(packed);

    LL = packed(1:R,       1:C);
    HL = packed(1:R,       C+1:2*C);
    LH = packed(R+1:2*R,   1:C);
    HH = packed(R+1:2*R,   C+1:2*C);
end

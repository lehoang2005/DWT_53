function [img, meta] = gen_dwt53_test_frame(rows, cols)
%GEN_DWT53_TEST_FRAME  Deterministic Y8 frame shared by MATLAB and DE10 RTL.
%
%   img = GEN_DWT53_TEST_FRAME(rows, cols) returns a rows-by-cols uint8
%   matrix. Both dimensions must be positive multiples of four because the
%   project performs exactly two DWT levels.
%
%   With zero-based coordinates x (column) and y (row):
%       t = 17*x + 31*y + xor(bitand(x,255), bitand(y,255)) ...
%           + 127*bitand(x+y,1)
%       pixel = bitand(t,255)
%
%   This definition uses only addition, AND and XOR, so the DE10 test-frame
%   generator can implement it bit-identically without multipliers or
%   floating-point rounding. Raster order is left-to-right, top-to-bottom.

    if nargin < 1 || isempty(rows)
        rows = 720;
    end
    if nargin < 2 || isempty(cols)
        cols = 1280;
    end
    validateattributes(rows, {'numeric'}, ...
        {'scalar','positive','integer'}, mfilename, 'rows');
    validateattributes(cols, {'numeric'}, ...
        {'scalar','positive','integer'}, mfilename, 'cols');
    if mod(rows, 4) ~= 0 || mod(cols, 4) ~= 0
        error('gen_dwt53_test_frame:notDivisibleBy4', ...
            'rows and cols must both be divisible by 4 (got %dx%d).', rows, cols);
    end

    x = uint32(0:cols-1);
    img = zeros(rows, cols, 'uint8');
    for row = 1:rows
        y = uint32(row - 1);
        checker = uint32(127) .* bitand(x + y, uint32(1));
        mixed = bitxor(bitand(x, uint32(255)), bitand(y, uint32(255)));
        t = uint32(17) .* x + uint32(31) .* y + mixed + checker;
        img(row, :) = uint8(bitand(t, uint32(255)));
    end

    meta = struct();
    meta.rule_id = 'DWT53_TEST_FRAME_V1';
    meta.rows = rows;
    meta.cols = cols;
    meta.sample_format = 'Y8 unsigned';
    meta.order = 'raster row-major';
    meta.equation = [ ...
        'pixel(x,y) = (17*x + 31*y + ((x&255) XOR (y&255)) ' ...
        '+ 127*((x+y)&1)) & 255'];
end

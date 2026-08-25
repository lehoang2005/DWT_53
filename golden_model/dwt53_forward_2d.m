function [LL, HL, LH, HH] = dwt53_forward_2d(img)
%DWT53_FORWARD_2D  Forward one-level 2D reversible Le Gall 5/3 transform.
%
%   [LL, HL, LH, HH] = DWT53_FORWARD_2D(img) applies the separable 5/3
%   lifting transform per algorithm_spec_v0.1 Section 8:
%     1. horizontal 1D forward transform across every row  (Section 8.1.1)
%     2. vertical   1D forward transform down  every column of the
%        row-transformed result                             (Section 8.1.2)
%
%   Subband naming (spec Section 8.2): the FIRST letter names the
%   horizontal filter, the SECOND letter names the vertical filter.
%       LL = horizontal Low,  vertical Low
%       HL = horizontal High, vertical Low
%       LH = horizontal Low,  vertical High
%       HH = horizontal High, vertical High
%   This function does not itself pack LL/HL/LH/HH into a single
%   matrix; use dwt53_pack_2d.m for the canonical [LL HL; LH HH] layout
%   (spec Section 8.2), which is verified bit-exact against the
%   Section 10.4 canonical 4x4 vector in tests/test_dwt53_2d.m.
%
%   INPUT
%       img - 2D integer-valued matrix, img(y,x) with y = row = vertical
%             coordinate, x = col = horizontal coordinate (spec Section 8).
%             Both dimensions must be even.
%
%   OUTPUT
%       LL, HL, LH, HH - each (rows/2) x (cols/2), signed int64.
%
%   Reuses dwt53_forward_1d.m for every row/column pass -- no lifting
%   arithmetic is duplicated here.

    % ---------------------------------------------------------------
    % Input validation
    % ---------------------------------------------------------------
    if isempty(img)
        error('dwt53_forward_2d:emptyInput', 'img must not be empty.');
    end
    if ~ismatrix(img) || isvector(img)
        error('dwt53_forward_2d:notMatrix', 'img must be a 2D matrix (not a vector).');
    end
    if any(~isfinite(img(:))) || any(mod(img(:), 1) ~= 0)
        error('dwt53_forward_2d:notInteger', 'img must contain only finite integer values.');
    end

    [rows, cols] = size(img);
    if mod(rows, 2) ~= 0 || mod(cols, 2) ~= 0
        error('dwt53_forward_2d:oddDimension', ...
            'img dimensions must both be even (got %dx%d).', rows, cols);
    end

    img = int64(img);

    % ---------------------------------------------------------------
    % Pass 1: HORIZONTAL forward transform across every row (x-direction)
    %   L_row(r,:) = horizontal-low  coefficients of row r
    %   H_row(r,:) = horizontal-high coefficients of row r
    % ---------------------------------------------------------------
    L_row = zeros(rows, cols/2, 'int64');
    H_row = zeros(rows, cols/2, 'int64');
    for r = 1:rows
        [l, h] = dwt53_forward_1d(img(r,:));
        L_row(r,:) = l(:).';
        H_row(r,:) = h(:).';
    end

    % ---------------------------------------------------------------
    % Pass 2: VERTICAL forward transform down every column (y-direction)
    %   columns of L_row (horizontal-low)  -> LL (vert-low), LH (vert-high)
    %   columns of H_row (horizontal-high) -> HL (vert-low), HH (vert-high)
    % ---------------------------------------------------------------
    LL = zeros(rows/2, cols/2, 'int64');
    LH = zeros(rows/2, cols/2, 'int64');
    HL = zeros(rows/2, cols/2, 'int64');
    HH = zeros(rows/2, cols/2, 'int64');

    for c = 1:cols/2
        [col_L, col_H] = dwt53_forward_1d(L_row(:,c));
        LL(:,c) = col_L(:);
        LH(:,c) = col_H(:);

        [col_L, col_H] = dwt53_forward_1d(H_row(:,c));
        HL(:,c) = col_L(:);
        HH(:,c) = col_H(:);
    end
end

function coeffs = dwt53_forward_2level(img)
%DWT53_FORWARD_2LEVEL  Forward two-level reversible Le Gall 5/3 transform.
%
%   coeffs = DWT53_FORWARD_2LEVEL(img) applies one level of
%   dwt53_forward_2d.m to img, then a SECOND level of dwt53_forward_2d.m
%   to ONLY the resulting LL1 subband, per algorithm_spec_v0.1
%   Section 9.1. HL1, LH1, HH1 are NOT decomposed further.
%
%   A struct (rather than positional outputs) is used deliberately, per
%   the project brief's preference for two-level 2D: with seven named
%   subbands in play, positional LL2/HL2/LH2/HH2/HL1/LH1/HH1 arguments
%   are an easy way to accidentally swap two same-shaped subbands.
%   Named struct fields remove that risk.
%
%   INPUT
%       img - 2D integer-valued matrix. Both dimensions must be
%             divisible by 4 (so that LL1, of size rows/2 x cols/2, has
%             even dimensions and can itself be decomposed once more).
%
%   OUTPUT
%       coeffs - struct with fields (spec Section 9.1):
%           .LL2, .HL2, .LH2, .HH2  - Level 2, each (rows/4) x (cols/4)
%           .HL1, .LH1, .HH1        - Level 1, each (rows/2) x (cols/2)
%                                      (LL1 itself is NOT returned --
%                                      it only exists transiently, fully
%                                      represented by LL2/HL2/LH2/HH2)
%
%   Reuses dwt53_forward_2d.m twice; no lifting arithmetic is duplicated.

    if isempty(img)
        error('dwt53_forward_2level:emptyInput', 'img must not be empty.');
    end
    if ~ismatrix(img) || isvector(img)
        error('dwt53_forward_2level:notMatrix', 'img must be a 2D matrix (not a vector).');
    end

    [rows, cols] = size(img);
    if mod(rows, 4) ~= 0 || mod(cols, 4) ~= 0
        error('dwt53_forward_2level:notDivisibleBy4', ...
            'img dimensions must both be divisible by 4 for two-level decomposition (got %dx%d).', ...
            rows, cols);
    end

    % ---------------------------------------------------------------
    % Level 1: transform the full image (spec Section 9.1, Level-1 table)
    % ---------------------------------------------------------------
    [LL1, HL1, LH1, HH1] = dwt53_forward_2d(img);

    % ---------------------------------------------------------------
    % Level 2: transform ONLY LL1 (spec Section 9.1, Level-2 table).
    % HL1, LH1, HH1 are passed through untouched.
    % ---------------------------------------------------------------
    [LL2, HL2, LH2, HH2] = dwt53_forward_2d(LL1);

    coeffs = struct( ...
        'LL2', LL2, 'HL2', HL2, 'LH2', LH2, 'HH2', HH2, ...
        'HL1', HL1, 'LH1', LH1, 'HH1', HH1);
end

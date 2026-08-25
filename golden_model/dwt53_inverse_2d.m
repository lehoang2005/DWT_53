function img = dwt53_inverse_2d(LL, HL, LH, HH)
%DWT53_INVERSE_2D  Inverse one-level 2D reversible Le Gall 5/3 transform.
%
%   img = DWT53_INVERSE_2D(LL, HL, LH, HH) undoes dwt53_forward_2d.m per
%   algorithm_spec_v0.1 Section 8.3: the VERTICAL inverse is applied
%   first (reconstructing the horizontally-transformed rows), THEN the
%   HORIZONTAL inverse is applied (reconstructing the image) -- the
%   exact reverse order of the forward transform.
%
%   INPUT
%       LL, HL, LH, HH - four subbands, all the same size R x C,
%                         integer-valued (same naming as dwt53_forward_2d.m).
%
%   OUTPUT
%       img - reconstructed matrix, size (2R) x (2C), signed int64.
%
%   Mandatory invariant: for any valid img,
%       dwt53_inverse_2d(dwt53_forward_2d(img)) == img   (bit-exact)

    % ---------------------------------------------------------------
    % Input validation
    % ---------------------------------------------------------------
    if isempty(LL) || isempty(HL) || isempty(LH) || isempty(HH)
        error('dwt53_inverse_2d:emptyInput', 'All four subbands must be non-empty.');
    end
    sz = size(LL);
    if ~isequal(size(HL), sz) || ~isequal(size(LH), sz) || ~isequal(size(HH), sz)
        error('dwt53_inverse_2d:sizeMismatch', 'LL, HL, LH, HH must all be the same size.');
    end
    all_vals = [LL(:); HL(:); LH(:); HH(:)];
    if any(~isfinite(all_vals)) || any(mod(all_vals, 1) ~= 0)
        error('dwt53_inverse_2d:notInteger', 'All subbands must contain only finite integer values.');
    end

    R = sz(1);
    C = sz(2);
    LL = int64(LL); HL = int64(HL); LH = int64(LH); HH = int64(HH);

    % ---------------------------------------------------------------
    % Step 1: undo VERTICAL transform (spec 8.3.1), per column
    %   (LL,LH) -> column of L_row (horizontal-low, length 2R)
    %   (HL,HH) -> column of H_row (horizontal-high, length 2R)
    % ---------------------------------------------------------------
    L_row = zeros(2*R, C, 'int64');
    H_row = zeros(2*R, C, 'int64');
    for c = 1:C
        L_row(:,c) = dwt53_inverse_1d(LL(:,c), LH(:,c));
        H_row(:,c) = dwt53_inverse_1d(HL(:,c), HH(:,c));
    end

    % ---------------------------------------------------------------
    % Step 2: undo HORIZONTAL transform (spec 8.3.2), per row
    % ---------------------------------------------------------------
    img = zeros(2*R, 2*C, 'int64');
    for r = 1:2*R
        img(r,:) = dwt53_inverse_1d(L_row(r,:), H_row(r,:));
    end
end

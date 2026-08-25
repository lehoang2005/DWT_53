function x = dwt53_inverse_1d(L, H)
%DWT53_INVERSE_1D  Inverse 1D reversible Le Gall 5/3 lifting transform.
%
%   x = DWT53_INVERSE_1D(L, H) reconstructs the original integer vector
%   from its low-pass (L) and high-pass (H) subbands, per
%   algorithm_spec_v0.1 Section 7. The update step is undone before the
%   predict step is undone (mandatory order).
%
%   Equations (0-based, spec Section 7; M = length(L) = length(H)):
%       H[-1] = H[0]                                            (boundary)
%       e[n] = L[n] - floor( (H[n-1] + H[n] + 2) / 4 )          (undo update)
%       e[M] = e[M-1]                                           (boundary)
%       o[n] = H[n] + floor( (e[n] + e[n+1]) / 2 )              (undo predict)
%       x[2n] = e[n],   x[2n+1] = o[n]                          (merge)
%
%   MATLAB 1-based indexing note: as in dwt53_forward_1d, a 0-based
%   quantity q[n] is stored at 1-based array index (n+1).
%
%   INPUT
%       L, H - integer-valued subbands of equal length M >= 1, row or
%              column orientation (must match each other).
%
%   OUTPUT
%       x - reconstructed integer vector, length 2M, same orientation
%           as L/H.
%
%   For every valid forward/inverse pair, dwt53_inverse_1d(dwt53_forward_1d(x))
%   must equal x exactly (spec Section 7.3, mandatory invariant). All
%   arithmetic is carried out in signed int64.

    % ---------------------------------------------------------------
    % Input validation
    % ---------------------------------------------------------------
    if isempty(L) || isempty(H)
        error('dwt53_inverse_1d:emptyInput', 'L and H must not be empty.');
    end
    if ~isvector(L) || ~isvector(H)
        error('dwt53_inverse_1d:notVector', 'L and H must be row or column vectors.');
    end
    if numel(L) ~= numel(H)
        error('dwt53_inverse_1d:lengthMismatch', 'L and H must have the same length.');
    end
    if any(~isfinite(L(:))) || any(mod(L(:), 1) ~= 0) || ...
       any(~isfinite(H(:))) || any(mod(H(:), 1) ~= 0)
        error('dwt53_inverse_1d:notInteger', ...
            'L and H must contain only finite integer-valued numbers.');
    end

    % NOTE on orientation for the M=1 edge case (N=2 original vector):
    % a 1x1 array satisfies both isrow() and iscolumn() in MATLAB/Octave,
    % so a single-element subband carries no row/column information at
    % all -- the forward transform cannot encode "was a column" into a
    % scalar any more distinctly than "was a row". We therefore only
    % treat the input as column-oriented when it is unambiguously so
    % (more than one element AND iscolumn); otherwise we default to row
    % output. This matches the interface contract's "preserve
    % orientation when possible" (orientation genuinely cannot be
    % recovered from a length-1 subband pair).
    is_column = (numel(L) > 1) && iscolumn(L);

    L_row = int64(L(:).');
    H_row = int64(H(:).');
    M = length(L_row);

    % ---------------------------------------------------------------
    % Step 1: undo UPDATE -> even samples e (spec Eq. 7.1)
    %   e[n] = L[n] - floor( (H[n-1] + H[n] + 2) / 4 )
    %   Boundary: H[-1] = H[0]  ->  prepend H(1) once more (1-based)
    % ---------------------------------------------------------------
    H_ext_l = [H_row(1), H_row];   % H_ext_l(1) = H[-1] = H[0], H_ext_l(n+2) = H[n]
    e = L_row - floor_divide_int(H_ext_l(1:M) + H_ext_l(2:M+1) + int64(2), 4);

    % ---------------------------------------------------------------
    % Step 2: undo PREDICT -> odd samples o (spec Eq. 7.2)
    %   o[n] = H[n] + floor( (e[n] + e[n+1]) / 2 )
    %   Boundary: e[M] = e[M-1]  ->  append e(M) once more (1-based)
    % ---------------------------------------------------------------
    e_ext_r = [e, e(end)];         % e_ext_r(n+1) = e[n], e_ext_r(M+1) = e[M] = e[M-1]
    o = H_row + floor_divide_int(e_ext_r(1:M) + e_ext_r(2:M+1), 2);

    % ---------------------------------------------------------------
    % Step 3: interleave -> x[2n] = e[n], x[2n+1] = o[n]
    % ---------------------------------------------------------------
    x = zeros(1, 2 * M, 'int64');
    x(1:2:end) = e;
    x(2:2:end) = o;

    if is_column
        x = x(:);
    end
end

function [L, H] = dwt53_forward_1d(x)
%DWT53_FORWARD_1D  Forward 1D reversible Le Gall 5/3 lifting transform.
%
%   [L, H] = DWT53_FORWARD_1D(x) applies the integer 5/3 lifting DWT
%   defined in algorithm_spec_v0.1 Section 6.
%
%   Equations (0-based, spec Section 6; N = 2M, 0 <= n < M):
%       e[n] = x[2n],   o[n] = x[2n+1]                          (split)
%       d[n] = o[n] - floor( (e[n] + e[n+1]) / 2 )              (predict)
%       s[n] = e[n] + floor( (d[n-1] + d[n] + 2) / 4 )          (update)
%       e[M] = e[M-1],   d[-1] = d[0]                           (boundary)
%       L[n] = s[n],     H[n] = d[n]
%
%   The '+2' bias in the update step is mandatory (spec Section 6.4);
%   omitting it defines a different, non-conformant transform.
%
%   MATLAB 1-based indexing note: x(1) corresponds to 0-based x[0], so
%   throughout this function a variable holding 0-based quantity q[n]
%   is stored at 1-based array index (n+1). See inline comments.
%
%   INPUT
%       x - integer-valued row or column vector, even length N = 2M >= 2.
%
%   OUTPUT
%       L - low-pass (approximation) subband, length M
%       H - high-pass (detail) subband, length M
%       Both outputs preserve the orientation (row/column) of x.
%
%   All arithmetic is carried out in signed int64 (algorithm_spec_v0.1
%   Section 5.2: "MATLAB, CPU, and CUDA golden calculations shall use
%   signed 32-bit or wider intermediate arithmetic"). No intermediate
%   value is cast to uint8 or any narrow type.

    % ---------------------------------------------------------------
    % Input validation (spec Section 5: integer domain; reject silently
    % wrong shapes rather than guessing)
    % ---------------------------------------------------------------
    if isempty(x)
        error('dwt53_forward_1d:emptyInput', 'x must not be empty.');
    end
    if ~isvector(x)
        error('dwt53_forward_1d:notVector', 'x must be a row or column vector.');
    end
    if any(~isfinite(x(:))) || any(mod(x(:), 1) ~= 0)
        error('dwt53_forward_1d:notInteger', ...
            'x must contain only finite integer-valued numbers.');
    end

    % x always has N >= 2 elements here (enforced above), so iscolumn(x)
    % is unambiguous. NOTE: if N == 2 (M == 1), the resulting L and H are
    % 1x1 scalars, which cannot themselves carry row/column information
    % (a 1x1 array is simultaneously isrow()==true and iscolumn()==true).
    % dwt53_inverse_1d handles that edge case explicitly and defaults to
    % row output when it cannot be recovered -- see its header comment.
    is_column = (numel(x) > 1) && iscolumn(x);

    x_row = int64(x(:).');      % widen to signed int64; work row-wise internally
    N = length(x_row);

    if mod(N, 2) ~= 0
        error('dwt53_forward_1d:oddLength', ...
            'x must have even length (got N=%d).', N);
    end
    M = N / 2;

    % ---------------------------------------------------------------
    % Step 1: polyphase split (lazy wavelet)
    %   e(k) = x_row(2k-1)  <->  e[n] = x[2n],     1-based k = n+1
    %   o(k) = x_row(2k)    <->  o[n] = x[2n+1]
    % ---------------------------------------------------------------
    e = x_row(1:2:end);   % length M; e(n+1) holds e[n]
    o = x_row(2:2:end);   % length M; o(n+1) holds o[n]

    % ---------------------------------------------------------------
    % Step 2: PREDICT -> detail coefficients d (spec Eq. 6.3)
    %   d[n] = o[n] - floor( (e[n] + e[n+1]) / 2 ),  0 <= n < M
    %   Boundary: e[M] = e[M-1]  ->  append e(M) once more (1-based)
    % ---------------------------------------------------------------
    e_ext = [e, e(end)];      % e_ext(n+1) = e[n] for n=0..M-1, e_ext(M+1)=e[M]=e[M-1]
    d = o - floor_divide_int(e_ext(1:M) + e_ext(2:M+1), 2);

    % ---------------------------------------------------------------
    % Step 3: UPDATE -> approximation coefficients s (spec Eq. 6.4)
    %   s[n] = e[n] + floor( (d[n-1] + d[n] + 2) / 4 ),  0 <= n < M
    %   Boundary: d[-1] = d[0]  ->  prepend d(1) once more (1-based)
    % ---------------------------------------------------------------
    d_ext = [d(1), d];        % d_ext(1) = d[-1] = d[0], d_ext(n+2) = d[n]
    s = e + floor_divide_int(d_ext(1:M) + d_ext(2:M+1) + int64(2), 4);

    L = s;
    H = d;

    % ---------------------------------------------------------------
    % Restore caller's orientation
    % ---------------------------------------------------------------
    if is_column
        L = L(:);
        H = H(:);
    end
end

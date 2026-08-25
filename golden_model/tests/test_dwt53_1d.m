function stats = test_dwt53_1d()
%TEST_DWT53_1D  Gate 1 self-checking regression for the 1D 5/3 transform.
%
%   stats = TEST_DWT53_1D() exercises dwt53_forward_1d.m / dwt53_inverse_1d.m
%   against every category required by algorithm_spec_v0.1 Section 12.2 and
%   the Gate 1 checklist in the project prompt: canonical known-answer
%   vectors, constant/ramp/impulse/alternating patterns, an exhaustive
%   sweep of all 65536 length-2 Y8 vectors, >=1000 seeded random Y8
%   vectors, every even length from 2 to >=256, row/column orientation,
%   and explicit negative-rounding / boundary cases.
%
%   Every case is checked with a hard integer-equality assertion (no
%   floating-point tolerance, no try/catch swallowing errors). A single
%   mismatch aborts the run via error()/assert().

    stats = struct();
    stats.n_cases = 0;
    stats.max_abs_recon_error = int64(0);
    stats.min_coeff = intmax('int64');
    stats.max_coeff = intmin('int64');

    fprintf('=== test_dwt53_1d: Gate 1 regression ===\n');

    % =================================================================
    % 1) Canonical known-answer vectors (algorithm_spec_v0.1 Section 10)
    % =================================================================

    % --- Section 10.1: nominal ramp vector ---
    x = int64([10 20 30 40 50 60 70 80]);
    [L, H] = dwt53_forward_1d(x);
    assert(isequal(L, int64([10 30 50 73])), ...
        sprintf('spec-10.1: L mismatch, got %s', mat2str(double(L))));
    assert(isequal(H, int64([0 0 0 10])), ...
        sprintf('spec-10.1: H mismatch, got %s', mat2str(double(H))));
    x_rec = dwt53_inverse_1d(L, H);
    assert(isequal(x_rec, x), 'spec-10.1: reconstruction mismatch');
    stats = tally(stats, x, L, H);

    % --- Section 10.2: negative-rounding and boundary vector ---
    x = int64([0, 0, 10, 0, 20, 0, 30, 0]);
    [L, H] = dwt53_forward_1d(x);
    assert(isequal(L, int64([-2, 5, 10, 16])), ...
        sprintf('spec-10.2: L mismatch, got %s', mat2str(double(L))));
    assert(isequal(H, int64([-5, -15, -25, -30])), ...
        sprintf('spec-10.2: H mismatch, got %s', mat2str(double(H))));
    x_rec = dwt53_inverse_1d(L, H);
    assert(isequal(x_rec, x), 'spec-10.2: reconstruction mismatch');
    stats = tally(stats, x, L, H);

    % --- Section 10.3: two-sample edge vectors (N=2 boundary case) ---
    x = int64([0, 255]);
    [L, H] = dwt53_forward_1d(x);
    assert(isequal(L, int64(128)) && isequal(H, int64(255)), ...
        sprintf('spec-10.3a: got L=%d H=%d', double(L), double(H)));
    x_rec = dwt53_inverse_1d(L, H);
    assert(isequal(x_rec, x), 'spec-10.3a: reconstruction mismatch');
    stats = tally(stats, x, L, H);

    x = int64([255, 0]);
    [L, H] = dwt53_forward_1d(x);
    assert(isequal(L, int64(128)) && isequal(H, int64(-255)), ...
        sprintf('spec-10.3b: got L=%d H=%d', double(L), double(H)));
    x_rec = dwt53_inverse_1d(L, H);
    assert(isequal(x_rec, x), 'spec-10.3b: reconstruction mismatch');
    stats = tally(stats, x, L, H);

    fprintf('  [PASS] canonical spec vectors (Section 10.1-10.3)\n');

    % =================================================================
    % 2) Structured patterns: constant, ramps, impulses, alternating
    %    Exercised at several even lengths, including boundary lengths.
    % =================================================================
    lengths_struct = [2, 4, 6, 8, 16, 32, 64, 128, 256];

    for N = lengths_struct
        % constant vector
        stats = check_pattern(stats, repmat(int64(127), 1, N), 'constant');
        stats = check_pattern(stats, zeros(1, N, 'int64'), 'constant-zero');
        stats = check_pattern(stats, repmat(int64(255), 1, N), 'constant-max');

        % increasing / decreasing ramp, clipped to Y8 range via mod
        ramp_up   = int64(mod(0:N-1, 256));
        ramp_down = int64(mod(N-1:-1:0, 256));
        stats = check_pattern(stats, ramp_up,   'ramp-up');
        stats = check_pattern(stats, ramp_down, 'ramp-down');

        % impulses at start / middle / end
        imp_start = zeros(1, N, 'int64'); imp_start(1) = 255;
        imp_mid   = zeros(1, N, 'int64'); imp_mid(floor(N/2)+1) = 255;
        imp_end   = zeros(1, N, 'int64'); imp_end(end) = 255;
        stats = check_pattern(stats, imp_start, 'impulse-start');
        stats = check_pattern(stats, imp_mid,   'impulse-mid');
        stats = check_pattern(stats, imp_end,   'impulse-end');

        % alternating patterns
        alt_a = int64(repmat([0 255], 1, N/2));
        alt_b = int64(repmat([255 0], 1, N/2));
        stats = check_pattern(stats, alt_a, 'alt-0-255');
        stats = check_pattern(stats, alt_b, 'alt-255-0');
    end
    fprintf('  [PASS] constant/ramp/impulse/alternating patterns at %d lengths\n', ...
        numel(lengths_struct));

    % =================================================================
    % 3) Exhaustive sweep: ALL 256x256 = 65536 length-2 Y8 vectors
    % =================================================================
    n_exhaustive = 0;
    for a = 0:255
        row = zeros(256, 2);
        row(:,1) = a;
        row(:,2) = 0:255;
        for b = 1:256
            x = int64(row(b,:));
            [L, H] = dwt53_forward_1d(x);
            x_rec = dwt53_inverse_1d(L, H);
            err = max(abs(x_rec - x));
            if err ~= 0
                error('exhaustive-N2(a=%d,b=%d): reconstruction error=%d', a, b-1, err);
            end
            stats.max_abs_recon_error = max(stats.max_abs_recon_error, err);
            stats.min_coeff = min([stats.min_coeff, L, H]);
            stats.max_coeff = max([stats.max_coeff, L, H]);
            n_exhaustive = n_exhaustive + 1;
        end
    end
    stats.n_cases = stats.n_cases + n_exhaustive;
    assert(n_exhaustive == 65536, 'exhaustive sweep must cover exactly 65536 vectors');
    fprintf('  [PASS] exhaustive length-2 Y8 sweep: %d/%d vectors bit-exact\n', ...
        n_exhaustive, 65536);

    % =================================================================
    % 4) >=1000 seeded random Y8 vectors, random even length in [2,256]
    % =================================================================
    seed = 12345;
    rand('seed', seed);            %#ok<RAND> Octave legacy RNG, seeded for reproducibility
    n_random = 1000;
    for k = 1:n_random
        N = 2 * randi_local(1, 128);          % even length in [2,256]
        x = int64(floor(rand(1, N) * 256));   % Y8 in [0,255]
        x(x > 255) = 255;                     % guard float edge case at 1.0
        stats = check_pattern(stats, x, sprintf('random-%d', k));
    end
    fprintf('  [PASS] %d seeded random Y8 vectors (seed=%d), all bit-exact\n', ...
        n_random, seed);

    % =================================================================
    % 5) Every even length from 2 through 256 (coverage requirement)
    % =================================================================
    for N = 2:2:256
        x = int64(mod(0:N-1, 256));    % deterministic ramp content
        stats = check_pattern(stats, x, sprintf('length-sweep-N%d', N));
    end
    fprintf('  [PASS] every even length from 2 to 256 exercised\n');

    % =================================================================
    % 6) Row-vector vs column-vector orientation preservation
    % =================================================================
    x_row = int64([10 20 30 40 50 60 70 80]);
    x_col = x_row(:);

    [Lr, Hr] = dwt53_forward_1d(x_row);
    [Lc, Hc] = dwt53_forward_1d(x_col);
    assert(isrow(x_row) && isrow(Lr) && isrow(Hr), 'row orientation not preserved on forward');
    assert(iscolumn(x_col) && iscolumn(Lc) && iscolumn(Hc), 'column orientation not preserved on forward');
    assert(isequal(Lr(:), Lc(:)) && isequal(Hr(:), Hc(:)), 'row/column results must match numerically');

    xr_row = dwt53_inverse_1d(Lr, Hr);
    xr_col = dwt53_inverse_1d(Lc, Hc);
    assert(isrow(xr_row), 'row orientation not preserved on inverse');
    assert(iscolumn(xr_col), 'column orientation not preserved on inverse');
    assert(isequal(xr_row(:), x_row(:)) && isequal(xr_col(:), x_col(:)), ...
        'row/column reconstruction mismatch');
    stats.n_cases = stats.n_cases + 2;
    fprintf('  [PASS] row-vector and column-vector orientation preserved\n');

    % =================================================================
    % 6b) Known, documented limitation: for N=2 (M=1) inputs, L and H
    % are 1x1 scalars and cannot carry row/column orientation (a 1x1
    % array is simultaneously isrow()==true and iscolumn()==true in
    % MATLAB/Octave). Values must still round-trip exactly; the
    % *shape* of x_rec is allowed to default to row in this one edge
    % case even if the original x was a column. This is documented in
    % dwt53_forward_1d.m / dwt53_inverse_1d.m headers.
    % =================================================================
    x_col_n2 = int64([0; 255]);
    [Lc2, Hc2] = dwt53_forward_1d(x_col_n2);
    xr_col_n2 = dwt53_inverse_1d(Lc2, Hc2);
    assert(isequal(xr_col_n2(:), x_col_n2(:)), ...
        'N=2 column case: reconstructed VALUES must still match exactly');
    stats.n_cases = stats.n_cases + 1;
    fprintf('  [PASS] N=2 (M=1) scalar-subband orientation limitation documented and value-exact\n');

    % =================================================================
    % 7) Explicit negative-rounding corner cases beyond spec 10.2
    % =================================================================
    neg_cases = {
        int64([0 0 0 3 0 0 0 0]), 'neg-corner-a';
        int64([0 1 0 0 0 0 0 5]), 'neg-corner-b';
        int64([255 0 0 255 0 0 255 0]), 'neg-corner-c';
        int64([1 0 3 0 1 0 3 0]), 'neg-corner-d'
    };
    for i = 1:size(neg_cases, 1)
        stats = check_pattern(stats, neg_cases{i,1}, neg_cases{i,2});
    end
    fprintf('  [PASS] explicit negative-rounding corner cases\n');

    % =================================================================
    % 8) Boundary-sample-specific cases (first/last sample extremes)
    % =================================================================
    stats = check_pattern(stats, int64([255 0 0 0 0 0 0 0]), 'boundary-first-max');
    stats = check_pattern(stats, int64([0 0 0 0 0 0 0 255]), 'boundary-last-max');
    stats = check_pattern(stats, int64([255 255]), 'boundary-N2-both-max');
    stats = check_pattern(stats, int64([0 0]), 'boundary-N2-both-zero');
    fprintf('  [PASS] boundary-sample-specific cases\n');

    % =================================================================
    % 9) Error-path checks: reject empty / odd length / non-integer
    % =================================================================
    assert(throws_error(@() dwt53_forward_1d([])), 'must reject empty input');
    assert(throws_error(@() dwt53_forward_1d([1 2 3])), 'must reject odd length');
    assert(throws_error(@() dwt53_forward_1d([1.5 2])), 'must reject non-integer input');
    assert(throws_error(@() dwt53_forward_1d([1 2; 3 4])), 'must reject non-vector input');
    fprintf('  [PASS] error-path validation (empty/odd-length/non-integer/non-vector)\n');

    % =================================================================
    % Summary
    % =================================================================
    fprintf('\n--- test_dwt53_1d summary ---\n');
    fprintf('Total cases executed        : %d\n', stats.n_cases);
    fprintf('Maximum reconstruction error: %d\n', double(stats.max_abs_recon_error));
    fprintf('Observed coefficient range  : [%d, %d]\n', ...
        double(stats.min_coeff), double(stats.max_coeff));
    fprintf('Arithmetic dtype            : int64 throughout\n');
    assert(stats.max_abs_recon_error == 0, 'Gate 1 FAIL: nonzero reconstruction error observed');
    fprintf('[PASS] test_dwt53_1d: ALL categories passed, max reconstruction error = 0\n');
end

% =====================================================================
% Local helper subfunctions (Octave/MATLAB subfunctions: no shared
% workspace with the caller; all state passed explicitly)
% =====================================================================

function stats = check_pattern(stats, x, label)
% Run one forward+inverse round trip, assert bit-exact reconstruction,
% and fold the result into the running stats struct.
    [L, H] = dwt53_forward_1d(x);
    x_rec = dwt53_inverse_1d(L, H);
    err = max(abs(int64(x_rec(:)) - int64(x(:))));
    if isempty(err)
        err = int64(0);
    end
    if err ~= 0
        error('check_pattern(%s): reconstruction error=%d', label, double(err));
    end
    stats.n_cases = stats.n_cases + 1;
    stats.max_abs_recon_error = max(stats.max_abs_recon_error, err);
    stats.min_coeff = min([stats.min_coeff; L(:); H(:)]);
    stats.max_coeff = max([stats.max_coeff; L(:); H(:)]);
end

function stats = tally(stats, x, L, H)
% Fold a manually-checked known-answer case into the running stats.
    stats.n_cases = stats.n_cases + 1;
    stats.min_coeff = min([stats.min_coeff; L(:); H(:)]);
    stats.max_coeff = max([stats.max_coeff; L(:); H(:)]);
end

function n = randi_local(lo, hi)
% Minimal seeded-RNG-compatible integer generator using rand(), since
% this file relies only on the legacy rand('seed',...) call for
% reproducibility across MATLAB/Octave.
    n = lo + floor(rand() * (hi - lo + 1));
    n = min(n, hi);
end

function tf = throws_error(fn)
    tf = false;
    try
        fn();
    catch
        tf = true;
    end
end

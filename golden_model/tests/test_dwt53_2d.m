function stats = test_dwt53_2d()
%TEST_DWT53_2D  Gate 2 self-checking regression for the one-level 2D
%   5/3 transform (forward + inverse + pack/unpack layout).
%
%   Covers algorithm_spec_v0.1 Section 12 GOLDEN_MODEL_GATE_2 plus the
%   Gate 2 checklist in the project prompt: the canonical Section 10.4
%   4x4 vector (forward AND packed-layout bit-exact match), constant,
%   ramp, checkerboard, impulse, and random images, small sizes for
%   indexing/boundary correctness, and bit-exact round trips throughout.

    stats = struct();
    stats.n_cases = 0;
    stats.max_abs_recon_error = int64(0);
    stats.min_coeff = intmax('int64');
    stats.max_coeff = intmin('int64');

    fprintf('=== test_dwt53_2d: Gate 2 regression ===\n');

    % =================================================================
    % 1) Canonical vector: algorithm_spec_v0.1 Section 10.4 (4x4)
    %    This is the strongest available check: an exact numeric
    %    reference from the frozen spec, not just self-consistency.
    % =================================================================
    X = int64([0 1 2 3; 4 5 6 7; 8 9 10 11; 12 13 14 15]);
    [LL, HL, LH, HH] = dwt53_forward_2d(X);

    C1_expected = int64([0 2 0 1; 9 11 0 1; 0 0 0 0; 4 4 0 0]);
    C1 = dwt53_pack_2d(LL, HL, LH, HH);
    assert(isequal(C1, C1_expected), ...
        sprintf('spec-10.4: packed C1 mismatch.\nGot:\n%s\nExpected:\n%s', ...
                mat2str(double(C1)), mat2str(double(C1_expected))));

    % explicit quadrant-position check called out by the spec text:
    % "the top-right quadrant is HL1, and the bottom-left quadrant is LH1"
    assert(isequal(C1(1:2,3:4), HL), 'spec-10.4: top-right quadrant must be HL');
    assert(isequal(C1(3:4,1:2), LH), 'spec-10.4: bottom-left quadrant must be LH');
    assert(isequal(C1(1:2,1:2), LL), 'spec-10.4: top-left quadrant must be LL');
    assert(isequal(C1(3:4,3:4), HH), 'spec-10.4: bottom-right quadrant must be HH');

    [LLu, HLu, LHu, HHu] = dwt53_unpack_2d(C1);
    assert(isequal(LLu,LL) && isequal(HLu,HL) && isequal(LHu,LH) && isequal(HHu,HH), ...
        'spec-10.4: unpack(pack(...)) must recover original subbands exactly');

    X_rec = dwt53_inverse_2d(LL, HL, LH, HH);
    assert(isequal(X_rec, X), 'spec-10.4: 2D reconstruction must equal X exactly');
    stats = tally(stats, X, LL, HL, LH, HH);
    fprintf('  [PASS] canonical spec vector Section 10.4 (forward, pack, unpack, inverse all bit-exact)\n');

    % =================================================================
    % 2) Explicit packed-layout position check with distinguishable values
    %    (independent of any real transform -- pure pack/unpack layout test)
    % =================================================================
    LLv = int64(ones(2,3) * 1);
    HLv = int64(ones(2,3) * 2);
    LHv = int64(ones(2,3) * 3);
    HHv = int64(ones(2,3) * 4);
    P = dwt53_pack_2d(LLv, HLv, LHv, HHv);
    assert(isequal(P(1:2, 1:3), LLv), 'layout: top-left must be LL');
    assert(isequal(P(1:2, 4:6), HLv), 'layout: top-right must be HL');
    assert(isequal(P(3:4, 1:3), LHv), 'layout: bottom-left must be LH');
    assert(isequal(P(3:4, 4:6), HHv), 'layout: bottom-right must be HH');
    [a,b,c,d] = dwt53_unpack_2d(P);
    assert(isequal(a,LLv) && isequal(b,HLv) && isequal(c,LHv) && isequal(d,HHv), ...
        'layout: unpack must recover LL/HL/LH/HH in the right slots');
    stats.n_cases = stats.n_cases + 1;
    fprintf('  [PASS] pack/unpack quadrant layout verified with distinguishable values\n');

    % =================================================================
    % 3) Structured image patterns at several sizes (including small
    %    non-square sizes to catch row/col indexing bugs)
    % =================================================================
    sizes = [2 2; 2 4; 4 2; 2 8; 8 2; 4 6; 6 4; 4 4; 8 8; 16 16; 32 24; 64 64];

    for i = 1:size(sizes,1)
        R = sizes(i,1); C = sizes(i,2);

        stats = check_2d(stats, repmat(int64(127), R, C), sprintf('constant-127-%dx%d',R,C));
        stats = check_2d(stats, zeros(R, C, 'int64'),      sprintf('constant-0-%dx%d',R,C));
        stats = check_2d(stats, repmat(int64(255), R, C), sprintf('constant-255-%dx%d',R,C));

        [xg, yg] = meshgrid(0:C-1, 0:R-1);
        ramp_h = int64(mod(xg, 256));           % increases along columns (x)
        ramp_v = int64(mod(yg, 256));           % increases along rows (y)
        ramp_d = int64(mod(xg + yg, 256));      % diagonal
        stats = check_2d(stats, ramp_h, sprintf('ramp-horizontal-%dx%d',R,C));
        stats = check_2d(stats, ramp_v, sprintf('ramp-vertical-%dx%d',R,C));
        stats = check_2d(stats, ramp_d, sprintf('ramp-diagonal-%dx%d',R,C));

        checker = int64(255 * mod(xg + yg, 2));
        stats = check_2d(stats, checker, sprintf('checkerboard-%dx%d',R,C));

        imp_corner_tl = zeros(R, C, 'int64'); imp_corner_tl(1,1) = 255;
        imp_corner_br = zeros(R, C, 'int64'); imp_corner_br(end,end) = 255;
        imp_center    = zeros(R, C, 'int64'); imp_center(ceil(R/2), ceil(C/2)) = 255;
        stats = check_2d(stats, imp_corner_tl, sprintf('impulse-tl-%dx%d',R,C));
        stats = check_2d(stats, imp_corner_br, sprintf('impulse-br-%dx%d',R,C));
        stats = check_2d(stats, imp_center,    sprintf('impulse-center-%dx%d',R,C));
    end
    fprintf('  [PASS] constant/ramp/checkerboard/impulse patterns at %d sizes (incl. non-square small sizes)\n', ...
        size(sizes,1));

    % =================================================================
    % 4) Seeded random images at several sizes
    % =================================================================
    seed = 777;
    rand('seed', seed);   %#ok<RAND> Octave legacy RNG; reproducible within this platform
    random_sizes = [4 4; 8 8; 16 16; 32 32; 64 64; 96 64; 64 96; 128 128];
    n_random = 0;
    for i = 1:size(random_sizes,1)
        R = random_sizes(i,1); C = random_sizes(i,2);
        for rep = 1:3
            img = int64(floor(rand(R,C) * 256));
            img(img > 255) = 255;
            stats = check_2d(stats, img, sprintf('random-%dx%d-rep%d', R, C, rep));
            n_random = n_random + 1;
        end
    end
    fprintf('  [PASS] %d seeded random images (seed=%d) across %d sizes, all bit-exact\n', ...
        n_random, seed, size(random_sizes,1));

    % =================================================================
    % 5) Error-path checks
    % =================================================================
    assert(throws_error(@() dwt53_forward_2d([])), 'must reject empty img');
    assert(throws_error(@() dwt53_forward_2d([1 2 3; 4 5 6])), 'must reject odd column count');
    assert(throws_error(@() dwt53_forward_2d([1 2; 3 4; 5 6])), 'must reject odd row count');
    assert(throws_error(@() dwt53_forward_2d([1.5 2; 3 4])), 'must reject non-integer img');
    assert(throws_error(@() dwt53_forward_2d([1 2 3 4])), 'must reject vector input (not a 2D matrix)');
    assert(throws_error(@() dwt53_inverse_2d(ones(2,2),ones(2,3),ones(2,2),ones(2,2))), ...
        'must reject mismatched subband sizes');
    assert(throws_error(@() dwt53_pack_2d(ones(2,2),ones(2,3),ones(2,2),ones(2,2))), ...
        'pack must reject mismatched subband sizes');
    assert(throws_error(@() dwt53_unpack_2d(ones(3,4))), 'unpack must reject odd row count');
    fprintf('  [PASS] error-path validation\n');

    % =================================================================
    % Summary
    % =================================================================
    fprintf('\n--- test_dwt53_2d summary ---\n');
    fprintf('Total cases executed        : %d\n', stats.n_cases);
    fprintf('Maximum reconstruction error: %d\n', double(stats.max_abs_recon_error));
    fprintf('Observed coefficient range  : [%d, %d]\n', ...
        double(stats.min_coeff), double(stats.max_coeff));
    fprintf('Arithmetic dtype            : int64 throughout\n');
    assert(stats.max_abs_recon_error == 0, 'Gate 2 FAIL: nonzero reconstruction error observed');
    fprintf('[PASS] test_dwt53_2d: ALL categories passed, max reconstruction error = 0\n');
end

% =====================================================================
% Local helper subfunctions
% =====================================================================

function stats = check_2d(stats, img, label)
    [LL, HL, LH, HH] = dwt53_forward_2d(img);
    img_rec = dwt53_inverse_2d(LL, HL, LH, HH);
    err = max(abs(int64(img_rec(:)) - int64(img(:))));
    if isempty(err)
        err = int64(0);
    end
    if err ~= 0
        error('check_2d(%s): reconstruction error=%d', label, double(err));
    end
    stats = tally(stats, img, LL, HL, LH, HH);
end

function stats = tally(stats, img, LL, HL, LH, HH)
    stats.n_cases = stats.n_cases + 1;
    all_coeffs = [LL(:); HL(:); LH(:); HH(:)];
    stats.min_coeff = min([stats.min_coeff; all_coeffs]);
    stats.max_coeff = max([stats.max_coeff; all_coeffs]);
end

function tf = throws_error(fn)
    tf = false;
    try
        fn();
    catch
        tf = true;
    end
end

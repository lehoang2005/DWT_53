function stats = test_dwt53_2level()
%TEST_DWT53_2LEVEL  Gate 3 self-checking regression for the two-level
%   2D 5/3 transform (forward + inverse + pack/unpack layout).
%
%   Covers algorithm_spec_v0.1 Section 12.3 GOLDEN_MODEL_GATE_3, whose
%   exact wording is "bit-exact for synthetic AND real 1280x720 Y8
%   frames" -- this suite includes BOTH: seeded synthetic random frames
%   (Section 5 below) AND a real (non-synthetic) photographic 1280x720
%   Y8 frame (Section 5b below). Also covers the Gate 3 checklist in the
%   project prompt: the canonical Section 10.4 C2 vector, subband
%   dimension checks, minimum required sizes (4x4, 8x8, 64x64), and
%   bit-exact round trips with maximum pixel error 0.

    stats = struct();
    stats.n_cases = 0;
    stats.max_abs_recon_error = int64(0);
    stats.min_coeff = intmax('int64');
    stats.max_coeff = intmin('int64');

    fprintf('=== test_dwt53_2level: Gate 3 regression ===\n');

    % =================================================================
    % 1) Canonical vector: algorithm_spec_v0.1 Section 10.4 (C2, 4x4)
    % =================================================================
    X = int64([0 1 2 3; 4 5 6 7; 8 9 10 11; 12 13 14 15]);
    coeffs = dwt53_forward_2level(X);

    assert(isequal(coeffs.LL2, int64(6)), sprintf('spec-10.4: LL2 mismatch, got %d', double(coeffs.LL2)));
    assert(isequal(coeffs.HL2, int64(2)), sprintf('spec-10.4: HL2 mismatch, got %d', double(coeffs.HL2)));
    assert(isequal(coeffs.LH2, int64(9)), sprintf('spec-10.4: LH2 mismatch, got %d', double(coeffs.LH2)));
    assert(isequal(coeffs.HH2, int64(0)), sprintf('spec-10.4: HH2 mismatch, got %d', double(coeffs.HH2)));

    C2 = dwt53_pack_2level(coeffs);
    C2_expected = int64([6 2 0 1; 9 0 0 1; 0 0 0 0; 4 4 0 0]);
    assert(isequal(C2, C2_expected), ...
        sprintf('spec-10.4: packed C2 mismatch.\nGot:\n%s\nExpected:\n%s', ...
                mat2str(double(C2)), mat2str(double(C2_expected))));

    coeffs_u = dwt53_unpack_2level(C2);
    assert(isequal(coeffs_u.LL2,coeffs.LL2) && isequal(coeffs_u.HL2,coeffs.HL2) && ...
           isequal(coeffs_u.LH2,coeffs.LH2) && isequal(coeffs_u.HH2,coeffs.HH2) && ...
           isequal(coeffs_u.HL1,coeffs.HL1) && isequal(coeffs_u.LH1,coeffs.LH1) && ...
           isequal(coeffs_u.HH1,coeffs.HH1), ...
        'spec-10.4: unpack_2level(pack_2level(...)) must recover coeffs exactly');

    X_rec = dwt53_inverse_2level(coeffs);
    assert(isequal(X_rec, X), 'spec-10.4: two-level reconstruction must equal X exactly');
    stats = tally(stats, X, coeffs);
    fprintf('  [PASS] canonical spec vector Section 10.4 (LL2/HL2/LH2/HH2, packed C2, unpack, inverse all bit-exact)\n');

    % =================================================================
    % 2) "Level 2 decomposes ONLY LL1" cross-check: HL1/LH1/HH1 from the
    %    two-level call must equal a plain one-level dwt53_forward_2d
    %    call on the same image (i.e. they must not be touched by Level 2)
    % =================================================================
    img_check = int64(mod((0:63)' + (0:63), 256));   % 64x64, distinct from other tests
    coeffs_2 = dwt53_forward_2level(img_check);
    [~, HL1_direct, LH1_direct, HH1_direct] = dwt53_forward_2d(img_check);
    assert(isequal(coeffs_2.HL1, HL1_direct), 'HL1 must match a direct one-level forward_2d (Level 2 must not touch it)');
    assert(isequal(coeffs_2.LH1, LH1_direct), 'LH1 must match a direct one-level forward_2d (Level 2 must not touch it)');
    assert(isequal(coeffs_2.HH1, HH1_direct), 'HH1 must match a direct one-level forward_2d (Level 2 must not touch it)');
    stats.n_cases = stats.n_cases + 1;
    fprintf('  [PASS] Level 2 decomposes ONLY LL1 -- HL1/LH1/HH1 untouched, cross-checked against one-level forward_2d\n');

    % =================================================================
    % 3) Subband dimension checks (explicit, at several sizes)
    % =================================================================
    % GEOMETRY NOTE (fixed in r2).  MATLAB sizes are [rows cols], i.e.
    % [height width].  The baseline frame is 1280 WIDE by 720 HIGH, which is
    % 720x1280 in this notation -- NOT 1280x720.  Revision r1 listed
    % [1280 720], a 720-wide PORTRAIT image: a valid shape check, but not the
    % baseline geometry, and the log line claiming "incl. 1280x720" was
    % therefore misleading.  Both orientations are now exercised and each is
    % labelled for what it actually is.
    dim_check_sizes = [4 4; 8 8; 16 16; 64 64; 320 640; 720 1280; 1280 720];
    for i = 1:size(dim_check_sizes,1)
        R = dim_check_sizes(i,1); C = dim_check_sizes(i,2);
        img = zeros(R, C, 'int64');   % content irrelevant for a shape-only check
        c = dwt53_forward_2level(img);
        assert(isequal(size(c.LL2), [R/4, C/4]), sprintf('LL2 dim mismatch at %dx%d', R, C));
        assert(isequal(size(c.HL2), [R/4, C/4]), sprintf('HL2 dim mismatch at %dx%d', R, C));
        assert(isequal(size(c.LH2), [R/4, C/4]), sprintf('LH2 dim mismatch at %dx%d', R, C));
        assert(isequal(size(c.HH2), [R/4, C/4]), sprintf('HH2 dim mismatch at %dx%d', R, C));
        assert(isequal(size(c.HL1), [R/2, C/2]), sprintf('HL1 dim mismatch at %dx%d', R, C));
        assert(isequal(size(c.LH1), [R/2, C/2]), sprintf('LH1 dim mismatch at %dx%d', R, C));
        assert(isequal(size(c.HH1), [R/2, C/2]), sprintf('HH1 dim mismatch at %dx%d', R, C));
    end
    stats.n_cases = stats.n_cases + size(dim_check_sizes,1);
    fprintf(['  [PASS] all 7 subband dimensions verified correct at %d sizes\n' ...
             '         (incl. 720x1280 = the 1280-wide x 720-high baseline frame,\n' ...
             '          and 1280x720 = its portrait transpose)\n'], ...
        size(dim_check_sizes,1));

    % =================================================================
    % 4) Structured patterns at required minimum sizes (4x4, 8x8, 64x64)
    %    plus extra sizes divisible by 4, including non-square
    % =================================================================
    sizes = [4 4; 8 8; 4 8; 8 4; 4 12; 12 4; 16 16; 32 32; 64 64; 128 128];

    for i = 1:size(sizes,1)
        R = sizes(i,1); C = sizes(i,2);

        stats = check_2level(stats, repmat(int64(127), R, C), sprintf('constant-127-%dx%d',R,C));
        stats = check_2level(stats, zeros(R, C, 'int64'),      sprintf('constant-0-%dx%d',R,C));
        stats = check_2level(stats, repmat(int64(255), R, C), sprintf('constant-255-%dx%d',R,C));

        [xg, yg] = meshgrid(0:C-1, 0:R-1);
        ramp_h = int64(mod(xg, 256));
        ramp_v = int64(mod(yg, 256));
        ramp_d = int64(mod(xg + yg, 256));
        stats = check_2level(stats, ramp_h, sprintf('ramp-horizontal-%dx%d',R,C));
        stats = check_2level(stats, ramp_v, sprintf('ramp-vertical-%dx%d',R,C));
        stats = check_2level(stats, ramp_d, sprintf('ramp-diagonal-%dx%d',R,C));

        checker = int64(255 * mod(xg + yg, 2));
        stats = check_2level(stats, checker, sprintf('checkerboard-%dx%d',R,C));

        imp = zeros(R, C, 'int64'); imp(1,1) = 255;
        stats = check_2level(stats, imp, sprintf('impulse-tl-%dx%d',R,C));
    end
    fprintf('  [PASS] constant/ramp/checkerboard/impulse patterns at %d sizes (incl. required 4x4/8x8/64x64)\n', ...
        size(sizes,1));

    % =================================================================
    % 5) Seeded random frames, including the required 1280x720 real-size
    %    frame (spec baseline configuration)
    % =================================================================
    seed = 2026;
    rand('seed', seed);   %#ok<RAND> Octave legacy RNG; reproducible within this platform

    random_sizes = [8 8; 32 32; 64 64; 320 640];
    n_random = 0;
    for i = 1:size(random_sizes,1)
        R = random_sizes(i,1); C = random_sizes(i,2);
        img = int64(floor(rand(R,C) * 256));
        img(img > 255) = 255;
        stats = check_2level(stats, img, sprintf('random-%dx%d', R, C));
        n_random = n_random + 1;
    end

    % the required minimum: at least one random 1280x720 Y8 frame
    img_1280x720 = int64(floor(rand(720,1280) * 256));
    img_1280x720(img_1280x720 > 255) = 255;
    stats = check_2level(stats, img_1280x720, 'random-1280x720');
    n_random = n_random + 1;

    fprintf('  [PASS] %d seeded random (synthetic) frames (seed=%d), including 1280x720, all bit-exact\n', ...
        n_random, seed);

    % =================================================================
    % 5b) REAL/NATURAL (not synthetic) 1280x720 Y8 frame --
    %     algorithm_spec_v0.1 Section 12.3 GOLDEN_MODEL_GATE_3 explicitly
    %     requires bit-exact round trip for "synthetic AND real 1280x720
    %     Y8 frames", not synthetic/random alone (Section 5 above covers
    %     the synthetic half only -- IID random noise has no spatial
    %     correlation and cannot exercise the same coefficient statistics
    %     as genuine photographic content).
    %
    %     PROVENANCE: matlab/test_data/real_frame_1280x720.png is the
    %     classic "Cameraman" grayscale test photograph
    %     (skimage.data.camera(), 512x512 uint8) -- a real photograph,
    %     not synthetic/procedurally generated, long used as a standard
    %     reference image in image-compression/wavelet literature.
    %     Resized to 1280x720 via bicubic interpolation with
    %     anti-aliasing (Python skimage.transform.resize) and
    %     rounded/clipped to Y8 [0,255], then saved as a single-channel
    %     8-bit grayscale PNG (Python PIL, mode 'L').
    %
    %     HONEST CAVEAT: this is a real photograph, but it is NOT a
    %     literal D8M-camera capture cropped from a 1408x792 sensor frame
    %     per spec Section 4 -- no physical camera is available in this
    %     environment. Swap in an actual D8M-captured Y8 PNG at this same
    %     path/size for full spec compliance on that specific point.
    %
    %     Path is resolved relative to this test file's own location
    %     (mfilename('fullpath')), not MATLAB's Current Folder.
    % =================================================================
    this_test_dir = fileparts(mfilename('fullpath'));
    real_frame_path = fullfile(this_test_dir, '..', 'test_data', 'real_frame_1280x720.png');

    assert(exist(real_frame_path, 'file') == 2, sprintf( ...
        ['Required real/natural-frame test asset not found: %s\n' ...
         'Gate 3 cannot claim real-frame compliance without it -- this is ' ...
         'a hard failure, not a skip.'], real_frame_path));

    frame = imread(real_frame_path);

    assert(ndims(frame) == 2, sprintf( ...
        'real frame must be single-channel grayscale, got ndims=%d', ndims(frame)));
    assert(isa(frame, 'uint8'), sprintf( ...
        'real frame must be uint8, got class %s', class(frame)));
    assert(isequal(size(frame), [720 1280]), sprintf( ...
        'real frame must be 720x1280, got %dx%d', size(frame,1), size(frame,2)));

    % Run the existing golden-model functions directly, unmodified.
    C = dwt53_forward_2level(frame);
    rec = dwt53_inverse_2level(C);

    % Exact signed wide-integer comparison -- no tolerance, no cast to
    % uint8 before comparing (which could silently hide overflow/range
    % errors if rec ever fell outside [0,255]).
    max_err = max(abs(int64(rec(:)) - int64(frame(:))));
    assert(max_err == 0, sprintf('real frame: nonzero reconstruction error=%d', double(max_err)));
    assert(isequal(int64(rec), int64(frame)), 'real frame: reconstruction must equal input exactly');

    stats = tally(stats, frame, C);
    stats.max_abs_recon_error = max(stats.max_abs_recon_error, max_err);

    fprintf('  [PASS] Real/natural 1280x720 Y8 frame\n');
    fprintf('    PROVENANCE CAVEAT           : upscaled "Cameraman" photograph,\n');
    fprintf('                                  NOT a D8M capture cropped from a\n');
    fprintf('                                  1408x792 sensor frame (spec 4).\n');
    fprintf('                                  Bicubic resize band-limits the\n');
    fprintf('                                  image, so HH1/HH2 energy is lower\n');
    fprintf('                                  than a genuine camera frame.\n');
    fprintf('    Input size                  : %dx%d\n', size(frame,1), size(frame,2));
    fprintf('    Input type                  : %s\n', class(frame));
    fprintf('    Input range                 : %d..%d\n', double(min(frame(:))), double(max(frame(:))));
    fprintf('    Maximum reconstruction error: %d\n', double(max_err));
    fprintf('    Bit-exact reconstruction    : PASS\n');

    % =================================================================
    % 5c) COEFFICIENT EXTREMES vs the frozen conservative bounds
    %
    %     algorithm_spec_v0.1 Section 5.2 fixes conservative storage bounds:
    %         any completed 2D Level-1 subband within [-510,  638]
    %         any completed 2D Level-2 subband within [-2040, 2168]
    %
    %     Random Y8 frames never come close to these, so a suite built only
    %     from random content silently leaves the widest arithmetic paths --
    %     and, later, the RTL's 16-bit resize guards -- unexercised.  The
    %     directed patterns below were found by searching pattern families
    %     and random {0,255} tiles for the widest coefficient spread.
    %
    %     Two jobs here:
    %       1. HARD ASSERT that no coefficient ever leaves its frozen bound;
    %       2. REPORT how close the best-known input actually gets, so the
    %          remaining headroom is visible in the log instead of implied.
    % =================================================================
    ext_R = 32; ext_C = 32;
    [exg, eyg] = meshgrid(0:ext_C-1, 0:ext_R-1);

    ext_cases = { ...
        'checker_p1',   int64(255 * mod(exg + eyg, 2)) ; ...
        'colstripe_p1', int64(255 * mod(exg, 2)) ; ...
        'rowstripe_p1', int64(255 * mod(eyg, 2)) ; ...
        'checker_p2',   int64(255 * mod(floor(exg/2) + floor(eyg/2), 2)) ; ...
        'checker_p4',   int64(255 * mod(floor(exg/4) + floor(eyg/4), 2)) ; ...
        'p1_x_p2',      int64(255 * mod(mod(exg,2) + mod(floor(eyg/2),2), 2)) };

    L1_LO = -510;  L1_HI = 638;
    L2_LO = -2040; L2_HI = 2168;

    obs_l1_lo = 0; obs_l1_hi = 0; obs_l2_lo = 0; obs_l2_hi = 0;
    worst_l1 = ''; worst_l2 = '';

    for i = 1:size(ext_cases, 1)
        nm  = ext_cases{i, 1};
        eim = ext_cases{i, 2};

        % round trip must still be exact on adversarial content
        stats = check_2level(stats, eim, sprintf('extreme-%s', nm));

        % Level-1 subbands: from a plain one-level transform, so they are
        % genuinely Level-1 quantities and the Level-1 bound applies.
        [~, eHL1, eLH1, eHH1] = dwt53_forward_2d(eim);
        l1v = [eHL1(:); eLH1(:); eHH1(:)];

        ec  = dwt53_forward_2level(eim);
        l2v = [ec.LL2(:); ec.HL2(:); ec.LH2(:); ec.HH2(:)];

        assert(min(l1v) >= L1_LO && max(l1v) <= L1_HI, sprintf( ...
            'extreme-%s: Level-1 subband left the frozen bound [%d,%d]: got [%d,%d]', ...
            nm, L1_LO, L1_HI, double(min(l1v)), double(max(l1v))));
        assert(min(l2v) >= L2_LO && max(l2v) <= L2_HI, sprintf( ...
            'extreme-%s: Level-2 subband left the frozen bound [%d,%d]: got [%d,%d]', ...
            nm, L2_LO, L2_HI, double(min(l2v)), double(max(l2v))));

        if min(l1v) < obs_l1_lo, obs_l1_lo = min(l1v); worst_l1 = nm; end
        if max(l1v) > obs_l1_hi, obs_l1_hi = max(l1v); end
        if min(l2v) < obs_l2_lo, obs_l2_lo = min(l2v); worst_l2 = nm; end
        if max(l2v) > obs_l2_hi, obs_l2_hi = max(l2v); end
    end

    fprintf('  [PASS] %d directed extreme patterns: bounds respected, round trip exact\n', ...
        size(ext_cases, 1));
    fprintf('    Level-1 frozen bound        : [%6d, %6d]\n', L1_LO, L1_HI);
    fprintf('    Level-1 best observed       : [%6d, %6d]  (%s)\n', ...
        double(obs_l1_lo), double(obs_l1_hi), worst_l1);
    fprintf('    Level-2 frozen bound        : [%6d, %6d]\n', L2_LO, L2_HI);
    fprintf('    Level-2 best observed       : [%6d, %6d]  (%s)\n', ...
        double(obs_l2_lo), double(obs_l2_hi), worst_l2);
    fprintf('    HEADROOM NOTE: the Level-2 bound is provably conservative and is\n');
    fprintf('    NOT reachable by any Y8 input found so far, so signed 16-bit\n');
    fprintf('    storage is never stressed near its limit by this suite.\n');

    % =================================================================
    % 6) Error-path checks
    % =================================================================
    assert(throws_error(@() dwt53_forward_2level([])), 'must reject empty img');
    assert(throws_error(@() dwt53_forward_2level(zeros(6,6))), ...
        'must reject dims not divisible by 4 (6x6 is even but not /4)');
    assert(throws_error(@() dwt53_forward_2level(zeros(2,2))), ...
        'must reject dims not divisible by 4 (2x2 -> LL1 would be 1x1, not further decomposable)');
    assert(throws_error(@() dwt53_forward_2level(zeros(4,6))), ...
        'must reject mixed divisible/non-divisible dims (4x6)');

    bad_coeffs = struct('LL2',1,'HL2',1,'LH2',1); % missing HH2/HL1/LH1/HH1
    assert(throws_error(@() dwt53_inverse_2level(bad_coeffs)), 'inverse must reject incomplete coeffs struct');
    assert(throws_error(@() dwt53_pack_2level(bad_coeffs)), 'pack must reject incomplete coeffs struct');
    fprintf('  [PASS] error-path validation (non-/4 dimensions, incomplete struct)\n');

    % =================================================================
    % Summary
    % =================================================================
    fprintf('\n--- test_dwt53_2level summary ---\n');
    fprintf('Total cases executed        : %d\n', stats.n_cases);
    fprintf('Maximum reconstruction error: %d\n', double(stats.max_abs_recon_error));
    fprintf('Observed coefficient range  : [%d, %d]\n', ...
        double(stats.min_coeff), double(stats.max_coeff));
    fprintf('Arithmetic dtype            : int64 throughout\n');
    assert(stats.max_abs_recon_error == 0, 'Gate 3 FAIL: nonzero reconstruction error observed');
    fprintf('[PASS] test_dwt53_2level: ALL categories passed, max reconstruction error = 0\n');
end

% =====================================================================
% Local helper subfunctions
% =====================================================================

function stats = check_2level(stats, img, label)
    coeffs = dwt53_forward_2level(img);
    img_rec = dwt53_inverse_2level(coeffs);
    err = max(abs(int64(img_rec(:)) - int64(img(:))));
    if isempty(err)
        err = int64(0);
    end
    if err ~= 0
        error('check_2level(%s): reconstruction error=%d', label, double(err));
    end
    stats = tally(stats, img, coeffs);
end

function stats = tally(stats, img, coeffs)
    stats.n_cases = stats.n_cases + 1;
    all_coeffs = [coeffs.LL2(:); coeffs.HL2(:); coeffs.LH2(:); coeffs.HH2(:); ...
                  coeffs.HL1(:); coeffs.LH1(:); coeffs.HH1(:)];
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

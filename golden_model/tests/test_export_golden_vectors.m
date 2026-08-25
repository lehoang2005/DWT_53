function n_pass = test_export_golden_vectors()
%TEST_EXPORT_GOLDEN_VECTORS  Gate 4 self-checking regression: export
%   golden vectors to disk, read every file back independently of
%   export_golden_vectors.m's own return values, and verify exact
%   (bit-exact) recovery of both the input image and all seven
%   coefficient subbands -- covering the project brief's explicit
%   requirement "Có test đọc ngược file và khôi phục đúng coefficient."

    n_pass = 0;
    fprintf('=== test_export_golden_vectors: Gate 4 regression ===\n');

    out_dir = fullfile(tempdir(), sprintf('dwt53_golden_vectors_test_%d', round(rand()*1e9)));

    % =================================================================
    % 1) Export a test image chosen to guarantee BOTH positive and
    %    negative coefficients appear (spec requires the negative-hex
    %    path to be exercised, not just the positive one)
    % =================================================================
    rand('seed', 4040);  %#ok<RAND>
    R = 16; C = 24;
    img = int64(floor(rand(R, C) * 256));
    img(img > 255) = 255;

    info = export_golden_vectors(img, out_dir);
    n_pass = n_pass + 1;

    all_exported_coeffs = [info.coeffs.LL2(:); info.coeffs.HL2(:); info.coeffs.LH2(:); ...
                            info.coeffs.HH2(:); info.coeffs.HL1(:); info.coeffs.LH1(:); ...
                            info.coeffs.HH1(:)];
    assert(any(all_exported_coeffs < 0), ...
        'test image must produce at least one negative coefficient (got none -- test is not exercising the negative-hex path)');
    n_pass = n_pass + 1;
    fprintf('  [PASS] export produced both positive and negative coefficients (min=%d, max=%d)\n', ...
        double(min(all_exported_coeffs)), double(max(all_exported_coeffs)));

    % =================================================================
    % 2) Read back input_pixels_dec.txt and input_pixels_hex.txt,
    %    reconstruct the image, compare to the ORIGINAL img (not to
    %    info.img, to avoid a test that trivially passes by comparing
    %    a value against itself)
    % =================================================================
    img_from_dec = read_dec_matrix(info.files.input_pixels_dec, R, C);
    assert(isequal(img_from_dec, img), 'input_pixels_dec.txt did not reconstruct the original image exactly');
    n_pass = n_pass + 1;

    img_from_hex = read_hex_matrix(info.files.input_pixels_hex, R, C, 8, false);
    assert(isequal(img_from_hex, img), 'input_pixels_hex.txt did not reconstruct the original image exactly');
    n_pass = n_pass + 1;
    fprintf('  [PASS] input pixels: dec and hex readback both reconstruct the original image exactly\n');

    % =================================================================
    % 3) Read back every one of the seven coefficient subbands (dec AND
    %    hex), compare to the freshly-computed reference from
    %    dwt53_forward_2level.m directly (independent of export_golden_vectors'
    %    internal coeffs, though they should of course agree too)
    % =================================================================
    ref_coeffs = dwt53_forward_2level(img);
    subband_names = {'LL2','HL2','LH2','HH2','HL1','LH1','HH1'};
    for i = 1:numel(subband_names)
        name = subband_names{i};
        ref = ref_coeffs.(name);
        [sr, sc] = size(ref);

        dec_field = sprintf('%s_dec', name);
        hex_field = sprintf('%s_hex', name);

        from_dec = read_dec_matrix(info.files.(dec_field), sr, sc);
        assert(isequal(from_dec, ref), sprintf('%s: dec readback mismatch', name));
        n_pass = n_pass + 1;

        from_hex = read_hex_matrix(info.files.(hex_field), sr, sc, info.coeff_bits, true);
        assert(isequal(from_hex, ref), sprintf('%s: hex readback mismatch', name));
        n_pass = n_pass + 1;
    end
    fprintf('  [PASS] all 7 subbands: dec and hex readback both reconstruct exactly (14 files checked)\n');

    % =================================================================
    % 4) README sanity checks: exists, non-empty, mentions the
    %    mandatory row-major convention and all 7 subband names
    % =================================================================
    assert(exist(info.files.readme, 'file') == 2, 'README file must exist');
    fid = fopen(info.files.readme, 'r');
    readme_text = fread(fid, Inf, '*char')';
    fclose(fid);
    assert(~isempty(readme_text), 'README must not be empty');
    assert(~isempty(strfind(readme_text, 'reshape(A')), 'README must document the row-major reshape(A.'',[],1) convention');
    for i = 1:numel(subband_names)
        assert(~isempty(strfind(readme_text, subband_names{i})), ...
            sprintf('README must mention subband %s', subband_names{i}));
    end
    n_pass = n_pass + 1;
    fprintf('  [PASS] README exists, non-empty, documents row-major convention and all subband names\n');

    % =================================================================
    % 5) Error-path checks
    % =================================================================
    assert(throws_error(@() export_golden_vectors([], out_dir)), 'must reject empty img');
    assert(throws_error(@() export_golden_vectors(zeros(6,6), out_dir)), ...
        'must reject dims not divisible by 4');
    assert(throws_error(@() export_golden_vectors([300 0; 0 0], out_dir)), ...
        'must reject img values outside [0,255]');
    assert(throws_error(@() export_golden_vectors([-1 0; 0 0], out_dir)), ...
        'must reject negative img values (Y8 is unsigned)');
    assert(throws_error(@() export_golden_vectors([1.5 0; 0 0], out_dir)), ...
        'must reject non-integer img values');
    fprintf('  [PASS] error-path validation\n');

    % cleanup
    try
        rmdir(out_dir, 's');
    catch
        % non-fatal: leftover temp dir does not affect correctness
    end

    fprintf('\n[PASS] test_export_golden_vectors: %d assertions passed, all files bit-exact round trip\n', n_pass);
end

% =====================================================================
% Local helper subfunctions
% =====================================================================

function A = read_dec_matrix(path, R, C)
% Read a *_dec.txt file (one decimal integer per line, row-major) and
% reconstruct the original RxC matrix.
    fid = fopen(path, 'r');
    if fid < 0
        error('read_dec_matrix: could not open %s', path);
    end
    v = fscanf(fid, '%d');
    fclose(fid);
    assert(numel(v) == R*C, sprintf('%s: expected %d values, got %d', path, R*C, numel(v)));
    A = int64(reshape(v, C, R).');   % inverse of reshape(A.',[],1)
end

function A = read_hex_matrix(path, R, C, bits, is_signed)
% Read a *_hex.txt file (one fixed-width hex value per line, row-major)
% and reconstruct the original RxC matrix. is_signed selects two's
% complement decoding (coefficients) vs plain unsigned decoding (pixels).
    fid = fopen(path, 'r');
    if fid < 0
        error('read_hex_matrix: could not open %s', path);
    end
    raw = textscan(fid, '%s');
    fclose(fid);
    hex_lines = raw{1};
    assert(numel(hex_lines) == R*C, sprintf('%s: expected %d hex lines, got %d', path, R*C, numel(hex_lines)));
    hex_matrix = char(hex_lines);
    if is_signed
        v = hex_signed_to_int(hex_matrix, bits);
    else
        v = int64(hex2dec(hex_matrix));
    end
    A = int64(reshape(v, C, R).');
end

function tf = throws_error(fn)
    tf = false;
    try
        fn();
    catch
        tf = true;
    end
end

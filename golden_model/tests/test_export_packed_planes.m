function n_pass = test_export_packed_planes()
%TEST_EXPORT_PACKED_PLANES  Self-checking regression for export_packed_planes.m.
%
%   Exports a packed vector set to disk, reads EVERY file back with parsers
%   that are independent of export_packed_planes.m's own return values, and
%   verifies exact recovery of the input, of both packed planes, and of the
%   reconstruction.
%
%   WHY THE READBACK MATTERS MORE THAN THE EXPORT
%       These files exist to be consumed by $readmemh in a SystemVerilog
%       testbench.  A file that is written correctly but cannot be parsed back
%       into the same numbers is useless, and the failure would surface as an
%       RTL "mismatch" that costs a day to trace.  So every plane is compared
%       against a freshly-computed reference, not against info.C1 / info.C2.
%
%   WHAT IS CHECKED
%       1. the test image genuinely produces negative coefficients, so the
%          two's-complement path is exercised rather than assumed;
%       2. input_y8 dec and hex both reconstruct the original image;
%       3. c1_packed dec and hex both equal dwt53_pack_2d(dwt53_forward_2d(.));
%       4. c2_packed dec and hex both equal dwt53_pack_2level(...);
%       5. recon_y8 equals the input exactly (the spec ALG-OUT-001 invariant,
%          checked through the files rather than in memory);
%       6. C2 read back from disk differs from C1 read back from disk ONLY in
%          the top-left LL1 quadrant;
%       7. the manifest signature triple matches a count/XOR/sum computed here
%          independently, using the same semantics as
%          dwt53_signature_checkpoint.sv;
%       8. line counts equal rows*cols in every file;
%       9. error paths reject bad input instead of writing a bad set.

    n_pass = 0;
    fprintf('=== test_export_packed_planes: packed C1/C2 export regression ===\n');

    out_dir = fullfile(tempdir(), sprintf('dwt53_packed_planes_test_%d', ...
                                          round(rand() * 1e9)));

    % =================================================================
    % 1) Export an image chosen to guarantee negative coefficients
    % =================================================================
    rand('seed', 5150);  %#ok<RAND>
    R = 16; C = 24;
    img = int64(floor(rand(R, C) * 256));
    img(img > 255) = 255;

    info = export_packed_planes(img, out_dir);
    n_pass = n_pass + 1;

    c2_all = reshape(info.C2.', [], 1);
    assert(any(c2_all < 0), ...
        ['test image must produce at least one negative coefficient ' ...
         '(got none -- the two''s-complement path is not being exercised)']);
    n_pass = n_pass + 1;
    fprintf('  [PASS] export produced both positive and negative coefficients (min=%d, max=%d)\n', ...
        double(min(c2_all)), double(max(c2_all)));

    % =================================================================
    % 2) Independent references, computed here and not taken from info
    % =================================================================
    [LL1, HL1, LH1, HH1] = dwt53_forward_2d(img);
    ref_C1 = dwt53_pack_2d(LL1, HL1, LH1, HH1);
    ref_C2 = dwt53_pack_2level(dwt53_forward_2level(img));

    % =================================================================
    % 3) Input plane readback
    % =================================================================
    got = read_dec_plane(fullfile(out_dir, 'input_y8_dec.txt'), R, C);
    assert(isequal(got, img), 'input_y8_dec.txt did not reconstruct the image');
    n_pass = n_pass + 1;

    got = read_hex_plane(fullfile(out_dir, 'input_y8_hex.txt'), R, C, 8, false);
    assert(isequal(got, img), 'input_y8_hex.txt did not reconstruct the image');
    n_pass = n_pass + 1;
    fprintf('  [PASS] input_y8: dec and hex readback both exact (8-bit unsigned)\n');

    % =================================================================
    % 4) Packed C1 readback  -- this is the plane that did not exist before
    % =================================================================
    c1_dec = read_dec_plane(fullfile(out_dir, 'c1_packed_dec.txt'), R, C);
    assert(isequal(c1_dec, ref_C1), 'c1_packed_dec.txt mismatch');
    n_pass = n_pass + 1;

    c1_hex = read_hex_plane(fullfile(out_dir, 'c1_packed_hex.txt'), R, C, info.coeff_bits, true);
    assert(isequal(c1_hex, ref_C1), 'c1_packed_hex.txt mismatch');
    n_pass = n_pass + 1;

    % LL1 must be recoverable from C1's top-left quadrant.  This is the whole
    % reason C1 is exported: export_golden_vectors.m never emits LL1.
    assert(isequal(c1_hex(1:R/2, 1:C/2), LL1), 'LL1 not recoverable from packed C1');
    assert(isequal(c1_hex(1:R/2, C/2+1:C), HL1), 'HL1 quadrant wrong in packed C1');
    assert(isequal(c1_hex(R/2+1:R, 1:C/2), LH1), 'LH1 quadrant wrong in packed C1');
    assert(isequal(c1_hex(R/2+1:R, C/2+1:C), HH1), 'HH1 quadrant wrong in packed C1');
    n_pass = n_pass + 1;
    fprintf('  [PASS] c1_packed: dec and hex exact; LL/HL/LH/HH quadrants in the spec 8.2 positions\n');

    % =================================================================
    % 5) Packed C2 readback
    % =================================================================
    c2_dec = read_dec_plane(fullfile(out_dir, 'c2_packed_dec.txt'), R, C);
    assert(isequal(c2_dec, ref_C2), 'c2_packed_dec.txt mismatch');
    n_pass = n_pass + 1;

    c2_hex = read_hex_plane(fullfile(out_dir, 'c2_packed_hex.txt'), R, C, info.coeff_bits, true);
    assert(isequal(c2_hex, ref_C2), 'c2_packed_hex.txt mismatch');
    n_pass = n_pass + 1;
    fprintf('  [PASS] c2_packed: dec and hex readback both exact\n');

    % =================================================================
    % 6) Level-2 containment, checked on the data read BACK from disk
    % =================================================================
    assert(isequal(c2_hex(1:R/2, C/2+1:C), c1_hex(1:R/2, C/2+1:C)), ...
        'HL1 differs between C1 and C2 on disk');
    assert(isequal(c2_hex(R/2+1:R, 1:C/2), c1_hex(R/2+1:R, 1:C/2)), ...
        'LH1 differs between C1 and C2 on disk');
    assert(isequal(c2_hex(R/2+1:R, C/2+1:C), c1_hex(R/2+1:R, C/2+1:C)), ...
        'HH1 differs between C1 and C2 on disk');
    assert(~isequal(c2_hex(1:R/2, 1:C/2), c1_hex(1:R/2, 1:C/2)), ...
        'LL1 quadrant is identical in C1 and C2 -- Level 2 did nothing');
    n_pass = n_pass + 1;
    fprintf('  [PASS] Level-2 containment holds on the files: only the LL1 quadrant changed\n');

    % =================================================================
    % 7) Reconstruction plane equals the input (spec ALG-OUT-001)
    % =================================================================
    rec = read_hex_plane(fullfile(out_dir, 'recon_y8_hex.txt'), R, C, 8, false);
    assert(isequal(rec, img), 'recon_y8_hex.txt does not equal the input image');
    n_pass = n_pass + 1;
    fprintf('  [PASS] recon_y8 equals the input exactly, verified through the files\n');

    % =================================================================
    % 8) Manifest signature triple, recomputed independently here
    % =================================================================
    flat  = reshape(ref_C2.', [], 1);
    pats  = mod(double(flat), 2^info.coeff_bits);
    exp_count = numel(flat);
    exp_sum   = mod(sum(pats), 2^32);
    exp_xor   = 0;
    for k = 1:numel(pats)
        exp_xor = bitxor(exp_xor, pats(k));
    end

    m = read_manifest(fullfile(out_dir, 'manifest.txt'));
    assert(str2double(m.sig_count) == exp_count, 'manifest sig_count mismatch');
    assert(hex2dec(m.sig_xor) == exp_xor, 'manifest sig_xor mismatch');
    assert(hex2dec(m.sig_sum) == exp_sum, 'manifest sig_sum mismatch');
    assert(str2double(m.rows) == R && str2double(m.cols) == C, 'manifest dims mismatch');
    assert(str2double(m.lines_c2) == R*C, 'manifest lines_c2 mismatch');
    assert(str2double(m.coeff_bits) == info.coeff_bits, 'manifest coeff_bits mismatch');
    n_pass = n_pass + 1;
    fprintf('  [PASS] manifest: dims, line counts and signature triple all independently reproduced\n');
    fprintf('         sig_count=%d  sig_xor=%04X  sig_sum=%08X\n', exp_count, exp_xor, exp_sum);

    % =================================================================
    % 9) Error paths -- a bad set must not be written
    % =================================================================
    assert(throws_error(@() export_packed_planes([], out_dir)), 'must reject empty img');
    assert(throws_error(@() export_packed_planes(zeros(6,6), out_dir)), ...
        'must reject dims not divisible by 4');
    assert(throws_error(@() export_packed_planes([300 0 0 0; zeros(3,4)], out_dir)), ...
        'must reject values above 255');
    assert(throws_error(@() export_packed_planes([-1 0 0 0; zeros(3,4)], out_dir)), ...
        'must reject negative values (Y8 is unsigned)');
    assert(throws_error(@() export_packed_planes([1.5 0 0 0; zeros(3,4)], out_dir)), ...
        'must reject non-integer values');
    assert(throws_error(@() export_packed_planes(zeros(4,4), out_dir, 15)), ...
        'must reject coeff_bits that is not a multiple of 4');
    n_pass = n_pass + 1;
    fprintf('  [PASS] error-path validation\n');

    try
        rmdir(out_dir, 's');
    catch
        % non-fatal: a leftover temp dir does not affect correctness
    end

    fprintf('\n[PASS] test_export_packed_planes: %d assertions passed, all planes bit-exact round trip\n', ...
        n_pass);
end

% =====================================================================
% Local helper subfunctions
% =====================================================================

function A = read_dec_plane(path, R, C)
    fid = fopen(path, 'r');
    if fid < 0
        error('read_dec_plane: could not open %s', path);
    end
    v = fscanf(fid, '%d');
    fclose(fid);
    assert(numel(v) == R*C, sprintf('%s: expected %d values, got %d', path, R*C, numel(v)));
    A = int64(reshape(v, C, R).');   % inverse of reshape(A.', [], 1)
end

function A = read_hex_plane(path, R, C, bits, is_signed)
    fid = fopen(path, 'r');
    if fid < 0
        error('read_hex_plane: could not open %s', path);
    end
    raw = textscan(fid, '%s');
    fclose(fid);
    lines = raw{1};
    assert(numel(lines) == R*C, ...
        sprintf('%s: expected %d hex lines, got %d', path, R*C, numel(lines)));
    hm = char(lines);
    assert(size(hm, 2) == bits/4, ...
        sprintf('%s: expected %d hex digits per line, got %d', path, bits/4, size(hm, 2)));
    if is_signed
        v = hex_signed_to_int(hm, bits);
    else
        v = int64(hex2dec(hm));
    end
    A = int64(reshape(v, C, R).');
end

function m = read_manifest(path)
% Parse "key = value" lines, ignoring comments and blanks.  Repeated keys keep
% the first occurrence, which is enough for the fields checked here.
    fid = fopen(path, 'r');
    if fid < 0
        error('read_manifest: could not open %s', path);
    end
    m = struct();
    while true
        ln = fgetl(fid);
        if ~ischar(ln)
            break;
        end
        ln = strtrim(ln);
        if isempty(ln) || ln(1) == '#'
            continue;
        end
        p = strfind(ln, '=');
        if isempty(p)
            continue;
        end
        key = strtrim(ln(1:p(1)-1));
        val = strtrim(ln(p(1)+1:end));
        if ~isempty(key) && ~isfield(m, key)
            m.(key) = val;
        end
    end
    fclose(fid);
end

function tf = throws_error(fn)
    tf = false;
    try
        fn();
    catch
        tf = true;
    end
end

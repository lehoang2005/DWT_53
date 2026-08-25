function info = export_packed_planes(img, out_dir, coeff_bits)
%EXPORT_PACKED_PLANES  Export PACKED C1/C2 coefficient planes for RTL crosscheck.
%
%   info = EXPORT_PACKED_PLANES(img, out_dir) writes a complete, self-contained
%   golden-vector set for one image: the Y8 input, the one-level packed plane
%   C1, the two-level packed plane C2, and the reconstructed frame.
%
%   WHY THIS FILE EXISTS
%       export_golden_vectors.m writes the SEVEN LOGICAL SUBBANDS separately
%       (LL2/HL2/LH2/HH2/HL1/LH1/HH1).  That is the right serialization for a
%       CPU/CUDA implementation that keeps subbands as separate arrays, but it
%       is NOT what the RTL emits.  Both dwt53_forward_2d.sv and
%       dwt53_forward_2level.sv stream a single PACKED plane whose out_index is
%       the linear row-major index of the FULL plane.  Comparing those two
%       shapes required the testbench to reassemble seven files into quadrants
%       itself -- an unspecified step, and precisely the place where an HL/LH
%       swap would hide.
%
%       export_golden_vectors.m also never emits LL1 at all (Level 2 consumes
%       it), so there was no golden source whatsoever for the one-level DUT
%       dwt53_forward_2d.  C1 fixes that: LL1 is its top-left quadrant.
%
%       export_golden_vectors.m is a frozen/reviewed file and is NOT modified
%       or called by this one.  The two exporters coexist and serve different
%       consumers.
%
%   NO DUPLICATED ARITHMETIC
%       This function performs no lifting and no packing logic of its own.  It
%       calls dwt53_forward_2d.m, dwt53_forward_2level.m, dwt53_pack_2d.m,
%       dwt53_pack_2level.m, dwt53_inverse_2d.m, dwt53_inverse_2level.m and
%       int_to_hex_signed.m -- every one of which is already covered by
%       tests/run_all_tests.m.
%
%   SERIALIZATION (algorithm_spec_v0.1 Section 11, mandatory)
%       Every matrix is flattened ROW-MAJOR with reshape(A.', [], 1), never
%       MATLAB's native column-major A(:).
%
%   BIT WIDTHS -- deliberately NOT uniform, and this matters
%       input / recon : 8-bit UNSIGNED, plain 2-digit hex.  Y8 samples are
%                       never negative, and the RTL ingress port is
%                       in_y8[7:0], so a 4-digit signed encoding here would
%                       not load correctly with $readmemh into an 8-bit array.
%       C1 / C2       : coeff_bits-bit SIGNED two's complement (default 16,
%                       the frozen baseline of spec Section 5.2), matching
%                       out_data[COEFF_W-1:0] in the RTL.
%
%   SELF-CHECKS BEFORE ANYTHING IS WRITTEN
%       A vector set that is silently wrong is worse than no vector set, so
%       four invariants are asserted first and the function errors out rather
%       than writing a bad file:
%         1. one-level round trip  is bit exact;
%         2. two-level round trip  is bit exact;
%         3. C2 differs from C1 ONLY in the top-left LL1 quadrant
%            (spec Section 9.1 Level-2 containment);
%         4. every coefficient fits the signed coeff_bits range -- enforced by
%            int_to_hex_signed.m, which errors instead of wrapping.
%
%   SIGNATURE TRIPLE
%       The manifest records count / rolling XOR / modulo-2^32 sum over the
%       C2 two's-complement bit patterns, in row-major order.  These are the
%       SAME three accumulators as dwt53_signature_checkpoint.sv, so
%       tb_haps_wavelet_top_regression can check sig_count / sig_xor / sig_sum
%       against a MATLAB-computed value instead of against another
%       SystemVerilog reimplementation.
%
%   INPUT
%       img        - 2D integer matrix, values in [0,255], both dimensions
%                    divisible by 4
%       out_dir    - output directory (created if missing)
%       coeff_bits - optional, default 16
%
%   OUTPUT
%       info - struct with fields .img .C1 .C2 .recon .dims .coeff_bits
%              .signature (.count/.xor/.sum) and .files

    if nargin < 3 || isempty(coeff_bits)
        coeff_bits = 16;
    end

    % ---------------------------------------------------------------
    % Input validation
    % ---------------------------------------------------------------
    if isempty(img)
        error('export_packed_planes:emptyInput', 'img must not be empty.');
    end
    if ~ismatrix(img) || isvector(img)
        error('export_packed_planes:notMatrix', 'img must be a 2D matrix (not a vector).');
    end
    if any(~isfinite(img(:))) || any(mod(img(:), 1) ~= 0)
        error('export_packed_planes:notInteger', 'img must contain only finite integer values.');
    end
    if any(img(:) < 0) || any(img(:) > 255)
        error('export_packed_planes:notY8', ...
            'img must be Y8 (unsigned 8-bit): every sample must be in [0,255].');
    end
    [rows, cols] = size(img);
    if mod(rows, 4) ~= 0 || mod(cols, 4) ~= 0
        error('export_packed_planes:notDivisibleBy4', ...
            'img dimensions must both be divisible by 4 (got %dx%d).', rows, cols);
    end
    if isempty(out_dir)
        error('export_packed_planes:badOutDir', 'out_dir must not be empty.');
    end
    validateattributes(coeff_bits, {'numeric'}, ...
        {'scalar','positive','integer'}, mfilename, 'coeff_bits');
    if mod(coeff_bits, 4) ~= 0
        error('export_packed_planes:badBits', ...
            'coeff_bits must be a multiple of 4 (got %d).', coeff_bits);
    end

    img = int64(img);
    half_r = rows / 2;
    half_c = cols / 2;

    % ---------------------------------------------------------------
    % Level 1: subbands -> packed C1
    % ---------------------------------------------------------------
    [LL1, HL1, LH1, HH1] = dwt53_forward_2d(img);
    C1 = dwt53_pack_2d(LL1, HL1, LH1, HH1);

    % ---------------------------------------------------------------
    % Level 2 (transforms ONLY LL1) -> packed C2
    % ---------------------------------------------------------------
    coeffs = dwt53_forward_2level(img);
    C2 = dwt53_pack_2level(coeffs);

    % ---------------------------------------------------------------
    % Self-check 1: one-level round trip
    % ---------------------------------------------------------------
    recon_l1 = dwt53_inverse_2d(LL1, HL1, LH1, HH1);
    if ~isequal(int64(recon_l1), img)
        error('export_packed_planes:roundTripL1', ...
            ['one-level round trip is not bit exact (max abs error %d); ' ...
             'refusing to write a golden vector set'], ...
            double(max(abs(int64(recon_l1(:)) - img(:)))));
    end

    % ---------------------------------------------------------------
    % Self-check 2: two-level round trip
    % ---------------------------------------------------------------
    recon = dwt53_inverse_2level(coeffs);
    if ~isequal(int64(recon), img)
        error('export_packed_planes:roundTripL2', ...
            ['two-level round trip is not bit exact (max abs error %d); ' ...
             'refusing to write a golden vector set'], ...
            double(max(abs(int64(recon(:)) - img(:)))));
    end

    % ---------------------------------------------------------------
    % Self-check 3: Level-2 containment (spec Section 9.1).  C2 must differ
    % from C1 ONLY inside the top-left LL1 quadrant.  This is checked on the
    % packed planes themselves, so it also catches a packing mistake.
    % ---------------------------------------------------------------
    if ~isequal(C2(1:half_r, half_c+1:cols), C1(1:half_r, half_c+1:cols))
        error('export_packed_planes:level2Leak', 'Level 2 modified the HL1 quadrant.');
    end
    if ~isequal(C2(half_r+1:rows, 1:half_c), C1(half_r+1:rows, 1:half_c))
        error('export_packed_planes:level2Leak', 'Level 2 modified the LH1 quadrant.');
    end
    if ~isequal(C2(half_r+1:rows, half_c+1:cols), C1(half_r+1:rows, half_c+1:cols))
        error('export_packed_planes:level2Leak', 'Level 2 modified the HH1 quadrant.');
    end

    % ---------------------------------------------------------------
    % Output directory
    % ---------------------------------------------------------------
    if ~exist(out_dir, 'dir')
        [ok, msg] = mkdir(out_dir);
        if ~ok
            error('export_packed_planes:mkdirFailed', 'Could not create out_dir: %s', msg);
        end
    end

    % ---------------------------------------------------------------
    % Row-major flattening (spec Section 11)
    % ---------------------------------------------------------------
    img_flat   = reshape(img.',   [], 1);
    c1_flat    = reshape(C1.',    [], 1);
    c2_flat    = reshape(C2.',    [], 1);
    recon_flat = reshape(int64(recon).', [], 1);

    files = struct();

    % Y8 planes: unsigned, plain 2-digit hex (see header note on widths).
    files.input_y8_dec = write_pair(out_dir, 'input_y8', img_flat,   8,  false);
    files.input_y8_hex = strrep(files.input_y8_dec, '_dec.txt', '_hex.txt');
    files.recon_y8_dec = write_pair(out_dir, 'recon_y8', recon_flat, 8,  false);
    files.recon_y8_hex = strrep(files.recon_y8_dec, '_dec.txt', '_hex.txt');

    % Packed coefficient planes: signed two's complement.
    files.c1_packed_dec = write_pair(out_dir, 'c1_packed', c1_flat, coeff_bits, true);
    files.c1_packed_hex = strrep(files.c1_packed_dec, '_dec.txt', '_hex.txt');
    files.c2_packed_dec = write_pair(out_dir, 'c2_packed', c2_flat, coeff_bits, true);
    files.c2_packed_hex = strrep(files.c2_packed_dec, '_dec.txt', '_hex.txt');

    % ---------------------------------------------------------------
    % Signature triple over the C2 bit patterns (matches
    % dwt53_signature_checkpoint.sv semantics exactly)
    % ---------------------------------------------------------------
    sig = signature_triple(c2_flat, coeff_bits);

    % ---------------------------------------------------------------
    % Manifest
    % ---------------------------------------------------------------
    dims = struct();
    dims.rows       = rows;
    dims.cols       = cols;
    dims.total      = rows * cols;
    dims.quarter    = half_r * half_c;
    dims.l1_subband = [half_r, half_c];
    dims.l2_subband = [half_r/2, half_c/2];

    files.manifest = fullfile(out_dir, 'manifest.txt');
    write_manifest(files.manifest, dims, coeff_bits, c1_flat, c2_flat, sig);

    info            = struct();
    info.img        = img;
    info.C1         = C1;
    info.C2         = C2;
    info.recon      = int64(recon);
    info.dims       = dims;
    info.coeff_bits = coeff_bits;
    info.signature  = sig;
    info.files      = files;
end

% =====================================================================
% Local helper subfunctions
% =====================================================================

function dec_path = write_pair(out_dir, name, vec, bits, is_signed)
% Write <name>_dec.txt and <name>_hex.txt for one already-flattened vector.
% Returns the dec path; the hex path is the same with the suffix swapped.
    dec_path = fullfile(out_dir, sprintf('%s_dec.txt', name));
    hex_path = fullfile(out_dir, sprintf('%s_hex.txt', name));

    fid = fopen(dec_path, 'w');
    if fid < 0
        error('export_packed_planes:fileOpen', 'Could not open %s for writing.', dec_path);
    end
    fprintf(fid, '%d\n', double(vec));
    fclose(fid);

    if is_signed
        % int_to_hex_signed errors (never wraps) on out-of-range values, so a
        % coefficient that does not fit the frozen width fails loudly here.
        hex_matrix = int_to_hex_signed(vec, bits);
    else
        v = double(vec);
        if any(v < 0) || any(v >= 2^bits)
            error('export_packed_planes:unsignedRange', ...
                'unsigned %d-bit export out of range [0,%d] (min=%d, max=%d).', ...
                bits, 2^bits - 1, min(v), max(v));
        end
        hex_matrix = dec2hex(v, bits / 4);
    end

    fid = fopen(hex_path, 'w');
    if fid < 0
        error('export_packed_planes:fileOpen', 'Could not open %s for writing.', hex_path);
    end
    % Vectorized write: append a newline column, transpose, flatten, so the
    % linear byte order is row1+LF, row2+LF, ...  Avoids a per-line fprintf
    % for potentially 921,600-line files.
    hm_nl   = [hex_matrix, repmat(char(10), size(hex_matrix, 1), 1)];
    hm_nl_t = hm_nl.';
    fwrite(fid, hm_nl_t(:), 'char');
    fclose(fid);
end

function sig = signature_triple(flat, bits)
% count / rolling XOR / modulo-2^32 sum over two's-complement bit patterns,
% in the order given.  Mirrors dwt53_signature_checkpoint.sv:
%   sample_count <= sample_count + 1
%   xor_acc      <= xor_acc ^ sample_data
%   sum_acc      <= sum_acc + {zero-extended sample_data}
    pats = uint32(mod(double(flat), 2^bits));

    % XOR reduction without a per-element loop: for each bit position, the
    % XOR of the column equals the parity of the number of ones.
    x = uint32(0);
    for b = 1:bits
        if mod(sum(double(bitget(pats, b))), 2) == 1
            x = bitset(x, b);
        end
    end

    % Exact in double: numel * (2^bits - 1) stays far below 2^53 for every
    % supported frame size.
    sig        = struct();
    sig.count  = numel(flat);
    sig.xor    = double(x);
    sig.sum    = mod(sum(double(pats)), 2^32);
    sig.bits   = bits;
end

function write_manifest(path, dims, coeff_bits, c1_flat, c2_flat, sig)
    fid = fopen(path, 'w');
    if fid < 0
        error('export_packed_planes:fileOpen', 'Could not open %s for writing.', path);
    end

    fprintf(fid, '# DWT53 packed golden vector set\n');
    fprintf(fid, '# Generated by export_packed_planes.m per algorithm_spec_v0.1.\n');
    fprintf(fid, '# Every field below is machine readable: "key = value".\n');
    fprintf(fid, '\n');

    fprintf(fid, 'generated_at   = %s\n', datestr(now, 'yyyy-mm-ddTHH:MM:SS'));
    if exist('OCTAVE_VERSION', 'builtin')
        fprintf(fid, 'runtime        = Octave %s\n', OCTAVE_VERSION);
    else
        fprintf(fid, 'runtime        = MATLAB %s\n', version);
    end
    fprintf(fid, 'platform       = %s\n', computer());
    fprintf(fid, '\n');

    fprintf(fid, 'rows           = %d\n', dims.rows);
    fprintf(fid, 'cols           = %d\n', dims.cols);
    fprintf(fid, 'total          = %d\n', dims.total);
    fprintf(fid, 'coeff_bits     = %d\n', coeff_bits);
    fprintf(fid, 'input_bits     = 8\n');
    fprintf(fid, 'order          = row-major\n');
    fprintf(fid, 'packed_layout  = [LL HL; LH HH]\n');
    fprintf(fid, 'l2_replaces    = LL1 quadrant, rows 1..%d cols 1..%d\n', ...
        dims.rows/2, dims.cols/2);
    fprintf(fid, '\n');

    fprintf(fid, '# Line counts a $readmemh consumer must assert.\n');
    fprintf(fid, 'lines_input_y8 = %d\n', dims.total);
    fprintf(fid, 'lines_recon_y8 = %d\n', dims.total);
    fprintf(fid, 'lines_c1       = %d\n', dims.total);
    fprintf(fid, 'lines_c2       = %d\n', dims.total);
    fprintf(fid, '\n');

    fprintf(fid, '# Observed coefficient ranges (not design bounds).\n');
    fprintf(fid, 'c1_min         = %d\n', double(min(c1_flat)));
    fprintf(fid, 'c1_max         = %d\n', double(max(c1_flat)));
    fprintf(fid, 'c2_min         = %d\n', double(min(c2_flat)));
    fprintf(fid, 'c2_max         = %d\n', double(max(c2_flat)));
    fprintf(fid, '\n');

    fprintf(fid, '# Signature over the C2 two''s-complement patterns, row-major.\n');
    fprintf(fid, '# Same accumulators as dwt53_signature_checkpoint.sv, so\n');
    fprintf(fid, '# tb_haps_wavelet_top_regression can compare sig_count / sig_xor /\n');
    fprintf(fid, '# sig_sum directly against these values.\n');
    fprintf(fid, 'sig_count      = %d\n', sig.count);
    fprintf(fid, 'sig_xor        = %04X\n', sig.xor);
    fprintf(fid, 'sig_sum        = %08X\n', sig.sum);
    fprintf(fid, '\n');

    fprintf(fid, '# Files in this set\n');
    fprintf(fid, 'file           = input_y8_dec.txt   (8-bit unsigned decimal)\n');
    fprintf(fid, 'file           = input_y8_hex.txt   (2 hex digits, UNSIGNED)\n');
    fprintf(fid, 'file           = c1_packed_dec.txt  (signed decimal)\n');
    fprintf(fid, 'file           = c1_packed_hex.txt  (%d hex digits, two''s complement)\n', coeff_bits/4);
    fprintf(fid, 'file           = c2_packed_dec.txt  (signed decimal)\n');
    fprintf(fid, 'file           = c2_packed_hex.txt  (%d hex digits, two''s complement)\n', coeff_bits/4);
    fprintf(fid, 'file           = recon_y8_dec.txt   (must equal input_y8_dec.txt)\n');
    fprintf(fid, 'file           = recon_y8_hex.txt   (must equal input_y8_hex.txt)\n');
    fprintf(fid, '\n');

    fprintf(fid, '# Reconstructing a matrix from a row-major file: if the plane has\n');
    fprintf(fid, '# R rows and C columns and v is the length-(R*C) vector read back in\n');
    fprintf(fid, '# file order, the original matrix is  A = reshape(v, C, R).''\n');

    fclose(fid);
end

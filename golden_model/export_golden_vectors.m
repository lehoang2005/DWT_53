function info = export_golden_vectors(img, out_dir, coeff_bits)
%EXPORT_GOLDEN_VECTORS  Export two-level DWT53 golden vectors for RTL/CPU/CUDA.
%
%   info = EXPORT_GOLDEN_VECTORS(img, out_dir) runs the proven two-level
%   forward transform (dwt53_forward_2level.m, Gate 3) on img and writes
%   the input pixels plus all seven logical output subbands (spec
%   Section 9.1: LL2, HL2, LH2, HH2, HL1, LH1, HH1) to out_dir, each as
%   a matched pair of files:
%       <name>_dec.txt  - one decimal integer per line, for $fscanf
%       <name>_hex.txt  - one fixed-width hex value per line, for $readmemh
%   plus a README_golden_vectors.md describing sample order, subband
%   order, and bit widths.
%
%   info = EXPORT_GOLDEN_VECTORS(img, out_dir, coeff_bits) overrides the
%   coefficient hex bit width (default 16 -- the frozen correctness
%   baseline per algorithm_spec_v0.1 Section 5.2; a narrower width
%   requires a separate range proof and is out of scope here).
%
%   SERIALIZATION ORDER (spec Section 11, mandatory): every matrix is
%   flattened ROW-MAJOR using
%       reshape(A.', [], 1)
%   NOT MATLAB's native column-major A(:). This is the exact bug found
%   in the original golden_reference.m during Gate 0 inspection.
%
%   INPUT BIT WIDTH: input pixels are Y8 -- inherently UNSIGNED 8-bit
%   in [0,255] -- and are exported with plain (non-two's-complement)
%   2-digit hex. Only the signed coefficient subbands go through the
%   two's-complement helper (int_to_hex_signed.m).
%
%   INPUT
%       img       - 2D integer matrix, values in [0,255] (Y8), both
%                   dimensions divisible by 4 (required by
%                   dwt53_forward_2level.m for two-level decomposition)
%       out_dir   - output directory (created if it does not exist)
%       coeff_bits - optional, default 16
%
%   OUTPUT
%       info - struct with fields:
%           .img        - the validated int64 input image
%           .coeffs     - struct from dwt53_forward_2level.m (LL2/HL2/...)
%           .dims       - struct: size of img and of each subband
%           .coeff_bits - bit width used for coefficient hex export
%           .files      - struct of every file path written
%
%   This function performs NO lifting arithmetic itself -- it only
%   calls dwt53_forward_2level.m (Gate 3) and serializes the result.

    if nargin < 3 || isempty(coeff_bits)
        coeff_bits = 16;
    end

    % ---------------------------------------------------------------
    % Input validation
    % ---------------------------------------------------------------
    if isempty(img)
        error('export_golden_vectors:emptyInput', 'img must not be empty.');
    end
    if ~ismatrix(img) || isvector(img)
        error('export_golden_vectors:notMatrix', 'img must be a 2D matrix (not a vector).');
    end
    if any(~isfinite(img(:))) || any(mod(img(:), 1) ~= 0)
        error('export_golden_vectors:notInteger', 'img must contain only finite integer values.');
    end
    if any(img(:) < 0) || any(img(:) > 255)
        error('export_golden_vectors:notY8', ...
            'img must be Y8 (unsigned 8-bit): every sample must be in [0,255].');
    end
    [rows, cols] = size(img);
    if mod(rows, 4) ~= 0 || mod(cols, 4) ~= 0
        error('export_golden_vectors:notDivisibleBy4', ...
            'img dimensions must both be divisible by 4 (got %dx%d).', rows, cols);
    end
    if isempty(out_dir)
        error('export_golden_vectors:badOutDir', 'out_dir must not be empty.');
    end
    if ~exist(out_dir, 'dir')
        [ok, msg] = mkdir(out_dir);
        if ~ok
            error('export_golden_vectors:mkdirFailed', 'Could not create out_dir: %s', msg);
        end
    end

    img = int64(img);

    % ---------------------------------------------------------------
    % Run the proven two-level transform (Gate 3) -- no arithmetic
    % duplicated here.
    % ---------------------------------------------------------------
    coeffs = dwt53_forward_2level(img);

    % Canonical subband export order, spec Section 9.1:
    % "The seven logical output subbands are therefore: LL2, HL2, LH2, HH2, HL1, LH1, HH1"
    subband_names = {'LL2', 'HL2', 'LH2', 'HH2', 'HL1', 'LH1', 'HH1'};

    files = struct();
    dims = struct();
    dims.input = size(img);

    % ---------------------------------------------------------------
    % Input pixels: row-major, 8-bit UNSIGNED (plain hex, no two's
    % complement -- Y8 samples are never negative)
    % ---------------------------------------------------------------
    input_flat = reshape(img.', [], 1);
    dec_path = fullfile(out_dir, 'input_pixels_dec.txt');
    hex_path = fullfile(out_dir, 'input_pixels_hex.txt');
    write_dec_file(dec_path, input_flat);
    write_hex_file(hex_path, dec2hex(double(input_flat), 2));
    files.input_pixels_dec = dec_path;
    files.input_pixels_hex = hex_path;

    % ---------------------------------------------------------------
    % Seven coefficient subbands: row-major, signed two's-complement hex
    % ---------------------------------------------------------------
    for i = 1:numel(subband_names)
        name = subband_names{i};
        subband = coeffs.(name);
        flat = reshape(subband.', [], 1);

        dec_path = fullfile(out_dir, sprintf('out_%s_dec.txt', name));
        hex_path = fullfile(out_dir, sprintf('out_%s_hex.txt', name));
        write_dec_file(dec_path, flat);
        write_hex_file(hex_path, int_to_hex_signed(flat, coeff_bits));

        files.(sprintf('%s_dec', name)) = dec_path;
        files.(sprintf('%s_hex', name)) = hex_path;
        dims.(name) = size(subband);
    end

    % ---------------------------------------------------------------
    % Metadata / README
    % ---------------------------------------------------------------
    readme_path = fullfile(out_dir, 'README_golden_vectors.md');
    write_readme(readme_path, dims, coeff_bits, subband_names);
    files.readme = readme_path;

    info = struct();
    info.img = img;
    info.coeffs = coeffs;
    info.dims = dims;
    info.coeff_bits = coeff_bits;
    info.files = files;
end

% =====================================================================
% Local helper subfunctions
% =====================================================================

function write_dec_file(path, vec)
    fid = fopen(path, 'w');
    if fid < 0
        error('export_golden_vectors:fileOpen', 'Could not open %s for writing.', path);
    end
    fprintf(fid, '%d\n', double(vec));
    fclose(fid);
end

function write_hex_file(path, hex_matrix)
% Vectorized write: append a newline column, transpose, flatten
% column-major so the linear byte order is row1+"\n", row2+"\n", ...
% This avoids a per-line fprintf/fwrite call for potentially large
% (e.g. 1280x720 -> 921,600-line) files.
    fid = fopen(path, 'w');
    if fid < 0
        error('export_golden_vectors:fileOpen', 'Could not open %s for writing.', path);
    end
    hm_nl = [hex_matrix, repmat(char(10), size(hex_matrix,1), 1)];
    hm_nl_t = hm_nl.';
    fwrite(fid, hm_nl_t(:), 'char');
    fclose(fid);
end

function write_readme(path, dims, coeff_bits, subband_names)
    fid = fopen(path, 'w');
    if fid < 0
        error('export_golden_vectors:fileOpen', 'Could not open %s for writing.', path);
    end

    fprintf(fid, '# DWT53 Golden Vectors\n\n');
    fprintf(fid, 'Generated by export_golden_vectors.m (GOLDEN_MODEL_GATE_4), ');
    fprintf(fid, 'per algorithm_spec_v0.1.\n\n');

    fprintf(fid, '## Sample ordering\n\n');
    fprintf(fid, 'Every file is serialized in ROW-MAJOR order using\n\n');
    fprintf(fid, '    reshape(A.'', [], 1)\n\n');
    fprintf(fid, 'in MATLAB/Octave -- NOT the native column-major `A(:)` ');
    fprintf(fid, '(algorithm_spec_v0.1 Section 11). Within a row, samples/coefficients\n');
    fprintf(fid, 'are ordered left-to-right (increasing x); rows are ordered top-to-bottom\n');
    fprintf(fid, '(increasing y).\n\n');

    fprintf(fid, '## Input\n\n');
    fprintf(fid, '- `input_pixels_dec.txt` / `input_pixels_hex.txt`\n');
    fprintf(fid, '- Size: %d x %d (rows x cols)\n', dims.input(1), dims.input(2));
    fprintf(fid, '- 8-bit UNSIGNED (Y8, values in [0,255]); hex is plain 2-digit hex,\n');
    fprintf(fid, '  NOT two''s complement (pixels are never negative).\n\n');

    fprintf(fid, '## Subband export order (algorithm_spec_v0.1 Section 9.1)\n\n');
    fprintf(fid, 'Level 2 decomposes ONLY LL1; LL1 itself is not exported (it is fully\n');
    fprintf(fid, 'represented by LL2/HL2/LH2/HH2). The seven logical output subbands,\n');
    fprintf(fid, 'in the order they were generated below, are:\n\n');
    for i = 1:numel(subband_names)
        name = subband_names{i};
        d = dims.(name);
        fprintf(fid, '%d. `%s` -- `out_%s_dec.txt` / `out_%s_hex.txt` -- size %d x %d\n', ...
            i, name, name, name, d(1), d(2));
    end
    fprintf(fid, '\n');

    fprintf(fid, '## Bit widths\n\n');
    fprintf(fid, '- Input pixels: 8-bit unsigned (see above).\n');
    fprintf(fid, '- All seven coefficient subbands: %d-bit SIGNED two''s-complement hex\n', coeff_bits);
    fprintf(fid, '  (algorithm_spec_v0.1 Section 5.2 frozen correctness baseline is 16-bit;\n');
    fprintf(fid, '  a narrower width requires a separate range proof, out of scope here).\n');
    fprintf(fid, '  Decimal files store ordinary signed decimal (e.g. "-123") and need no\n');
    fprintf(fid, '  two''s-complement handling -- only the hex files do.\n\n');

    fprintf(fid, '## Reading these files\n\n');
    fprintf(fid, '- `*_dec.txt`: one decimal integer per line, e.g. `$fscanf(fp, "%%d", val)`.\n');
    fprintf(fid, '- `*_hex.txt`: one hex value per line (no leading "0x"), e.g.\n');
    fprintf(fid, '  `$readmemh("out_LL2_hex.txt", mem)`.\n\n');

    fprintf(fid, '## Reconstructing a 2D matrix from a row-major file\n\n');
    fprintf(fid, 'If a subband has R rows and C columns, and v is the length-(R*C) column\n');
    fprintf(fid, 'vector read back from its file (in file order), the original matrix is\n\n');
    fprintf(fid, '    A = reshape(v, C, R).''\n\n');
    fprintf(fid, '(the exact inverse of the reshape(A.'', [], 1) used to write it). This is\n');
    fprintf(fid, 'verified by tests/test_export_golden_vectors.m.\n');

    fclose(fid);
end

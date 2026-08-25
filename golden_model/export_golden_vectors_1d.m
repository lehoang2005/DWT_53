function info = export_golden_vectors_1d(x, out_dir, coeff_bits, input_bits)
%EXPORT_GOLDEN_VECTORS_1D  Export 1D DWT53 golden vectors for RTL testbench.
%
%   info = EXPORT_GOLDEN_VECTORS_1D(x, out_dir) runs the proven 1D
%   forward transform (dwt53_forward_1d.m, Gate 1 -- unmodified) on x
%   and writes the input samples plus the L (low-pass) and H (high-pass)
%   subbands to out_dir, each as a matched pair of files:
%       <name>_dec.txt  - one decimal integer per line, for $fscanf
%       <name>_hex.txt  - one fixed-width hex value per line, for $readmemh
%   plus a README_golden_vectors_1d.md describing sample order and bit
%   width.
%
%   This is the 1D companion to export_golden_vectors.m (Gate 4, two-level
%   2D export) -- intended for bringing up and verifying the atomic 1D
%   lifting datapath in RTL BEFORE assembling the full 2D / two-level
%   pipeline. export_golden_vectors.m itself is untouched by this file.
%
%   info = EXPORT_GOLDEN_VECTORS_1D(x, out_dir, coeff_bits) overrides the
%   hex bit width (default 16 -- the frozen correctness baseline per
%   algorithm_spec_v0.1 Section 5.2, same default as export_golden_vectors.m).
%
%   INPUT RANGE: unlike the 2-level exporter, x is NOT restricted to Y8
%   [0,255]. dwt53_forward_1d.m is used generically throughout the
%   pipeline -- on raw Y8 image rows AND on wider intermediate
%   coefficient vectors (e.g. columns of L_row/H_row in dwt53_forward_2d.m,
%   or LL1 rows/columns in dwt53_forward_2level.m) -- so this exporter
%   accepts any integer-valued vector within the representable range of
%   coeff_bits, and treats input/L/H uniformly as signed two's-complement
%   for hex export. If you specifically want a Y8-pixel-row-only 1D
%   export, validate/clip to [0,255] before calling this function; that
%   restriction is deliberately NOT built in here, since it would be
%   wrong for a coefficient-vector input.
%
%   SERIALIZATION: samples are written in plain vector order (index 0
%   first); there is no row/column transpose ambiguity for a 1D vector
%   the way there is for a 2D matrix (spec Section 11's row-major rule
%   only bites for 2D serialization). x is flattened with x(:) regardless
%   of whether it was supplied as a row or column vector.
%
%   INPUT
%       x          - 1D integer vector (row or column), even length >= 2
%       out_dir    - output directory (created if it does not exist)
%       coeff_bits - optional, default 16
%
%   OUTPUT
%       info - struct with fields:
%           .x, .L, .H  - the validated int64 input and its subbands
%           .dims       - struct: lengths of x, L, H
%           .coeff_bits - bit width used for hex export
%           .files      - struct of every file path written
%
%   This function performs NO lifting arithmetic itself -- it only calls
%   dwt53_forward_1d.m and serializes the result.

    if nargin < 3 || isempty(coeff_bits)
        coeff_bits = 16;
    end
    % input_bits defaults to coeff_bits, so an existing two-argument or
    % three-argument call produces byte-identical output to before this
    % parameter existed.
    if nargin < 4 || isempty(input_bits)
        input_bits = coeff_bits;
    end
    validateattributes(input_bits, {'numeric'}, ...
        {'scalar','positive','integer'}, mfilename, 'input_bits');
    if mod(input_bits, 4) ~= 0
        error('export_golden_vectors_1d:badInputBits', ...
            'input_bits must be a multiple of 4 (got %d).', input_bits);
    end

    % ---------------------------------------------------------------
    % Input validation (mirrors dwt53_forward_1d.m's own checks, plus
    % the extra checks needed before writing files)
    % ---------------------------------------------------------------
    if isempty(x)
        error('export_golden_vectors_1d:emptyInput', 'x must not be empty.');
    end
    if ~isvector(x)
        error('export_golden_vectors_1d:notVector', 'x must be a row or column vector.');
    end
    if any(~isfinite(x(:))) || any(mod(x(:), 1) ~= 0)
        error('export_golden_vectors_1d:notInteger', 'x must contain only finite integer values.');
    end
    if mod(numel(x), 2) ~= 0
        error('export_golden_vectors_1d:oddLength', ...
            'x must have even length (got N=%d).', numel(x));
    end
    if isempty(out_dir)
        error('export_golden_vectors_1d:badOutDir', 'out_dir must not be empty.');
    end
    if ~exist(out_dir, 'dir')
        [ok, msg] = mkdir(out_dir);
        if ~ok
            error('export_golden_vectors_1d:mkdirFailed', 'Could not create out_dir: %s', msg);
        end
    end

    x = int64(x(:));   % flatten to a column; no row/col ambiguity for 1D export

    % ---------------------------------------------------------------
    % Run the proven 1D transform (Gate 1) -- no arithmetic duplicated.
    % ---------------------------------------------------------------
    [L, H] = dwt53_forward_1d(x);
    L = int64(L(:));
    H = int64(H(:));

    dims = struct('x', numel(x), 'L', numel(L), 'H', numel(H));

    files = struct();

    % ---------------------------------------------------------------
    % Input samples, L, H -- all treated uniformly as signed two's-
    % complement at coeff_bits (see header note on why input is not
    % specially restricted to unsigned Y8 here).
    % ---------------------------------------------------------------
    names   = {'input', 'L', 'H'};
    vectors = {x, L, H};
    bits    = {input_bits, coeff_bits, coeff_bits};
    for i = 1:numel(names)
        name = names{i};
        v    = vectors{i};
        b    = bits{i};

        dec_path = fullfile(out_dir, sprintf('%s_dec.txt', name));
        hex_path = fullfile(out_dir, sprintf('%s_hex.txt', name));
        write_dec_file_1d(dec_path, v);

        if (i == 1) && (input_bits == 8)
            % Y8 MODE.  in_data on dwt53_forward_1d.sv is [7:0] UNSIGNED, so a
            % 4-digit signed encoding does not load correctly with $readmemh
            % into an 8-bit array.  At input_bits = 8 the input vector is
            % therefore written as plain 2-digit UNSIGNED hex, exactly like
            % export_golden_vectors.m writes image pixels.
            if any(v < 0) || any(v > 255)
                error('export_golden_vectors_1d:notY8', ...
                    ['input_bits = 8 selects unsigned Y8 encoding, so every ' ...
                     'sample must be in [0,255] (min=%d, max=%d). Use the ' ...
                     'default input_bits for signed coefficient vectors.'], ...
                    double(min(v)), double(max(v)));
            end
            write_hex_file_1d(hex_path, dec2hex(double(v), 2));
        else
            write_hex_file_1d(hex_path, int_to_hex_signed(v, b));
        end

        files.(sprintf('%s_dec', name)) = dec_path;
        files.(sprintf('%s_hex', name)) = hex_path;
    end

    % ---------------------------------------------------------------
    % Metadata / README
    % ---------------------------------------------------------------
    readme_path = fullfile(out_dir, 'README_golden_vectors_1d.md');
    write_readme_1d(readme_path, dims, coeff_bits, input_bits);
    files.readme = readme_path;

    info = struct();
    info.x = x;
    info.L = L;
    info.H = H;
    info.dims = dims;
    info.coeff_bits = coeff_bits;
    info.input_bits = input_bits;
    info.files = files;
end

% =====================================================================
% Local helper subfunctions
%
% NOTE: write_dec_file_1d / write_hex_file_1d are intentionally
% duplicated (not shared) from export_golden_vectors.m's own local
% helpers of the same shape, rather than extracting them into standalone
% files -- export_golden_vectors.m is a frozen/reviewed file that must
% not be touched or refactored. The duplicated logic is small,
% self-contained I/O plumbing, not DWT lifting arithmetic (which is
% never duplicated -- both exporters call dwt53_forward_*.m for that).
% =====================================================================

function write_dec_file_1d(path, vec)
    fid = fopen(path, 'w');
    if fid < 0
        error('export_golden_vectors_1d:fileOpen', 'Could not open %s for writing.', path);
    end
    fprintf(fid, '%d\n', double(vec));
    fclose(fid);
end

function write_hex_file_1d(path, hex_matrix)
% Vectorized write: append a newline column, transpose, flatten
% column-major (see export_golden_vectors.m for the same technique).
    fid = fopen(path, 'w');
    if fid < 0
        error('export_golden_vectors_1d:fileOpen', 'Could not open %s for writing.', path);
    end
    hm_nl = [hex_matrix, repmat(char(10), size(hex_matrix,1), 1)];
    hm_nl_t = hm_nl.';
    fwrite(fid, hm_nl_t(:), 'char');
    fclose(fid);
end

function write_readme_1d(path, dims, coeff_bits, input_bits)
    fid = fopen(path, 'w');
    if fid < 0
        error('export_golden_vectors_1d:fileOpen', 'Could not open %s for writing.', path);
    end

    fprintf(fid, '# DWT53 1D Golden Vectors\n\n');
    fprintf(fid, 'Generated by export_golden_vectors_1d.m, for bring-up/verification of the\n');
    fprintf(fid, 'atomic 1D 5/3 lifting RTL datapath BEFORE the full 2D / two-level pipeline\n');
    fprintf(fid, '(see export_golden_vectors.m for the two-level 2D export).\n\n');

    fprintf(fid, '## Files\n\n');
    fprintf(fid, '- `input_dec.txt` / `input_hex.txt` -- length %d\n', dims.x);
    fprintf(fid, '- `L_dec.txt` / `L_hex.txt` -- low-pass (approximation) subband, length %d\n', dims.L);
    fprintf(fid, '- `H_dec.txt` / `H_hex.txt` -- high-pass (detail) subband, length %d\n', dims.H);
    fprintf(fid, '\n');

    fprintf(fid, '## Sample ordering\n\n');
    fprintf(fid, 'Plain vector order, index 0 first (no row-major/column-major ambiguity\n');
    fprintf(fid, 'for a 1D vector -- that only applies to 2D serialization, spec Section 11).\n\n');

    fprintf(fid, '## Bit width\n\n');
    fprintf(fid, 'Input, L, and H are ALL exported as %d-bit SIGNED two''s-complement hex\n', coeff_bits);
    fprintf(fid, '(algorithm_spec_v0.1 Section 5.2 frozen correctness baseline is 16-bit).\n');
    fprintf(fid, 'Unlike export_golden_vectors.m''s image-pixel export, the input here is NOT\n');
    fprintf(fid, 'assumed to be unsigned Y8 -- dwt53_forward_1d.m is also used on wider\n');
    fprintf(fid, 'intermediate coefficient vectors elsewhere in the pipeline, so input is\n');
    fprintf(fid, 'treated the same as L/H: signed, %d-bit two''s complement.\n', coeff_bits);
    fprintf(fid, 'Decimal files store ordinary signed decimal and need no two''s-complement\n');
    fprintf(fid, 'handling -- only the hex files do.\n\n');

    fprintf(fid, '## Reading these files\n\n');
    fprintf(fid, '- `*_dec.txt`: one decimal integer per line, e.g. `$fscanf(fp, "%%d", val)`.\n');
    fprintf(fid, '- `*_hex.txt`: one hex value per line (no leading "0x"), e.g.\n');
    fprintf(fid, '  `$readmemh("L_hex.txt", mem)`.\n');

    fclose(fid);
end

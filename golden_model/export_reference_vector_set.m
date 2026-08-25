function info = export_reference_vector_set(img, out_dir, coeff_bits, source_label)
%EXPORT_REFERENCE_VECTOR_SET  Create and independently verify one 2D vector set.
%
%   This is a NEW wrapper around the reviewed export_packed_planes.m. It
%   does not modify or duplicate DWT arithmetic. In addition to input/C1/C2/
%   reconstruction, it adds LL1, all required checkpoint signatures, a
%   deterministic provenance manifest, and an independent file readback.
%
%   The target directory must not already exist. Generation occurs in a
%   temporary sibling directory and is published only after verification.

    if nargin < 3 || isempty(coeff_bits)
        coeff_bits = 16;
    end
    if nargin < 4 || isempty(source_label)
        source_label = 'caller_supplied_y8';
    end
    validateattributes(coeff_bits, {'numeric'}, ...
        {'scalar','positive','integer'}, mfilename, 'coeff_bits');
    if mod(coeff_bits, 4) ~= 0 || coeff_bits > 32
        error('export_reference_vector_set:badBits', ...
            'coeff_bits must be a multiple of four in [4,32].');
    end
    if isempty(out_dir)
        error('export_reference_vector_set:badOutDir', 'out_dir must not be empty.');
    end
    out_dir = char(out_dir);
    source_label = char(source_label);
    if exist(out_dir, 'file') || exist(out_dir, 'dir')
        error('export_reference_vector_set:outputExists', ...
            'Refusing to mix generations: output already exists: %s', out_dir);
    end

    parent = fileparts(out_dir);
    if isempty(parent)
        parent = pwd;
    end
    if ~exist(parent, 'dir')
        [ok, msg] = mkdir(parent);
        if ~ok
            error('export_reference_vector_set:mkdirFailed', '%s', msg);
        end
    end
    temp_dir = tempname(parent);
    [ok, msg] = mkdir(temp_dir);
    if ~ok
        error('export_reference_vector_set:mkdirFailed', '%s', msg);
    end
    cleaner = onCleanup(@() remove_temp_dir(temp_dir));

    base = export_packed_planes(img, temp_dir, coeff_bits);
    rows = base.dims.rows;
    cols = base.dims.cols;

    [LL1, HL1, LH1, HH1] = dwt53_forward_2d(base.img);
    coeffs = dwt53_forward_2level(base.img);
    ll1_flat = reshape(int64(LL1).', [], 1);
    write_signed_pair(temp_dir, 'll1', ll1_flat, coeff_bits);

    checkpoint = export_checkpoint_signatures(base, temp_dir, coeff_bits);
    if ~isequal(int64(checkpoint.LL1), int64(LL1))
        error('export_reference_vector_set:ll1ExtractionMismatch', ...
            'LL1 extracted from C1 disagrees with dwt53_forward_2d.');
    end
    if base.signature.count ~= checkpoint.storage.c2_zero.count || ...
       base.signature.xor ~= checkpoint.storage.c2_zero.xor || ...
       base.signature.sum ~= checkpoint.storage.c2_zero.A
        error('export_reference_vector_set:legacySignatureMismatch', ...
            'New C2 zero-fill signature disagrees with the reviewed legacy exporter.');
    end
    range_report = report_subband_ranges(base.img, ...
        fullfile(temp_dir, 'subband_ranges.csv'));
    write_readme(fullfile(temp_dir, 'README_reference_vector_set.md'), ...
        rows, cols, coeff_bits, source_label);

    ranges = build_ranges(base.C1, base.C2, LL1, HL1, LH1, HH1, coeffs);
    write_manifest(fullfile(temp_dir, 'reference_manifest.txt'), temp_dir, ...
        rows, cols, coeff_bits, source_label, ranges);

    report = verify_reference_vector_set(temp_dir, base.img);
    [ok, msg] = movefile(temp_dir, out_dir);
    if ~ok
        error('export_reference_vector_set:publishFailed', ...
            'Could not publish verified vector set: %s', msg);
    end
    clear cleaner;

    info = struct();
    info.path = out_dir;
    info.rows = rows;
    info.cols = cols;
    info.coeff_bits = coeff_bits;
    info.source_label = source_label;
    info.ranges = ranges;
    info.subband_ranges = range_report.items;
    info.verified = report.passed;
end

function ranges = build_ranges(C1, C2, LL1, HL1, LH1, HH1, c)
    names = {'c1','c2','ll1','hl1','lh1','hh1','ll2','hl2','lh2','hh2'};
    values = {C1,C2,LL1,HL1,LH1,HH1,c.LL2,c.HL2,c.LH2,c.HH2};
    ranges = struct();
    for i = 1:numel(names)
        ranges.([names{i} '_min']) = double(min(values{i}(:)));
        ranges.([names{i} '_max']) = double(max(values{i}(:)));
    end
end

function write_manifest(path, dir_path, rows, cols, bits, source_label, ranges)
    files = deterministic_files();
    model_names = model_functions();
    fid = fopen(path, 'w');
    if fid < 0
        error('export_reference_vector_set:fileOpen', 'Could not open %s.', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '# Deterministic DWT53 reference-vector manifest\n');
    fprintf(fid, '# manifest.txt from the legacy exporter is intentionally excluded: it contains time/runtime fields.\n');
    fprintf(fid, 'manifest_version = 1\n');
    fprintf(fid, 'source_label = %s\n', safe_label(source_label));
    fprintf(fid, 'rows = %d\n', rows);
    fprintf(fid, 'cols = %d\n', cols);
    fprintf(fid, 'total = %d\n', rows * cols);
    fprintf(fid, 'input_bits = 8\n');
    fprintf(fid, 'coeff_bits = %d\n', bits);
    fprintf(fid, 'serialization = row_major\n');
    fprintf(fid, 'packed_layout = LL_HL__LH_HH\n');
    fprintf(fid, 'lines_input_y8 = %d\n', rows * cols);
    fprintf(fid, 'lines_c1 = %d\n', rows * cols);
    fprintf(fid, 'lines_c2 = %d\n', rows * cols);
    fprintf(fid, 'lines_ll1 = %d\n', rows * cols / 4);
    fprintf(fid, 'lines_recon_y8 = %d\n', rows * cols);
    range_fields = fieldnames(ranges);
    for i = 1:numel(range_fields)
        fprintf(fid, '%s = %d\n', range_fields{i}, ranges.(range_fields{i}));
    end
    for i = 1:numel(files)
        fp = dwt53_file_fingerprint(fullfile(dir_path, files{i}));
        fprintf(fid, '%s = %s\n', fingerprint_key(files{i}), fp.text);
    end
    for i = 1:numel(model_names)
        located = which(model_names{i});
        if isempty(located)
            error('export_reference_vector_set:missingModelFile', ...
                'Required model function not found on MATLAB path: %s', model_names{i});
        end
        fp = dwt53_file_fingerprint(located);
        fprintf(fid, 'model_%s_fingerprint = %s\n', model_names{i}, fp.text);
    end
    clear cleaner;
end

function write_signed_pair(dir_path, stem, values, bits)
    dec_path = fullfile(dir_path, [stem '_dec.txt']);
    hex_path = fullfile(dir_path, [stem '_hex.txt']);
    fid = fopen(dec_path, 'w');
    if fid < 0
        error('export_reference_vector_set:fileOpen', 'Could not open %s.', dec_path);
    end
    fprintf(fid, '%d\n', double(values));
    fclose(fid);
    hex_matrix = int_to_hex_signed(values, bits);
    fid = fopen(hex_path, 'w');
    if fid < 0
        error('export_reference_vector_set:fileOpen', 'Could not open %s.', hex_path);
    end
    records = [hex_matrix, repmat(char(10), size(hex_matrix, 1), 1)].';
    fwrite(fid, records(:), 'char');
    fclose(fid);
end

function write_readme(path, rows, cols, bits, source_label)
    fid = fopen(path, 'w');
    if fid < 0
        error('export_reference_vector_set:fileOpen', 'Could not open %s.', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '# DWT53 2D/two-level reference vector set\n\n');
    fprintf(fid, '- Source: `%s`\n', safe_label(source_label));
    fprintf(fid, '- Shape: %d rows x %d columns\n', rows, cols);
    fprintf(fid, '- Input/reconstruction: unsigned Y8, two HEX digits\n');
    fprintf(fid, '- Coefficients: signed %d-bit two''s complement, %d HEX digits\n', bits, bits/4);
    fprintf(fid, '- Matrix serialization: row-major (`reshape(A.'', [], 1)`)\n');
    fprintf(fid, '- Packed layout: `[LL HL; LH HH]`; level 2 replaces only LL1\n\n');
    fprintf(fid, '## Files\n\n');
    fprintf(fid, '`input_y8_*`, `c1_packed_*`, `c2_packed_*`, `ll1_*`, and `recon_y8_*`\n');
    fprintf(fid, 'are matched DEC/HEX pairs. `reference_manifest.txt` is deterministic and\n');
    fprintf(fid, 'is the artifact-of-record manifest. The legacy `manifest.txt` is retained\n');
    fprintf(fid, 'only for compatibility and contains volatile generation metadata.\n\n');
    fprintf(fid, '`signatures.txt` includes count, XOR, A/sum and order-sensitive B.\n');
    fprintf(fid, '`signature_sweep.csv` covers W={8,13,16} x {zero-fill,sign-extend};\n');
    fprintf(fid, 'unrepresentable configurations are marked OUT_OF_RANGE, never wrapped.\n');
    fprintf(fid, '`subband_ranges.csv` reports every sizing-relevant row stage/subband\n');
    fprintf(fid, 'against the theoretical bounds frozen in system spec Section D.2.\n');
    fprintf(fid, 'B in this set uses packed row-major order; do not\n');
    fprintf(fid, 'compare it with a streaming checkpoint until OI-011 documents a matching\n');
    fprintf(fid, 'emission order. Count/XOR/A remain useful under their stated profile.\n');
    clear cleaner;
end

function files = deterministic_files()
    files = { ...
        'input_y8_dec.txt','input_y8_hex.txt', ...
        'c1_packed_dec.txt','c1_packed_hex.txt', ...
        'c2_packed_dec.txt','c2_packed_hex.txt', ...
        'll1_dec.txt','ll1_hex.txt', ...
        'recon_y8_dec.txt','recon_y8_hex.txt', ...
        'signatures.txt','signature_sweep.csv','subband_ranges.csv', ...
        'README_reference_vector_set.md'};
end

function names = model_functions()
    names = {'dwt53_forward_1d','dwt53_inverse_1d','dwt53_forward_2d', ...
        'dwt53_inverse_2d','dwt53_forward_2level','dwt53_inverse_2level', ...
        'dwt53_pack_2d','dwt53_pack_2level','floor_divide_int', ...
        'int_to_hex_signed','export_packed_planes','dwt53_signature', ...
        'dwt53_signature_sweep','dwt53_signature_sweep_text', ...
        'dwt53_write_signature_sweep','dwt53_verify_signature_sweep_file', ...
        'dwt53_read_dec_vector','dwt53_read_hex_vector', ...
        'dwt53_read_key_value_file','dwt53_file_fingerprint', ...
        'export_checkpoint_signatures','report_subband_ranges', ...
        'export_reference_vector_set','verify_reference_vector_set', ...
        'gen_dwt53_test_frame','gen_test_frame', ...
        'generate_reference_vectors'};
end

function key = fingerprint_key(filename)
    key = ['fingerprint_' lower(regexprep(filename, '[^A-Za-z0-9]+', '_'))];
    key = regexprep(key, '_$', '');
end

function label = safe_label(label)
    label = regexprep(char(label), '[\r\n=]', '_');
end

function remove_temp_dir(path)
    if exist(path, 'dir')
        rmdir(path, 's');
    end
end

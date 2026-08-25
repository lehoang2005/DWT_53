function report = verify_reference_vector_set(set_dir, expected_img)
%VERIFY_REFERENCE_VECTOR_SET  Independent readback of a committed 2D set.
%
%   This function trusts neither the exporter return struct nor one encoding
%   alone. It reads DEC and HEX files from disk, checks widths/counts and
%   fingerprints, recomputes the DWT, checks both round trips and containment,
%   and recomputes every signature.

    manifest_path = fullfile(set_dir, 'reference_manifest.txt');
    signature_path = fullfile(set_dir, 'signatures.txt');
    manifest = dwt53_read_key_value_file(manifest_path);
    sig_file = dwt53_read_key_value_file(signature_path);

    rows = required_integer(manifest, 'rows');
    cols = required_integer(manifest, 'cols');
    total = required_integer(manifest, 'total');
    bits = required_integer(manifest, 'coeff_bits');
    if required_integer(manifest, 'manifest_version') ~= 1 || ...
       required_integer(manifest, 'input_bits') ~= 8
        error('verify_reference_vector_set:badManifestVersion', ...
            'Unsupported manifest version or input width.');
    end
    if total ~= rows * cols || mod(rows, 4) ~= 0 || mod(cols, 4) ~= 0
        error('verify_reference_vector_set:badDimensions', ...
            'Manifest dimensions are inconsistent or not divisible by four.');
    end
    require_text(manifest, 'serialization', 'row_major');
    require_text(manifest, 'packed_layout', 'LL_HL__LH_HH');
    if required_integer(manifest, 'lines_input_y8') ~= total || ...
       required_integer(manifest, 'lines_c1') ~= total || ...
       required_integer(manifest, 'lines_c2') ~= total || ...
       required_integer(manifest, 'lines_ll1') ~= total/4 || ...
       required_integer(manifest, 'lines_recon_y8') ~= total
        error('verify_reference_vector_set:badLineMetadata', ...
            'Manifest line-count metadata is inconsistent.');
    end

    input_dec = dwt53_read_dec_vector(fullfile(set_dir, 'input_y8_dec.txt'), total);
    input_hex = dwt53_read_hex_vector(fullfile(set_dir, 'input_y8_hex.txt'), 8, false, total);
    c1_dec = dwt53_read_dec_vector(fullfile(set_dir, 'c1_packed_dec.txt'), total);
    c1_hex = dwt53_read_hex_vector(fullfile(set_dir, 'c1_packed_hex.txt'), bits, true, total);
    c2_dec = dwt53_read_dec_vector(fullfile(set_dir, 'c2_packed_dec.txt'), total);
    c2_hex = dwt53_read_hex_vector(fullfile(set_dir, 'c2_packed_hex.txt'), bits, true, total);
    ll1_dec = dwt53_read_dec_vector(fullfile(set_dir, 'll1_dec.txt'), total/4);
    ll1_hex = dwt53_read_hex_vector(fullfile(set_dir, 'll1_hex.txt'), bits, true, total/4);
    recon_dec = dwt53_read_dec_vector(fullfile(set_dir, 'recon_y8_dec.txt'), total);
    recon_hex = dwt53_read_hex_vector(fullfile(set_dir, 'recon_y8_hex.txt'), 8, false, total);

    require_equal(input_dec, input_hex, 'input DEC/HEX');
    require_equal(c1_dec, c1_hex, 'C1 DEC/HEX');
    require_equal(c2_dec, c2_hex, 'C2 DEC/HEX');
    require_equal(ll1_dec, ll1_hex, 'LL1 DEC/HEX');
    require_equal(recon_dec, recon_hex, 'reconstruction DEC/HEX');

    img = row_major_matrix(input_dec, rows, cols);
    C1_file = row_major_matrix(c1_dec, rows, cols);
    C2_file = row_major_matrix(c2_dec, rows, cols);
    LL1_file = row_major_matrix(ll1_dec, rows/2, cols/2);
    recon_file = row_major_matrix(recon_dec, rows, cols);
    if any(img(:) < 0) || any(img(:) > 255)
        error('verify_reference_vector_set:notY8', 'Input file is not unsigned Y8.');
    end
    if nargin >= 2 && ~isempty(expected_img)
        require_equal(img, int64(expected_img), 'input versus caller image');
    end

    [LL1, HL1, LH1, HH1] = dwt53_forward_2d(img);
    C1_ref = dwt53_pack_2d(LL1, HL1, LH1, HH1);
    coeffs = dwt53_forward_2level(img);
    C2_ref = dwt53_pack_2level(coeffs);
    recon_l1 = dwt53_inverse_2d(LL1, HL1, LH1, HH1);
    recon_l2 = dwt53_inverse_2level(coeffs);

    require_equal(recon_l1, img, 'one-level round trip');
    require_equal(recon_l2, img, 'two-level round trip');
    require_equal(C1_file, C1_ref, 'C1 versus model');
    require_equal(C2_file, C2_ref, 'C2 versus model');
    require_equal(LL1_file, LL1, 'LL1 versus model');
    require_equal(recon_file, img, 'reconstructed frame versus input');

    half_r = rows/2;
    half_c = cols/2;
    require_equal(C2_file(1:half_r, half_c+1:end), ...
        C1_file(1:half_r, half_c+1:end), 'C2/C1 HL1 containment');
    require_equal(C2_file(half_r+1:end, 1:half_c), ...
        C1_file(half_r+1:end, 1:half_c), 'C2/C1 LH1 containment');
    require_equal(C2_file(half_r+1:end, half_c+1:end), ...
        C1_file(half_r+1:end, half_c+1:end), 'C2/C1 HH1 containment');

    ranges = build_ranges(C1_ref, C2_ref, LL1, HL1, LH1, HH1, coeffs);
    check_range_proof(ranges);
    range_names = fieldnames(ranges);
    for i = 1:numel(range_names)
        key = range_names{i};
        if required_integer(manifest, key) ~= ranges.(key)
            error('verify_reference_vector_set:rangeMismatch', ...
                'Manifest %s does not match recomputed value.', key);
        end
    end

    signatures = build_signatures(img, C1_ref, C2_ref, LL1, recon_l2, bits);
    if required_integer(sig_file, 'signature_version') ~= 1 || ...
       required_integer(sig_file, 'coefficient_bits') ~= bits
        error('verify_reference_vector_set:signatureBits', ...
            'Signature and vector-set coefficient widths differ.');
    end
    require_text(sig_file, 'b_reference_order', 'row_major_stored_plane');
    compare_sig(sig_file, 'input_y8_w8_zero', signatures.input_zero);
    compare_sig(sig_file, sprintf('c1_w%d_zero', bits), signatures.c1_zero);
    compare_sig(sig_file, sprintf('c1_w%d_sign', bits), signatures.c1_sign);
    compare_sig(sig_file, sprintf('c2_w%d_zero', bits), signatures.c2_zero);
    compare_sig(sig_file, sprintf('c2_w%d_sign', bits), signatures.c2_sign);
    compare_sig(sig_file, sprintf('ll1_w%d_zero', bits), signatures.ll1_zero);
    compare_sig(sig_file, sprintf('ll1_w%d_sign', bits), signatures.ll1_sign);
    compare_sig(sig_file, 'recon_y8_w8_zero', signatures.recon_zero);
    streams = build_sweep_streams(img, C1_ref, C2_ref, LL1, recon_l2);
    dwt53_verify_signature_sweep_file(fullfile(set_dir, 'signature_sweep.csv'), ...
        streams, [8 13 16]);
    range_report = report_subband_ranges(img);
    range_file_text = fileread(fullfile(set_dir, 'subband_ranges.csv'));
    range_file_text(range_file_text == char(13)) = [];
    expected_range_text = range_report.csv_text;
    expected_range_text(expected_range_text == char(13)) = [];
    if ~strcmp(range_file_text, expected_range_text)
        error('verify_reference_vector_set:subbandRangeFileMismatch', ...
            'subband_ranges.csv does not match recomputed stage ranges.');
    end

    files = deterministic_files();
    for i = 1:numel(files)
        key = fingerprint_key(files{i});
        require_field(manifest, key);
        fp = dwt53_file_fingerprint(fullfile(set_dir, files{i}));
        if ~strcmp(manifest.(key), fp.text)
            error('verify_reference_vector_set:fingerprintMismatch', ...
                'Fingerprint mismatch for %s.', files{i});
        end
    end
    model_names = model_functions();
    for i = 1:numel(model_names)
        key = ['model_' model_names{i} '_fingerprint'];
        require_field(manifest, key);
        located = which(model_names{i});
        if isempty(located)
            error('verify_reference_vector_set:missingModelFile', ...
                'Required model function not found: %s', model_names{i});
        end
        fp = dwt53_file_fingerprint(located);
        if ~strcmp(manifest.(key), fp.text)
            error('verify_reference_vector_set:modelFingerprintMismatch', ...
                'Golden-model source changed after vector generation: %s.m', model_names{i});
        end
    end

    report = struct();
    report.passed = true;
    report.rows = rows;
    report.cols = cols;
    report.coeff_bits = bits;
    report.ranges = ranges;
    report.subband_ranges = range_report.items;
    report.message = 'DEC/HEX/readback/model/signature/fingerprint checks PASS';
end

function streams = build_sweep_streams(img, C1, C2, LL1, recon)
    template = struct('name','','values',[],'sample_format','','order','row-major');
    streams = repmat(template, 5, 1);
    streams(1).name = 'input_y8';
    streams(1).values = reshape(int64(img).', [], 1);
    streams(1).sample_format = 'unsigned';
    streams(2).name = 'c1';
    streams(2).values = reshape(int64(C1).', [], 1);
    streams(2).sample_format = 'signed';
    streams(3).name = 'c2';
    streams(3).values = reshape(int64(C2).', [], 1);
    streams(3).sample_format = 'signed';
    streams(4).name = 'll1';
    streams(4).values = reshape(int64(LL1).', [], 1);
    streams(4).sample_format = 'signed';
    streams(5).name = 'recon_y8';
    streams(5).values = reshape(int64(recon).', [], 1);
    streams(5).sample_format = 'unsigned';
end

function signatures = build_signatures(img, C1, C2, LL1, recon, bits)
    signatures = struct();
    signatures.input_zero = dwt53_signature(reshape(int64(img).', [], 1), ...
        8, 'unsigned', 'zero-fill', 'row-major');
    signatures.c1_zero = dwt53_signature(reshape(int64(C1).', [], 1), ...
        bits, 'signed', 'zero-fill', 'row-major');
    signatures.c1_sign = dwt53_signature(reshape(int64(C1).', [], 1), ...
        bits, 'signed', 'sign-extend', 'row-major');
    signatures.c2_zero = dwt53_signature(reshape(int64(C2).', [], 1), ...
        bits, 'signed', 'zero-fill', 'row-major');
    signatures.c2_sign = dwt53_signature(reshape(int64(C2).', [], 1), ...
        bits, 'signed', 'sign-extend', 'row-major');
    signatures.ll1_zero = dwt53_signature(reshape(int64(LL1).', [], 1), ...
        bits, 'signed', 'zero-fill', 'row-major');
    signatures.ll1_sign = dwt53_signature(reshape(int64(LL1).', [], 1), ...
        bits, 'signed', 'sign-extend', 'row-major');
    signatures.recon_zero = dwt53_signature(reshape(int64(recon).', [], 1), ...
        8, 'unsigned', 'zero-fill', 'row-major');
end

function compare_sig(kv, prefix, expected)
    prefix = lower(prefix);
    if required_integer(kv, [prefix '_count']) ~= expected.count
        error('verify_reference_vector_set:signatureMismatch', ...
            '%s count mismatch.', prefix);
    end
    compare_hex(kv, [prefix '_xor'], expected.xor);
    compare_hex(kv, [prefix '_a'], expected.A);
    compare_hex(kv, [prefix '_sum'], expected.A);
    compare_hex(kv, [prefix '_b'], expected.B);
end

function compare_hex(kv, key, expected)
    require_field(kv, key);
    value = kv.(key);
    if isempty(regexp(value, '^[0-9A-Fa-f]{8}$', 'once')) || hex2dec(value) ~= expected
        error('verify_reference_vector_set:signatureMismatch', ...
            '%s mismatch.', key);
    end
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

function check_range_proof(r)
    assert_bounded(r.ll1_min, r.ll1_max, -382, 638, 'LL1');
    assert_bounded(r.hl1_min, r.hl1_max, -510, 510, 'HL1');
    assert_bounded(r.lh1_min, r.lh1_max, -510, 510, 'LH1');
    assert_bounded(r.hh1_min, r.hh1_max, -510, 510, 'HH1');
    assert_bounded(r.ll2_min, r.ll2_max, -1912, 2168, 'LL2');
    assert_bounded(r.hl2_min, r.hl2_max, -2040, 2040, 'HL2');
    assert_bounded(r.lh2_min, r.lh2_max, -2040, 2040, 'LH2');
    assert_bounded(r.hh2_min, r.hh2_max, -2040, 2040, 'HH2');
end

function assert_bounded(observed_min, observed_max, allowed_min, allowed_max, name)
    if observed_min < allowed_min || observed_max > allowed_max
        error('verify_reference_vector_set:proofBoundExceeded', ...
            '%s observed [%d,%d] exceeds proof bound [%d,%d].', ...
            name, observed_min, observed_max, allowed_min, allowed_max);
    end
end

function matrix = row_major_matrix(vector, rows, cols)
    matrix = reshape(int64(vector), cols, rows).';
end

function require_equal(actual, expected, label)
    if ~isequal(int64(actual), int64(expected))
        if numel(actual) ~= numel(expected)
            detail = sprintf('different element counts: %d versus %d', ...
                numel(actual), numel(expected));
        else
            delta = max(abs(double(int64(actual(:))) - double(int64(expected(:)))));
            detail = sprintf('max absolute difference %g', delta);
        end
        error('verify_reference_vector_set:dataMismatch', ...
            '%s mismatch (%s).', label, detail);
    end
end

function value = required_integer(kv, key)
    require_field(kv, key);
    value = str2double(kv.(lower(key)));
    if ~isfinite(value) || mod(value, 1) ~= 0
        error('verify_reference_vector_set:badMetadataInteger', ...
            'Metadata key %s is not an integer.', key);
    end
end

function require_text(kv, key, expected)
    require_field(kv, key);
    if ~strcmp(kv.(lower(key)), expected)
        error('verify_reference_vector_set:badMetadataText', ...
            'Metadata key %s must equal %s.', key, expected);
    end
end

function require_field(kv, key)
    key = lower(key);
    if ~isfield(kv, key)
        error('verify_reference_vector_set:missingMetadata', ...
            'Missing metadata key: %s', key);
    end
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

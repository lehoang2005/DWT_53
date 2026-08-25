function report = verify_reference_vector_1d_set(set_dir, expected_x)
%VERIFY_REFERENCE_VECTOR_1D_SET  Strict independent readback of a 1D set.

    manifest = dwt53_read_key_value_file(fullfile(set_dir, 'reference_manifest.txt'));
    sig_file = dwt53_read_key_value_file(fullfile(set_dir, 'signatures.txt'));
    input_length = required_integer(manifest, 'input_length');
    l_length = required_integer(manifest, 'l_length');
    h_length = required_integer(manifest, 'h_length');
    input_bits = required_integer(manifest, 'input_bits');
    coeff_bits = required_integer(manifest, 'coeff_bits');
    if required_integer(manifest, 'manifest_version') ~= 1
        error('verify_reference_vector_1d_set:badManifestVersion', ...
            'Unsupported manifest version.');
    end
    require_text(manifest, 'serialization', 'plain_vector');
    require_field(manifest, 'input_format');
    input_format = manifest.input_format;
    if input_length < 2 || mod(input_length, 2) ~= 0 || ...
       l_length ~= input_length/2 || h_length ~= input_length/2
        error('verify_reference_vector_1d_set:badLengths', ...
            'Manifest lengths are inconsistent.');
    end
    if strcmp(input_format, 'unsigned_y8')
        input_is_signed = false;
        if input_bits ~= 8
            error('verify_reference_vector_1d_set:badY8Width', ...
                'unsigned_y8 input must use eight bits.');
        end
    elseif strcmp(input_format, 'signed')
        input_is_signed = true;
    else
        error('verify_reference_vector_1d_set:badInputFormat', ...
            'Unknown input_format: %s', input_format);
    end

    x_dec = dwt53_read_dec_vector(fullfile(set_dir, 'input_dec.txt'), input_length);
    x_hex = dwt53_read_hex_vector(fullfile(set_dir, 'input_hex.txt'), ...
        input_bits, input_is_signed, input_length);
    L_dec = dwt53_read_dec_vector(fullfile(set_dir, 'L_dec.txt'), l_length);
    L_hex = dwt53_read_hex_vector(fullfile(set_dir, 'L_hex.txt'), ...
        coeff_bits, true, l_length);
    H_dec = dwt53_read_dec_vector(fullfile(set_dir, 'H_dec.txt'), h_length);
    H_hex = dwt53_read_hex_vector(fullfile(set_dir, 'H_hex.txt'), ...
        coeff_bits, true, h_length);
    require_equal(x_dec, x_hex, 'input DEC/HEX');
    require_equal(L_dec, L_hex, 'L DEC/HEX');
    require_equal(H_dec, H_hex, 'H DEC/HEX');
    if ~input_is_signed && (any(x_dec < 0) || any(x_dec > 255))
        error('verify_reference_vector_1d_set:notY8', 'Y8 input is outside [0,255].');
    end
    if nargin >= 2 && ~isempty(expected_x)
        require_equal(x_dec, int64(expected_x(:)), 'input versus caller vector');
    end

    [L_ref, H_ref] = dwt53_forward_1d(x_dec);
    require_equal(L_dec, L_ref(:), 'L versus model');
    require_equal(H_dec, H_ref(:), 'H versus model');
    reconstructed = dwt53_inverse_1d(L_ref, H_ref);
    require_equal(reconstructed(:), x_dec, '1D round trip');

    compare_integer(manifest, 'input_min', min(x_dec));
    compare_integer(manifest, 'input_max', max(x_dec));
    compare_integer(manifest, 'l_min', min(L_dec));
    compare_integer(manifest, 'l_max', max(L_dec));
    compare_integer(manifest, 'h_min', min(H_dec));
    compare_integer(manifest, 'h_max', max(H_dec));

    require_text(sig_file, 'b_reference_order', 'plain_vector');
    if required_integer(sig_file, 'signature_version') ~= 1 || ...
       required_integer(sig_file, 'input_bits') ~= input_bits || ...
       required_integer(sig_file, 'coeff_bits') ~= coeff_bits
        error('verify_reference_vector_1d_set:signatureBits', ...
            'Signature and vector widths differ.');
    end
    if input_is_signed
        input_zero = dwt53_signature(x_dec, input_bits, 'signed', ...
            'zero-fill', 'plain-vector');
        input_sign = dwt53_signature(x_dec, input_bits, 'signed', ...
            'sign-extend', 'plain-vector');
    else
        input_zero = dwt53_signature(x_dec, input_bits, 'unsigned', ...
            'zero-fill', 'plain-vector');
        input_sign = [];
    end
    L_zero = dwt53_signature(L_dec, coeff_bits, 'signed', 'zero-fill', 'plain-vector');
    L_sign = dwt53_signature(L_dec, coeff_bits, 'signed', 'sign-extend', 'plain-vector');
    H_zero = dwt53_signature(H_dec, coeff_bits, 'signed', 'zero-fill', 'plain-vector');
    H_sign = dwt53_signature(H_dec, coeff_bits, 'signed', 'sign-extend', 'plain-vector');
    compare_sig(sig_file, sprintf('input_w%d_zero', input_bits), input_zero);
    if ~isempty(input_sign)
        compare_sig(sig_file, sprintf('input_w%d_sign', input_bits), input_sign);
    end
    compare_sig(sig_file, sprintf('l_w%d_zero', coeff_bits), L_zero);
    compare_sig(sig_file, sprintf('l_w%d_sign', coeff_bits), L_sign);
    compare_sig(sig_file, sprintf('h_w%d_zero', coeff_bits), H_zero);
    compare_sig(sig_file, sprintf('h_w%d_sign', coeff_bits), H_sign);

    files = deterministic_files();
    for i = 1:numel(files)
        key = fingerprint_key(files{i});
        require_field(manifest, key);
        fp = dwt53_file_fingerprint(fullfile(set_dir, files{i}));
        if ~strcmp(manifest.(key), fp.text)
            error('verify_reference_vector_1d_set:fingerprintMismatch', ...
                'Fingerprint mismatch for %s.', files{i});
        end
    end
    model_names = model_functions();
    for i = 1:numel(model_names)
        key = ['model_' model_names{i} '_fingerprint'];
        require_field(manifest, key);
        located = which(model_names{i});
        if isempty(located)
            error('verify_reference_vector_1d_set:missingModelFile', ...
                'Required model function not found: %s', model_names{i});
        end
        fp = dwt53_file_fingerprint(located);
        if ~strcmp(manifest.(key), fp.text)
            error('verify_reference_vector_1d_set:modelFingerprintMismatch', ...
                'Golden-model source changed after vector generation: %s.m', model_names{i});
        end
    end

    report = struct();
    report.passed = true;
    report.input_length = input_length;
    report.coeff_bits = coeff_bits;
    report.input_bits = input_bits;
    report.message = 'DEC/HEX/readback/model/signature/fingerprint checks PASS';
end

function compare_sig(kv, prefix, expected)
    prefix = lower(prefix);
    if required_integer(kv, [prefix '_count']) ~= expected.count
        error('verify_reference_vector_1d_set:signatureMismatch', ...
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
        error('verify_reference_vector_1d_set:signatureMismatch', '%s mismatch.', key);
    end
end

function compare_integer(kv, key, expected)
    if required_integer(kv, key) ~= double(expected)
        error('verify_reference_vector_1d_set:metadataMismatch', ...
            '%s does not match recomputed value.', key);
    end
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
        error('verify_reference_vector_1d_set:dataMismatch', ...
            '%s mismatch (%s).', label, detail);
    end
end

function value = required_integer(kv, key)
    require_field(kv, key);
    value = str2double(kv.(lower(key)));
    if ~isfinite(value) || mod(value, 1) ~= 0
        error('verify_reference_vector_1d_set:badMetadataInteger', ...
            'Metadata key %s is not an integer.', key);
    end
end

function require_text(kv, key, expected)
    require_field(kv, key);
    if ~strcmp(kv.(lower(key)), expected)
        error('verify_reference_vector_1d_set:badMetadataText', ...
            'Metadata key %s must equal %s.', key, expected);
    end
end

function require_field(kv, key)
    key = lower(key);
    if ~isfield(kv, key)
        error('verify_reference_vector_1d_set:missingMetadata', ...
            'Missing metadata key: %s', key);
    end
end

function files = deterministic_files()
    files = {'input_dec.txt','input_hex.txt','L_dec.txt','L_hex.txt', ...
        'H_dec.txt','H_hex.txt','signatures.txt','README_reference_vector_1d_set.md'};
end

function names = model_functions()
    names = {'dwt53_forward_1d','dwt53_inverse_1d','floor_divide_int', ...
        'int_to_hex_signed','export_golden_vectors_1d','dwt53_signature', ...
        'dwt53_read_dec_vector','dwt53_read_hex_vector', ...
        'dwt53_read_key_value_file','dwt53_file_fingerprint', ...
        'export_reference_vector_1d_set','verify_reference_vector_1d_set', ...
        'generate_reference_vectors_1d'};
end

function key = fingerprint_key(filename)
    key = ['fingerprint_' lower(regexprep(filename, '[^A-Za-z0-9]+', '_'))];
    key = regexprep(key, '_$', '');
end

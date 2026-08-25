function info = export_reference_vector_1d_set(x, out_dir, coeff_bits, input_bits, source_label)
%EXPORT_REFERENCE_VECTOR_1D_SET  Verified wrapper for the reviewed 1D exporter.
%
%   For raw-pixel bring-up use coeff_bits=16 and input_bits=8. The input HEX
%   file is then unsigned two-digit Y8, while L/H remain signed 16-bit.

    if nargin < 3 || isempty(coeff_bits)
        coeff_bits = 16;
    end
    if nargin < 4 || isempty(input_bits)
        input_bits = 8;
    end
    if nargin < 5 || isempty(source_label)
        source_label = 'caller_supplied_1d';
    end
    validateattributes(coeff_bits, {'numeric'}, ...
        {'scalar','positive','integer','<=',32}, mfilename, 'coeff_bits');
    validateattributes(input_bits, {'numeric'}, ...
        {'scalar','positive','integer','<=',32}, mfilename, 'input_bits');
    if mod(coeff_bits, 4) ~= 0 || mod(input_bits, 4) ~= 0
        error('export_reference_vector_1d_set:badBits', ...
            'coeff_bits and input_bits must be multiples of four.');
    end
    if isempty(out_dir)
        error('export_reference_vector_1d_set:badOutDir', 'out_dir must not be empty.');
    end
    out_dir = char(out_dir);
    if exist(out_dir, 'file') || exist(out_dir, 'dir')
        error('export_reference_vector_1d_set:outputExists', ...
            'Refusing to mix generations: output already exists: %s', out_dir);
    end
    parent = fileparts(out_dir);
    if isempty(parent)
        parent = pwd;
    end
    if ~exist(parent, 'dir')
        [ok, msg] = mkdir(parent);
        if ~ok
            error('export_reference_vector_1d_set:mkdirFailed', '%s', msg);
        end
    end
    temp_dir = tempname(parent);
    [ok, msg] = mkdir(temp_dir);
    if ~ok
        error('export_reference_vector_1d_set:mkdirFailed', '%s', msg);
    end
    cleaner = onCleanup(@() remove_temp_dir(temp_dir));

    base = export_golden_vectors_1d(x, temp_dir, coeff_bits, input_bits);
    legacy_readme = fullfile(temp_dir, 'README_golden_vectors_1d.md');
    if exist(legacy_readme, 'file')
        % Its legacy wording says all streams have coeff_bits width, which is
        % not true in the input_bits=8 Y8 mode. Keep the exporter frozen and
        % make this wrapper's accurate README the only README in the set.
        delete(legacy_readme);
    end

    if input_bits == 8
        input_format = 'unsigned_y8';
        input_zero = dwt53_signature(base.x, 8, 'unsigned', 'zero-fill', 'plain-vector');
        input_sign = [];
    else
        input_format = 'signed';
        input_zero = dwt53_signature(base.x, input_bits, 'signed', 'zero-fill', 'plain-vector');
        input_sign = dwt53_signature(base.x, input_bits, 'signed', 'sign-extend', 'plain-vector');
    end
    L_zero = dwt53_signature(base.L, coeff_bits, 'signed', 'zero-fill', 'plain-vector');
    L_sign = dwt53_signature(base.L, coeff_bits, 'signed', 'sign-extend', 'plain-vector');
    H_zero = dwt53_signature(base.H, coeff_bits, 'signed', 'zero-fill', 'plain-vector');
    H_sign = dwt53_signature(base.H, coeff_bits, 'signed', 'sign-extend', 'plain-vector');

    write_signatures(fullfile(temp_dir, 'signatures.txt'), input_zero, input_sign, ...
        L_zero, L_sign, H_zero, H_sign, input_bits, coeff_bits, input_format);
    write_readme(fullfile(temp_dir, 'README_reference_vector_1d_set.md'), ...
        base.dims, coeff_bits, input_bits, input_format, source_label);
    write_manifest(fullfile(temp_dir, 'reference_manifest.txt'), temp_dir, ...
        base, coeff_bits, input_bits, input_format, source_label);

    report = verify_reference_vector_1d_set(temp_dir, base.x);
    [ok, msg] = movefile(temp_dir, out_dir);
    if ~ok
        error('export_reference_vector_1d_set:publishFailed', '%s', msg);
    end
    clear cleaner;

    info = struct();
    info.path = out_dir;
    info.input_length = base.dims.x;
    info.subband_length = base.dims.L;
    info.coeff_bits = coeff_bits;
    info.input_bits = input_bits;
    info.input_format = input_format;
    info.source_label = char(source_label);
    info.verified = report.passed;
end

function write_signatures(path, input_zero, input_sign, L_zero, L_sign, ...
        H_zero, H_sign, input_bits, coeff_bits, input_format)
    fid = fopen(path, 'w');
    if fid < 0
        error('export_reference_vector_1d_set:fileOpen', 'Could not open %s.', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '# DWT53 1D reference signatures\n');
    fprintf(fid, 'signature_version = 1\n');
    fprintf(fid, 'b_reference_order = plain_vector\n');
    fprintf(fid, 'input_bits = %d\n', input_bits);
    fprintf(fid, 'coeff_bits = %d\n', coeff_bits);
    fprintf(fid, 'input_format = %s\n', input_format);
    write_sig(fid, sprintf('input_w%d_zero', input_bits), input_zero);
    if ~isempty(input_sign)
        write_sig(fid, sprintf('input_w%d_sign', input_bits), input_sign);
    end
    write_sig(fid, sprintf('l_w%d_zero', coeff_bits), L_zero);
    write_sig(fid, sprintf('l_w%d_sign', coeff_bits), L_sign);
    write_sig(fid, sprintf('h_w%d_zero', coeff_bits), H_zero);
    write_sig(fid, sprintf('h_w%d_sign', coeff_bits), H_sign);
    clear cleaner;
end

function write_sig(fid, prefix, sig)
    fprintf(fid, '%s_count = %d\n', prefix, sig.count);
    fprintf(fid, '%s_xor = %08X\n', prefix, sig.xor);
    fprintf(fid, '%s_a = %08X\n', prefix, sig.A);
    fprintf(fid, '%s_sum = %08X\n', prefix, sig.A);
    fprintf(fid, '%s_b = %08X\n', prefix, sig.B);
end

function write_readme(path, dims, coeff_bits, input_bits, input_format, source_label)
    fid = fopen(path, 'w');
    if fid < 0
        error('export_reference_vector_1d_set:fileOpen', 'Could not open %s.', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '# DWT53 1D reference vector set\n\n');
    fprintf(fid, '- Source: `%s`\n', safe_label(source_label));
    fprintf(fid, '- Input length: %d; L/H length: %d each\n', dims.x, dims.L);
    fprintf(fid, '- Vector order: index zero first\n');
    if strcmp(input_format, 'unsigned_y8')
        fprintf(fid, '- Input: unsigned Y8, %d bits, %d HEX digits\n', input_bits, input_bits/4);
    else
        fprintf(fid, '- Input: signed two''s complement, %d bits, %d HEX digits\n', input_bits, input_bits/4);
    end
    fprintf(fid, '- L/H: signed two''s complement, %d bits, %d HEX digits\n\n', ...
        coeff_bits, coeff_bits/4);
    fprintf(fid, 'Matched DEC/HEX files are independently read back before publication.\n');
    fprintf(fid, '`reference_manifest.txt` contains deterministic artifact and source\n');
    fprintf(fid, 'fingerprints. `signatures.txt` includes count, XOR, A/sum and B.\n');
    clear cleaner;
end

function write_manifest(path, dir_path, base, coeff_bits, input_bits, input_format, source_label)
    files = deterministic_files();
    model_names = model_functions();
    fid = fopen(path, 'w');
    if fid < 0
        error('export_reference_vector_1d_set:fileOpen', 'Could not open %s.', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '# Deterministic DWT53 1D reference-vector manifest\n');
    fprintf(fid, 'manifest_version = 1\n');
    fprintf(fid, 'source_label = %s\n', safe_label(source_label));
    fprintf(fid, 'input_length = %d\n', base.dims.x);
    fprintf(fid, 'l_length = %d\n', base.dims.L);
    fprintf(fid, 'h_length = %d\n', base.dims.H);
    fprintf(fid, 'input_bits = %d\n', input_bits);
    fprintf(fid, 'coeff_bits = %d\n', coeff_bits);
    fprintf(fid, 'input_format = %s\n', input_format);
    fprintf(fid, 'serialization = plain_vector\n');
    fprintf(fid, 'input_min = %d\n', double(min(base.x)));
    fprintf(fid, 'input_max = %d\n', double(max(base.x)));
    fprintf(fid, 'l_min = %d\n', double(min(base.L)));
    fprintf(fid, 'l_max = %d\n', double(max(base.L)));
    fprintf(fid, 'h_min = %d\n', double(min(base.H)));
    fprintf(fid, 'h_max = %d\n', double(max(base.H)));
    for i = 1:numel(files)
        fp = dwt53_file_fingerprint(fullfile(dir_path, files{i}));
        fprintf(fid, '%s = %s\n', fingerprint_key(files{i}), fp.text);
    end
    for i = 1:numel(model_names)
        located = which(model_names{i});
        if isempty(located)
            error('export_reference_vector_1d_set:missingModelFile', ...
                'Required model function not found: %s', model_names{i});
        end
        fp = dwt53_file_fingerprint(located);
        fprintf(fid, 'model_%s_fingerprint = %s\n', model_names{i}, fp.text);
    end
    clear cleaner;
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

function label = safe_label(label)
    label = regexprep(char(label), '[\r\n=]', '_');
end

function remove_temp_dir(path)
    if exist(path, 'dir')
        rmdir(path, 's');
    end
end

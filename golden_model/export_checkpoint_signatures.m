function result = export_checkpoint_signatures(packed_info, out_dir, coeff_bits)
%EXPORT_CHECKPOINT_SIGNATURES  Emit all GLD-009/012/014 reference signatures.
%
%   RESULT = EXPORT_CHECKPOINT_SIGNATURES(PACKED_INFO, OUT_DIR, COEFF_BITS)
%   accepts the struct returned by export_packed_planes.m and writes:
%       signatures.txt       concise storage-width profiles
%       signature_sweep.csv  W={8,13,16} x extension-rule sweep
%
%   LL1 is extracted from C1's top-left quadrant. No lifting arithmetic is
%   duplicated or rerun in this function.

    required = {'img','C1','C2','recon','dims'};
    for i = 1:numel(required)
        if ~isfield(packed_info, required{i})
            error('export_checkpoint_signatures:missingField', ...
                'packed_info is missing field %s.', required{i});
        end
    end
    if nargin < 3 || isempty(coeff_bits)
        if isfield(packed_info, 'coeff_bits')
            coeff_bits = packed_info.coeff_bits;
        else
            coeff_bits = 16;
        end
    end
    validateattributes(coeff_bits, {'numeric'}, ...
        {'scalar','positive','integer','<=',32}, mfilename, 'coeff_bits');
    if mod(coeff_bits, 4) ~= 0
        error('export_checkpoint_signatures:badBits', ...
            'coeff_bits must be a multiple of four.');
    end
    if ~exist(out_dir, 'dir')
        [ok, msg] = mkdir(out_dir);
        if ~ok
            error('export_checkpoint_signatures:mkdirFailed', '%s', msg);
        end
    end

    rows = packed_info.dims.rows;
    cols = packed_info.dims.cols;
    if ~isequal(size(packed_info.C1), [rows, cols]) || ...
       ~isequal(size(packed_info.C2), [rows, cols]) || ...
       ~isequal(size(packed_info.img), [rows, cols]) || ...
       ~isequal(size(packed_info.recon), [rows, cols])
        error('export_checkpoint_signatures:shapeMismatch', ...
            'packed_info matrices do not match packed_info.dims.');
    end
    LL1 = int64(packed_info.C1(1:rows/2, 1:cols/2));

    signatures = build_storage_signatures(packed_info.img, packed_info.C1, ...
        packed_info.C2, LL1, packed_info.recon, coeff_bits);
    signature_path = fullfile(out_dir, 'signatures.txt');
    write_storage_signatures(signature_path, signatures, coeff_bits);

    streams = build_sweep_streams(packed_info.img, packed_info.C1, ...
        packed_info.C2, LL1, packed_info.recon);
    sweep_path = fullfile(out_dir, 'signature_sweep.csv');
    sweep_entries = dwt53_write_signature_sweep(sweep_path, streams, [8 13 16]);

    result = struct();
    result.LL1 = LL1;
    result.storage = signatures;
    result.sweep = sweep_entries;
    result.files = struct('signatures', signature_path, 'sweep', sweep_path);
end

function signatures = build_storage_signatures(img, C1, C2, LL1, recon, bits)
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

function write_storage_signatures(path, s, bits)
    fid = fopen(path, 'w');
    if fid < 0
        error('export_checkpoint_signatures:fileOpen', 'Could not open %s.', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '# DWT53 checkpoint reference signatures\n');
    fprintf(fid, '# A equals the existing RTL sum_acc under zero-fill.\n');
    fprintf(fid, '# B uses post-update A and is order-sensitive.\n');
    fprintf(fid, 'signature_version = 1\n');
    fprintf(fid, 'b_reference_order = row_major_stored_plane\n');
    fprintf(fid, 'coefficient_bits = %d\n', bits);
    write_sig(fid, 'input_y8_w8_zero', s.input_zero);
    write_sig(fid, sprintf('c1_w%d_zero', bits), s.c1_zero);
    write_sig(fid, sprintf('c1_w%d_sign', bits), s.c1_sign);
    write_sig(fid, sprintf('c2_w%d_zero', bits), s.c2_zero);
    write_sig(fid, sprintf('c2_w%d_sign', bits), s.c2_sign);
    write_sig(fid, sprintf('ll1_w%d_zero', bits), s.ll1_zero);
    write_sig(fid, sprintf('ll1_w%d_sign', bits), s.ll1_sign);
    write_sig(fid, 'recon_y8_w8_zero', s.recon_zero);
    clear cleaner;
end

function write_sig(fid, prefix, sig)
    fprintf(fid, '%s_count = %d\n', prefix, sig.count);
    fprintf(fid, '%s_xor = %08X\n', prefix, sig.xor);
    fprintf(fid, '%s_a = %08X\n', prefix, sig.A);
    fprintf(fid, '%s_sum = %08X\n', prefix, sig.A);
    fprintf(fid, '%s_b = %08X\n', prefix, sig.B);
end

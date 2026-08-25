function generated = generate_reference_vectors_1d(output_root)
%GENERATE_REFERENCE_VECTORS_1D  Generate canonical and stress 1D vector sets.

    model_root = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(output_root)
        output_root = fullfile(model_root, 'golden_vectors', 'reference', '1d');
    end
    if ~exist(output_root, 'dir')
        [ok, msg] = mkdir(output_root);
        if ~ok
            error('generate_reference_vectors_1d:mkdirFailed', '%s', msg);
        end
    end

    plans = { ...
        'canonical_nominal_n0008', int64([10 20 30 40 50 60 70 80]), ...
            'algorithm_spec_v0_1_section_10_1'; ...
        'canonical_negative_rounding_n0008', int64([0 0 10 0 20 0 30 0]), ...
            'algorithm_spec_v0_1_section_10_2'; ...
        'canonical_edge_0_255_n0002', int64([0 255]), ...
            'algorithm_spec_v0_1_section_10_3_a'; ...
        'canonical_edge_255_0_n0002', int64([255 0]), ...
            'algorithm_spec_v0_1_section_10_3_b'; ...
        'deterministic_row_n0256', int64(gen_test_frame(4, 256)), ...
            'DWT53_TEST_FRAME_V1_first_row_n256'};
    % The final plan stores a 4x256 frame only to reuse the exact test-frame
    % rule; export its first raster row as the 1D input vector.
    plans{end, 2} = plans{end, 2}(1, :);

    generated = cell(size(plans, 1), 1);
    for i = 1:size(plans, 1)
        generated{i} = create_or_verify_set(plans{i, 2}, ...
            fullfile(output_root, plans{i, 1}), plans{i, 3});
    end
    fprintf('Created/reused and independently verified %d 1D reference vector set(s) in:\n%s\n', ...
        numel(generated), output_root);
end

function info = create_or_verify_set(x, set_dir, source_label)
    if exist(set_dir, 'dir')
        report = verify_reference_vector_1d_set(set_dir, x);
        info = struct();
        info.path = set_dir;
        info.input_length = report.input_length;
        info.subband_length = report.input_length / 2;
        info.coeff_bits = report.coeff_bits;
        info.input_bits = report.input_bits;
        info.input_format = 'unsigned_y8';
        info.source_label = source_label;
        info.verified = report.passed;
        info.reused = true;
    elseif exist(set_dir, 'file')
        error('generate_reference_vectors_1d:pathCollision', ...
            'A non-directory object already exists at %s.', set_dir);
    else
        info = export_reference_vector_1d_set(x, set_dir, 16, 8, source_label);
        info.reused = false;
    end
end

function generated = generate_reference_vectors(output_root, include_full_size, natural_frame_path)
%GENERATE_REFERENCE_VECTORS  Generate the reproducible 2D reference-set matrix.
%
%   generate_reference_vectors() writes under:
%       <this file>/golden_vectors/reference/2d
%
%   The default suite is intentionally small enough for routine regression.
%   Set INCLUDE_FULL_SIZE=true to add the deterministic 1280x720 frame.
%   NATURAL_FRAME_PATH may name an already-grayscale 1280x720 Y8 image.
%   Existing sets are never overwritten: each is fully verified against the
%   current source and expected input, then reused. Only missing sets are made.

    model_root = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(output_root)
        output_root = fullfile(model_root, 'golden_vectors', 'reference', '2d');
    end
    if nargin < 2 || isempty(include_full_size)
        include_full_size = false;
    end
    if nargin < 3
        natural_frame_path = '';
    end
    validateattributes(include_full_size, {'logical','numeric'}, ...
        {'scalar'}, mfilename, 'include_full_size');
    include_full_size = logical(include_full_size);
    if ~exist(output_root, 'dir')
        [ok, msg] = mkdir(output_root);
        if ~ok
            error('generate_reference_vectors:mkdirFailed', '%s', msg);
        end
    end

    plans = { ...
        'canonical_w0004_h0004', 4, 4, 'canonical'; ...
        'deterministic_w0008_h0008', 8, 8, 'deterministic'; ...
        'deterministic_w0012_h0008', 8, 12, 'deterministic'; ...
        'deterministic_w0008_h0012', 12, 8, 'deterministic'; ...
        'deterministic_w0016_h0016', 16, 16, 'deterministic'; ...
        'deterministic_w0064_h0064', 64, 64, 'deterministic'};
    if include_full_size
        plans(end+1, :) = {'deterministic_w1280_h0720', 720, 1280, 'deterministic'};
    end

    generated = cell(0, 1);
    for i = 1:size(plans, 1)
        name = plans{i, 1};
        rows = plans{i, 2};
        cols = plans{i, 3};
        kind = plans{i, 4};
        if strcmp(kind, 'canonical')
            img = int64(reshape(0:rows*cols-1, cols, rows).');
            label = 'algorithm_spec_v0_1_section_10_4';
        else
            img = gen_test_frame(rows, cols);
            label = sprintf('DWT53_TEST_FRAME_V1_w%d_h%d', cols, rows);
        end
        generated{end+1, 1} = create_or_verify_set( ...
            img, fullfile(output_root, name), label); %#ok<AGROW>
    end

    if ~isempty(natural_frame_path)
        img = imread(natural_frame_path);
        if ndims(img) ~= 2
            error('generate_reference_vectors:notGrayscale', ...
                ['Natural reference must already be a single-channel grayscale ' ...
                 'image; RGB-to-Y conversion is intentionally not guessed.']);
        end
        if ~isequal(size(img), [720, 1280])
            error('generate_reference_vectors:wrongNaturalSize', ...
                'Natural reference must be 1280x720 (got %dx%d).', size(img,2), size(img,1));
        end
        if any(~isfinite(double(img(:)))) || any(mod(double(img(:)), 1) ~= 0) || ...
           any(double(img(:)) < 0) || any(double(img(:)) > 255)
            error('generate_reference_vectors:notY8', ...
                'Natural reference must contain integer Y8 values in [0,255].');
        end
        generated{end+1, 1} = create_or_verify_set(uint8(img), ...
            fullfile(output_root, 'natural_w1280_h0720'), ...
            'natural_grayscale_y8_w1280_h720');
    end

    fprintf('Created/reused and independently verified %d 2D reference vector set(s) in:\n%s\n', ...
        numel(generated), output_root);
end

function info = create_or_verify_set(img, set_dir, source_label)
    if exist(set_dir, 'dir')
        report = verify_reference_vector_set(set_dir, img);
        info = struct();
        info.path = set_dir;
        info.rows = report.rows;
        info.cols = report.cols;
        info.coeff_bits = report.coeff_bits;
        info.source_label = source_label;
        info.ranges = report.ranges;
        info.subband_ranges = report.subband_ranges;
        info.verified = report.passed;
        info.reused = true;
    elseif exist(set_dir, 'file')
        error('generate_reference_vectors:pathCollision', ...
            'A non-directory object already exists at %s.', set_dir);
    else
        info = export_reference_vector_set(img, set_dir, 16, source_label);
        info.reused = false;
    end
end

function sets = gen_golden_vectors(base_dir, include_full_size)
%GEN_GOLDEN_VECTORS  Generate the RETAINED golden vector sets for RTL crosscheck.
%
%   sets = GEN_GOLDEN_VECTORS(base_dir) writes one self-contained vector set
%   per configuration under base_dir, using export_packed_planes.m.
%
%   sets = GEN_GOLDEN_VECTORS(base_dir, true) additionally generates the
%   1280x720 sets.  Those are large (about 4.6 MB per hex plane) and slow, so
%   they are opt-in.
%
%   WHY THIS FILE EXISTS
%       test_export_golden_vectors.m exports into tempdir() and then deletes
%       the directory, so no golden vector set has ever existed on disk.  A
%       testbench cannot $readmemh a file that is created and destroyed inside
%       a MATLAB test.  This driver produces sets that are COMMITTED and read
%       by the RTL regression.
%
%   THE INPUT IMAGE IS PART OF THE VECTOR SET
%       A testbench in golden mode must drive the DUT with exactly the image
%       MATLAB transformed, otherwise the comparison is meaningless.  Rather
%       than reimplementing MATLAB's PRNG in SystemVerilog -- fragile, and
%       already known to differ between MATLAB and Octave at the same seed --
%       each set ships input_y8_hex.txt as the STIMULUS.  The testbench reads
%       the stimulus and the expected planes from the same directory.
%
%   SIZE LADDER
%       The RTL testbenches currently top out at 12x8 = 96 pixels while the
%       baseline target is 1280x720 = 921,600.  Jumping straight to full size
%       makes a first failure very expensive to debug, so the ladder crosses
%       each interesting boundary one step at a time:
%
%         4x4      canonical spec Section 10.4 vector, ramp 0..15
%         8x8      smallest size the top-level testbench already runs
%         12x8     non-power-of-two total (96), exercises odd addressing
%         8x12     transposed twin of 12x8; catches row/column swaps
%         16x16    first size where INDEX_W exceeds 8 bits
%         64x64    4096 samples, still fast, INDEX_W = 12
%         128x64   non-square at scale, INDEX_W = 13
%         256x128  INDEX_W = 15, last size that simulates quickly
%         512x256  INDEX_W = 17, the last rehearsal before full size
%         1280x720 the baseline target, INDEX_W = 20   (opt-in)
%
%   REPRODUCIBILITY
%       Every random set uses a fixed, printed seed via the project's usual
%       rand('seed', N) convention.  As run_all_tests.m already documents,
%       MATLAB and Octave produce different sequences from the same seed, so
%       the vector files themselves are the artifact of record -- commit them,
%       do not regenerate them on a different runtime and expect a match.
%
%   INPUT
%       base_dir          - directory to create the sets under
%       include_full_size - optional, default false
%
%   OUTPUT
%       sets - struct array with fields .name .rows .cols .dir .info

    if nargin < 2 || isempty(include_full_size)
        include_full_size = false;
    end
    if nargin < 1 || isempty(base_dir)
        error('gen_golden_vectors:badBaseDir', 'base_dir must be given.');
    end

    if ~exist(base_dir, 'dir')
        [ok, msg] = mkdir(base_dir);
        if ~ok
            error('gen_golden_vectors:mkdirFailed', 'Could not create base_dir: %s', msg);
        end
    end

    % name, rows, cols, pattern, seed
    plan = { ...
        'canonical_0004x0004', 4,    4,   'ramp',      0     ; ...
        'random_0008x0008',    8,    8,   'random',    8008  ; ...
        'random_0008x0012',    8,   12,   'random',    8012  ; ...
        'random_0012x0008',   12,    8,   'random',    12008 ; ...
        'random_0016x0016',   16,   16,   'random',    16016 ; ...
        'edges_0016x0016',    16,   16,   'edges',     0     ; ...
        'random_0064x0064',   64,   64,   'random',    64064 ; ...
        'random_0064x0128',   64,  128,   'random',    64128 ; ...
        'random_0128x0256',  128,  256,   'random',    128256; ...
        'random_0256x0512',  256,  512,   'random',    256512 };

    if include_full_size
        plan = [plan; { ...
            'random_0720x1280',  720, 1280, 'random',   7201280 ; ...
            'real_0720x1280',    720, 1280, 'realframe', 0       }];
    end

    fprintf('=== gen_golden_vectors ===\n');
    fprintf('base_dir : %s\n', base_dir);
    fprintf('sets     : %d\n\n', size(plan, 1));

    sets = struct('name', {}, 'rows', {}, 'cols', {}, 'dir', {}, 'info', {});

    for i = 1:size(plan, 1)
        name    = plan{i, 1};
        r       = plan{i, 2};
        c       = plan{i, 3};
        pattern = plan{i, 4};
        seed    = plan{i, 5};

        img = make_image(r, c, pattern, seed);

        out_dir = fullfile(base_dir, name);
        fprintf('[%2d/%2d] %-22s %4dx%-4d %-9s ', ...
            i, size(plan, 1), name, r, c, pattern);

        info = export_packed_planes(img, out_dir);

        fprintf('C2 in [%6d,%6d]  sig_xor=%04X  sig_sum=%08X\n', ...
            double(min(reshape(info.C2.', [], 1))), ...
            double(max(reshape(info.C2.', [], 1))), ...
            info.signature.xor, info.signature.sum);

        sets(end+1) = struct('name', name, 'rows', r, 'cols', c, ...
                             'dir', out_dir, 'info', info); %#ok<AGROW>
    end

    fprintf('\n%d vector sets written under %s\n', numel(sets), base_dir);
    fprintf('Commit these directories: they are the artifact of record.\n');
end

% =====================================================================
% Local helper subfunctions
% =====================================================================

function img = make_image(rows, cols, pattern, seed)
    switch pattern
        case 'ramp'
            % Spec Section 10.4 canonical input when rows==cols==4.
            img = int64(reshape(0:(rows*cols - 1), cols, rows).');
            img = int64(mod(img, 256));

        case 'random'
            rand('seed', seed);   %#ok<RAND> project convention, see header
            img = int64(floor(rand(rows, cols) * 256));
            img(img > 255) = 255;

        case 'edges'
            % Deterministic structure with strong horizontal AND vertical
            % detail plus flat regions, so HL/LH/HH are all non-trivial and
            % an orientation mistake shows up in the coefficients.
            [xg, yg] = meshgrid(0:cols-1, 0:rows-1);
            img = int64(zeros(rows, cols));
            img(xg >= cols/2) = 255;
            img(yg >= rows/2) = int64(128);
            img(1:2:end, 1:2:end) = int64(255);
            img = int64(mod(img, 256));

        case 'realframe'
            % The same asset tests/test_dwt53_2level.m uses for Gate 3.
            this_dir = fileparts(mfilename('fullpath'));
            p = fullfile(this_dir, 'test_data', 'real_frame_1280x720.png');
            if exist(p, 'file') ~= 2
                p = fullfile(this_dir, '..', 'test_data', 'real_frame_1280x720.png');
            end
            if exist(p, 'file') ~= 2
                error('gen_golden_vectors:missingAsset', ...
                    ['real frame asset not found: %s\n' ...
                     'This is a hard failure, not a skip.'], p);
            end
            frame = imread(p);
            if ndims(frame) ~= 2 || ~isa(frame, 'uint8') %#ok<ISMAT>
                error('gen_golden_vectors:badAsset', ...
                    'real frame must be a single-channel uint8 image.');
            end
            if ~isequal(size(frame), [rows, cols])
                error('gen_golden_vectors:badAssetSize', ...
                    'real frame must be %dx%d, got %dx%d.', ...
                    rows, cols, size(frame, 1), size(frame, 2));
            end
            img = int64(frame);

        otherwise
            error('gen_golden_vectors:badPattern', 'unknown pattern "%s".', pattern);
    end

    if any(img(:) < 0) || any(img(:) > 255)
        error('gen_golden_vectors:notY8', 'generated image left the Y8 range.');
    end
end

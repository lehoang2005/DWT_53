function report = report_subband_ranges(img, output_path)
%REPORT_SUBBAND_RANGES  Measure every sizing-relevant stage against §D.2.
%
%   REPORT = REPORT_SUBBAND_RANGES(IMG) calls the frozen 1D/2D transform
%   functions; it does not reproduce lifting equations. If OUTPUT_PATH is
%   supplied, it writes a deterministic CSV table.

    if nargin < 2
        output_path = '';
    end
    if isempty(img) || ~ismatrix(img) || isvector(img)
        error('report_subband_ranges:badImage', 'img must be a non-empty 2D matrix.');
    end
    if any(~isfinite(img(:))) || any(mod(img(:), 1) ~= 0) || ...
       any(img(:) < 0) || any(img(:) > 255)
        error('report_subband_ranges:notY8', 'img must contain integer Y8 values in [0,255].');
    end
    [rows, cols] = size(img);
    if mod(rows, 4) ~= 0 || mod(cols, 4) ~= 0
        error('report_subband_ranges:notDivisibleBy4', ...
            'rows and cols must both be divisible by four.');
    end
    img = int64(img);

    L_row_l1 = zeros(rows, cols/2, 'int64');
    H_row_l1 = zeros(rows, cols/2, 'int64');
    for row = 1:rows
        [low_row, high_row] = dwt53_forward_1d(img(row, :));
        L_row_l1(row, :) = low_row(:).';
        H_row_l1(row, :) = high_row(:).';
    end
    [LL1, HL1, LH1, HH1] = dwt53_forward_2d(img);

    L_row_l2 = zeros(rows/2, cols/4, 'int64');
    H_row_l2 = zeros(rows/2, cols/4, 'int64');
    for row = 1:rows/2
        [low_row, high_row] = dwt53_forward_1d(LL1(row, :));
        L_row_l2(row, :) = low_row(:).';
        H_row_l2(row, :) = high_row(:).';
    end
    coeffs = dwt53_forward_2level(img);

    names = {'l_row_l1','h_row_l1','ll1','hl1','lh1','hh1', ...
        'l_row_l2','h_row_l2','ll2','hl2','lh2','hh2'};
    values = {L_row_l1,H_row_l1,LL1,HL1,LH1,HH1, ...
        L_row_l2,H_row_l2,coeffs.LL2,coeffs.HL2,coeffs.LH2,coeffs.HH2};
    lower_bound = [-127,-255,-382,-510,-510,-510, ...
        -892,-1020,-1912,-2040,-2040,-2040];
    upper_bound = [383,255,638,510,510,510, ...
        1148,1020,2168,2040,2040,2040];

    item_template = struct('quantity','','observed_min',0,'observed_max',0, ...
        'theoretical_min',0,'theoretical_max',0,'passed',false);
    items = repmat(item_template, numel(names), 1);
    for i = 1:numel(names)
        items(i).quantity = names{i};
        items(i).observed_min = double(min(values{i}(:)));
        items(i).observed_max = double(max(values{i}(:)));
        items(i).theoretical_min = lower_bound(i);
        items(i).theoretical_max = upper_bound(i);
        items(i).passed = items(i).observed_min >= lower_bound(i) && ...
            items(i).observed_max <= upper_bound(i);
        if ~items(i).passed
            error('report_subband_ranges:boundExceeded', ...
                '%s observed [%d,%d] exceeds [%d,%d].', names{i}, ...
                items(i).observed_min, items(i).observed_max, ...
                lower_bound(i), upper_bound(i));
        end
    end

    csv_lines = cell(numel(items) + 1, 1);
    csv_lines{1} = 'quantity,observed_min,observed_max,theoretical_min,theoretical_max,status';
    for i = 1:numel(items)
        csv_lines{i+1} = sprintf('%s,%d,%d,%d,%d,PASS', ...
            items(i).quantity, items(i).observed_min, items(i).observed_max, ...
            items(i).theoretical_min, items(i).theoretical_max);
    end
    csv_text = sprintf('%s\n', csv_lines{:});
    if ~isempty(output_path)
        fid = fopen(output_path, 'w');
        if fid < 0
            error('report_subband_ranges:fileOpen', 'Could not open %s.', output_path);
        end
        cleaner = onCleanup(@() fclose(fid));
        fprintf(fid, '%s', csv_text);
        clear cleaner;
    end

    report = struct();
    report.rows = rows;
    report.cols = cols;
    report.items = items;
    report.csv_text = csv_text;
    report.passed = all([items.passed]);
end

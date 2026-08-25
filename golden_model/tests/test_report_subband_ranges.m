function test_report_subband_ranges()
%TEST_REPORT_SUBBAND_RANGES  Cover row intermediates and all named subbands.

    root = tempname;
    mkdir(root);
    cleaner = onCleanup(@() remove_root(root));
    path = fullfile(root, 'ranges.csv');
    img = gen_test_frame(8, 12);
    report = report_subband_ranges(img, path);
    assert(report.passed);
    assert(numel(report.items) == 12);
    assert(all([report.items.passed]));
    assert(strcmp(report.items(1).quantity, 'l_row_l1'));
    assert(strcmp(report.items(end).quantity, 'hh2'));
    actual = fileread(path);
    actual(actual == char(13)) = [];
    expected = report.csv_text;
    expected(expected == char(13)) = [];
    assert(strcmp(actual, expected));
    clear cleaner;
end

function remove_root(path)
    if exist(path, 'dir')
        rmdir(path, 's');
    end
end

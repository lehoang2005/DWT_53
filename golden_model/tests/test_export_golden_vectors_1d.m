function test_export_golden_vectors_1d()
%TEST_EXPORT_GOLDEN_VECTORS_1D  Directly lock legacy exporter Y8 behaviour.

    root = tempname;
    mkdir(root);
    cleaner = onCleanup(@() remove_root(root));

    y8_dir = fullfile(root, 'y8');
    x = int64([10 20 30 40 50 60 70 80]);
    info = export_golden_vectors_1d(x, y8_dir, 16, 8);
    x_hex = dwt53_read_hex_vector(fullfile(y8_dir, 'input_hex.txt'), 8, false, 8);
    L_hex = dwt53_read_hex_vector(fullfile(y8_dir, 'L_hex.txt'), 16, true, 4);
    H_hex = dwt53_read_hex_vector(fullfile(y8_dir, 'H_hex.txt'), 16, true, 4);
    assert(isequal(x_hex, x(:)));
    assert(isequal(L_hex, info.L(:)));
    assert(isequal(H_hex, info.H(:)));

    signed_dir = fullfile(root, 'signed');
    signed_x = int64([-10 20 -30 40]);
    signed_info = export_golden_vectors_1d(signed_x, signed_dir, 16);
    signed_hex = dwt53_read_hex_vector(fullfile(signed_dir, 'input_hex.txt'), 16, true, 4);
    assert(isequal(signed_hex, signed_info.x(:)));

    expect_error(@() export_golden_vectors_1d([-1 0], fullfile(root, 'bad'), 16, 8), ...
        'export_golden_vectors_1d:notY8');
    clear cleaner;
end

function remove_root(path)
    if exist(path, 'dir')
        rmdir(path, 's');
    end
end

function expect_error(action, identifier)
    caught = false;
    try
        action();
    catch ME
        caught = strcmp(ME.identifier, identifier);
    end
    assert(caught, 'Expected error %s was not raised.', identifier);
end

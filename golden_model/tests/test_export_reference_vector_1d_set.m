function test_export_reference_vector_1d_set()
%TEST_EXPORT_REFERENCE_VECTOR_1D_SET  End-to-end wrapper and readback test.

    root = tempname;
    mkdir(root);
    cleaner = onCleanup(@() remove_root(root));
    out = fullfile(root, 'canonical');
    x = int64([0 0 10 0 20 0 30 0]);
    info = export_reference_vector_1d_set(x, out, 16, 8, 'unit_test');
    assert(info.verified);
    report = verify_reference_vector_1d_set(out, x);
    assert(report.passed);
    assert(~exist(fullfile(out, 'README_golden_vectors_1d.md'), 'file'));
    assert(exist(fullfile(out, 'README_reference_vector_1d_set.md'), 'file') == 2);
    expect_error(@() export_reference_vector_1d_set(x, out, 16, 8, 'duplicate'), ...
        'export_reference_vector_1d_set:outputExists');
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

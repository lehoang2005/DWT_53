function test_export_reference_vector_set()
%TEST_EXPORT_REFERENCE_VECTOR_SET  Canonical layout plus rectangular readback.

    root = tempname;
    mkdir(root);
    cleaner = onCleanup(@() remove_root(root));

    canonical = int64(reshape(0:15, 4, 4).');
    canonical_dir = fullfile(root, 'canonical');
    info = export_reference_vector_set(canonical, canonical_dir, 16, 'unit_canonical');
    assert(info.verified);
    report = verify_reference_vector_set(canonical_dir, canonical);
    assert(report.passed);
    c1_vec = dwt53_read_dec_vector(fullfile(canonical_dir, 'c1_packed_dec.txt'), 16);
    c2_vec = dwt53_read_dec_vector(fullfile(canonical_dir, 'c2_packed_dec.txt'), 16);
    C1 = reshape(c1_vec, 4, 4).';
    C2 = reshape(c2_vec, 4, 4).';
    expected_C1 = int64([0 2 0 1; 9 11 0 1; 0 0 0 0; 4 4 0 0]);
    expected_C2 = int64([6 2 0 1; 9 0 0 1; 0 0 0 0; 4 4 0 0]);
    assert(isequal(C1, expected_C1));
    assert(isequal(C2, expected_C2));

    rectangular = gen_dwt53_test_frame(8, 12);
    rectangular_dir = fullfile(root, 'rectangular');
    rect_info = export_reference_vector_set(rectangular, rectangular_dir, 16, 'unit_rect');
    assert(rect_info.verified);
    sweep_text = fileread(fullfile(rectangular_dir, 'signature_sweep.csv'));
    assert(~isempty(strfind(sweep_text, 'input_y8,8,zero-fill,VALID'))); %#ok<STREMP>
    assert(~isempty(strfind(sweep_text, 'c2,13,sign-extend,VALID'))); %#ok<STREMP>
    expect_error(@() export_reference_vector_set(rectangular, rectangular_dir, 16, 'duplicate'), ...
        'export_reference_vector_set:outputExists');
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

function run_reference_package_tests()
%RUN_REFERENCE_PACKAGE_TESTS  Run tests added by the reference-vector package.

    tests_dir = fileparts(mfilename('fullpath'));
    model_dir = fileparts(tests_dir);
    original_path = path;
    path_cleaner = onCleanup(@() path(original_path));
    addpath(model_dir);
    addpath(tests_dir);

    tests = { ...
        @test_dwt53_signature, ...
        @test_gen_dwt53_test_frame, ...
        @test_export_checkpoint_signatures, ...
        @test_report_subband_ranges, ...
        @test_export_golden_vectors_1d, ...
        @test_export_reference_vector_1d_set, ...
        @test_export_reference_vector_set, ...
        @test_generate_reference_vectors};
    fprintf('\nDWT53 reference-vector package tests\n');
    fprintf('====================================\n');
    for i = 1:numel(tests)
        name = func2str(tests{i});
        fprintf('  [RUN ] %s\n', name);
        tests{i}();
        fprintf('  [PASS] %s\n', name);
    end
    fprintf('====================================\n');
    fprintf('ALL %d REFERENCE-PACKAGE TESTS PASS\n\n', numel(tests));
    clear path_cleaner;
end

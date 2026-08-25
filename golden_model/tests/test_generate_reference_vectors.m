function test_generate_reference_vectors()
%TEST_GENERATE_REFERENCE_VECTORS  Exercise the fixed plan and metadata-only driver.

    root = tempname;
    mkdir(root);
    cleaner = onCleanup(@() remove_root(root));
    output_root = fullfile(root, 'vectors_2d');
    generated = generate_reference_vectors(output_root, false, '');
    assert(numel(generated) == 6);
    assert(exist(fullfile(output_root, 'canonical_w0004_h0004'), 'dir') == 7);
    assert(exist(fullfile(output_root, 'deterministic_w0012_h0008'), 'dir') == 7);
    assert(exist(fullfile(output_root, 'deterministic_w0008_h0012'), 'dir') == 7);
    for i = 1:numel(generated)
        assert(generated{i}.verified);
        assert(~generated{i}.reused);
        assert(~isfield(generated{i}, 'img'));
        assert(~isfield(generated{i}, 'C1'));
        assert(~isfield(generated{i}, 'C2'));
        assert(~isfield(generated{i}, 'recon'));
    end
    reused = generate_reference_vectors(output_root, false, '');
    assert(numel(reused) == 6);
    assert(all(cellfun(@(item) item.verified && item.reused, reused)));
    clear cleaner;
end

function remove_root(path)
    if exist(path, 'dir')
        rmdir(path, 's');
    end
end

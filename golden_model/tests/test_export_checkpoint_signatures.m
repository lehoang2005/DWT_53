function test_export_checkpoint_signatures()
%TEST_EXPORT_CHECKPOINT_SIGNATURES  Independently check all five streams.

    root = tempname;
    mkdir(root);
    cleaner = onCleanup(@() remove_root(root));
    img = int64(reshape(0:15, 4, 4).');
    packed = export_packed_planes(img, root, 16);
    result = export_checkpoint_signatures(packed, root, 16);

    assert(result.storage.input_zero.count == 16);
    assert(result.storage.input_zero.xor == result.storage.recon_zero.xor);
    assert(result.storage.input_zero.A == result.storage.recon_zero.A);
    assert(result.storage.input_zero.B == result.storage.recon_zero.B);
    assert(result.storage.c2_zero.count == packed.signature.count);
    assert(result.storage.c2_zero.xor == packed.signature.xor);
    assert(result.storage.c2_zero.A == packed.signature.sum);
    assert(isequal(result.LL1, packed.C1(1:2, 1:2)));
    assert(numel(result.sweep) == 5 * 3 * 2);
    streams = make_streams(packed, result.LL1);
    dwt53_verify_signature_sweep_file(result.files.sweep, streams, [8 13 16]);
    clear cleaner;
end

function streams = make_streams(packed, LL1)
    template = struct('name','','values',[],'sample_format','','order','row-major');
    streams = repmat(template, 5, 1);
    names = {'input_y8','c1','c2','ll1','recon_y8'};
    values = {packed.img,packed.C1,packed.C2,LL1,packed.recon};
    formats = {'unsigned','signed','signed','signed','unsigned'};
    for i = 1:5
        streams(i).name = names{i};
        streams(i).values = reshape(int64(values{i}).', [], 1);
        streams(i).sample_format = formats{i};
    end
end

function remove_root(path)
    if exist(path, 'dir')
        rmdir(path, 's');
    end
end

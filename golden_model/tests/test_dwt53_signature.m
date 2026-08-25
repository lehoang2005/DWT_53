function test_dwt53_signature()
%TEST_DWT53_SIGNATURE  Known-answer and sensitivity checks for signatures.

    s = dwt53_signature([1 2], 8, 'unsigned', 'zero-fill', 'test-order');
    assert(s.count == 2);
    assert(s.xor == 3);
    assert(s.A == 3);
    assert(s.B == 4);  % post-update A values are 1 and 3

    reversed = dwt53_signature([2 1], 8, 'unsigned', 'zero-fill', 'test-order');
    assert(reversed.count == s.count);
    assert(reversed.xor == s.xor);
    assert(reversed.A == s.A);
    assert(reversed.B == 5);
    assert(reversed.B ~= s.B);

    equal_sum_rows = [1 2 3 4; 0 1 4 5];
    swapped_rows = equal_sum_rows([2 1], :);
    row_sig = dwt53_signature(reshape(equal_sum_rows.', [], 1), ...
        8, 'unsigned', 'zero-fill', 'row-major');
    swapped_sig = dwt53_signature(reshape(swapped_rows.', [], 1), ...
        8, 'unsigned', 'zero-fill', 'row-major');
    assert(~isequal(equal_sum_rows, swapped_rows));
    assert(row_sig.count == swapped_sig.count && row_sig.xor == swapped_sig.xor);
    assert(row_sig.A == swapped_sig.A && row_sig.B == swapped_sig.B);

    zero_fill = dwt53_signature(-1, 16, 'signed', 'zero-fill', 'test-order');
    sign_extend = dwt53_signature(-1, 16, 'signed', 'sign-extend', 'test-order');
    assert(zero_fill.xor == hex2dec('0000FFFF'));
    assert(zero_fill.A == hex2dec('0000FFFF'));
    assert(sign_extend.xor == hex2dec('0000FFFF'));
    assert(sign_extend.A == hex2dec('FFFFFFFF'));

    y = [0 1 127 128 255];
    y8_zero = dwt53_signature(y, 8, 'unsigned', 'zero-fill', 'test-order');
    y8_sign = dwt53_signature(y, 8, 'unsigned', 'sign-extend', 'test-order');
    y16_zero = dwt53_signature(y, 16, 'unsigned', 'zero-fill', 'test-order');
    assert(y8_zero.xor == y8_sign.xor && y8_zero.A == y8_sign.A && y8_zero.B == y8_sign.B);
    assert(y8_zero.xor == y16_zero.xor && y8_zero.A == y16_zero.A && y8_zero.B == y16_zero.B);

    expect_error(@() dwt53_signature(128, 8, 'signed', 'zero-fill', 'x'), ...
        'dwt53_signature:outOfRange');

    streams = struct('name','coeff','values',int64([-200 0 200]), ...
        'sample_format','signed','order','row-major');
    entries = dwt53_signature_sweep(streams, [8 13 16]);
    assert(numel(entries) == 6);
    assert(all(strcmp({entries(1:2).status}, 'OUT_OF_RANGE')));
    assert(all(strcmp({entries(3:6).status}, 'VALID')));
    csv = dwt53_signature_sweep_text(entries);
    assert(~isempty(strfind(csv, 'coeff,8,zero-fill,OUT_OF_RANGE'))); %#ok<STREMP>
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

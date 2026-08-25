function test_gen_dwt53_test_frame()
%TEST_GEN_DWT53_TEST_FRAME  Lock the DE10/MATLAB deterministic frame rule.

    [a, meta] = gen_dwt53_test_frame(8, 16);
    b = gen_dwt53_test_frame(8, 16);
    [alias_frame, alias_meta] = gen_test_frame(8, 16);
    assert(isa(a, 'uint8'));
    assert(isequal(size(a), [8 16]));
    assert(isequal(a, b));
    assert(isequal(a, alias_frame));
    assert(strcmp(meta.rule_id, alias_meta.rule_id));
    assert(strcmp(meta.rule_id, 'DWT53_TEST_FRAME_V1'));
    expected_first16 = uint8([0 145 36 181 72 217 108 253 ...
        144 33 180 69 216 105 252 141]);
    assert(isequal(a(1, :), expected_first16));

    [~, HL, LH, HH] = dwt53_forward_2d(a);
    assert(any(HL(:) ~= 0) || any(LH(:) ~= 0) || any(HH(:) ~= 0));
    expect_error(@() gen_dwt53_test_frame(6, 8), ...
        'gen_dwt53_test_frame:notDivisibleBy4');
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

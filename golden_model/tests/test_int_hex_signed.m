function n_pass = test_int_hex_signed()
%TEST_INT_HEX_SIGNED  Self-checking regression for int_to_hex_signed.m /
%   hex_signed_to_int.m: round-trip correctness and known two's-complement
%   values at 8-bit and 16-bit widths, including boundary and negative cases.

    n_pass = 0;

    % -----------------------------------------------------------
    % Known two's-complement values, 16-bit (the frozen coefficient
    % storage baseline, spec Section 5.2)
    % -----------------------------------------------------------
    known = { 0, '0000'; 1, '0001'; -1, 'FFFF'; 32767, '7FFF'; ...
              -32768, '8000'; -2, 'FFFE'; 255, '00FF'; -255, 'FF01' };
    for i = 1:size(known,1)
        val = known{i,1}; expect_hex = known{i,2};
        got_hex = int_to_hex_signed(val, 16);
        assert(strcmp(got_hex, expect_hex), ...
            sprintf('int_to_hex_signed(%d,16): got %s expected %s', val, got_hex, expect_hex));
        n_pass = n_pass + 1;

        got_val = hex_signed_to_int(expect_hex, 16);
        assert(isequal(got_val, int64(val)), ...
            sprintf('hex_signed_to_int(%s,16): got %d expected %d', expect_hex, double(got_val), val));
        n_pass = n_pass + 1;
    end

    % -----------------------------------------------------------
    % Known values, 8-bit SIGNED (valid range [-128,127]). NOTE: Y8
    % pixels in this project are UNSIGNED 0-255 and are exported with
    % plain dec2hex() in export_golden_vectors.m, NOT through this
    % signed helper -- 255 is deliberately not tested here because it
    % is outside the representable signed 8-bit range.
    % -----------------------------------------------------------
    known8 = { 0, '00'; 127, '7F'; -128, '80'; -1, 'FF'; 1, '01' };
    for i = 1:size(known8,1)
        val = known8{i,1}; expect_hex = known8{i,2};
        got_hex = int_to_hex_signed(val, 8);
        assert(strcmp(got_hex, expect_hex), ...
            sprintf('int_to_hex_signed(%d,8): got %s expected %s', val, got_hex, expect_hex));
        n_pass = n_pass + 1;
    end

    % -----------------------------------------------------------
    % Vectorized round trip over a dense sweep of the full 16-bit
    % signed range
    % -----------------------------------------------------------
    vals = int64(-32768:32767)';
    hexmat = int_to_hex_signed(vals, 16);
    assert(size(hexmat,1) == numel(vals), 'hex matrix row count must match input count');
    vals_back = hex_signed_to_int(hexmat, 16);
    assert(isequal(vals_back, vals), 'full 16-bit sweep round-trip mismatch');
    n_pass = n_pass + numel(vals);

    % -----------------------------------------------------------
    % Vectorized round trip over the full 8-bit SIGNED range
    % (-128..127). This validates the helper generically; it is not
    % how Y8 pixels are exported (see note above).
    % -----------------------------------------------------------
    vals8 = int64(-128:127)';
    hexmat8 = int_to_hex_signed(vals8, 8);
    vals8_back = hex_signed_to_int(hexmat8, 8);
    assert(isequal(vals8_back, vals8), 'full 8-bit signed sweep round-trip mismatch');
    n_pass = n_pass + numel(vals8);

    % -----------------------------------------------------------
    % Error paths: out-of-range values must be rejected, not wrapped
    % -----------------------------------------------------------
    threw = false;
    try, int_to_hex_signed(32768, 16); catch, threw = true; end
    assert(threw, 'must reject 32768 at 16-bit (one past max positive)');
    n_pass = n_pass + 1;

    threw = false;
    try, int_to_hex_signed(-32769, 16); catch, threw = true; end
    assert(threw, 'must reject -32769 at 16-bit (one past min negative)');
    n_pass = n_pass + 1;

    threw = false;
    try, int_to_hex_signed(1, 15); catch, threw = true; end
    assert(threw, 'must reject bits not a multiple of 4');
    n_pass = n_pass + 1;

    threw = false;
    try, int_to_hex_signed(1.5, 16); catch, threw = true; end
    assert(threw, 'must reject non-integer value');
    n_pass = n_pass + 1;

    fprintf('[PASS] test_int_hex_signed: %d assertions passed\n', n_pass);
end

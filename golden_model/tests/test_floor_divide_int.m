function n_pass = test_floor_divide_int()
%TEST_FLOOR_DIVIDE_INT  Self-checking regression for floor_divide_int.m.
%
%   n_pass = TEST_FLOOR_DIVIDE_INT() runs every case via ASSERT (any
%   failure throws and aborts the run -- there is no silent skip path).
%   Returns the number of cases that passed, for reporting.

    n_pass = 0;

    % -----------------------------------------------------------
    % Mandatory negative-rounding assertions (spec Section 5.1 / user
    % prompt Section 3)
    % -----------------------------------------------------------
    assert(isequal(floor_divide_int(-1, 2), int64(-1)), 'floor(-1/2) must be -1');
    n_pass = n_pass + 1;
    assert(isequal(floor_divide_int(-3, 2), int64(-2)), 'floor(-3/2) must be -2');
    n_pass = n_pass + 1;
    assert(isequal(floor_divide_int(-1, 4), int64(-1)), 'floor(-1/4) must be -1');
    n_pass = n_pass + 1;
    assert(isequal(floor_divide_int(-5, 4), int64(-2)), 'floor(-5/4) must be -2');
    n_pass = n_pass + 1;

    % -----------------------------------------------------------
    % Positive and zero cases (sanity, must match ordinary floor)
    % -----------------------------------------------------------
    assert(isequal(floor_divide_int(5, 2), int64(2)));   n_pass = n_pass + 1;
    assert(isequal(floor_divide_int(4, 2), int64(2)));   n_pass = n_pass + 1;
    assert(isequal(floor_divide_int(0, 2), int64(0)));   n_pass = n_pass + 1;
    assert(isequal(floor_divide_int(0, 4), int64(0)));   n_pass = n_pass + 1;
    assert(isequal(floor_divide_int(7, 4), int64(1)));   n_pass = n_pass + 1;
    assert(isequal(floor_divide_int(-7, 4), int64(-2))); n_pass = n_pass + 1;
    assert(isequal(floor_divide_int(-4, 2), int64(-2))); n_pass = n_pass + 1;
    assert(isequal(floor_divide_int(-8, 4), int64(-2))); n_pass = n_pass + 1;

    % -----------------------------------------------------------
    % Cross-check against an independent mathematical-floor reference
    % (double-precision floor, exact for this integer magnitude range)
    % over a dense sweep of numerators, denominators in {2,4}
    % -----------------------------------------------------------
    for den = [2, 4]
        for num = -2000:2000
            expected = int64(floor(num / den));
            got = floor_divide_int(num, den);
            assert(isequal(got, expected), ...
                sprintf('floor_divide_int(%d,%d): got %d, expected %d', ...
                        num, den, got, expected));
            n_pass = n_pass + 1;
        end
    end

    % -----------------------------------------------------------
    % Vectorized input
    % -----------------------------------------------------------
    num_vec = int64([-5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5]);
    expected_vec = int64([-2, -1, -1, -1, -1, 0, 0, 0, 0, 1, 1]); % /4 floor
    got_vec = floor_divide_int(num_vec, 4);
    assert(isequal(got_vec, expected_vec), 'vectorized floor_divide_int(., 4) mismatch');
    n_pass = n_pass + 1;

    % -----------------------------------------------------------
    % Error path: non-integer numerator must be rejected, not silently
    % rounded
    % -----------------------------------------------------------
    threw = false;
    try
        floor_divide_int(1.5, 2);
    catch
        threw = true;
    end
    assert(threw, 'floor_divide_int must reject non-integer numerator');
    n_pass = n_pass + 1;

    fprintf('[PASS] test_floor_divide_int: %d assertions passed\n', n_pass);
end

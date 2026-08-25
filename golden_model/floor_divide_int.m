function q = floor_divide_int(numerator, denominator)
%FLOOR_DIVIDE_INT  Mathematical floor division for integer-valued data.
%
%   q = FLOOR_DIVIDE_INT(numerator, denominator) computes
%
%       q = floor( numerator / denominator )
%
%   using signed int64 arithmetic (via IDIVIDE(...,'floor')), so the
%   result matches mathematical floor (rounds toward -Infinity) for
%   negative numerators as well as positive ones. This is required
%   because MATLAB/Octave's built-in integer division operators do NOT
%   have unambiguous negative-rounding behavior across all code paths,
%   and algorithm_spec_v0.1 Section 5.1 mandates true mathematical floor:
%
%       floor(-1/2) = -1
%       floor(-3/2) = -2
%       floor(-1/4) = -1
%       floor(-5/4) = -2
%
%   INPUT
%       numerator   - integer-valued scalar, vector, or matrix (numeric)
%       denominator - positive integer scalar (this project only ever
%                     divides by 2 or 4, per the 5/3 lifting equations)
%
%   OUTPUT
%       q - int64 array, same size as numerator, q = floor(numerator/denominator)
%
%   This function is a single, tested chokepoint for floor-division so
%   that dwt53_forward_1d.m / dwt53_inverse_1d.m never call MATLAB's
%   built-in floor()/idivide() directly with ambiguous rounding modes.

    validateattributes(numerator, {'numeric'}, {}, mfilename, 'numerator');
    validateattributes(denominator, {'numeric'}, ...
        {'scalar', 'positive', 'integer'}, mfilename, 'denominator');

    if any(mod(numerator(:), 1) ~= 0) || any(~isfinite(numerator(:)))
        error('floor_divide_int:nonInteger', ...
            'numerator must contain only finite integer-valued numbers.');
    end

    num64 = int64(numerator);
    den64 = int64(denominator);

    q = idivide(num64, den64, 'floor');
end

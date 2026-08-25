function img = dwt53_inverse_2level(coeffs)
%DWT53_INVERSE_2LEVEL  Inverse two-level reversible Le Gall 5/3 transform.
%
%   img = DWT53_INVERSE_2LEVEL(coeffs) undoes dwt53_forward_2level.m per
%   algorithm_spec_v0.1 Section 9.2, in the mandatory order:
%       1. LL2 + HL2 + LH2 + HH2  -> reconstructed LL1
%       2. reconstructed LL1 + HL1 + LH1 + HH1  -> reconstructed image
%
%   INPUT
%       coeffs - struct with fields LL2, HL2, LH2, HH2, HL1, LH1, HH1
%                (as produced by dwt53_forward_2level.m).
%
%   OUTPUT
%       img - reconstructed matrix, signed int64.
%
%   Mandatory invariant: for any valid img (dims divisible by 4),
%       dwt53_inverse_2level(dwt53_forward_2level(img)) == img  (bit-exact)

    required_fields = {'LL2','HL2','LH2','HH2','HL1','LH1','HH1'};
    for i = 1:numel(required_fields)
        f = required_fields{i};
        if ~isfield(coeffs, f)
            error('dwt53_inverse_2level:missingField', ...
                'coeffs is missing required field "%s".', f);
        end
    end

    % ---------------------------------------------------------------
    % Step 1: reconstruct Level 2 first -> LL1 (spec Section 9.2, item 1)
    % ---------------------------------------------------------------
    LL1_rec = dwt53_inverse_2d(coeffs.LL2, coeffs.HL2, coeffs.LH2, coeffs.HH2);

    % ---------------------------------------------------------------
    % Step 2: reconstruct Level 1 using the just-reconstructed LL1
    % (spec Section 9.2, item 2)
    % ---------------------------------------------------------------
    img = dwt53_inverse_2d(LL1_rec, coeffs.HL1, coeffs.LH1, coeffs.HH1);
end

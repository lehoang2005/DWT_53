function packed = dwt53_pack_2level(coeffs)
%DWT53_PACK_2LEVEL  Assemble two-level coefficients into one packed matrix.
%
%   packed = DWT53_PACK_2LEVEL(coeffs) returns the full-size packed
%   coefficient matrix where the Level-2 packed block REPLACES the LL1
%   quadrant, and HL1/LH1/HH1 remain in their Level-1 quadrant positions
%   -- exactly as described in algorithm_spec_v0.1 Section 9.1:
%   "In a packed ... coefficient matrix, the Level-2 packed matrix
%   replaces the LL1 quadrant; the other three Level-1 quadrants remain
%   in place."
%
%   Implemented by calling dwt53_pack_2d.m twice (no packing logic is
%   duplicated): once to build the Level-2 block, once to place that
%   block alongside HL1/LH1/HH1. Verified bit-exact against the
%   canonical C2 matrix in spec Section 10.4 by tests/test_dwt53_2level.m.
%
%   NOTE: like dwt53_pack_2d.m / dwt53_unpack_2d.m, this file is not in
%   the originally requested file list; added for the same reason
%   (Section 5 requires a tested pack/unpack pair for any packed matrix,
%   and it is the only direct way to check against the spec's canonical
%   C2 vector).
%
%   INPUT
%       coeffs - struct with fields LL2, HL2, LH2, HH2, HL1, LH1, HH1
%
%   OUTPUT
%       packed - full coefficient matrix, signed int64

    required_fields = {'LL2','HL2','LH2','HH2','HL1','LH1','HH1'};
    for i = 1:numel(required_fields)
        f = required_fields{i};
        if ~isfield(coeffs, f)
            error('dwt53_pack_2level:missingField', ...
                'coeffs is missing required field "%s".', f);
        end
    end

    level2_block = dwt53_pack_2d(coeffs.LL2, coeffs.HL2, coeffs.LH2, coeffs.HH2);
    packed = dwt53_pack_2d(level2_block, coeffs.HL1, coeffs.LH1, coeffs.HH1);
end

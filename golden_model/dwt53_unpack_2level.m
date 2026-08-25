function coeffs = dwt53_unpack_2level(packed)
%DWT53_UNPACK_2LEVEL  Split a packed two-level coefficient matrix.
%
%   coeffs = DWT53_UNPACK_2LEVEL(packed) is the exact inverse of
%   dwt53_pack_2level.m. Implemented by calling dwt53_unpack_2d.m twice:
%   once to split the outer Level-1 layout (recovering HL1/LH1/HH1 and
%   the still-packed Level-2 block), once to split that Level-2 block
%   into LL2/HL2/LH2/HH2.
%
%   OUTPUT
%       coeffs - struct with fields LL2, HL2, LH2, HH2, HL1, LH1, HH1

    [level2_block, HL1, LH1, HH1] = dwt53_unpack_2d(packed);
    [LL2, HL2, LH2, HH2] = dwt53_unpack_2d(level2_block);

    coeffs = struct( ...
        'LL2', LL2, 'HL2', HL2, 'LH2', LH2, 'HH2', HH2, ...
        'HL1', HL1, 'LH1', LH1, 'HH1', HH1);
end

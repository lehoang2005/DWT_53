function packed = dwt53_pack_2d(LL, HL, LH, HH)
%DWT53_PACK_2D  Assemble 4 subbands into the canonical packed layout.
%
%   packed = DWT53_PACK_2D(LL, HL, LH, HH) returns the (2R)x(2C) matrix
%
%       [ LL  HL ]
%       [ LH  HH ]
%
%   per algorithm_spec_v0.1 Section 8.2 (LL top-left, HL top-right,
%   LH bottom-left, HH bottom-right). This exact ordering is verified
%   bit-exact against the canonical 4x4 vector in spec Section 10.4 by
%   tests/test_dwt53_2d.m -- do NOT reorder these quadrants without
%   re-checking that vector.
%
%   NOTE: this file is not in the originally requested file list; it
%   was added because building and testing a packed coefficient matrix
%   is the only way to directly verify against the spec's canonical
%   Section 10.4 vector, and Section 5 of the collaboration brief
%   requires a tested pack/unpack pair whenever a packed matrix is
%   produced.

    sz = size(LL);
    if ~isequal(size(HL), sz) || ~isequal(size(LH), sz) || ~isequal(size(HH), sz)
        error('dwt53_pack_2d:sizeMismatch', 'LL, HL, LH, HH must all be the same size.');
    end
    all_vals = [LL(:); HL(:); LH(:); HH(:)];
    if any(~isfinite(all_vals)) || any(mod(all_vals, 1) ~= 0)
        error('dwt53_pack_2d:notInteger', 'All subbands must contain only finite integer values.');
    end

    packed = [int64(LL), int64(HL); int64(LH), int64(HH)];
end

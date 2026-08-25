function [img, meta] = gen_test_frame(rows, cols)
%GEN_TEST_FRAME  Work-order entry point for the deterministic DE10/MATLAB frame.
%
%   This compatibility entry point keeps the exact work-order filename while
%   delegating the single normative implementation to gen_dwt53_test_frame.m.

    if nargin < 1
        rows = [];
    end
    if nargin < 2
        cols = [];
    end
    [img, meta] = gen_dwt53_test_frame(rows, cols);
end

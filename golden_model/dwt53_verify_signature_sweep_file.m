function entries = dwt53_verify_signature_sweep_file(path, streams, widths)
%DWT53_VERIFY_SIGNATURE_SWEEP_FILE  Recompute and byte-compare sweep CSV.

    if nargin < 3
        widths = [8 13 16];
    end
    entries = dwt53_signature_sweep(streams, widths);
    expected = dwt53_signature_sweep_text(entries);
    actual = fileread(path);
    expected(expected == char(13)) = [];
    actual(actual == char(13)) = [];
    if ~strcmp(actual, expected)
        error('dwt53_verify_signature_sweep_file:mismatch', ...
            'Signature sweep file does not match recomputed values: %s', path);
    end
end

function entries = dwt53_write_signature_sweep(path, streams, widths)
%DWT53_WRITE_SIGNATURE_SWEEP  Compute and write canonical signature-sweep CSV.

    if nargin < 3
        widths = [8 13 16];
    end
    entries = dwt53_signature_sweep(streams, widths);
    contents = dwt53_signature_sweep_text(entries);
    fid = fopen(path, 'w');
    if fid < 0
        error('dwt53_write_signature_sweep:fileOpen', 'Could not open %s.', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', contents);
    clear cleaner;
end

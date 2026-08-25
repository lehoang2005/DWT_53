function fp = dwt53_file_fingerprint(path)
%DWT53_FILE_FINGERPRINT  Portable deterministic fingerprint for text artifacts.
%
%   fp = DWT53_FILE_FINGERPRINT(path) normalizes CRLF to LF by removing CR,
%   then computes two independent weighted sums modulo 2^32. The result is
%   intended for provenance/diff detection, not cryptographic security.
%
%   fp.text has the stable form HHHHHHHH-HHHHHHHH-BYTES.

    if ~(ischar(path) || (isstring(path) && isscalar(path)))
        error('dwt53_file_fingerprint:badPath', 'path must be a file path.');
    end
    path = char(path);
    fid = fopen(path, 'rb');
    if fid < 0
        error('dwt53_file_fingerprint:fileOpen', 'Could not open %s.', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    bytes = fread(fid, Inf, '*uint8');
    clear cleaner;
    bytes(bytes == 13) = [];  % Normalize CRLF and lone CR to LF convention.

    mod32 = 2^32;
    h1 = 0;
    h2 = 0;
    n = numel(bytes);
    chunk_length = 100000;
    for first = 1:chunk_length:n
        last = min(first + chunk_length - 1, n);
        positions = double(first-1:last-1);
        b = double(bytes(first:last)).';
        w1 = mod(positions, 65521) + 1;
        w2 = mod(40503 .* positions + 17, 65521) + 1;
        h1 = mod(h1 + mod(sum(b .* w1), mod32), mod32);
        h2 = mod(h2 + mod(sum(b .* w2), mod32), mod32);
    end

    fp = struct();
    fp.hash1 = h1;
    fp.hash2 = h2;
    fp.bytes = n;
    fp.text = sprintf('%08X-%08X-%d', h1, h2, n);
    fp.normalization = 'CR removed; LF retained';
    fp.security = 'non-cryptographic provenance fingerprint';
end

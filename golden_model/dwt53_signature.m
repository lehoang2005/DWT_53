function sig = dwt53_signature(values, sample_bits, sample_format, extension_rule, order_label)
%DWT53_SIGNATURE  Reference checkpoint signature for one serialized stream.
%
%   sig = DWT53_SIGNATURE(values, sample_bits, sample_format,
%                         extension_rule, order_label)
%
%   VALUES MUST ALREADY BE IN THE OBSERVED SERIALIZATION ORDER.  For a
%   stored 2D matrix this project's canonical order is row-major:
%       values = reshape(A.', [], 1)
%
%   The returned fields implement DWT53_SYSTEM_SPEC_v0.5 G.3:
%       count : number of accepted samples
%       xor   : rolling bitwise XOR of the sample patterns
%       A     : modulo-2^32 sum of value(v)
%       B     : modulo-2^32 sum of each post-update A
%
%   SAMPLE_FORMAT is 'unsigned' or 'signed'. EXTENSION_RULE is
%   'zero-fill' or 'sign-extend'. Sign extension is only meaningful for a
%   signed stream. ORDER_LABEL is metadata; the function never reorders.
%
%   The current 16-bit RTL checkpoint's sum_acc corresponds to A under
%   'zero-fill'. B is order-sensitive and is only comparable when the RTL
%   checkpoint observes the same order named by ORDER_LABEL.

    if nargin < 3 || isempty(sample_format)
        sample_format = 'signed';
    end
    if nargin < 4 || isempty(extension_rule)
        extension_rule = 'zero-fill';
    end
    if nargin < 5 || isempty(order_label)
        order_label = 'caller-supplied';
    end

    validateattributes(sample_bits, {'numeric'}, ...
        {'scalar','integer','>=',1,'<=',32}, mfilename, 'sample_bits');
    if ~(ischar(sample_format) || (isstring(sample_format) && isscalar(sample_format)))
        error('dwt53_signature:badFormat', 'sample_format must be signed or unsigned.');
    end
    if ~(ischar(extension_rule) || (isstring(extension_rule) && isscalar(extension_rule)))
        error('dwt53_signature:badExtension', ...
            'extension_rule must be zero-fill or sign-extend.');
    end

    sample_format = lower(char(sample_format));
    extension_rule = lower(char(extension_rule));
    order_label = char(order_label);

    if ~ismember(sample_format, {'signed','unsigned'})
        error('dwt53_signature:badFormat', ...
            'sample_format must be ''signed'' or ''unsigned'' (got %s).', sample_format);
    end
    if ~ismember(extension_rule, {'zero-fill','sign-extend'})
        error('dwt53_signature:badExtension', ...
            ['extension_rule must be ''zero-fill'' or ''sign-extend'' ' ...
             '(got %s).'], extension_rule);
    end
    v = double(values(:));
    if any(~isfinite(v)) || any(mod(v, 1) ~= 0)
        error('dwt53_signature:notInteger', ...
            'values must contain only finite integers.');
    end

    if strcmp(sample_format, 'signed')
        lo = -(2^(sample_bits - 1));
        hi = 2^(sample_bits - 1) - 1;
    else
        lo = 0;
        hi = 2^sample_bits - 1;
    end
    if any(v < lo) || any(v > hi)
        error('dwt53_signature:outOfRange', ...
            ['sample outside %d-bit %s range [%d,%d] ' ...
             '(observed min=%d, max=%d).'], ...
            sample_bits, sample_format, lo, hi, min(v), max(v));
    end

    modulus32 = 2^32;
    patterns = mod(v, 2^sample_bits);
    if strcmp(extension_rule, 'zero-fill') || strcmp(sample_format, 'unsigned')
        values32 = patterns;
    else
        values32 = mod(v, modulus32);
    end

    % XOR reduction by bit parity. This avoids relying on integer arithmetic
    % wrap behaviour, which differs between MATLAB numeric classes.
    xor_acc = uint32(0);
    pattern_u = uint32(patterns);
    for bit_index = 1:sample_bits
        if mod(sum(double(bitget(pattern_u, bit_index))), 2) ~= 0
            xor_acc = bitset(xor_acc, bit_index);
        end
    end

    % Compute A and B in bounded chunks. Every chunk sum remains below
    % flintmax, so modulo-2^32 arithmetic is exact in double precision.
    A = 0;
    B = 0;
    chunk_length = 100000;
    for first = 1:chunk_length:numel(values32)
        last = min(first + chunk_length - 1, numel(values32));
        prefix = mod(cumsum(values32(first:last)) + A, modulus32);
        B = mod(B + mod(sum(prefix), modulus32), modulus32);
        A = prefix(end);
    end

    sig = struct();
    sig.count = numel(v);
    sig.xor = double(xor_acc);
    sig.A = A;
    sig.B = B;
    sig.sum = A;  % Compatibility name for the existing RTL sum_acc port.
    sig.bits = sample_bits;
    sig.sample_format = sample_format;
    sig.extension_rule = extension_rule;
    sig.order = order_label;
end

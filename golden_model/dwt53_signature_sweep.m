function entries = dwt53_signature_sweep(streams, widths)
%DWT53_SIGNATURE_SWEEP  Sweep W and extension rule without silent wrapping.
%
%   STREAMS is a struct array with fields name, values, sample_format and
%   order. WIDTHS defaults to [8 13 16], as required by spec Part M.4.
%   Every stream/width/rule combination produces one entry. An unrepresentable
%   stream produces status OUT_OF_RANGE and no wrapped signature.

    if nargin < 2 || isempty(widths)
        widths = [8 13 16];
    end
    validateattributes(widths, {'numeric'}, ...
        {'vector','integer','>=',1,'<=',32}, mfilename, 'widths');
    required = {'name','values','sample_format','order'};
    for r = 1:numel(required)
        if ~isfield(streams, required{r})
            error('dwt53_signature_sweep:missingField', ...
                'streams is missing field %s.', required{r});
        end
    end

    template = struct('stream','','width',0,'extension','','status','', ...
        'count',0,'xor',NaN,'A',NaN,'sum',NaN,'B',NaN, ...
        'observed_min',NaN,'observed_max',NaN,'order','');
    entries = repmat(template, 0, 1);
    rules = {'zero-fill','sign-extend'};
    for s = 1:numel(streams)
        values = double(streams(s).values(:));
        if isempty(values)
            observed_min = NaN;
            observed_max = NaN;
        else
            observed_min = min(values);
            observed_max = max(values);
        end
        for w = widths(:).'
            for e = 1:numel(rules)
                item = template;
                item.stream = char(streams(s).name);
                item.width = w;
                item.extension = rules{e};
                item.count = numel(values);
                item.observed_min = observed_min;
                item.observed_max = observed_max;
                item.order = char(streams(s).order);
                try
                    sig = dwt53_signature(values, w, streams(s).sample_format, ...
                        rules{e}, streams(s).order);
                    item.status = 'VALID';
                    item.xor = sig.xor;
                    item.A = sig.A;
                    item.sum = sig.A;
                    item.B = sig.B;
                catch ME
                    if strcmp(ME.identifier, 'dwt53_signature:outOfRange')
                        item.status = 'OUT_OF_RANGE';
                    else
                        rethrow(ME);
                    end
                end
                entries(end+1, 1) = item; %#ok<AGROW>
            end
        end
    end
end

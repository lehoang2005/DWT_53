function text = dwt53_signature_sweep_text(entries)
%DWT53_SIGNATURE_SWEEP_TEXT  Canonical CSV serialization of sweep entries.

    lines = cell(numel(entries) + 1, 1);
    lines{1} = ['stream,width,extension,status,count,xor,A,sum,B,' ...
        'observed_min,observed_max,order'];
    for i = 1:numel(entries)
        e = entries(i);
        if strcmp(e.status, 'VALID')
            xor_text = sprintf('%08X', e.xor);
            a_text = sprintf('%08X', e.A);
            sum_text = sprintf('%08X', e.sum);
            b_text = sprintf('%08X', e.B);
        else
            xor_text = 'NA';
            a_text = 'NA';
            sum_text = 'NA';
            b_text = 'NA';
        end
        lines{i+1} = sprintf('%s,%d,%s,%s,%d,%s,%s,%s,%s,%g,%g,%s', ...
            csv_atom(e.stream), e.width, csv_atom(e.extension), ...
            csv_atom(e.status), e.count, xor_text, a_text, sum_text, b_text, ...
            e.observed_min, e.observed_max, csv_atom(e.order));
    end
    text = sprintf('%s\n', lines{:});
end

function value = csv_atom(value)
    value = char(value);
    if ~isempty(regexp(value, '[,\r\n"]', 'once'))
        error('dwt53_signature_sweep_text:unsafeValue', ...
            'CSV metadata values must not contain comma, quote or newline.');
    end
end

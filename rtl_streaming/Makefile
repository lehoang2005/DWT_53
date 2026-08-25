TOP      ?= dwt53_streaming_top
VERILATOR?= verilator
RTL_F    ?= rtl_streaming.f

.PHONY: lint clean

lint:
	$(VERILATOR) --lint-only --language 1800-2017 -Wall -Wno-fatal \
		--top-module $(TOP) -f $(RTL_F)

clean:
	rm -rf obj_dir *.vcd *.fst *.log

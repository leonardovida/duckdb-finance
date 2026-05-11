DUCKDB_ROOT ?= $(abspath $(CURDIR)/../duckdb)
EXTENSION_CONFIG ?= $(CURDIR)/extension_config.cmake
BUILD_DIR ?= $(DUCKDB_ROOT)/build/debug
DUCKDB ?= $(BUILD_DIR)/duckdb
EXTENSION_PATH ?= $(BUILD_DIR)/extension/finance/finance.duckdb_extension
EXT_NAME ?= finance
EXT_CONFIG ?= $(EXTENSION_CONFIG)
SMOKE_SQL ?= test/sql/smoke_queries.sql
GOLD_DATASET_SQL ?= test/sql/gold_dataset.sql
GOLD_TEST_SQL ?= test/sql/gold_tests.sql
PERF_OUTPUT ?= /tmp/duckdb-finance-profile.json
DUCKDB_EXTRA_CMAKE_VARIABLES ?= -DBUILD_EXTENSIONS=

.PHONY: debug release test smoke smoke-quiet gold gold-quiet perf check-docs check-docs-site check-tests check-perf-tests check-gs-quant-surface check-release-metadata check ci-static ci-duckdb ci clean

debug:
	$(MAKE) -C $(DUCKDB_ROOT) debug EXTENSION_CONFIGS="$(EXTENSION_CONFIG)" EXTRA_CMAKE_VARIABLES="$(DUCKDB_EXTRA_CMAKE_VARIABLES)"

release:
	$(MAKE) -C $(DUCKDB_ROOT) release EXTENSION_CONFIGS="$(EXTENSION_CONFIG)" EXTRA_CMAKE_VARIABLES="$(DUCKDB_EXTRA_CMAKE_VARIABLES)"

smoke: debug
	{ printf "LOAD '$(EXTENSION_PATH)';\n"; cat $(SMOKE_SQL); } | $(DUCKDB) -unsigned

smoke-quiet: debug
	{ printf "LOAD '$(EXTENSION_PATH)';\n"; cat $(SMOKE_SQL); } | $(DUCKDB) -unsigned >/dev/null

gold: debug
	{ printf "LOAD '$(EXTENSION_PATH)';\n"; cat $(GOLD_DATASET_SQL); printf "\n"; cat $(GOLD_TEST_SQL); } | $(DUCKDB) -unsigned

gold-quiet: debug
	{ printf "LOAD '$(EXTENSION_PATH)';\n"; cat $(GOLD_DATASET_SQL); printf "\n"; cat $(GOLD_TEST_SQL); } | $(DUCKDB) -unsigned >/dev/null

perf: debug
	{ printf "LOAD '$(EXTENSION_PATH)';\n"; printf "PRAGMA enable_profiling='json';\nPRAGMA profiling_output='$(PERF_OUTPUT)';\n"; cat $(GOLD_DATASET_SQL); printf "\n"; cat $(GOLD_TEST_SQL); } | $(DUCKDB) -unsigned

test: smoke gold

check-docs:
	python3 scripts/check_function_docs.py

check-docs-site:
	python3 scripts/check_docs_site.py

check-tests:
	python3 scripts/check_function_tests.py

check-perf-tests:
	python3 scripts/check_function_perf_tests.py

check-gs-quant-surface:
	python3 scripts/check_gs_quant_surface.py

check-release-metadata:
	python3 scripts/check_release_metadata.py

check: check-docs check-docs-site check-tests check-perf-tests check-gs-quant-surface check-release-metadata test

ci-static: check-docs check-docs-site check-tests check-perf-tests check-gs-quant-surface check-release-metadata

ci-duckdb: gold-quiet

ci: ci-static ci-duckdb

clean:
	cmake --build $(BUILD_DIR) --target clean

ifneq ("$(wildcard $(CURDIR)/extension-ci-tools/makefiles/duckdb_extension.Makefile)","")
include extension-ci-tools/makefiles/duckdb_extension.Makefile
endif

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
SQL_TEST_PREAMBLE = printf "LOAD '$(EXTENSION_PATH)';\n.bail on\n"

.PHONY: debug release test smoke smoke-quiet gold gold-quiet perf check-yaml check-docs check-docs-site check-tests check-perf-tests check-function-surface check-function-usability check-release-metadata check ci-static ci-duckdb-smoke ci-duckdb ci clean

debug:
	$(MAKE) -C $(DUCKDB_ROOT) debug EXTENSION_CONFIGS="$(EXTENSION_CONFIG)" EXTRA_CMAKE_VARIABLES="$(DUCKDB_EXTRA_CMAKE_VARIABLES)"

release:
	$(MAKE) -C $(DUCKDB_ROOT) release EXTENSION_CONFIGS="$(EXTENSION_CONFIG)" EXTRA_CMAKE_VARIABLES="$(DUCKDB_EXTRA_CMAKE_VARIABLES)"

smoke: debug
	{ $(SQL_TEST_PREAMBLE); cat $(SMOKE_SQL); } | $(DUCKDB) -unsigned

smoke-quiet: debug
	python3 scripts/run_sql_with_trace.py --duckdb "$(DUCKDB)" --extension "$(EXTENSION_PATH)" "$(SMOKE_SQL)" >/dev/null

gold: debug
	{ $(SQL_TEST_PREAMBLE); cat $(GOLD_DATASET_SQL); printf "\n"; cat $(GOLD_TEST_SQL); } | $(DUCKDB) -unsigned

gold-quiet: debug
	{ $(SQL_TEST_PREAMBLE); cat $(GOLD_DATASET_SQL); printf "\n"; cat $(GOLD_TEST_SQL); } | $(DUCKDB) -unsigned >/dev/null

perf: debug
	{ $(SQL_TEST_PREAMBLE); printf "PRAGMA enable_profiling='json';\nPRAGMA profiling_output='$(PERF_OUTPUT)';\n"; cat $(GOLD_DATASET_SQL); printf "\n"; cat $(GOLD_TEST_SQL); } | $(DUCKDB) -unsigned

test: smoke gold

check-yaml:
	ruby -e 'require "yaml"; Dir[".github/workflows/*.yml", ".github/ISSUE_TEMPLATE/*.yml"].each { |f| YAML.load_file(f); puts "ok #{f}" }'

check-docs:
	python3 scripts/check_function_docs.py

check-docs-site:
	python3 scripts/check_docs_site.py

check-tests:
	python3 scripts/check_function_tests.py

check-perf-tests:
	python3 scripts/check_function_perf_tests.py

check-function-surface:
	python3 scripts/check_function_surface.py

check-function-usability:
	python3 scripts/check_function_usability.py

check-release-metadata:
	python3 scripts/check_release_metadata.py

check: check-yaml check-docs check-docs-site check-tests check-perf-tests check-function-surface check-function-usability check-release-metadata test

ci-static: check-yaml check-docs check-docs-site check-tests check-perf-tests check-function-surface check-function-usability check-release-metadata

ci-duckdb-smoke: smoke-quiet

ci-duckdb: gold-quiet

ci: ci-static ci-duckdb

clean:
	cmake --build $(BUILD_DIR) --target clean

ifneq ("$(wildcard $(CURDIR)/extension-ci-tools/makefiles/duckdb_extension.Makefile)","")
include extension-ci-tools/makefiles/duckdb_extension.Makefile

set_duckdb_version:
	if [ ! -d duckdb/.git ]; then \
		git clone --depth=1 --branch "$(DUCKDB_GIT_VERSION)" https://github.com/duckdb/duckdb.git duckdb; \
	else \
		cd duckdb && git fetch --tags --depth=1 origin "$(DUCKDB_GIT_VERSION)" && git checkout "$(DUCKDB_GIT_VERSION)"; \
	fi
endif

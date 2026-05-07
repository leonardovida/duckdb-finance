DUCKDB_ROOT ?= $(abspath $(CURDIR)/../duckdb)
EXTENSION_CONFIG ?= $(CURDIR)/extension_config.cmake
BUILD_DIR ?= $(DUCKDB_ROOT)/build/debug
DUCKDB ?= $(BUILD_DIR)/duckdb
EXTENSION_PATH ?= $(BUILD_DIR)/extension/finance/finance.duckdb_extension
SMOKE_SQL ?= test/sql/smoke_queries.sql
GOLD_DATASET_SQL ?= test/sql/gold_dataset.sql
GOLD_TEST_SQL ?= test/sql/gold_tests.sql
DUCKDB_EXTRA_CMAKE_VARIABLES ?= -DBUILD_EXTENSIONS=

.PHONY: debug release test smoke gold check-docs check clean

debug:
	$(MAKE) -C $(DUCKDB_ROOT) debug EXTENSION_CONFIGS="$(EXTENSION_CONFIG)" EXTRA_CMAKE_VARIABLES="$(DUCKDB_EXTRA_CMAKE_VARIABLES)"

release:
	$(MAKE) -C $(DUCKDB_ROOT) release EXTENSION_CONFIGS="$(EXTENSION_CONFIG)" EXTRA_CMAKE_VARIABLES="$(DUCKDB_EXTRA_CMAKE_VARIABLES)"

smoke: debug
	{ printf "LOAD '$(EXTENSION_PATH)';\n"; cat $(SMOKE_SQL); } | $(DUCKDB) -unsigned

gold: debug
	{ printf "LOAD '$(EXTENSION_PATH)';\n"; cat $(GOLD_DATASET_SQL); printf "\n"; cat $(GOLD_TEST_SQL); } | $(DUCKDB) -unsigned

test: smoke gold

check-docs:
	python3 scripts/check_function_docs.py

check: check-docs test

clean:
	cmake --build $(BUILD_DIR) --target clean

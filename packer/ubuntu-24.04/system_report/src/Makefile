# Makefile for system_report standalone zipapp
# -----------------------------------------------------------

# Name of the final pyz
APP = system_report.pyz

# Source directory (top-level folder containing system_report/)
SRC_DIR = .

# Output directory for build artifacts
BUILD_DIR = build

# Python interpreter inside the zipapp
PY = /usr/bin/env python3

# -----------------------------------------------------------
# CLEAN BUILD DIRECTORY
# -----------------------------------------------------------

clean:
	@rm -rf $(BUILD_DIR)
	@rm -f $(APP)

# -----------------------------------------------------------
# COPY SOURCE TO BUILD DIR
# -----------------------------------------------------------

prepare:
	@mkdir -p $(BUILD_DIR)
	@cp -r $(SRC_DIR)/system_report $(BUILD_DIR)/
	@cp $(SRC_DIR)/system_report/__main__.py $(BUILD_DIR)/ 2>/dev/null || true

# -----------------------------------------------------------
# REMOVE __pycache__ DIRECTORIES
# -----------------------------------------------------------

cleanpyc:
	@find $(BUILD_DIR) -name "__pycache__" -type d -exec rm -rf {} +

# -----------------------------------------------------------
# BUILD ZIPAPP (STANDALONE)
# -----------------------------------------------------------

build: clean prepare cleanpyc
	@python3 -m zipapp $(BUILD_DIR) -o $(APP) --python "$(PY)"

# -----------------------------------------------------------
# CONVENIENCE TARGET
# -----------------------------------------------------------

all: build

# -----------------------------------------------------------
# Run directly
# -----------------------------------------------------------

run:
	@sudo python3 ./$(APP) --cis-mode 1 --out-dir /tmp/report

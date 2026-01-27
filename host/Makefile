BUILD_DIR := ../build/host
CC := gcc
CFLAGS := -g -O0 -Wall -Wextra -Iinclude
SRC := $(wildcard src/*.c)
OUT := $(BUILD_DIR)/host_app

.PHONY: all clean compdb

all: $(OUT)

$(OUT): $(SRC)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -o $@ $^

clean:
	rm -rf $(BUILD_DIR)

# Generate compile_commands.json for host
compdb:
	@mkdir -p $(BUILD_DIR)
	@rm -f $(BUILD_DIR)/compile_commands.json
	@cd .. && bear -- make -C host
	@mv ../compile_commands.json $(BUILD_DIR)/compile_commands.json 2>/dev/null || true


#TODO: Make this less coupled on hard implementation of archetecture, extract implementation for FBC
BUILD_DIR := ../build/target

# Toolchain
CC      := arm-none-eabi-gcc
OBJCOPY := arm-none-eabi-objcopy
SIZE    := arm-none-eabi-size

# MCU (STM32F411RE = Cortex-M4F)
MCUFLAGS := -mcpu=cortex-m4 -mthumb -mfpu=fpv4-sp-d16 -mfloat-abi=hard

# C/ASM flags for bare-metal
CFLAGS := -g -O0 -Wall -Wextra \
  -ffreestanding -fdata-sections -ffunction-sections \
  -fno-builtin \
  $(MCUFLAGS)

# Define the specific STM32F4 device family variant
# (Cube headers expect one of these to pick the right device header)
CFLAGS += -DSTM32F411xE

# Include paths (match your current layout)
# - CMSIS Core: provides core_cm4.h
# - CMSIS Device: provides stm32f4xx.h, stm32f411xe.h
# - system/Inc: if system_stm32f4xx.c includes headers from there
INCLUDES := \
  -Iinclude \
  -Istm32/system/Inc \
  -Istm32/cmsis/Drivers/CMSIS/Include \
  -Istm32/cmsis/Drivers/CMSIS/Device/ST/STM32F4xx/Include

# Linker script + link flags
LDSCRIPT := stm32/linker/STM32F411XX_FLASH.ld
LDFLAGS := $(MCUFLAGS) \
  -T$(LDSCRIPT) \
  -Wl,-Map=$(BUILD_DIR)/firmware.map \
  -Wl,--gc-sections \
  -nostartfiles

# Sources
APP_SRC := $(wildcard src/*.c)
SYS_SRC := stm32/system/system_stm32f4xx.c
STARTUP := stm32/startup/startup_stm32f411xe.s

# Objects
APP_OBJ := $(patsubst src/%.c,$(BUILD_DIR)/src/%.o,$(APP_SRC))
SYS_OBJ := $(patsubst stm32/system/%.c,$(BUILD_DIR)/stm32/system/%.o,$(SYS_SRC))
STARTUP_OBJ := $(patsubst stm32/startup/%.s,$(BUILD_DIR)/stm32/startup/%.o,$(STARTUP))

OBJ := $(APP_OBJ) $(SYS_OBJ) $(STARTUP_OBJ)

# Outputs
ELF := $(BUILD_DIR)/firmware.elf
BIN := $(BUILD_DIR)/firmware.bin
HEX := $(BUILD_DIR)/firmware.hex

.PHONY: all clean compdb

all: $(ELF) $(BIN) $(HEX)
	@$(SIZE) $(ELF)

# Compile C sources
$(BUILD_DIR)/src/%.o: src/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

$(BUILD_DIR)/stm32/system/%.o: stm32/system/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

# Assemble startup
$(BUILD_DIR)/stm32/startup/%.o: stm32/startup/%.s
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

# Link ELF
$(ELF): $(OBJ)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(OBJ) $(LDFLAGS) -o $@

# Convert to binary/hex
$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(HEX): $(ELF)
	$(OBJCOPY) -O ihex $< $@

clean:
	rm -rf $(BUILD_DIR)

# Bear compile database (forces rebuild so Bear sees commands)
compdb: clean
	@mkdir -p $(BUILD_DIR)
	@cd .. && bear -- make -C target
	@mv ../compile_commands.json $(BUILD_DIR)/compile_commands.json 2>/dev/null || true


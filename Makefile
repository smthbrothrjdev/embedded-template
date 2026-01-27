.PHONY: host target clean switch-host switch-target

host:
	@$(MAKE) -C host

target:
	@$(MAKE) -C target

clean:
	@$(MAKE) -C host clean || true
	@$(MAKE) -C target clean || true
	@rm -rf build/host build/target

# These make clangd “switch brains” by pointing compile_commands.json
switch-host: host
	@mkdir -p build/host
	@ln -sf build/host/compile_commands.json compile_commands.json
	@echo "Now using HOST compile_commands.json"

switch-target: target
	@mkdir -p build/target
	@ln -sf build/target/compile_commands.json compile_commands.json
	@echo "Now using TARGET compile_commands.json"


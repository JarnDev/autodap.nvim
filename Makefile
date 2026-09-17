.PHONY: test
test:
	nvim --headless -u tests/minimal_init.lua -l tests/run.lua

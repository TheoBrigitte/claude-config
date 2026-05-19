.PHONY: install uninstall

install:
	ln --symbolic --relative --interactive --no-dereference --no-target-directory $(CURDIR)/.claude $(HOME)/.claude
	ln --symbolic --relative --interactive --no-dereference --no-target-directory $(CURDIR)/.claude.json $(HOME)/.claude.json

uninstall:
	rm --interactive $(HOME)/.claude $(HOME)/.claude.json

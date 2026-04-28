REPO_REL := $(shell realpath --relative-to=$(HOME) $(CURDIR))

.PHONY: install uninstall

install:
	ln -sin $(REPO_REL)/.claude $(HOME)/.claude
	ln -sin $(REPO_REL)/.claude.giantswarm_subscription.json $(HOME)/.claude.json

uninstall:
	rm -i $(HOME)/.claude $(HOME)/.claude.json

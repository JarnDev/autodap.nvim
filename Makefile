.PHONY: test docs docs-check release release-dry

PANVIMDOC_DIR := .deps/panvimdoc
# Pin every input to the doc generation so `make docs` is deterministic and
# byte-identical between your machine and CI: the pandoc image, the panvimdoc
# version, and the "Last change" date (taken from the last commit via git rather
# than the wall clock, so CI reproduces it whatever day it runs).
PANDOC_IMAGE   := pandoc/core:3.11
PANVIMDOC_REF  := v5.0.0
DOCDATE        := $(shell git log -1 --format=%cd --date=format:'%Y %B %d' 2>/dev/null || date -u '+%Y %B %d')

test:
	nvim --headless -u tests/minimal_init.lua -l tests/run.lua

# Cut a release: bump CHANGELOG, then create a signed commit and signed tag.
# The tag is NOT pushed for you — review, then `git push origin main vX.Y.Z`,
# which triggers the release workflow. Usage: make release VERSION=X.Y.Z
release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=X.Y.Z"; exit 1; }
	@scripts/release.sh "$(VERSION)"

# Preview the CHANGELOG bump without touching anything. Usage: make release-dry VERSION=X.Y.Z
release-dry:
	@test -n "$(VERSION)" || { echo "usage: make release-dry VERSION=X.Y.Z"; exit 1; }
	@scripts/release.sh --dry-run "$(VERSION)"

# Regenerate doc/autodap.txt from README.md. CI runs this exact target (not a
# third-party action) and diffs the result, so the output is byte-identical to
# what CI checks. Runs pandoc in Docker so no local pandoc install is needed;
# --user keeps the generated file owned by you rather than root.
docs: $(PANVIMDOC_DIR)
	@mkdir -p doc
	docker run --rm --user "$(shell id -u):$(shell id -g)" \
		-v "$(CURDIR)":/work -v "$(CURDIR)/$(PANVIMDOC_DIR)":/pv -w /work $(PANDOC_IMAGE) \
		--citeproc --shift-heading-level-by=0 \
		--metadata=project:autodap --metadata="vimversion:Neovim >= 0.10" \
		--metadata=toc:true --metadata=description: \
		--metadata="titledatepattern:%Y %B %d" --metadata=date="$(DOCDATE)" \
		--metadata=dedupsubheadings:true --metadata=ignorerawblocks:true \
		--metadata=docmapping:false --metadata=docmappingproject:true \
		--metadata=treesitter:true --metadata=incrementheadinglevelby:0 \
		--lua-filter=/pv/scripts/include-files.lua \
		--lua-filter=/pv/scripts/skip-blocks.lua \
		--data-dir=/pv/lib \
		--lua-filter=/pv/scripts/remove-emojis.lua \
		-t /pv/scripts/panvimdoc.lua README.md -o doc/autodap.txt
	@echo "doc/autodap.txt regenerated — commit it alongside the README change."

# Fails when the committed vimdoc is stale. CI runs this instead of pushing a
# commit of its own, so every commit in the history stays signed by a human.
docs-check: docs
	@git diff --exit-code -- doc/ \
		|| (echo "doc/autodap.txt is out of date. Run 'make docs' and commit the result."; exit 1)

$(PANVIMDOC_DIR):
	git clone --depth 1 --branch $(PANVIMDOC_REF) https://github.com/kdheepak/panvimdoc $@

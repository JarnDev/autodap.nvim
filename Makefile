.PHONY: test docs docs-check release release-dry

PANVIMDOC_DIR := .deps/panvimdoc
PANDOC_IMAGE  := pandoc/core:latest

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

# Regenerate doc/autodap.txt from README.md, byte-identical to what CI checks.
# Runs pandoc in Docker so no local pandoc install is needed; --user keeps the
# generated file owned by you rather than root.
#
# nodate:true drops panvimdoc's "Last change: <today>" stamp from the title line.
# Without it the output depends on the clock, so docs-check compares the docs
# *and* the date: a README change regenerated one day fails the check the next,
# on that one line. The same flag has to be set in
# .github/workflows/panvimdoc.yml (as `nodate: true`) or the two disagree again.
docs: $(PANVIMDOC_DIR)
	@mkdir -p doc
	docker run --rm --user "$(shell id -u):$(shell id -g)" \
		-v "$(CURDIR)":/work -v "$(CURDIR)/$(PANVIMDOC_DIR)":/pv -w /work $(PANDOC_IMAGE) \
		--citeproc --shift-heading-level-by=0 \
		--metadata=project:autodap --metadata="vimversion:Neovim >= 0.10" \
		--metadata=toc:true --metadata=description: \
		--metadata=nodate:true --metadata="titledatepattern:%Y %B %d" \
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
	git clone --depth 1 https://github.com/kdheepak/panvimdoc $@

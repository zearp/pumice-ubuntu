# ubuntu/debian or compatible build host required, usage:
#   make            # -> ./outdir/*.iso
#   make clean      # remove build dir + outdir

DESCRIPTION := .
BUILD_DIR   := build-tmp
OUTDIR      := outdir

.PHONY: all build bundle clean

all: bundle

config-cdroot.tar: config-cdroot/casper/install-sources.yaml
	tar -C config-cdroot -cf config-cdroot.tar casper

build: config-cdroot.tar
	sudo kiwi-ng --color-output --profile Live --type iso system build \
		--description $(DESCRIPTION) \
		--target-dir $(BUILD_DIR)

bundle: build
	sudo kiwi-ng result bundle --target-dir $(BUILD_DIR) --bundle-dir $(OUTDIR) --id build
	sudo sh -c 'for f in $(OUTDIR)/pumice_ubuntu.*; do \
		mv "$$f" "$(OUTDIR)/$$(basename "$$f" | sed "s/^pumice_ubuntu\.x86_64-26\.04-build/Pumice-Ubuntu-26_04-x86_64/")"; \
	done'

clean:
	sudo rm -rf $(BUILD_DIR) $(OUTDIR)
	rm -f config-cdroot.tar

APP     := Ledge.app
CONTENT := $(APP)/Contents
CONFIG  ?= release

.PHONY: all build app intents run stop clean test install-cli dist

all: app

## Compile every target.
build:
	swift build -c $(CONFIG)

## Assemble a launchable .app bundle around the compiled binaries.
app: build
	@rm -rf $(APP)
	@mkdir -p $(CONTENT)/MacOS $(CONTENT)/Helpers $(CONTENT)/Resources
	@cp .build/$(CONFIG)/Ledge $(CONTENT)/MacOS/Ledge
	@# The CLI ships inside the bundle so `ledge` is always the same build as
	@# the app it talks to. It lives in Helpers/, NOT MacOS/: macOS filesystems
	@# are case-insensitive, so MacOS/ledge and MacOS/Ledge are the same file
	@# and the copy would silently clobber the app binary.
	@cp .build/$(CONFIG)/ledge-cli $(CONTENT)/Helpers/ledge
	@cp Resources/Info.plist $(CONTENT)/Info.plist
	@cp Resources/AppIcon.icns $(CONTENT)/Resources/AppIcon.icns
	@$(MAKE) --no-print-directory intents
	@codesign --force --sign - $(CONTENT)/Helpers/ledge >/dev/null 2>&1 || true
	@codesign --force --sign - $(APP) >/dev/null 2>&1 || true
	@echo "Built $(APP)"

## Extract App Intents metadata so Shortcuts and Siri can find the actions.
##
## Xcode does this automatically; SwiftPM doesn't, so we drive the same
## toolchain tool by hand against the const-value files the compiler already
## emitted. Non-fatal: without it the app still works, you just build your
## shortcuts around the `ledge` CLI instead.
intents:
	@find Sources/Ledge -name '*.swift' > /tmp/ledge-intent-srcs.txt
	@find .build -path '*$(shell echo $(CONFIG) | awk '{print toupper(substr($$0,1,1)) substr($$0,2)}')/Ledge-p.build*' \
		-name '*.swiftconstvalues' > /tmp/ledge-intent-consts.txt 2>/dev/null || true
	@if [ -s /tmp/ledge-intent-consts.txt ]; then \
		xcrun appintentsmetadataprocessor \
			--toolchain-dir "$$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
			--module-name Ledge \
			--sdk-root "$$(xcrun --show-sdk-path)" \
			--xcode-version "$$(xcodebuild -version | head -1 | awk '{print $$2}')" \
			--platform-family macOS \
			--deployment-target 14.0 \
			--bundle-identifier dev.ledge.Ledge \
			--output $(CONTENT)/Resources \
			--target-triple arm64-apple-macos14.0 \
			--binary-file $(CONTENT)/MacOS/Ledge \
			--source-file-list /tmp/ledge-intent-srcs.txt \
			--swift-const-vals-list /tmp/ledge-intent-consts.txt >/dev/null 2>&1 \
			&& echo "  App Intents metadata embedded" \
			|| echo "  App Intents metadata skipped (Shortcuts can still call the ledge CLI)"; \
	else \
		echo "  App Intents metadata skipped (no const values found)"; \
	fi

## Rebuild and relaunch, replacing any running copy.
run: stop app
	@open $(APP)
	@echo "Ledge is running. Look up."

stop:
	@pkill -x Ledge 2>/dev/null || true
	@# Wait for it to actually exit. Launching a new copy while the old one is
	@# still tearing down races over the socket file.
	@for i in $$(seq 1 40); do pgrep -x Ledge >/dev/null || break; sleep 0.1; done

test:
	swift test

## Put `ledge` on your PATH. Prints the command rather than running it, so you
## can read what you're about to sudo.
install-cli: app
	@echo "Run this to add ledge to your PATH:"
	@echo "  sudo ln -sf \"$(CURDIR)/$(CONTENT)/Helpers/ledge\" /usr/local/bin/ledge"

## Zip the app for distribution, preserving signatures and symlinks.
dist: app
	@mkdir -p dist
	@ditto -c -k --keepParent $(APP) dist/Ledge-$$(defaults read "$(CURDIR)/Resources/Info" CFBundleShortVersionString).zip
	@ls -lh dist/

clean:
	@rm -rf .build $(APP) dist

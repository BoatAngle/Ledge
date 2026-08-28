APP     := Islet.app
CONTENT := $(APP)/Contents
CONFIG  ?= release

.PHONY: all build app intents run stop clean test install-cli

all: app

## Compile every target.
build:
	swift build -c $(CONFIG)

## Assemble a launchable .app bundle around the compiled binaries.
app: build
	@rm -rf $(APP)
	@mkdir -p $(CONTENT)/MacOS $(CONTENT)/Helpers $(CONTENT)/Resources
	@cp .build/$(CONFIG)/Islet $(CONTENT)/MacOS/Islet
	@# The CLI ships inside the bundle so `islet` is always the same build as
	@# the app it talks to. It lives in Helpers/, NOT MacOS/: macOS filesystems
	@# are case-insensitive, so MacOS/islet and MacOS/Islet are the same file
	@# and the copy would silently clobber the app binary.
	@cp .build/$(CONFIG)/islet-cli $(CONTENT)/Helpers/islet
	@cp Resources/Info.plist $(CONTENT)/Info.plist
	@cp Resources/AppIcon.icns $(CONTENT)/Resources/AppIcon.icns
	@$(MAKE) --no-print-directory intents
	@codesign --force --sign - $(CONTENT)/Helpers/islet >/dev/null 2>&1 || true
	@codesign --force --sign - $(APP) >/dev/null 2>&1 || true
	@echo "Built $(APP)"

## Extract App Intents metadata so Shortcuts and Siri can find the actions.
##
## Xcode does this automatically; SwiftPM doesn't, so we drive the same
## toolchain tool by hand against the const-value files the compiler already
## emitted. Non-fatal: without it the app still works, you just build your
## shortcuts around the `islet` CLI instead.
intents:
	@find Sources/Islet -name '*.swift' > /tmp/islet-intent-srcs.txt
	@find .build -path '*$(shell echo $(CONFIG) | awk '{print toupper(substr($$0,1,1)) substr($$0,2)}')/Islet-p.build*' \
		-name '*.swiftconstvalues' > /tmp/islet-intent-consts.txt 2>/dev/null || true
	@if [ -s /tmp/islet-intent-consts.txt ]; then \
		xcrun appintentsmetadataprocessor \
			--toolchain-dir "$$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
			--module-name Islet \
			--sdk-root "$$(xcrun --show-sdk-path)" \
			--xcode-version "$$(xcodebuild -version | head -1 | awk '{print $$2}')" \
			--platform-family macOS \
			--deployment-target 14.0 \
			--bundle-identifier dev.islet.Islet \
			--output $(CONTENT)/Resources \
			--target-triple arm64-apple-macos14.0 \
			--binary-file $(CONTENT)/MacOS/Islet \
			--source-file-list /tmp/islet-intent-srcs.txt \
			--swift-const-vals-list /tmp/islet-intent-consts.txt >/dev/null 2>&1 \
			&& echo "  App Intents metadata embedded" \
			|| echo "  App Intents metadata skipped (Shortcuts can still call the islet CLI)"; \
	else \
		echo "  App Intents metadata skipped (no const values found)"; \
	fi

## Rebuild and relaunch, replacing any running copy.
run: stop app
	@open $(APP)
	@echo "Islet is running. Look up."

stop:
	@pkill -x Islet 2>/dev/null || true
	@# Wait for it to actually exit. Launching a new copy while the old one is
	@# still tearing down races over the socket file.
	@for i in $$(seq 1 40); do pgrep -x Islet >/dev/null || break; sleep 0.1; done

test:
	swift test

## Put `islet` on your PATH. Prints the command rather than running it, so you
## can read what you're about to sudo.
install-cli: app
	@echo "Run this to add islet to your PATH:"
	@echo "  sudo ln -sf \"$(CURDIR)/$(CONTENT)/Helpers/islet\" /usr/local/bin/islet"

clean:
	@rm -rf .build $(APP)

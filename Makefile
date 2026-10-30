.PHONY: build run install clean test

DERIVED=build
APP=$(DERIVED)/Build/Products/Debug/Altitude.app
RELEASE_APP=$(DERIVED)/Build/Products/Release/Altitude.app
INSTALL_APP=/Applications/Altitude.app

# Local signing identity (untracked). Copy .env.example → .env and set SIGN_ID.
ifneq (,$(wildcard .env))
include .env
endif

# A stable identity keeps the Accessibility grant across rebuilds.
# Set SIGN_ID in .env, or override with `make SIGN_ID=...`.
SIGN_ID ?=

# Unsigned Domain XCTest suite (no SIGN_ID). Prefer this for local/CI verification.
test:
	xcodebuild test -project Altitude.xcodeproj -scheme Altitude -configuration Debug -derivedDataPath $(DERIVED) -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

build:
ifndef SIGN_ID
	$(error SIGN_ID is not set. Copy .env.example to .env and set your Apple Development identity.)
endif
	xcodebuild -project Altitude.xcodeproj -scheme Altitude -configuration Debug -derivedDataPath $(DERIVED) CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES
	@for bin in $(APP)/Contents/MacOS/*; do \
		codesign --force --sign "$(SIGN_ID)" --options runtime "$$bin"; \
	done
	codesign --force --sign "$(SIGN_ID)" --options runtime \
		--entitlements Altitude/Altitude.entitlements \
		$(APP)

run: build
	open $(APP)

# Force-quit running instances, Release-build + sign, install to /Applications, open.
# Does not touch git — the caller owns the working tree.
install:
ifndef SIGN_ID
	$(error SIGN_ID is not set. Copy .env.example to .env and set your Apple Development identity.)
endif
	@echo "Quitting Altitude…"
	-osascript -e 'tell application "Altitude" to quit' 2>/dev/null || true
	@sleep 0.5
	-pkill -x Altitude 2>/dev/null || true
	@sleep 0.3
	xcodebuild -project Altitude.xcodeproj -scheme Altitude -configuration Release -derivedDataPath $(DERIVED) CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES
	@for bin in $(RELEASE_APP)/Contents/MacOS/*; do \
		codesign --force --sign "$(SIGN_ID)" --options runtime "$$bin"; \
	done
	codesign --force --sign "$(SIGN_ID)" --options runtime \
		--entitlements Altitude/Altitude.entitlements \
		$(RELEASE_APP)
	rm -rf $(INSTALL_APP)
	cp -R $(RELEASE_APP) $(INSTALL_APP)
	open $(INSTALL_APP)

clean:
	rm -rf $(DERIVED)

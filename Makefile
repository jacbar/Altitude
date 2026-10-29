.PHONY: build run clean

DERIVED=build
APP=$(DERIVED)/Build/Products/Debug/Altitude.app

# Local signing identity (untracked). Copy .env.example → .env and set SIGN_ID.
ifneq (,$(wildcard .env))
include .env
endif

# A stable identity keeps the Accessibility grant across rebuilds.
# Set SIGN_ID in .env, or override with `make SIGN_ID=...`.
SIGN_ID ?=

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

clean:
	rm -rf $(DERIVED)

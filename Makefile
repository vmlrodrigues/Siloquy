WHISPER_CPP_DIR := $(HOME)/Code/opensource/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build

# ── Release configuration ─────────────────────────────────────────────────────
RELEASE_SIGN_IDENTITY    := Developer ID Application: Victor Rodrigues (9N354A3UZK)
RELEASE_TEAM             := 9N354A3UZK
RELEASE_PROFILE_UUID     := f8dcb4b0-e37c-4257-9642-bc80baf94376
NOTARIZE_PROFILE         := siloquy-notarization
RELEASE_DERIVED_DATA     := $(CURDIR)/.release-build
RELEASE_STAGING          := $(CURDIR)/.release-staging
DMG_NAME                 := Siloquy-$(VERSION).dmg

.PHONY: all clean whisper setup build local check healthcheck help dev run release

# Default target
all: check build

# Development workflow
dev: build run

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Build process
whisper:
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(WHISPER_CPP_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		else \
			(cd $(WHISPER_CPP_DIR) && git pull); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
	else \
		echo "whisper.xcframework already built at $(FRAMEWORK_PATH), skipping build"; \
	fi

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project Siloquy.xcodeproj -scheme Siloquy -configuration Debug CODE_SIGN_IDENTITY="" build

# Build for local use — ad-hoc build, then re-signed with Apple Development cert via codesign.
# Re-signing gives a stable identity so Accessibility/Microphone permissions survive rebuilds.
local: check setup
	@echo "Building Siloquy..."
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	GIT_LFS_SKIP_SMUDGE=1 xcodebuild -project Siloquy.xcodeproj -scheme Siloquy -configuration Debug \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/Siloquy/Siloquy.local.entitlements" \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Debug/Siloquy.app" && \
	if [ -d "$$APP_PATH" ]; then \
		echo "Copying Siloquy.app to ~/Downloads..."; \
		rm -rf "$$HOME/Downloads/Siloquy.app"; \
		ditto "$$APP_PATH" "$$HOME/Downloads/Siloquy.app"; \
		xattr -cr "$$HOME/Downloads/Siloquy.app"; \
		echo "Re-signing with Apple Development certificate..."; \
		codesign --force --deep \
			--sign "Apple Development: Victor Rodrigues (BWSYTSDVGC)" \
			--entitlements "$(CURDIR)/Siloquy/Siloquy.local.entitlements" \
			"$$HOME/Downloads/Siloquy.app"; \
		echo ""; \
		echo "Build complete! App saved to: ~/Downloads/Siloquy.app"; \
		echo "Run with: open ~/Downloads/Siloquy.app"; \
		echo ""; \
		echo "Note: Permissions (Accessibility, Microphone, etc.) will persist across rebuilds."; \
		echo "No automatic updates (pull new code and rebuild to update)."; \
	else \
		echo "Error: Could not find built Siloquy.app at $$APP_PATH"; \
		exit 1; \
	fi

# Run application
run:
	@if [ -d "$$HOME/Downloads/Siloquy.app" ]; then \
		echo "Opening ~/Downloads/Siloquy.app..."; \
		open "$$HOME/Downloads/Siloquy.app"; \
	else \
		echo "Looking for Siloquy.app in DerivedData..."; \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "Siloquy.app" -type d | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "Siloquy.app not found. Please run 'make build' or 'make local' first."; \
			exit 1; \
		fi; \
	fi

# Distribution build — sign with Developer ID, package DMG, notarise, publish GitHub Release.
# Usage: make release VERSION=1.2.3
release: check setup
	@[ -n "$(VERSION)" ] || { echo "Error: VERSION is required.  Usage: make release VERSION=x.y.z"; exit 1; }
	@command -v create-dmg >/dev/null 2>&1 || { echo "create-dmg not found — run: brew install create-dmg"; exit 1; }
	@command -v gh >/dev/null 2>&1 || { echo "gh not found — run: brew install gh"; exit 1; }
	@security find-identity -v -p codesigning | grep -q "$(RELEASE_SIGN_IDENTITY)" || \
		{ echo "Error: Developer ID Application certificate not found in keychain."; \
		  echo "Expected: \"$(RELEASE_SIGN_IDENTITY)\""; exit 1; }
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  Building Siloquy $(VERSION) for distribution"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""

	@echo "→ Cleaning previous release artifacts..."
	@rm -rf "$(RELEASE_DERIVED_DATA)" "$(RELEASE_STAGING)"
	@rm -f "$(DMG_NAME)"
	@mkdir -p "$(RELEASE_STAGING)"

	@echo "→ Building (Release · Developer ID · Hardened Runtime)..."
	GIT_LFS_SKIP_SMUDGE=1 xcodebuild \
		-project Siloquy.xcodeproj \
		-scheme Siloquy \
		-configuration Release \
		-derivedDataPath "$(RELEASE_DERIVED_DATA)" \
		CODE_SIGN_IDENTITY="$(RELEASE_SIGN_IDENTITY)" \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGNING_REQUIRED=YES \
		DEVELOPMENT_TEAM="$(RELEASE_TEAM)" \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/Siloquy/Siloquy.entitlements" \
		ENABLE_HARDENED_RUNTIME=YES \
		OTHER_CODE_SIGN_FLAGS="--timestamp" \
		ONLY_ACTIVE_ARCH=NO \
		MACOSX_DEPLOYMENT_TARGET=14.0 \
		MARKETING_VERSION="$(VERSION)" \
		build

	@APP_PATH="$(RELEASE_DERIVED_DATA)/Build/Products/Release/Siloquy.app" && \
	[ -d "$$APP_PATH" ] || { echo "Error: build succeeded but Siloquy.app not found at $$APP_PATH"; exit 1; } && \
	echo "→ Copying app to staging..." && \
	ditto "$$APP_PATH" "$(RELEASE_STAGING)/Siloquy.app"

	@echo "→ Re-signing Sparkle with Developer ID (inside-out)..."
	@APP="$(RELEASE_STAGING)/Siloquy.app" && \
	SPARKLE="$$APP/Contents/Frameworks/Sparkle.framework/Versions/B" && \
	IDENTITY="$(RELEASE_SIGN_IDENTITY)" && \
	codesign --force --sign "$$IDENTITY" --timestamp --options runtime \
		"$$SPARKLE/XPCServices/Downloader.xpc" && \
	codesign --force --sign "$$IDENTITY" --timestamp --options runtime \
		"$$SPARKLE/XPCServices/Installer.xpc" && \
	codesign --force --sign "$$IDENTITY" --timestamp --options runtime \
		"$$SPARKLE/Updater.app" && \
	codesign --force --sign "$$IDENTITY" --timestamp --options runtime \
		"$$SPARKLE/Autoupdate" && \
	codesign --force --sign "$$IDENTITY" --timestamp --options runtime \
		"$$APP/Contents/Frameworks/Sparkle.framework" && \
	codesign --force --sign "$$IDENTITY" --timestamp --options runtime \
		--entitlements "$(CURDIR)/Siloquy/Siloquy.entitlements" \
		"$$APP"

	@echo "→ Creating DMG..."
	create-dmg \
		--volname "Siloquy $(VERSION)" \
		--window-pos 200 120 \
		--window-size 540 380 \
		--icon-size 128 \
		--icon "Siloquy.app" 170 185 \
		--hide-extension "Siloquy.app" \
		--app-drop-link 370 185 \
		"$(DMG_NAME)" \
		"$(RELEASE_STAGING)/"

	@echo "→ Submitting DMG for notarisation (this takes a few minutes)..."
	xcrun notarytool submit "$(DMG_NAME)" \
		--keychain-profile "$(NOTARIZE_PROFILE)" \
		--wait

	@echo "→ Stapling notarisation ticket..."
	xcrun stapler staple "$(DMG_NAME)"

	@echo "→ Verifying with Gatekeeper..."
	@xcrun stapler validate "$(DMG_NAME)" && echo "  Stapler: OK"
	@spctl --assess --type open --context context:primary-signature \
		--ignore-cache "$(RELEASE_STAGING)/Siloquy.app" && \
		echo "  Gatekeeper: OK" || echo "  Warning: Gatekeeper check failed — check entitlements"

	@echo "→ Tagging v$(VERSION) and pushing..."
	git tag "v$(VERSION)"
	git push origin "v$(VERSION)"

	@echo "→ Creating GitHub release v$(VERSION)..."
	gh release create "v$(VERSION)" \
		--title "Siloquy v$(VERSION)" \
		--notes "See [CHANGES.md](CHANGES.md) for what's new." \
		"$(DMG_NAME)"

	@echo "→ Cleaning temporary build directories..."
	@rm -rf "$(RELEASE_DERIVED_DATA)" "$(RELEASE_STAGING)"

	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  Siloquy v$(VERSION) released!"
	@echo "  DMG: $(DMG_NAME)"
	@echo "  https://github.com/vmlrodrigues/Siloquy/releases/tag/v$(VERSION)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Copy whisper XCFramework to Siloquy project"
	@echo "  build              Build the Siloquy Xcode project (Debug, unsigned)"
	@echo "  local              Build for local use, re-sign with Apple Development cert"
	@echo "  release            Build, sign, notarise, and publish a GitHub release"
	@echo "                     Usage: make release VERSION=x.y.z"
	@echo "  run                Launch the built Siloquy app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  all                Run full build process (default)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"
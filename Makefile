WHISPER_CPP_DIR := $(HOME)/Code/opensource/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build
LOCAL_DIST         := $(CURDIR)/.dist
# The dev bundle is named "Siloquy Dev.app" so System Settings privacy panels,
# Finder and Spotlight all label it distinctly from the release "Siloquy.app".
# (The executable inside stays "Siloquy" — it never appears in those panels.)
LOCAL_APP          := $(LOCAL_DIST)/Siloquy Dev.app

# ── Version — single source of truth is the VERSION file ──────────────────────
# Override on the command line if needed: make release VERSION=1.2.3
VERSION ?= $(shell cat $(CURDIR)/VERSION 2>/dev/null || echo "0.0.0")

# ── Release configuration ─────────────────────────────────────────────────────
RELEASE_SIGN_IDENTITY    := Developer ID Application: Victor Rodrigues (9N354A3UZK)
RELEASE_TEAM             := 9N354A3UZK
RELEASE_PROFILE_UUID     := f8dcb4b0-e37c-4257-9642-bc80baf94376
RELEASE_DERIVED_DATA     := $(CURDIR)/.release-build
RELEASE_STAGING          := $(CURDIR)/.release-staging
DMG_NAME                 := Siloquy.dmg
SPARKLE_SIGN_UPDATE      := $(RELEASE_DERIVED_DATA)/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update

.PHONY: all clean whisper setup build local check healthcheck help dev run reset-onboarding reset-dev release deploy-docs

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
	@echo "Quitting any running Siloquy dev instance..."
	@osascript -e 'if application id "com.victorrodrigues.siloquy.dev" is running then tell application id "com.victorrodrigues.siloquy.dev" to quit' 2>/dev/null || true
	@sleep 0.5
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
		MARKETING_VERSION="$(VERSION)-dev" \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Debug/Siloquy.app" && \
	if [ -d "$$APP_PATH" ]; then \
		mkdir -p "$(LOCAL_DIST)"; \
		echo "Copying to .dist/Siloquy Dev.app..."; \
		rm -rf "$(LOCAL_DIST)/Siloquy.app" "$(LOCAL_APP)"; \
		ditto "$$APP_PATH" "$(LOCAL_APP)"; \
		xattr -cr "$(LOCAL_APP)"; \
		echo "Patching CFBundleName to 'Siloquy Dev'..."; \
		/usr/libexec/PlistBuddy -c "Set :CFBundleName 'Siloquy Dev'" \
			"$(LOCAL_APP)/Contents/Info.plist"; \
		echo "Re-signing with Apple Development certificate..."; \
		codesign --force --deep \
			--sign "Apple Development: Victor Rodrigues (BWSYTSDVGC)" \
			--entitlements "$(CURDIR)/Siloquy/Siloquy.local.entitlements" \
			"$(LOCAL_APP)"; \
		echo "Clearing the stray build-output registration (else macOS shows two dock icons)..."; \
		LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"; \
		"$$LSREG" -u "$$APP_PATH" >/dev/null 2>&1 || true; \
		rm -rf "$$APP_PATH"; \
		"$$LSREG" -f "$(LOCAL_APP)" >/dev/null 2>&1 || true; \
		echo ""; \
		echo "Build complete! Run 'make run' to launch."; \
		echo ""; \
		echo "Note: Permissions (Accessibility, Microphone, etc.) will persist across rebuilds."; \
		echo "No automatic updates (pull new code and rebuild to update)."; \
	else \
		echo "Error: Could not find built Siloquy.app at $$APP_PATH"; \
		exit 1; \
	fi

# Run application
run:
	@if [ -d "$(LOCAL_APP)" ]; then \
		echo "Opening .dist/Siloquy Dev.app..."; \
		open "$(LOCAL_APP)"; \
	else \
		echo "Siloquy Dev.app not found. Run 'make local' first."; \
		exit 1; \
	fi

# Reset the dev build's onboarding so the next launch replays the onboarding flow.
# Only touches the dev build's UserDefaults; the release app and your data are untouched.
reset-onboarding:
	@echo "Quitting the dev app (if running)..."
	@osascript -e 'if application id "com.victorrodrigues.siloquy.dev" is running then tell application id "com.victorrodrigues.siloquy.dev" to quit' 2>/dev/null || true
	@pkill -f "Siloquy Dev.app/Contents/MacOS/Siloquy" 2>/dev/null || true
	@n=0; while pgrep -f "Siloquy Dev.app/Contents/MacOS/Siloquy" >/dev/null 2>&1 && [ $$n -lt 25 ]; do sleep 0.2; n=$$((n+1)); done
	@defaults delete com.victorrodrigues.siloquy.dev hasCompletedOnboarding 2>/dev/null || true
	@defaults delete com.victorrodrigues.siloquy.dev onboardingStarted 2>/dev/null || true
	@defaults delete com.victorrodrigues.siloquy.dev onboardingPermissionIndex 2>/dev/null || true
	@echo "Onboarding reset. Run 'make run' to relaunch into the onboarding flow."

# Full from-scratch reset of the DEV build: onboarding flags, the dev app's macOS
# permission grants (Accessibility, Microphone, Screen Recording, Input Monitoring),
# AND the downloaded models (Parakeet + Gemma 4 E2B) so both onboarding download steps
# actually run. The next launch replays onboarding from scratch. Release app untouched.
# NOTE: model files live in shared paths, so this also forces a re-download for release.
reset-dev: reset-onboarding
	@echo "Resetting the dev build's macOS permissions..."
	@tccutil reset All com.victorrodrigues.siloquy.dev >/dev/null 2>&1 || true
	@echo "Deleting onboarding models (Parakeet + Gemma 4 E2B) so the downloads re-run..."
	@rm -rf "$$HOME/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v2"
	@rm -f "$$HOME/Library/Application Support/Siloquy/Models/gemma4-e2b-it.litertlm" "$$HOME/Library/Application Support/Siloquy/Models/"gemma4-e2b-it.litertlm_*.bin "$$HOME/Library/Application Support/Siloquy/Models/gemma3-1b-it-int4-qat.litertlm" 2>/dev/null || true
	@echo "Done. Run 'make run' for a from-scratch onboarding (models re-download, ~2.9 GB)."

# Distribution build — sign with Developer ID, package DMG, notarise, publish GitHub Release.
# Usage: make release VERSION=1.2.3
release: check setup
	@[ -n "$(VERSION)" ] || { echo "Error: VERSION not set. Edit the VERSION file or pass VERSION=x.y.z"; exit 1; }
	@command -v create-dmg >/dev/null 2>&1 || { echo "create-dmg not found — run: brew install create-dmg"; exit 1; }
	@command -v gh >/dev/null 2>&1 || { echo "gh not found — run: brew install gh"; exit 1; }
	@security find-identity -v -p codesigning | grep -q "$(RELEASE_SIGN_IDENTITY)" || \
		{ echo "Error: Developer ID Application certificate not found in keychain."; \
		  echo "Expected: \"$(RELEASE_SIGN_IDENTITY)\""; exit 1; }
	@set -a; . "$(CURDIR)/.env" 2>/dev/null; set +a; \
		if [ -z "$$NOTARY_KEY" ] || [ -z "$$NOTARY_KEY_ID" ] || [ -z "$$NOTARY_ISSUER" ]; then \
			echo "Error: notarisation needs NOTARY_KEY / NOTARY_KEY_ID / NOTARY_ISSUER in .env (copy .env.example)"; exit 1; \
		elif [ ! -f "$$NOTARY_KEY" ]; then \
			echo "Error: NOTARY_KEY file not found: $$NOTARY_KEY"; exit 1; \
		fi
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
		ARCHS=arm64 \
		VALID_ARCHS=arm64 \
		MACOSX_DEPLOYMENT_TARGET=14.0 \
		MARKETING_VERSION="$(VERSION)" \
		CURRENT_PROJECT_VERSION="$(VERSION)" \
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
	@set -a; . "$(CURDIR)/.env"; set +a; \
	xcrun notarytool submit "$(DMG_NAME)" \
		--key "$$NOTARY_KEY" \
		--key-id "$$NOTARY_KEY_ID" \
		--issuer "$$NOTARY_ISSUER" \
		--wait

	@echo "→ Stapling notarisation ticket..."
	xcrun stapler staple "$(DMG_NAME)"

	@echo "→ Verifying with Gatekeeper..."
	@xcrun stapler validate "$(DMG_NAME)" && echo "  Stapler: OK"
	@spctl --assess --type open --context context:primary-signature \
		--ignore-cache "$(RELEASE_STAGING)/Siloquy.app" && \
		echo "  Gatekeeper: OK" || echo "  Warning: Gatekeeper check failed — check entitlements"

	@echo "→ Signing DMG and updating appcast..."
	@SIG_LINE=$$("$(SPARKLE_SIGN_UPDATE)" "$(DMG_NAME)" 2>&1) && \
	SIG=$$(echo "$$SIG_LINE" | awk -F'"' '{print $$2}') && \
	LEN=$$(echo "$$SIG_LINE" | awk -F'"' '{print $$4}') && \
	python3 scripts/update_appcast.py "$(VERSION)" "$$SIG" "$$LEN"
	@git add appcast.xml
	@git commit -m "chore: Update appcast for v$(VERSION)"

	@echo "→ Tagging v$(VERSION) and pushing..."
	git tag "v$(VERSION)"
	git push origin main "v$(VERSION)"

	@echo "→ Creating GitHub release v$(VERSION)..."
	@awk -v ver="$(VERSION)" 'index($$0, "### " ver) == 1 {f=1; next} f && (/^### [0-9]/ || /^---/) {exit} f {print}' CHANGES.md > /tmp/siloquy-release-notes.md
	gh release create "v$(VERSION)" \
		--title "Siloquy v$(VERSION)" \
		--notes-file /tmp/siloquy-release-notes.md \
		"$(DMG_NAME)"
	@rm -f /tmp/siloquy-release-notes.md

	@echo "→ Cleaning temporary build directories..."
	@rm -rf "$(RELEASE_DERIVED_DATA)" "$(RELEASE_STAGING)"

	@echo "→ Deploying docs site..."
	@if [ -f "$(CURDIR)/.env" ]; then \
		bash tools/deploy-docs.sh deploy; \
	else \
		echo "  Skipped: .env not found (copy .env.example to .env to enable)"; \
	fi

	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  Siloquy v$(VERSION) released!"
	@echo "  DMG: $(DMG_NAME)"
	@echo "  https://github.com/vmlrodrigues/Siloquy/releases/tag/v$(VERSION)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Deploy docs site to WebDAV
deploy-docs:
	@[ -f "$(CURDIR)/.env" ] || { echo "Error: .env not found. Copy .env.example to .env and fill in your credentials."; exit 1; }
	@bash tools/deploy-docs.sh deploy

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
	@echo "  reset-onboarding   Reset the dev build's onboarding flow (re-show it)"
	@echo "  reset-dev          Full fresh-install reset (onboarding + permissions + models)"
	@echo "  dev                Build and run the app (for development)"
	@echo "  all                Run full build process (default)"
	@echo "  deploy-docs        Upload docs/ to the configured WebDAV server"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"
WHISPER_CPP_DIR := $(HOME)/Code/opensource/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build

.PHONY: all clean whisper setup build local check healthcheck help dev run

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
	xcodebuild -project Siloquy.xcodeproj -scheme Siloquy -configuration Debug \
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
	@echo "  build              Build the Siloquy Xcode project"
	@echo "  local              Build for local use (no Apple Developer certificate needed)"
	@echo "  run                Launch the built Siloquy app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  all                Run full build process (default)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"
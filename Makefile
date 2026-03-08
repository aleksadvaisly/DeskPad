APP_NAME := DeskPad
SCHEME := $(APP_NAME)
PROJECT := $(APP_NAME).xcodeproj
BUILD_DIR := build
INSTALL_DIR := /Applications
SIGN_FLAGS := CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

.PHONY: build release clean install uninstall

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(BUILD_DIR) $(SIGN_FLAGS)

release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath $(BUILD_DIR) $(SIGN_FLAGS)

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean -derivedDataPath $(BUILD_DIR)
	rm -rf $(BUILD_DIR)

install: release
	@if [ -d "$(INSTALL_DIR)/$(APP_NAME).app" ]; then \
		echo "Removing existing $(APP_NAME).app..."; \
		rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"; \
	fi
	cp -R "$(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app" "$(INSTALL_DIR)/"
	@echo "Installed $(APP_NAME).app to $(INSTALL_DIR)"

uninstall:
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Removed $(APP_NAME).app from $(INSTALL_DIR)"

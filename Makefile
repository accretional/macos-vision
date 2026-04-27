BINARY_DEBUG   = .build/debug/macos-vision
BINARY_RELEASE = .build/release/macos-vision
APP_NAME       = macos-vision.app
APP_BUNDLE     = .build/$(APP_NAME)
INSTALL_PATH   = /usr/local/bin/macos-vision
INSTALL_APP    = /Applications/$(APP_NAME)
ENTITLEMENTS   = macos-vision.entitlements
INFO_PLIST     = Sources/Info.plist

.PHONY: all build release bundle install clean

all: build

build:
	swift build
	codesign --force --sign - --entitlements $(ENTITLEMENTS) $(BINARY_DEBUG)

release:
	swift build -c release
	codesign --force --sign - --entitlements $(ENTITLEMENTS) $(BINARY_RELEASE)

bundle: release
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp $(BINARY_RELEASE) $(APP_BUNDLE)/Contents/MacOS/macos-vision
	cp $(INFO_PLIST) $(APP_BUNDLE)/Contents/Info.plist
	codesign --force --sign - --entitlements $(ENTITLEMENTS) $(APP_BUNDLE)

install: bundle
	@echo "Sudo permissions required to install to $(INSTALL_APP) and $(INSTALL_PATH)"
	sudo rm -rf $(INSTALL_APP)
	sudo cp -R $(APP_BUNDLE) $(INSTALL_APP)
	sudo ln -sf $(INSTALL_APP)/Contents/MacOS/macos-vision $(INSTALL_PATH)

clean:
	swift package clean

BINARY_DEBUG   = .build/debug/macos-vision
BINARY_RELEASE = .build/release/macos-vision
INSTALL_PATH   = /usr/local/bin/macos-vision

.PHONY: all build release install clean

all: build

build:
	swift build

release:
	swift build -c release

install: release
	cp $(BINARY_RELEASE) $(INSTALL_PATH)

clean:
	swift package clean

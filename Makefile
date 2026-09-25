APP_BUNDLE := dist/AI Bar.app

.PHONY: build test app run

build:
	swift build

test:
	swift test

# Assembled by hand rather than via Xcode so the whole project stays a plain Swift package.
app:
	swift build -c release --product AIBar
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	cp "$$(swift build -c release --show-bin-path)/AIBar" "$(APP_BUNDLE)/Contents/MacOS/AIBar"
	cp Support/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"

run: app
	open "$(APP_BUNDLE)"

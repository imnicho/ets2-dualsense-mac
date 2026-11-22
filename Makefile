VERSION := 0.1.2
APP := build/ETS2 DualSense.app
PLUGIN := build/ets2_dualsense.dylib
DMG := build/ETS2-DualSense-$(VERSION).dmg
# Fresh folder per run: the notarized-app export refuses to overwrite an earlier one.
STAGE := build/notarized-$(shell date +%Y%m%d-%H%M%S)

.PHONY: all plugin app dmg archive upload notarized-dmg test clean run

all: app

# The game is x86_64 (it runs under Rosetta), so the plugin must be too.
plugin: $(PLUGIN)
$(PLUGIN): plugin/plugin.cpp shared/ipc.h
	mkdir -p build
	clang++ -std=c++17 -O2 -Wall -Wextra -Wno-unused-parameter -arch x86_64 -mmacosx-version-min=11.0 \
		-dynamiclib -Isdk/include -o $@ plugin/plugin.cpp
	codesign --force -s - $@

app: plugin
	swift build -c release --arch arm64
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$$(swift build -c release --arch arm64 --show-bin-path)/ETS2DualSense" "$(APP)/Contents/MacOS/"
	cp $(PLUGIN) LICENSE packaging/icon/AppIcon.icns "$(APP)/Contents/Resources/"
	sed 's/VERSION/$(VERSION)/' packaging/Info.plist > "$(APP)/Contents/Info.plist"
	codesign --force --deep -s - "$(APP)"

dmg: app
	mkdir -p build/dmg
	rsync -a "$(APP)" build/dmg/
	ln -sfn /Applications build/dmg/Applications
	hdiutil create -volname "ETS2 DualSense" -srcfolder build/dmg -ov -format UDZO $(DMG)

# Sandboxed, team-signed archive for App Store Connect / TestFlight (needs xcodegen and an Xcode account).
archive: plugin
	xcodegen generate
	xcodebuild -project ETS2DualSense.xcodeproj -scheme ETS2DualSenseApp -configuration Release \
		-derivedDataPath build/xcode -archivePath build/ETS2DualSense.xcarchive -allowProvisioningUpdates archive

upload: archive
	xcodebuild -exportArchive -archivePath build/ETS2DualSense.xcarchive \
		-exportOptionsPlist packaging/ExportOptions.plist -exportPath build/export -allowProvisioningUpdates

# Developer ID signed + notarized DMG for the releases page (non-sandboxed build).
notarized-dmg: plugin
	xcodegen generate
	xcodebuild -project ETS2DualSense.xcodeproj -scheme ETS2DualSenseDirect -configuration Release \
		-derivedDataPath build/xcode -archivePath build/ETS2DualSenseDirect.xcarchive -allowProvisioningUpdates archive
	xcodebuild -exportArchive -archivePath build/ETS2DualSenseDirect.xcarchive \
		-exportOptionsPlist packaging/ExportOptions-DeveloperID.plist -exportPath build/export-direct -allowProvisioningUpdates
	until xcodebuild -exportNotarizedApp -archivePath build/ETS2DualSenseDirect.xcarchive -exportPath $(STAGE); do sleep 30; done
	ln -sfn /Applications $(STAGE)/Applications
	hdiutil create -volname "ETS2 DualSense" -srcfolder $(STAGE) -ov -format UDZO build/ETS2-DualSense-$(VERSION)-notarized.dmg

test:
	swift test

run: app
	open "$(APP)"

clean:
	rm -rf build .build

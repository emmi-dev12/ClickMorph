APP       = ClickMorph
VERSION  ?= 0.1.0
BUNDLE    = $(APP).app
BINARY    = .build/release/$(APP)
CONTENTS  = $(BUNDLE)/Contents
RESOURCES = $(CONTENTS)/Resources
DMG       = $(APP)-$(VERSION).dmg

.PHONY: all build icon bundle sign run install clean dmg

## Default: build + bundle (no icon — fast dev loop)
all: bundle

## Compile with optimisations
build:
	swift build -c release

## Generate AppIcon.icns from the Swift drawing script (requires macOS)
icon:
	@mkdir -p $(RESOURCES)
	@echo "Generating icon…"
	@swift scripts/make_icon.swift _iconset
	@iconutil -c icns _iconset -o $(RESOURCES)/AppIcon.icns
	@rm -rf _iconset
	@echo "Created $(RESOURCES)/AppIcon.icns"

## Wrap the binary in a proper .app bundle
bundle: build
	@mkdir -p $(CONTENTS)/MacOS $(RESOURCES)
	@cp $(BINARY) $(CONTENTS)/MacOS/$(APP)
	@cp Sources/ClickMorph/Resources/Info.plist $(CONTENTS)/Info.plist
	@echo "Built $(BUNDLE)"

## Ad-hoc code-sign (required for CGEventTap on Apple Silicon)
sign: bundle
	codesign -s - -f --deep $(BUNDLE)
	@echo "Signed $(BUNDLE)"

## Build, sign, and launch from the project folder (dev — may re-ask accessibility)
run: sign
	open $(BUNDLE)

## Install to /Applications so accessibility permission persists across rebuilds.
## Run this once; then launch ClickMorph from /Applications normally.
install: icon sign
	@echo "Installing to /Applications/$(BUNDLE)…"
	@rm -rf /Applications/$(BUNDLE)
	@cp -r $(BUNDLE) /Applications/$(BUNDLE)
	@codesign -s - -f --deep /Applications/$(BUNDLE)
	@echo "Done. Opening /Applications/$(BUNDLE)"
	@open /Applications/$(BUNDLE)

## Package a drag-to-install DMG  (override: make dmg VERSION=1.2.3)
dmg: icon sign
	@rm -rf "$(DMG)" _dmg_staging
	@mkdir _dmg_staging
	@cp -r $(BUNDLE) _dmg_staging/
	@ln -s /Applications _dmg_staging/Applications
	hdiutil create -volname "ClickMorph $(VERSION)" \
	    -srcfolder _dmg_staging -ov -format UDZO "$(DMG)"
	@rm -rf _dmg_staging
	@echo "Created $(DMG)"

## Remove build artefacts and the app bundle
clean:
	swift package clean
	@rm -rf $(BUNDLE) ClickMorph-*.dmg

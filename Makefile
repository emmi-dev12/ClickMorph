APP       = ClickMorph
VERSION  ?= 0.1.0
BUNDLE    = $(APP).app
BINARY    = .build/release/$(APP)
CONTENTS  = $(BUNDLE)/Contents
DMG       = $(APP)-$(VERSION).dmg

.PHONY: all build bundle run clean sign dmg

## Default: build then bundle
all: bundle

## Compile with optimisations
build:
	swift build -c release

## Wrap the binary in a proper .app bundle
## (LSUIElement only takes effect when launched as an .app bundle)
bundle: build
	@mkdir -p $(CONTENTS)/MacOS
	@cp $(BINARY) $(CONTENTS)/MacOS/$(APP)
	@cp Sources/ClickMorph/Resources/Info.plist $(CONTENTS)/Info.plist
	@echo "Built $(BUNDLE)"

## Ad-hoc code-sign (required for CGEventTap on Apple Silicon)
sign: bundle
	codesign -s - -f --deep $(BUNDLE)
	@echo "Signed $(BUNDLE) with ad-hoc identity"

## Build, sign, and open the app
run: sign
	open $(BUNDLE)

## Package a drag-to-install DMG  (override version: make dmg VERSION=1.2.3)
dmg: sign
	@rm -rf "$(DMG)" _dmg_staging
	@mkdir _dmg_staging
	@cp -r $(BUNDLE) _dmg_staging/
	@ln -s /Applications _dmg_staging/Applications
	hdiutil create -volname "ClickMorph $(VERSION)" \
	    -srcfolder _dmg_staging -ov -format UDZO "$(DMG)"
	@rm -rf _dmg_staging
	@echo "Created $(DMG) — drag to /Applications to install"

## Remove build artefacts and the app bundle
clean:
	swift package clean
	@rm -rf $(BUNDLE) ClickMorph-*.dmg

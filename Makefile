APP       = ClickMorph
BUNDLE    = $(APP).app
BINARY    = .build/release/$(APP)
CONTENTS  = $(BUNDLE)/Contents

.PHONY: all build bundle run clean sign

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

## Remove build artefacts and the app bundle
clean:
	swift package clean
	@rm -rf $(BUNDLE)

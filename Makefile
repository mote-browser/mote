# Mote — common tasks. Everything here is a thin layer over xcodebuild;
# opening Mote.xcodeproj in Xcode and pressing Run works just as well.
#
#   make            list the targets
#   make build      Release build → build/Mote.app
#   make dev        Debug build, opened in the test world
#   make fresh      Release build, opened in a wiped test world (WORLD=name for another)
#   make reopen     open the test world as it was left
#   make dmg        build/Mote.dmg, unsigned
#   make scripts    build the injected TypeScript (Scripts/) into Mote/Resources/Scripts
#   make test       unit, script and integration tests
#   make test-ui    end-to-end tests (the first run asks for Accessibility access)
#   make format     format the Swift sources with swift-format
#   make lint       check formatting without changing anything
#   make clean      remove build/

PROJECT   := Mote.xcodeproj
SCHEME    := Mote
BUILD_DIR := build
DERIVED   := $(BUILD_DIR)/DerivedData
APP       := $(BUILD_DIR)/Mote.app
# Extra build settings, e.g. XCODEBUILD_FLAGS="MARKETING_VERSION=1.0.0 CURRENT_PROJECT_VERSION=42".
XCODEBUILD_FLAGS ?=
XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS,arch=$(shell uname -m)' -derivedDataPath $(DERIVED) $(XCODEBUILD_FLAGS)

# Test worlds keep their own folder, settings and WebKit store (see Store.swift),
# so nothing here can touch the Mote you use every day.
WORLD       ?= test
WORLD_NAME  := $(shell printf '%s' '$(WORLD)' | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9-' | sed -e 's/^1$$/test/' -e 's/^$$/test/')
WORLD_SUITE := io.github.mote-browser.mote.test$(if $(filter test,$(WORLD_NAME)),,.$(WORLD_NAME))
# Store.probeStore(1): FNV-1a of the world's name inside a fixed UUID.
WORLD_STORE := $(shell python3 -c 'import sys,functools;w=sys.argv[1];h=0 if w=="test" else functools.reduce(lambda h,b:((h^b)*16777619)&0xFFFFFFFF,w.encode(),2166136261);print("5E4C%04X-%04X-4000-8000-000000000001"%(h>>16,h&0xFFFF))' '$(WORLD_NAME)')

.DEFAULT_GOAL := help
.PHONY: help build dev fresh reopen dmg scripts test test-unit test-scripts test-integration test-ui format lint clean

help: ## List the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-8s %s\n", $$1, $$2}'

build: ## Release build → build/Mote.app
	$(XCODEBUILD) -configuration Release build
	@rm -rf $(APP) $(APP).dSYM
	@ditto $(DERIVED)/Build/Products/Release/Mote.app $(APP)
	@ditto $(DERIVED)/Build/Products/Release/Mote.app.dSYM $(APP).dSYM
	@echo "built: $(APP)"

dev: ## Debug build, opened in the test world
	$(XCODEBUILD) -configuration Debug build
	open -n $(DERIVED)/Build/Products/Debug/Mote.app

fresh: build ## Release build, opened in a wiped test world (WORLD=name for another)
	rm -rf "$(HOME)/Library/Application Support/Mote ($(WORLD_NAME))"
	-defaults delete $(WORLD_SUITE) 2>/dev/null
	rm -rf "$(HOME)/Library/WebKit/io.github.mote-browser.mote/WebsiteDataStore/$(WORLD_STORE)"
	open -n --env MOTE_PROBE=$(WORLD_NAME) $(APP)

reopen: ## Open the test world as it was left (WORLD=name for another)
	@test -d $(APP) || $(MAKE) build
	open -n --env MOTE_PROBE=$(WORLD_NAME) $(APP)

dmg: build ## build/Mote.dmg, unsigned (needs uv: https://docs.astral.sh/uv)
	@rm -rf $(BUILD_DIR)/dmg-art $(BUILD_DIR)/Mote.dmg
	swift Tools/dmg/art.swift $(APP) $(BUILD_DIR)/dmg-art
	tiffutil -cathidpicheck $(BUILD_DIR)/dmg-art/background.png $(BUILD_DIR)/dmg-art/background@2x.png -out $(BUILD_DIR)/dmg-art/background.tiff
	iconutil -c icns $(BUILD_DIR)/dmg-art/VolumeIcon.iconset -o $(BUILD_DIR)/dmg-art/VolumeIcon.icns
	uvx 'dmgbuild>=1.6.7' -s Tools/dmg/settings.py -D app=$(APP) -D art=$(BUILD_DIR)/dmg-art Mote $(BUILD_DIR)/Mote.dmg
	@rm -rf $(BUILD_DIR)/dmg-art

PNPM = pnpm --dir Scripts

scripts: ## Build the injected TypeScript into Mote/Resources/Scripts
	$(PNPM) install --frozen-lockfile
	$(PNPM) build

test: test-unit test-scripts test-integration ## Unit, script and integration tests

test-unit: ## Unit tests of MoteCore (swift test, no app needed)
	swift test --package-path Packages/MoteKit

test-scripts: ## Type-check, lint and unit-test the injected scripts; check the committed build is current
	$(PNPM) install --frozen-lockfile
	$(PNPM) check
	$(PNPM) build
	git diff --exit-code -- Mote/Resources/Scripts || (echo "Mote/Resources/Scripts is out of date: run 'make scripts' and commit it" && exit 1)

test-integration: ## Integration tests, hosted in the app with real WebKit
	$(XCODEBUILD) -configuration Debug test -only-testing:MoteTests

test-ui: ## End-to-end tests that drive the app
	$(XCODEBUILD) -configuration Debug test -only-testing:MoteUITests

SWIFT_SOURCES := Mote MoteTests MoteUITests Packages/MoteKit/Sources Packages/MoteKit/Tests Packages/MoteKit/Package.swift

format: ## Format the Swift sources (swift-format) and the scripts (oxfmt)
	swift format format --in-place --recursive $(SWIFT_SOURCES)
	$(PNPM) format

lint: ## Check formatting and lint without changing anything
	swift format lint --strict --recursive $(SWIFT_SOURCES)
	$(PNPM) lint
	$(PNPM) format:check

clean: ## Remove build/
	rm -rf $(BUILD_DIR) Packages/MoteKit/.build Scripts/node_modules

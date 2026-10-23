# KISS Translator — Safari extension packaging
#
# Everything is driven from config/build.config.mjs; this file only wires the
# steps together. Run `make help` for the short version.
#
#   make all        extension -> project -> app -> DMG + ZIP (the full build)
#   make all SIGNING=0          unsigned build (not usable with Safari)
#   make all DEVELOPER_ID="Developer ID Application: …"   notarisation-ready build

SHELL := /bin/bash
.DEFAULT_GOAL := help
.SUFFIXES:

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------
# Read the single source of truth. Fall back to a clear error if node is absent.
VERSION := $(shell node -e 'import("./config/build.config.mjs").then(m=>process.stdout.write(m.app.marketingVersion))' 2>/dev/null)
PRODUCT := $(shell node -e 'import("./config/build.config.mjs").then(m=>process.stdout.write(m.app.productName))' 2>/dev/null)
DISPLAY := $(shell node -e 'import("./config/build.config.mjs").then(m=>process.stdout.write(m.app.displayName))' 2>/dev/null)

XCODEGEN ?= $(shell command -v xcodegen 2>/dev/null || mise which xcodegen 2>/dev/null)
NODE_BIN := $(shell command -v node)
PYTHON ?= $(shell command -v python3)

# PROJECT/SCHEME/binary stay ASCII (`productName`); only the user-visible
# .app bundle name uses `displayName` (简约翻译.app).
PROJECT   := $(PRODUCT).xcodeproj
SCHEME    := $(PRODUCT)
CONFIG    := Release
DERIVED   := build/DerivedData
APP       := build/App/$(DISPLAY).app
BUILT_APP := $(DERIVED)/Build/Products/$(CONFIG)/$(PRODUCT).app
DIST      := build/dist

# SIGNING=1 (default) signs with a local development identity when available.
# SIGNING=0 builds completely unsigned (never usable with Safari — it needs a
# real Team Identifier, see docs/BUILDING.md).
SIGNING ?= 1
DEVELOPMENT_TEAM ?= $(shell security find-certificate -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -nameopt sep_multiline -subject 2>/dev/null | awk -F= '/OU=/{print $$2; exit}')
DEVELOPER_ID ?=

# Universal build: never let an Apple-Silicon-only machine ship a thin binary.
XCODEBUILD_FLAGS := \
	-project $(PROJECT) \
	-scheme $(SCHEME) \
	-configuration $(CONFIG) \
	-derivedDataPath $(DERIVED) \
	ARCHS="arm64 x86_64" \
	ONLY_ACTIVE_ARCH=NO

ifeq ($(SIGNING),0)
XCODEBUILD_FLAGS += CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
else ifneq ($(DEVELOPER_ID),)
XCODEBUILD_FLAGS += CODE_SIGN_IDENTITY="$(DEVELOPER_ID)" CODE_SIGN_STYLE=Manual
else ifneq ($(DEVELOPMENT_TEAM),)
XCODEBUILD_FLAGS += DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) CODE_SIGN_STYLE=Automatic
else
XCODEBUILD_FLAGS += CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
endif

.PHONY: help all deps extension preclean project build sign package dmg zip verify clean distclean icons

help:
	@printf '\n简约翻译 (KISS Translator for Safari) — build\n\n'
	@printf '  make all        Full build: web extension, Xcode project, .app, DMG + ZIP (starts clean)\n'
	@printf '  make deps       Fetch + build the pinned upstream web extension only\n'
	@printf '  make extension  Same as deps (alias kept for clarity)\n'
	@printf '  make project    Generate $(PROJECT) with XcodeGen\n'
	@printf '  make build      Compile the app (assumes project + extension exist)\n'
	@printf '  make sign       Sign the built app (DEVELOPER_ID="Developer ID Application: …")\n'
	@printf '  make dmg        Produce $(DIST)/$(DISPLAY)-$(VERSION).dmg and .zip\n'
	@printf '  make package    sign + dmg\n'
	@printf '  make verify     Check the built bundle is a valid Safari extension\n'
	@printf '  make icons      Regenerate the app icon PNGs\n'
	@printf '  make clean      Remove build outputs (keeps upstream checkout)\n'
	@printf '  make distclean  Remove build outputs AND the upstream checkout\n\n'
	@printf '  Options: SIGNING=0 (unsigned)  DEVELOPMENT_TEAM=…  DEVELOPER_ID=…\n\n'
	@printf '  Version: %s   Product: %s\n\n' '$(VERSION)' '$(PRODUCT)'

# `dmg` runs after `build` so the package always contains the freshly compiled
# .app. `dmg` itself keeps no prerequisite on purpose: re-signing the app and
# then re-running a phony `build` would re-execute the appex resource-copy
# phase after signing.
all: extension project build dmg

# --------------------------------------------------------------------------
# Web extension
# --------------------------------------------------------------------------
deps extension:
	@$(NODE_BIN) scripts/build-extension.mjs

# --------------------------------------------------------------------------
# Xcode project
# --------------------------------------------------------------------------
# Regenerating the project always starts from a clean slate: stale
# DerivedData or a leftover staged app can leak deleted files into an
# incremental build. The upstream extension output (build/extension) is kept;
# it is cheap to re-publish. `dmg`/`sign` alone never trigger this, so
# re-packaging or re-signing an existing bundle keeps working.
preclean:
	@rm -rf "$(DERIVED)" "$(APP)" "$(DIST)" "$(PROJECT)"
	@echo "==> cleaned previous build outputs"

project: preclean
	@if [ -z "$(XCODEGEN)" ]; then \
		echo "error: xcodegen not found. Install it with 'brew install xcodegen'." >&2; \
		exit 1; \
	fi
	@if [ ! -f build/extension/manifest.json ]; then \
		echo "error: build/extension/manifest.json is missing. Run 'make extension' first." >&2; \
		exit 1; \
	fi
	@echo "==> Generating $(PROJECT)"
	@$(XCODEGEN) generate --spec config/project.yml --project . --project-root . --quiet

# --------------------------------------------------------------------------
# App
# --------------------------------------------------------------------------
build: project
	@echo "==> Building $(PRODUCT) $(VERSION) ($(CONFIG))"
	@set -o pipefail; xcodebuild $(XCODEBUILD_FLAGS) build \
		| grep -E '^(=== |\*\* |error:|warning: )' || { echo "build failed" >&2; exit 1; }
	@rm -rf "$(APP)"
	@mkdir -p "$(dir $(APP))"
	@ditto "$(BUILT_APP)" "$(APP)"
	@echo "==> $(APP)"

sign:
	@if [ -z "$(DEVELOPER_ID)" ]; then \
		echo "error: DEVELOPER_ID is not set." >&2; \
		echo '  make sign DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"' >&2; \
		exit 1; \
	fi
	@echo "==> Signing with $(DEVELOPER_ID)"
	@# Inside-out: nested appex executable -> appex bundle -> app. Never
	@# `codesign --deep` the outer bundle only: that leaves the extension with an
	@# inconsistent signature and Safari then cannot verify/load it.
	@codesign --force --options runtime --timestamp --sign "$(DEVELOPER_ID)" \
		"$(APP)/Contents/PlugIns/KISSTranslator Extension.appex/Contents/MacOS/KISSTranslator Extension"
	@codesign --force --options runtime --timestamp --sign "$(DEVELOPER_ID)" \
		--entitlements extension/KISSTranslatorExtension.entitlements \
		"$(APP)/Contents/PlugIns/KISSTranslator Extension.appex"
	@codesign --force --options runtime --timestamp --sign "$(DEVELOPER_ID)" \
		--entitlements app/KISSTranslator.entitlements "$(APP)"
	@# An ad-hoc `--sign -` (identity "-") drops entitlements unless they are
	@# passed explicitly; verify they survived instead of trusting the tool.
	@codesign --verify --deep --strict --verbose=2 "$(APP)"
	@echo "==> Signed"

# --------------------------------------------------------------------------
# Distribution
# --------------------------------------------------------------------------
package: dmg

dmg:
	@$(NODE_BIN) scripts/package.mjs

# --------------------------------------------------------------------------
# Verification
# --------------------------------------------------------------------------
verify:
	@$(NODE_BIN) scripts/verify.mjs

# --------------------------------------------------------------------------
# Housekeeping
# --------------------------------------------------------------------------
icons:
	@$(PYTHON) scripts/generate-icons.py

clean: preclean
	@rm -rf build/extension build/upstream-safari-raw
	@echo "==> cleaned build outputs"

distclean: clean
	@rm -rf build .build
	@echo "==> removed all local state (upstream checkout will be re-fetched)"

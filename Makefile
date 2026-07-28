PLUGIN_ID = com.dv.fokus
VERSION := $(shell python3 -c "import json; print(json.load(open('package/metadata.json'))['KPlugin']['Version'])")
ARCHIVE = fokus_v$(VERSION).plasmoid

QMLLINT ?= /usr/lib/qt6/bin/qmllint
QMLTESTRUNNER ?= /usr/lib/qt6/bin/qmltestrunner

QML_SOURCES = $(wildcard package/contents/ui/*.qml package/contents/ui/lib/*.qml)
PACKAGE_FILES = $(shell find package -type f)

# plasmoid.configuration is an attached property qmllint cannot resolve outside
# plasmashell, so those two categories are pure noise here.
QMLLINT_FLAGS = --unqualified disable --missing-property disable

.PHONY: check lint test install upgrade uninstall package clean

check: lint test

lint:
	$(QMLLINT) $(QMLLINT_FLAGS) $(QML_SOURCES)

test:
	QT_QPA_PLATFORM=offscreen $(QMLTESTRUNNER) -input tests

install:
	kpackagetool6 -t Plasma/Applet -i package

upgrade:
	kpackagetool6 -t Plasma/Applet -u package

uninstall:
	kpackagetool6 -t Plasma/Applet -r $(PLUGIN_ID)

# A .plasmoid is just a zip of the package directory. The name tracks the
# version in metadata.json so the two cannot drift.
package: $(ARCHIVE)

$(ARCHIVE): $(PACKAGE_FILES)
	rm -f $@
	cd package && zip -qr "$(abspath $@)" .
	@echo "built $@"

clean:
	rm -f *.plasmoid

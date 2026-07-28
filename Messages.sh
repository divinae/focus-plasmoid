#!/usr/bin/env bash
# Extracts translatable strings for the KDE translation workflow.
# Run through the ki18n scripty tooling, which supplies $XGETTEXT and $podir.
#
# The catalog name must stay plasma_applet_<plugin id>, because that is the
# translation domain KPackage binds i18n() to for a Plasma applet.
$XGETTEXT $(find package -name '*.qml' -o -name '*.js') \
    -o "$podir/plasma_applet_com.dv.fokus.pot"

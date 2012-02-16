# -*- Mode: Automake; indent-tabs-mode: t; tab-width: 4 -*-

xgreeterdir = $(datarootdir)/xgreeters
dist_xgreeter_DATA = unity-greeter.desktop

dist_pkgdata_DATA = a11y.svg cof.png cog.png logo.png message.png

@GSETTINGS_RULES@
gsettings_SCHEMAS = com.canonical.unity-greeter.gschema.xml

EXTRA_DIST = \
	$(gsettings_SCHEMAS)

DISTCLEANFILES = \
	Makefile.in

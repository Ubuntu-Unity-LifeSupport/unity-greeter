# -*- Mode: Automake; indent-tabs-mode: t; tab-width: 4 -*-

sbin_PROGRAMS = unity-greeter

unity_greeter_SOURCES = \
	config.vapi \
	fixes.vapi \
	indicator.vapi \
	animate-timer.vala \
	background.vala \
	dash-box.vala \
	dash-button.vala \
	dash-entry.vala \
	fadable.vala \
	main-window.vala \
	menu.vala \
	menubar.vala \
	settings.vala \
	settings-daemon.vala \
	unity-greeter.vala \
	user-list.vala

unity_greeter_CFLAGS = \
	$(UNITY_GREETER_CFLAGS) \
	$(WARN_CFLAGS) \
	-DGETTEXT_PACKAGE=\"$(GETTEXT_PACKAGE)\" \
	-DLOCALEDIR=\""$(localedir)"\" \
	-DVERSION=\"$(VERSION)\" \
	-DCONFIG_FILE=\""$(sysconfdir)/lightdm/unity-greeter.conf"\" \
	-DPKGDATADIR=\""$(pkgdatadir)"\" \
	-DINDICATORDIR=\""$(INDICATORDIR)"\"

unity_greeter_VALAFLAGS = \
	--pkg posix \
	--pkg gtk+-3.0 \
	--pkg gdk-x11-3.0 \
	--pkg x11 \
	--pkg liblightdm-gobject-1

unity_greeter_LDADD = \
	$(UNITY_GREETER_LIBS)

DISTCLEANFILES = \
	Makefile.in

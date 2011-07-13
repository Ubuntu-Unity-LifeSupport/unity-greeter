greeter_PROGRAMS = unity-greeter
greeterdir = $(GREETER_DIR)

unity_greeter_SOURCES = \
	config.vapi \
	indicator.vapi \
	unity-greeter.vala \
	user-list.vala

unity_greeter_CFLAGS = \
	$(UNITY_GREETER_CFLAGS) \
	$(WARN_CFLAGS) \
	-DGETTEXT_PACKAGE=\"$(GETTEXT_PACKAGE)\" \
	-DVERSION=\"$(VERSION)\"

unity_greeter_VALAFLAGS = \
	--pkg posix \
	--pkg gtk+-3.0 \
	--pkg liblightdm-gobject-0

unity_greeter_LDADD = \
	$(UNITY_GREETER_LIBS)

DISTCLEANFILES = \
	Makefile.in

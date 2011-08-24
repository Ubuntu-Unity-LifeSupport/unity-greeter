dnl Process this file with autoconf to produce a configure script.

AC_INIT(unity-greeter, 0.0.3)
AC_CONFIG_MACRO_DIR(m4)
AM_INIT_AUTOMAKE
AM_PROG_CC_C_O
AM_PROG_VALAC
AM_CONFIG_HEADER(config.h)
AM_MAINTAINER_MODE
m4_ifdef([AM_SILENT_RULES], [AM_SILENT_RULES(yes)])

GNOME_COMPILE_WARNINGS(maximum)

dnl ###########################################################################
dnl Dependencies
dnl ###########################################################################

PKG_CHECK_MODULES(UNITY_GREETER, [
    gtk+-3.0
    gdk-x11-3.0
    indicator3-0.4
    liblightdm-gobject-1 >= 0.9.2
    freetype2
    cairo-ft
])

dnl ###########################################################################
dnl Internationalization
dnl ###########################################################################

IT_PROG_INTLTOOL(0.35.0)
GETTEXT_PACKAGE=unity-greeter
AC_DEFINE_UNQUOTED(GETTEXT_PACKAGE, "$GETTEXT_PACKAGE", Gettext package)
AC_SUBST(GETTEXT_PACKAGE)

dnl ###########################################################################
dnl Files to generate
dnl ###########################################################################

AC_CONFIG_FILES([
Makefile
data/Makefile
po/Makefile.in
src/Makefile
])
AC_OUTPUT

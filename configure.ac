dnl Process this file with autoconf to produce a configure script.

AC_INIT(unity-greeter, 0.0.1)
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
    indicator3-0.4
    liblightdm-gobject-0 >= 0.4.3
])

dnl ###########################################################################
dnl Configurable values
dnl ###########################################################################
THEME_DIR=`$PKG_CONFIG --define-variable=prefix=$prefix --variable=themedir liblightdm-gobject-0`
AC_SUBST(THEME_DIR)

GREETER_DIR=`$PKG_CONFIG --define-variable=prefix=$prefix --variable=greeterdir liblightdm-gobject-0`
AC_SUBST(GREETER_DIR)

dnl ###########################################################################
dnl Internationalization
dnl ###########################################################################

IT_PROG_INTLTOOL(0.35.0)
GETTEXT_PACKAGE=unity-greeter
AC_DEFINE_UNQUOTED(GETTEXT_PACKAGE, "$GETTEXT_PACKAGE", Gettext package)

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

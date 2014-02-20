/* -*- Mode:Vala; indent-tabs-mode:nil; tab-width:4 -*-
 *
 * Copyright (C) 2011 Canonical Ltd
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authored by: Michael Terry <michael.terry@canonical.com>
 */

public class SettingsDaemon : Object
{
    private int logind_inhibit_fd = -1;

    public async void start ()
    {
        configure ();
        yield run ();
    }

    private void configure ()
    {
        string[] disabled = { "org.gnome.settings-daemon.plugins.background",
                              "org.gnome.settings-daemon.plugins.clipboard",
                              "org.gnome.settings-daemon.plugins.font",
                              "org.gnome.settings-daemon.plugins.gconf",
                              "org.gnome.settings-daemon.plugins.gsdwacom",
                              "org.gnome.settings-daemon.plugins.housekeeping",
                              "org.gnome.settings-daemon.plugins.keybindings",
                              "org.gnome.settings-daemon.plugins.keyboard",
                              "org.gnome.settings-daemon.plugins.media-keys",
                              "org.gnome.settings-daemon.plugins.mouse",
                              "org.gnome.settings-daemon.plugins.print-notifications",
                              "org.gnome.settings-daemon.plugins.smartcard",
                              "org.gnome.settings-daemon.plugins.sound",
                              "org.gnome.settings-daemon.plugins.wacom" };

        string[] enabled =  { "org.gnome.settings-daemon.plugins.a11y-keyboard",
                              "org.gnome.settings-daemon.plugins.a11y-settings",
                              "org.gnome.settings-daemon.plugins.color",
                              "org.gnome.settings-daemon.plugins.cursor",
                              "org.gnome.settings-daemon.plugins.power",
                              "org.gnome.settings-daemon.plugins.xrandr",
                              "org.gnome.settings-daemon.plugins.xsettings" };

        foreach (var schema in disabled)
            set_plugin_enabled (schema, false);

        foreach (var schema in enabled)
            set_plugin_enabled (schema, true);

        /* We want to block the screensaver from being activated by g-s-d or
           any of the indicators.  So we own the name, preventing dbus
           activation by anyone else.
           If the screensaver were allowed to start, it would disable X's
           builtin blanking logic which we do use and instead, blanking would
           require gnome-session and it's Presence DBus interface to be run. */
        GLib.Bus.own_name (GLib.BusType.SESSION, "org.gnome.ScreenSaver",
                           GLib.BusNameOwnerFlags.NONE);

        /* The media-keys plugin inhibits the power key, but we don't want
           all the other keys doing things. So inhibit it ourselves */
        /* NOTE: We are using the synchronous method here since there is a bug in Vala/GLib in that
         * g_dbus_connection_call_with_unix_fd_list_finish and g_dbus_proxy_call_with_unix_fd_list_finish
         * don't have the GAsyncResult as the second argument.
         * https://bugzilla.gnome.org/show_bug.cgi?id=688907
         */
        try
        {
            var b = Bus.get_sync (BusType.SYSTEM);
            UnixFDList fd_list;
            var result = b.call_with_unix_fd_list_sync  ("org.freedesktop.login1",
                                                         "/org/freedesktop/login1",
                                                         "org.freedesktop.login1.Manager",
                                                         "Inhibit",
                                                         new Variant ("(ssss)",
                                                                      "handle-power-key",
                                                                      Environment.get_user_name (),
                                                                      "Unity Greeter handling keypresses",
                                                                      "block"),
                                                         new VariantType ("(h)"),
                                                         DBusCallFlags.NONE,
                                                         -1,
                                                         null,
                                                         out fd_list);
            int32 index = -1;
            result.get ("(h)", &index);
            logind_inhibit_fd = fd_list.get (index);
        }
        catch (Error e)
        {
            warning ("Failed to inhibit power keys: %s", e.message);
        }
    }

    private void set_plugin_enabled (string schema_name, bool enabled)
    {
        var source = SettingsSchemaSource.get_default ();
        var schema = source.lookup (schema_name, false);
        if (schema != null)
        {
            var settings = new Settings (schema_name);
            settings.set_boolean ("active", enabled);
        }
    }

    private async void run ()
    {
        try
        {
            Process.spawn_command_line_async (Config.USD_BINARY);
        }
        catch (SpawnError e)
        {
            debug ("Could not start unity-settings-daemon: %s", e.message);
        }
    }
}

/* -*- Mode: Vala; indent-tabs-mode: nil; tab-width: 4 -*-
 *
 * Copyright (C) 2011,2012 Canonical Ltd
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
 * Authors: Robert Ancell <robert.ancell@canonical.com>
 *          Michael Terry <michael.terry@canonical.com>
 */

private class IndicatorMenuItem : Gtk.MenuItem
{
    public unowned Indicator.ObjectEntry entry;
    private Gtk.HBox hbox;

    public IndicatorMenuItem (Indicator.ObjectEntry entry)
    {
        this.entry = entry;
        this.hbox = new Gtk.HBox (false, 3);
        this.add (this.hbox);
        this.hbox.show ();

        if (entry.label != null)
        {
            entry.label.show.connect (this.visibility_changed_cb);
            entry.label.hide.connect (this.visibility_changed_cb);
            hbox.pack_start (entry.label, false, false, 0);
        }
        if (entry.image != null)
        {
            entry.image.show.connect (visibility_changed_cb);
            entry.image.hide.connect (visibility_changed_cb);
            hbox.pack_start (entry.image, false, false, 0);
        }
        if (entry.accessible_desc != null)
            get_accessible ().set_name (entry.accessible_desc);
        if (entry.menu != null)
            submenu = entry.menu;

        if (has_visible_child ())
            show ();
    }

    public bool has_visible_child ()
    {
        return (entry.image != null && entry.image.get_visible ()) ||
               (entry.label != null && entry.label.get_visible ());
    }

    public void visibility_changed_cb (Gtk.Widget widget)
    {
        visible = has_visible_child ();
    }
}

public class MenuBar : Gtk.MenuBar
{
    public Background? background {get; construct; default = null;}
    public bool high_contrast {get; private set; default = false;}

    public MenuBar (Background bg)
    {
        Object (background: bg);
    }

    public void set_layout (LightDM.Layout? layout)
    {
        if (layout == null)
            layout = LightDM.get_layout (); /* default layout */

        var item = layout.get_data<Gtk.RadioMenuItem> ("unity-greeter-radio");
        if (item != null)
            item.active = true; /* will trigger callback to do rest of work */
    }

    public override bool draw (Cairo.Context c)
    {
        if (background != null)
        {
            int x, y;
            background.translate_coordinates (this, 0, 0, out x, out y);
            c.save ();
            c.translate (x, y);
            background.draw_full (c, Background.DrawFlags.NONE);
            c.restore ();
        }

        c.set_source_rgb (0, 0, 0);
        c.paint_with_alpha (0.5);

        foreach (var child in get_children ())
        {
            propagate_draw (child, c);
        }

        return false;
    }

    private string default_theme_name;
    private List<Indicator.Object> indicator_objects;
    private Gtk.CheckMenuItem high_contrast_item;
    private Gtk.Label keyboard_label = null;
    private Pid keyboard_pid = 0;
    private Gtk.Window? keyboard_window = null;

    construct
    {
        Gtk.Settings.get_default ().get ("gtk-theme-name", out default_theme_name);

        pack_direction = Gtk.PackDirection.RTL;

        var label = new Gtk.Label (Posix.utsname ().nodename);
        label.show ();
        var hostname_item = new Gtk.MenuItem ();
        hostname_item.add (label);
        hostname_item.sensitive = false;
        hostname_item.right_justified = true;
        hostname_item.show ();
        append (hostname_item);

        /* Hack to get a label showing on the menubar */
        label.ensure_style ();
        label.modify_fg (Gtk.StateType.INSENSITIVE, label.get_style ().fg[Gtk.StateType.NORMAL]);

        setup_indicators ();
    }

    ~MenuBar ()
    {
        if (keyboard_pid != 0)
        {
            Posix.kill (keyboard_pid, Posix.SIGKILL);
            int status;
            Posix.waitpid (keyboard_pid, out status, 0);
            keyboard_pid = 0;
        }
    }

    private void greeter_set_env (string key, string val)
    {
        GLib.Environment.set_variable (key, val, true);

        /* And also set it in the DBus activation environment so that any
         * indicator services pick it up. */
        try
        {
            var proxy = new GLib.DBusProxy.for_bus_sync (GLib.BusType.SESSION,
                                                         GLib.DBusProxyFlags.NONE, null,
                                                         "org.freedesktop.DBus",
                                                         "/org/freedesktop/DBus",
                                                         "org.freedesktop.DBus",
                                                         null);

            var builder = new GLib.VariantBuilder (GLib.VariantType.ARRAY);
            builder.add ("{ss}", key, val);

            proxy.call ("UpdateActivationEnvironment", new GLib.Variant ("(a{ss})", builder), GLib.DBusCallFlags.NONE, -1, null);
        }
        catch (Error e)
        {
            warning ("Could not get set environment for indicators: %s", e.message);
            return;
        }
    }

    private Gtk.Widget make_a11y_indicator ()
    {
        var a11y_item = new Gtk.MenuItem ();
        var hbox = new Gtk.HBox (false, 3);
        hbox.show ();
        a11y_item.add (hbox);
        var image = new Gtk.Image.from_file (Path.build_filename (Config.PKGDATADIR, "a11y.svg"));
        image.show ();
        hbox.add (image);
        a11y_item.show ();
        a11y_item.submenu = new Gtk.Menu ();
        var item = new Gtk.CheckMenuItem.with_label (_("Onscreen keyboard"));
        item.toggled.connect (keyboard_toggled_cb);
        item.show ();
        a11y_item.submenu.append (item);
        high_contrast_item = new Gtk.CheckMenuItem.with_label (_("High Contrast"));
        high_contrast_item.toggled.connect (high_contrast_toggled_cb);
        high_contrast_item.show ();
        a11y_item.submenu.append (high_contrast_item);
        item = new Gtk.CheckMenuItem.with_label (_("Screen Reader"));
        item.toggled.connect (screen_reader_toggled_cb);
        item.show ();
        a11y_item.submenu.append (item);
        return a11y_item;
    }

    private void layout_toggled_cb (Gtk.CheckMenuItem item)
    {
        if (!item.active)
            return;

        var layout = item.get_data<LightDM.Layout> ("unity-greeter-layout");
        if (layout == null)
            return;

        keyboard_label.label = layout.short_description;
        LightDM.set_layout (layout);
    }

    private static int cmp_layout (LightDM.Layout? a, LightDM.Layout? b)
    {
        if (a == null && b == null)
            return 0;
        else if (a == null)
            return 1;
        else if (b == null)
            return -1;
        else
        {
            /* Use a dumb, ascii comparison for now.  If it turns out that some
               descriptions can be in unicode, we'll have to use libicu's collation
               algorithms. */
            return strcmp (a.description, b.description);
        }
    }

    private Gtk.Widget make_keyboard_indicator ()
    {
        var keyboard_item = new Gtk.MenuItem ();
        var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 3);
        hbox.show ();
        keyboard_item.add (hbox);
        var image = new Gtk.Image.from_icon_name ("keyboard", Gtk.IconSize.LARGE_TOOLBAR);
        image.show ();
        hbox.add (image);
        keyboard_label = new Gtk.Label ("");
        keyboard_label.width_chars = 2;
        keyboard_label.show ();
        hbox.add (keyboard_label);
        keyboard_item.show ();

        var submenu = new Gtk.Menu ();
        keyboard_item.set_submenu (submenu);

        var layouts = LightDM.get_layouts ().copy ();
        layouts.sort (cmp_layout);

        Gtk.RadioMenuItem? last_item = null;
        foreach (var layout in layouts)
        {
            var item = new Gtk.RadioMenuItem.with_label (last_item == null ? null : last_item.get_group (), layout.description);
            last_item = item;

            item.show ();

            /* LightDM does not change its layout list during its lifetime, so this is safe */
            item.set_data ("unity-greeter-layout", layout);
            layout.set_data ("unity-greeter-radio", item);

            item.toggled.connect (layout_toggled_cb);

            submenu.append (item);
        }

        return keyboard_item;
    }

    private void setup_indicators ()
    {
        /* Set indicators to run with reduced functionality */
        greeter_set_env ("INDICATOR_GREETER_MODE", "1");

        /* Don't allow virtual file systems? */
        greeter_set_env ("GIO_USE_VFS", "local");
        greeter_set_env ("GVFS_DISABLE_FUSE", "1");

        /* Hint to have gnome-settings-daemon run in greeter mode */
        greeter_set_env ("RUNNING_UNDER_GDM", "1");

        var keyboard_item = make_keyboard_indicator ();
        insert (keyboard_item, (int) get_children ().length () - 1);

        var a11y_item = make_a11y_indicator ();
        insert (a11y_item, (int) get_children ().length () - 1);

        debug ("LANG=%s LANGUAGE=%s", Environment.get_variable ("LANG"), Environment.get_variable ("LANGUAGE"));
        string[] filenames = {"/usr/lib/indicators3/6/libsession.so",
                              "/usr/lib/indicators3/6/libdatetime.so",
                              "/usr/lib/indicators3/6/libpower.so",
                              "/usr/lib/indicators3/6/libsoundmenu.so"};
        foreach (var filename in filenames)
        {
            var io = new Indicator.Object.from_file (filename);
            indicator_objects.append (io);
            io.entry_added.connect (indicator_added_cb);
            io.entry_removed.connect (indicator_removed_cb);
            foreach (var entry in io.get_entries ())
                indicator_added_cb (io, entry);
        }
        debug ("LANG=%s LANGUAGE=%s", Environment.get_variable ("LANG"), Environment.get_variable ("LANGUAGE"));
    }

    private void keyboard_toggled_cb (Gtk.CheckMenuItem item)
    {
        /* FIXME: The below would be sufficient if gnome-session were running
         * to notice and run a screen keyboard in /etc/xdg/autostart...  But
         * since we're not running gnome-session, we hardcode onboard here. */
        /* var settings = new Settings ("org.gnome.desktop.a11y.applications");*/
        /*settings.set_boolean ("screen-keyboard-enabled", item.active);*/

        if (keyboard_window == null)
        {
            int id;

            try
            {
                string[] argv;
                int onboard_stdout_fd;

                Shell.parse_argv ("onboard --xid", out argv);
                Process.spawn_async_with_pipes (null,
                                                argv,
                                                null,
                                                SpawnFlags.SEARCH_PATH,
                                                null,
                                                out keyboard_pid,
                                                null,
                                                out onboard_stdout_fd,
                                                null);
                var f = FileStream.fdopen (onboard_stdout_fd, "r");
                var stdout_text = new char[1024];
                f.gets (stdout_text);
                id = int.parse ((string) stdout_text);

            }
            catch (Error e)
            {
                warning ("Error setting up keyboard: %s", e.message);
                return;
            }

            var keyboard_socket = new Gtk.Socket ();
            keyboard_socket.show ();
            keyboard_window = new Gtk.Window ();
            keyboard_window.accept_focus = false;
            keyboard_window.focus_on_map = false;
            keyboard_window.add (keyboard_socket);
            Gtk.socket_add_id (keyboard_socket, id);

            /* Put keyboard at the bottom of the screen */
            var screen = get_screen ();
            var monitor = screen.get_monitor_at_window (get_window ());
            Gdk.Rectangle geom;
            screen.get_monitor_geometry (monitor, out geom);
            keyboard_window.move (geom.x, geom.y + geom.height - 200);
            keyboard_window.resize (geom.width, 200);
        }

        keyboard_window.visible = item.active;
    }

    private void high_contrast_toggled_cb (Gtk.CheckMenuItem item)
    {
        var settings = Gtk.Settings.get_default ();
        if (item.active)
            settings.set ("gtk-theme-name", "HighContrastInverse");
        else
            settings.set ("gtk-theme-name", default_theme_name);
        high_contrast = item.active;
    }

    private void screen_reader_toggled_cb (Gtk.CheckMenuItem item)
    {
        /* FIXME: The below would be sufficient if gnome-session were running
         * to notice and run a screen reader in /etc/xdg/autostart...  But
         * since we're not running gnome-session, we hardcode orca here.
        /*var settings = new Settings ("org.gnome.desktop.a11y.applications");*/
        /*settings.set_boolean ("screen-reader-enabled", item.active);*/

        /* Hardcoded orca: */
        try
        {
            if (item.active)
                Process.spawn_command_line_async ("orca --replace --no-setup --disable=splash-window --disable=main-window");
            else
                Process.spawn_command_line_async ("orca --quit");
        }
        catch (Error e)
        {
            warning ("Failed to run Orca: %s", e.message);
        }
    }

    private uint get_indicator_index (Indicator.Object object)
    {
        uint index = 0;

        foreach (var io in indicator_objects)
        {
            if (io == object)
                return index;
            index++;
        }

        return index;
    }

    private Indicator.Object? get_indicator_object_from_entry (Indicator.ObjectEntry entry)
    {
        foreach (var io in indicator_objects)
        {
            foreach (var e in io.get_entries ())
            {
                if (e == entry)
                    return io;
            }
        }

        return null;
    }

    private void indicator_added_cb (Indicator.Object object, Indicator.ObjectEntry entry)
    {
        var index = get_indicator_index (object);
        var pos = 0;
        foreach (var child in get_children ())
        {
            if (!(child is IndicatorMenuItem))
                break;

            var menuitem = (IndicatorMenuItem) child;
            var child_object = get_indicator_object_from_entry (menuitem.entry);
            var child_index = get_indicator_index (child_object);
            if (child_index > index)
                break;
            pos++;
        }

        debug ("Adding indicator object %p at position %d", entry, pos);

        var menuitem = new IndicatorMenuItem (entry);
        insert (menuitem, pos);
    }

    private void indicator_removed_cb (Indicator.Object object, Indicator.ObjectEntry entry)
    {
        debug ("Removing indicator object %p", entry);

        foreach (var child in get_children ())
        {
            var menuitem = (IndicatorMenuItem) child;
            if (menuitem.entry == entry)
            {
                remove (child);
                return;
            }
        }

        warning ("Indicator object %p not in menubar", entry);
    }
}

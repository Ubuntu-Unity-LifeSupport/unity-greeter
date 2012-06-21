/* -*- Mode: Vala; indent-tabs-mode: nil; tab-width: 4 -*-
 *
 * Copyright (C) 2012 Canonical Ltd
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
 * Authors: Michael Terry <michael.terry@canonical.com>
 */

public class SessionChooser : FadableBox
{
    public signal void session_clicked (string? session);

    construct
    {
        orientation = Gtk.Orientation.VERTICAL;
        border_width = 6;

        var back = build_back_button ();
        pack_start (back, false, false, 0);

        if (UnityGreeter.test_mode)
        {
            add_session ("ubuntu", "Ubuntu");
            add_session ("gnome", "GNOME");
            add_session ("kde", "KDE");
        }
        else
        {
            foreach (var session in LightDM.get_sessions ())
            {
                debug ("Adding session %s (%s)", session.key, session.name);
                add_session (session.key, session.name);
            }
        }
    }

    private Gtk.Widget build_back_button ()
    {
        var align = new Gtk.Alignment (0.0f, 0.5f, 0.0f, 1.0f);

        var back = new Gtk.Button ();
        UnityGreeter.add_style_class (back);
        back.clicked.connect (() => {session_clicked (null);});
        align.add (back);

        var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        back.add (hbox);

        var image = new Gtk.Image.from_file (Path.build_filename (Config.PKGDATADIR, "arrow_left.png", null));
        hbox.pack_start (image, false, false, 0);

        var label = new Gtk.Label.with_mnemonic (_("_Back"));
        label.mnemonic_widget = back;
        label.halign = Gtk.Align.START;
        hbox.pack_start (label, false, false, 0);

        align.show_all ();
        return align;
    }

    private void add_session (string key, string name)
    {
        var item = new Gtk.Button ();
        item.clicked.connect (() => {session_clicked (key);});
        UnityGreeter.add_style_class (item);

        var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);

        var pixbuf = get_badge (key);
        if (pixbuf != null)
        {
            var image = new CachedImage (pixbuf);
            hbox.pack_start (image, false, false, 0);
        }

        var label = new Gtk.Label (name);
        label.halign = Gtk.Align.START;
        hbox.pack_start (label, true, true, 0);

        item.relief = Gtk.ReliefStyle.NONE;
        item.add (hbox);
        item.show_all ();

        try
        {
            /* Tighten padding on buttons to not be so large */
            var style = new Gtk.CssProvider ();
            style.load_from_data ("* {padding: 3px;}", -1);
            item.get_style_context ().add_provider (style, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }
        catch (Error e)
        {
            debug ("Internal error loading session chooser style: %s", e.message);
        }

        add (item);
    }

    private static string? get_badge_name (string session)
    {
        switch (session)
        {
        case "ubuntu":
        case "ubuntu-2d":
            return "ubuntu_badge.png";
        case "gnome-classic":
        case "gnome-fallback":
        case "gnome-shell":
        case "gnome":
            return "gnome_badge.png";
        case "kde":
        case "kde-plasma":
            return "kde_badge.png";
        case "xterm":
            return "recovery_console_badge.png";
        default:
            return null;
        }
    }

    private static HashTable<string, Gdk.Pixbuf> badges; /* cache of badges */
    public static Gdk.Pixbuf? get_badge (string session)
    {
        var name = get_badge_name (session);

        if (name == null)
        {
            /* Not a known name, but let's see if we have a custom badge before
               giving up entirely and using the unknown badget. */
            var maybe_name = "custom_%s_badge.png".printf (session);
            var maybe_path = Path.build_filename (Config.PKGDATADIR, maybe_name, null);
            if (FileUtils.test (maybe_path, FileTest.EXISTS))
                name = maybe_name;
            else
                name = "unknown_badge.png";
        }

        if (badges == null)
            badges = new HashTable<string, Gdk.Pixbuf> (str_hash, str_equal);

        var pixbuf = badges.lookup (name);
        if (pixbuf == null)
        {
            try
            {
                pixbuf = new Gdk.Pixbuf.from_file (Path.build_filename (Config.PKGDATADIR, name, null));
                badges.insert (name, pixbuf);
            }
            catch (Error e)
            {
                debug ("Error loading badge %s: %s", name, e.message);
            }
        }

        return pixbuf;
    }
}

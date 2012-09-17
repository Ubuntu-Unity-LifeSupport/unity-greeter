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

public class SessionPrompt : PromptBox
{
    public string session { get; construct; }
    public string default_session { get; construct; }

    private Gtk.Widget active;

    public SessionPrompt (string id, string? session, string? default_session)
    {
        Object (id: id, session: session, default_session: default_session);
    }

    construct
    {
        label = _("Select desktop environment");

        if (UnityGreeter.singleton.test_mode)
        {
            add_session ("gnome", "GNOME");
            add_session ("kde", "KDE");
            add_session ("ubuntu", "Ubuntu");
        }
        else
        {
            foreach (var session in LightDM.get_sessions ())
            {
                debug ("Adding session %s (%s)", session.key, session.name);
                add_session (session.key, session.name);
            }
        }

        var ok = new DashButton (_("OK"));
        ok.clicked.connect (() =>
        {
            if (active != null)
                respond ({ active.get_data<string> ("session-list-key") });
            else
                respond ({ null });
        });
        attach_item (ok);

        /* Only have the OK button be end-aligned.  The rest of them are near the top. */
        name_label.vexpand = false;
        ok.valign = Gtk.Align.END;
        ok.vexpand = true;
    }

    private void add_session (string key, string name_in)
    {
        var item = new Gtk.Button ();
        item.clicked.connect (button_clicked_cb);
        UnityGreeter.add_style_class (item);

        var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);

        var pixbuf = SessionList.get_badge (key);
        if (pixbuf != null)
        {
            var image = new CachedImage (pixbuf);
            hbox.pack_start (image, false, false, 0);
        }

        var name = name_in;
        if (key == default_session)
        {
            /* Translators: %s is a session name like KDE or Ubuntu */
            name = _("%s (Default)").printf (name);
        }

        var label = new Gtk.Label (null);
        label.set_markup ("<span font=\"Ubuntu 13\">%s</span>".printf (name));
        label.halign = Gtk.Align.START;
        hbox.pack_start (label, true, true, 0);

        item.hexpand = true;
        item.add (hbox);
        hbox.show_all ();

        try
        {
            /* Tighten padding on buttons to not be so large */
            var style = new Gtk.CssProvider ();
            style.load_from_data ("* {padding: 8px;}", -1);
            item.get_style_context ().add_provider (style, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }
        catch (Error e)
        {
            debug ("Internal error loading session chooser style: %s", e.message);
        }

        item.set_data<string> ("session-list-key", key);
        attach_item (item);
    }

    private void button_clicked_cb (Gtk.Widget button)
    {
        foreach_prompt_widget ((w) =>
        {
            if (w == button)
                w.override_background_color (Gtk.StateFlags.NORMAL, { 0.5f, 0.5f, 0.5f, 0.4f });
            else
                w.override_background_color (Gtk.StateFlags.NORMAL, null);
        });
        active = button;
    }

    public override void grab_focus ()
    {
        var done = false;
        Gtk.Widget best = null;
        foreach_prompt_widget ((w) =>
        {
            if (done)
                return;
            if (best == null)
                best = w; /* first button wins, all else considered */
            var key = w.get_data<string> ("session-list-key");
            if (session == key || (session == null && default_session == key))
            {
                best = w;
                done = true;
            }
        });

        if (best != null)
        {
            best.grab_focus ();
            button_clicked_cb (best);
        }
    }
}

public class SessionList : GreeterList
{
    public signal void session_clicked (string session);
    public string session { get; construct; }
    public string default_session { get; construct; }

    private SessionPrompt prompt;

    public SessionList (Background bg, MenuBar mb, string? session, string? default_session)
    {
        Object (background: bg, menubar: mb, session: session, default_session: default_session);
    }

    construct
    {
        prompt = add_session_prompt ("session");
    }

    private SessionPrompt add_session_prompt (string id)
    {
        var e = new SessionPrompt (id, session, default_session);
        e.respond.connect ((responses) => { session_clicked (responses[0]); });
        add_entry (e);
        return e;
    }

    protected override void add_manual_entry () {}
    public override void show_authenticated (bool successful = true) {}

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
        case "remote-login":
            return "remote_login_help.png";
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

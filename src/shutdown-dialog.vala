/* -*- Mode: Vala; indent-tabs-mode: nil; tab-width: 4 -*-
 *
 * Copyright (C) 2013 Canonical Ltd
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
 */

public enum ShutdownDialogType
{
    LOGOUT,
    SHUTDOWN,
    RESTART
}

public class ShutdownDialog : Gtk.Fixed
{
    public signal void close ();

    private Cairo.ImageSurface? corner_surface = null;
    private Cairo.ImageSurface? left_surface = null;
    private Cairo.ImageSurface? top_surface = null;
    private Cairo.Pattern? corner_pattern = null;
    private Cairo.Pattern? left_pattern = null;
    private Cairo.Pattern? top_pattern = null;
    
    private const int BORDER_SIZE = 30;
    private const int CLOSE_OFFSET = 3;

    private Gtk.Box vbox;
    private DialogButton close_button;
    private Gtk.Box button_box;

    public ShutdownDialog (ShutdownDialogType type)
    {
        vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
        vbox.visible = true;
        add (vbox);

        vbox.border_width = 20;

        var title_label = new Gtk.Label (_("Shutdown"));
        title_label.override_font (Pango.FontDescription.from_string ("Ubuntu Light 15"));
        title_label.override_color (Gtk.StateFlags.NORMAL, { 1.0f, 1.0f, 1.0f, 1.0f });
        title_label.set_alignment (0.0f, 0.5f);
        vbox.pack_start (title_label, false, false, 0);

        string text;
        if (type == ShutdownDialogType.SHUTDOWN)
            text = _("Goodbye. Would you like to…");
        else
        {
            text = _("Are you sure you want to shut down the computer?");
            title_label.visible = true;
        }
        var label = new Gtk.Label (text);
        label.set_line_wrap (true);
        label.override_font (Pango.FontDescription.from_string ("Ubuntu Light 12"));
        label.override_color (Gtk.StateFlags.NORMAL, { 1.0f, 1.0f, 1.0f, 1.0f });
        label.set_alignment (0.0f, 0.5f);
        label.visible = true;
        vbox.pack_start (label, false, false, 0);

        button_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 20);
        button_box.visible = true;
        vbox.pack_start (button_box, false, false, 0);

        if (type == ShutdownDialogType.SHUTDOWN)
        {
            if (LightDM.get_can_suspend ())
            {
                var button = add_button (_("Suspend"), Path.build_filename (Config.PKGDATADIR, "suspend.png"), Path.build_filename (Config.PKGDATADIR, "suspend_highlight.png"));
                button.clicked.connect (() =>
                {
                    try
                    {
                        LightDM.suspend ();
                        close ();
                    }
                    catch (Error e)
                    {
                        warning ("Failed to suspend: %s", e.message);
                    }
                });
            }

            if (LightDM.get_can_hibernate ())
            {
                var button = add_button (_("Hibernate"), Path.build_filename (Config.PKGDATADIR, "hibernate.png"), Path.build_filename (Config.PKGDATADIR, "hibernate_highlight.png"));
                button.clicked.connect (() =>
                {
                    try
                    {
                        LightDM.hibernate ();
                        close ();
                    }
                    catch (Error e)
                    {
                        warning ("Failed to hibernate: %s", e.message);
                    }
                });
            }
        }

        if (LightDM.get_can_restart ())
        {
            var button = add_button (_("Restart"), Path.build_filename (Config.PKGDATADIR, "restart.png"), Path.build_filename (Config.PKGDATADIR, "restart_highlight.png"));
            button.clicked.connect (() =>
            {
                try
                {
                    LightDM.restart ();
                    close ();
                }
                catch (Error e)
                {
                    warning ("Failed to restart: %s", e.message);
                }
            });
        }

        if (LightDM.get_can_shutdown ())
        {
            var button = add_button (_("Shutdown"), Path.build_filename (Config.PKGDATADIR, "shutdown.png"), Path.build_filename (Config.PKGDATADIR, "shutdown_highlight.png"));
            button.clicked.connect (() =>
            {
                try
                {
                    LightDM.shutdown ();
                    close ();
                }
                catch (Error e)
                {
                    warning ("Failed to shutdown: %s", e.message);
                }
            });
        }

        close_button = new DialogButton (Path.build_filename (Config.PKGDATADIR, "dialog_close.png"), Path.build_filename (Config.PKGDATADIR, "dialog_close_highlight.png"));
        close_button.can_focus = false;
        close_button.clicked.connect (() => { close (); });
        close_button.visible = true;
        add (close_button);
    }

    public void focus_next ()
    {
        (get_toplevel () as Gtk.Window).move_focus (Gtk.DirectionType.TAB_FORWARD);
    }

    public void focus_prev ()
    {
        (get_toplevel () as Gtk.Window).move_focus (Gtk.DirectionType.TAB_BACKWARD);
    }

    public void cancel ()
    {
        var widget = (get_toplevel () as Gtk.Window).get_focus ();
        if (widget is DialogButton)
            (get_toplevel () as Gtk.Window).set_focus (null);
        else
            close ();
    }

    public override void size_allocate (Gtk.Allocation allocation)
    {
        base.size_allocate (allocation);

        var content_allocation = Gtk.Allocation ();
        int minimum_width, natural_width, minimum_height, natural_height;
        vbox.get_preferred_width (out minimum_width, out natural_width);
        vbox.get_preferred_height_for_width (minimum_width, out minimum_height, out natural_height);
        content_allocation.x = allocation.x + (allocation.width - minimum_width) / 2;
        content_allocation.y = allocation.y + (allocation.height - minimum_height) / 2;
        content_allocation.width = minimum_width;
        content_allocation.height = minimum_height;
        vbox.size_allocate (content_allocation);

        var a = Gtk.Allocation ();
        close_button.get_preferred_width (out minimum_width, out natural_width);
        close_button.get_preferred_height (out minimum_height, out natural_height);
        a.x = content_allocation.x - BORDER_SIZE + CLOSE_OFFSET;
        a.y = content_allocation.y - BORDER_SIZE + CLOSE_OFFSET;
        a.width = minimum_width;
        a.height = minimum_height;       
        close_button.size_allocate (a);
    }

    public override bool draw (Cairo.Context c)
    {
        if (corner_surface == null)
        {
            corner_surface = new Cairo.ImageSurface.from_png (Path.build_filename (Config.PKGDATADIR, "switcher_corner.png"));
            left_surface = new Cairo.ImageSurface.from_png (Path.build_filename (Config.PKGDATADIR, "switcher_left.png"));
            top_surface = new Cairo.ImageSurface.from_png (Path.build_filename (Config.PKGDATADIR, "switcher_top.png"));
            corner_pattern = new Cairo.Pattern.for_surface (corner_surface);
            left_pattern = new Cairo.Pattern.for_surface (left_surface);
            left_pattern.set_extend (Cairo.Extend.REPEAT);
            top_pattern = new Cairo.Pattern.for_surface (top_surface);
            top_pattern.set_extend (Cairo.Extend.REPEAT);
        }

        var width = vbox.get_allocated_width () + 20 * 2 + BORDER_SIZE * 2;
        var height = vbox.get_allocated_height () + 20 * 2 + BORDER_SIZE * 2;

        /* Darken background */
        c.set_source_rgba (0, 0, 0, 0.25);
        c.paint ();

        /* Draw dialog */
        c.save ();
        c.translate ((get_allocated_width () - width) * 0.5, (get_allocated_height () - height) * 0.5);

        /* Top left */
        var m = Cairo.Matrix.identity ();
        corner_pattern.set_matrix (m);
        c.set_source (corner_pattern);
        c.rectangle (0, 0, BORDER_SIZE, BORDER_SIZE);
        c.fill ();

        /* Top right */
        m = Cairo.Matrix.identity ();
        m.translate (width, 0);
        m.scale (-1, 1);
        corner_pattern.set_matrix (m);
        c.set_source (corner_pattern);
        c.rectangle (width - BORDER_SIZE, 0, BORDER_SIZE, BORDER_SIZE);
        c.fill ();

        /* Bottom left */
        m = Cairo.Matrix.identity ();
        m.translate (0, height);
        m.scale (1, -1);
        corner_pattern.set_matrix (m);
        c.set_source (corner_pattern);
        c.rectangle (0, height - BORDER_SIZE, BORDER_SIZE, BORDER_SIZE);
        c.fill ();

        /* Bottom right */
        m = Cairo.Matrix.identity ();
        m.translate (width, height);
        m.scale (-1, -1);
        corner_pattern.set_matrix (m);
        c.set_source (corner_pattern);
        c.rectangle (width - BORDER_SIZE, height - BORDER_SIZE, BORDER_SIZE, BORDER_SIZE);
        c.fill ();

        /* Left */
        m = Cairo.Matrix.identity ();
        left_pattern.set_matrix (m);
        c.set_source (left_pattern);
        c.rectangle (0, BORDER_SIZE, BORDER_SIZE, height - BORDER_SIZE * 2);
        c.fill ();

        /* Right */
        m = Cairo.Matrix.identity ();
        m.translate (width, 0);
        m.scale (-1, 1);
        left_pattern.set_matrix (m);
        c.set_source (left_pattern);
        c.rectangle (width - BORDER_SIZE, BORDER_SIZE, BORDER_SIZE, height - BORDER_SIZE * 2);
        c.fill ();

        /* Top */
        m = Cairo.Matrix.identity ();
        top_pattern.set_matrix (m);
        c.set_source (top_pattern);
        c.rectangle (BORDER_SIZE, 0, width - BORDER_SIZE * 2, BORDER_SIZE);
        c.fill ();

        /* Right */
        m = Cairo.Matrix.identity ();
        m.translate (0, height);
        m.scale (1, -1);
        top_pattern.set_matrix (m);
        c.set_source (top_pattern);
        c.rectangle (BORDER_SIZE, height - BORDER_SIZE, width - BORDER_SIZE * 2, BORDER_SIZE);
        c.fill ();

        /* Background */
        DashBox.cairo_rounded_rectangle (c, 20, 20, width - 40, height - 40, 5);
        c.set_source_rgba (0, 0, 0, 0.75);
        c.fill ();
       
        c.restore ();

        return base.draw (c);
    }

    public override bool button_press_event (Gdk.EventButton event)
    {
        /* Close when selecting the background */
        // FIXME: Broken..
        close ();
        return true;
    }

    private DialogButton add_button (string text, string inactive_filename, string active_filename)
    {
        var b = new Gtk.Box (Gtk.Orientation.VERTICAL, 9);
        b.visible = true;
        button_box.pack_start (b, false, false, 0);

        var label = new Gtk.Label (text);
        label.visible = true;
        label.override_font (Pango.FontDescription.from_string ("Ubuntu Light 12"));
        label.override_color (Gtk.StateFlags.NORMAL, { 1.0f, 1.0f, 1.0f, 0.0f });
        var button = new DialogButton (inactive_filename, active_filename, label);
        button.visible = true;

        b.pack_start (button, false, false, 0);
        b.pack_start (label, false, false, 0);

        return button;
    }
}

private class DialogButton : Gtk.Button
{
    private string inactive_filename;
    private string active_filename;
    private Gtk.Image i;
    private Gtk.Label? l;
    
    public DialogButton (string inactive_filename, string active_filename, Gtk.Label? label = null)
    {
        this.inactive_filename = inactive_filename;
        this.active_filename = active_filename;
        l = label;
        relief = Gtk.ReliefStyle.NONE;
        focus_on_click = false;
        i = new Gtk.Image.from_file (inactive_filename);
        i.visible = true;
        add (i);
    }
    
    public override bool enter_notify_event (Gdk.EventCrossing event)
    {
        grab_focus ();
        return base.enter_notify_event (event);
    }

    public override bool leave_notify_event (Gdk.EventCrossing event)
    {
        (get_toplevel () as Gtk.Window).set_focus (null);
        return base.leave_notify_event (event);
    }

    public override bool focus_in_event (Gdk.EventFocus event)
    {
        i.set_from_file (active_filename);
        if (l != null)
            l.override_color (Gtk.StateFlags.NORMAL, { 1.0f, 1.0f, 1.0f, 1.0f });
        return base.focus_in_event (event);
    }

    public override bool focus_out_event (Gdk.EventFocus event)
    {
        i.set_from_file (inactive_filename);
        if (l != null)
            l.override_color (Gtk.StateFlags.NORMAL, { 1.0f, 1.0f, 1.0f, 0.0f });
        return base.focus_out_event (event);
    }

    public override bool draw (Cairo.Context c)
    {
        i.draw (c);
        return true;
    }
}

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

public class MainWindow : Gtk.Window
{
    public UserList user_list;

    private List<Monitor> monitors;
    private Background background;
    private MenuBar menubar;
    private Gtk.Box login_box;

    private uint change_background_timeout = 0;

    construct
    {
        events |= Gdk.EventMask.POINTER_MOTION_MASK;

        var accel_group = new Gtk.AccelGroup ();
        add_accel_group (accel_group);

        var bg_color = Gdk.RGBA ();
        bg_color.parse ("#2C001E");
        override_background_color (Gtk.StateFlags.NORMAL, bg_color);
        get_accessible ().set_name (_("Login Screen"));
        has_resize_grip = false;
        UnityGreeter.add_style_class (this);

        realize ();
        background = new Background (Gdk.cairo_create (get_window ()).get_target ());
        background.draw_grid = UGSettings.get_boolean (UGSettings.KEY_DRAW_GRID);
        background.default_background = UGSettings.get_string (UGSettings.KEY_BACKGROUND);
        background.set_logo (UGSettings.get_string (UGSettings.KEY_LOGO), UGSettings.get_string (UGSettings.KEY_BACKGROUND_LOGO));
        background.show ();
        add (background);
        UnityGreeter.add_style_class (background);

        login_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        login_box.show ();
        background.add (login_box);

        menubar = new MenuBar (background, accel_group);
        menubar.notify["high-contrast"].connect (() => {change_background ();});
        menubar.show ();
        login_box.add (menubar);
        UnityGreeter.add_style_class (menubar);

        user_list = new UserList (background, menubar);
        user_list.expand = true;
        user_list.user_displayed_start.connect (() => {
            change_background ();
        });
        user_list.user_displayed_done.connect (() => {
            menubar.set_layouts (user_list.selected_entry.keyboard_layouts);
            change_background ();
        });
        user_list.show ();
        login_box.add (user_list);
        UnityGreeter.add_style_class (user_list);

        if (UnityGreeter.test_mode)
        {
            /* Simulate an 800x600 monitor to the left of a 640x480 monitor */
            monitors = new List<Monitor> ();
            monitors.append (new Monitor (0, 0, 800, 600));
            monitors.append (new Monitor (800, 120, 640, 480));
            background.set_monitors (monitors);
            move_to_monitor (monitors.nth_data (0));
            resize (800 + 640, 600);
        }
        else
        {
            var screen = get_screen ();
            screen.monitors_changed.connect (monitors_changed_cb);
            monitors_changed_cb (screen);
        }
    }

    private void monitors_changed_cb (Gdk.Screen screen)
    {
        debug ("Screen is %dx%d pixels", screen.get_width (), screen.get_height ());
        monitors = new List<Monitor> ();
        for (var i = 0; i < screen.get_n_monitors (); i++)
        {
            Gdk.Rectangle geometry;
            screen.get_monitor_geometry (i, out geometry);
            debug ("Monitor %d is %dx%d pixels at %d,%d", i, geometry.width, geometry.height, geometry.x, geometry.y);

            if (monitor_is_unique_position (screen, i))
                monitors.append (new Monitor (geometry.x, geometry.y, geometry.width, geometry.height));
        }

        background.set_monitors (monitors);
        resize (screen.get_width (), screen.get_height ());
        move (0, 0);
        move_to_monitor (monitors.nth_data (0));
    }
    
    /* Check if a monitor has a unique position */
    private bool monitor_is_unique_position (Gdk.Screen screen, int n)
    {
        Gdk.Rectangle g0;
        screen.get_monitor_geometry (n, out g0);

        for (var i = n + 1; i < screen.get_n_monitors (); i++)
        {
            Gdk.Rectangle g1;
            screen.get_monitor_geometry (i, out g1);

            if (g0.x == g1.x && g0.y == g1.y)
                return false;
        }

        return true;
    }

    private bool change_background_timeout_cb ()
    {
        string new_background_file;
        if (menubar.high_contrast ||
            !UGSettings.get_boolean (UGSettings.KEY_DRAW_USER_BACKGROUNDS))
            new_background_file = null;
        else
            new_background_file = user_list.selected_entry.background;

        background.current_background = new_background_file;

        change_background_timeout = 0;
        return false;
    }

    private void change_background ()
    {
        if (background.current_background != null)
        {
            if (change_background_timeout == 0)
                change_background_timeout = Idle.add (change_background_timeout_cb);
        }
        else
            change_background_timeout_cb ();
    }

    public override bool motion_notify_event (Gdk.EventMotion event)
    {
        var x = (int) (event.x + 0.5);
        var y = (int) (event.y + 0.5);

        /* Get motion event relative to this widget */
        if (event.window != get_window ())
        {
            int w_x, w_y;
            get_window ().get_origin (out w_x, out w_y);
            x -= w_x;
            y -= w_y;
            event.window.get_origin (out w_x, out w_y);
            x += w_x;
            y += w_y;
        }

        foreach (var m in monitors)
        {
            if (x >= m.x && x <= m.x + m.width && y >= m.y && y <= m.y + m.height)
            {
                move_to_monitor (m);
                break;
            }
        }

        return false;
    }

    private void move_to_monitor (Monitor monitor)
    {
        login_box.set_size_request (monitor.width, monitor.height);
        background.set_active_monitor (monitor);
        background.move (login_box, monitor.x, monitor.y);
    }

    public override bool key_press_event (Gdk.EventKey event)
    {
        switch (event.keyval)
        {
        case Gdk.KEY_Escape:
            user_list.cancel_authentication ();
            break;
        case Gdk.KEY_Page_Up:
        case Gdk.KEY_KP_Page_Up:
            user_list.scroll (UserList.ScrollTarget.START);
            break;
        case Gdk.KEY_Page_Down:
        case Gdk.KEY_KP_Page_Down:
            user_list.scroll (UserList.ScrollTarget.END);
            break;
        case Gdk.KEY_Up:
        case Gdk.KEY_KP_Up:
            user_list.scroll (UserList.ScrollTarget.UP);
            break;
        case Gdk.KEY_Down:
        case Gdk.KEY_KP_Down:
            user_list.scroll (UserList.ScrollTarget.DOWN);
            break;
        case Gdk.KEY_F10:
            menubar.select_first (false);
            break;
        default:
            return base.key_press_event (event);
        }

        return true;
    }
}

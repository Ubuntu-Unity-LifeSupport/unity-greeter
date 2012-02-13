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

    private Background background;
    private MenuBar menubar;

    private uint change_background_timeout = 0;

    construct
    {
        var bg_color = Gdk.Color ();
        Gdk.Color.parse ("#2C001E", out bg_color);
        modify_bg (Gtk.StateType.NORMAL, bg_color);
        get_accessible ().set_name (_("Login Screen"));
        has_resize_grip = false;
        UnityGreeter.add_style_class (this);

        if (UnityGreeter.test_mode)
            resize (1024, 600);
        else
        {
            var screen = get_screen ();
            screen.monitors_changed.connect (monitors_changed_cb);
            monitors_changed_cb (screen);
        }

        background = new Background ();
        background.draw_grid = UGSettings.get_boolean (UGSettings.KEY_DRAW_GRID);
        background.default_background = UGSettings.get_string (UGSettings.KEY_BACKGROUND);
        background.set_logo (UGSettings.get_string (UGSettings.KEY_LOGO));
        background.show ();
        add (background);
        UnityGreeter.add_style_class (background);

        menubar = new MenuBar (background);
        menubar.notify["high-contrast"].connect (() => {change_background ();});
        menubar.show ();
        background.add (menubar);
        UnityGreeter.add_style_class (menubar);

        user_list = new UserList (background, menubar);
        user_list.expand = true;
        user_list.user_displayed.connect (() => {
            menubar.set_layouts (user_list.selected_entry.keyboard_layouts);
            change_background ();
        });
        user_list.show ();
        background.add (user_list);
        UnityGreeter.add_style_class (user_list);
    }

    private void monitors_changed_cb (Gdk.Screen screen)
    {
        Gdk.Rectangle geometry;
        screen.get_monitor_geometry (screen.get_primary_monitor (), out geometry);

        debug ("Monitor is %dx%d pixels at %d,%d", geometry.width, geometry.height, geometry.x, geometry.y);

        resize (geometry.width, geometry.height);
        move (geometry.x, geometry.y);
    }

    private bool change_background_timeout_cb ()
    {
        string new_background_file;
        if (menubar.high_contrast)
            new_background_file = null;
        else
            new_background_file = user_list.selected_entry.background;

        background.current_background = new_background_file;

        change_background_timeout = 0;
        return false;
    }

    private void change_background ()
    {
        /* Set background after user stops scrolling */
        if (background.current_background != null)
        {
            if (change_background_timeout != 0)
                Source.remove (change_background_timeout);
            change_background_timeout = Timeout.add (200, change_background_timeout_cb);
        }
        else
            change_background_timeout_cb ();
    }

    public override bool key_press_event (Gdk.EventKey event)
    {
        switch (event.keyval)
        {
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
            var focus = get_focus ();
            if (focus != null && focus != this)
                return focus.key_press_event (event);
            else
                return false;
        }

        return true;
    }
}

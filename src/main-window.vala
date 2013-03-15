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
    public MenuBar menubar;

    private List<Monitor> monitors;
    private Background background;
    private Gtk.Box login_box;
    private Gtk.Box hbox;
    private Gtk.Button back_button;

    public ListStack stack;

    // Menubar is smaller, but with shadow, we reserve more space
    public static const int MENUBAR_HEIGHT = 32;

    construct
    {
        events |= Gdk.EventMask.POINTER_MOTION_MASK;

        var accel_group = new Gtk.AccelGroup ();
        add_accel_group (accel_group);

        var bg_color = Gdk.RGBA ();
        bg_color.parse (UGSettings.get_string (UGSettings.KEY_BACKGROUND_COLOR));
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

        /* Box for menubar shadow */
        var menubox = new Gtk.EventBox ();
        var menualign = new Gtk.Alignment (0.0f, 0.0f, 1.0f, 0.0f);
        var shadow_path = Path.build_filename (Config.PKGDATADIR,
                                               "shadow.png", null);
        var shadow_style = "";
        if (FileUtils.test (shadow_path, FileTest.EXISTS))
        {
            shadow_style = "background-image: url('%s');
                            background-repeat: repeat;".printf(shadow_path);
        }
        try
        {
            var style = new Gtk.CssProvider ();
            style.load_from_data ("* {background-color: transparent;
                                      %s
                                     }".printf(shadow_style), -1);
            var context = menubox.get_style_context ();
            context.add_provider (style,
                                  Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }
        catch (Error e)
        {
            debug ("Internal error loading menubox style: %s", e.message);
        }
        menubox.set_size_request (-1, MENUBAR_HEIGHT);
        menubox.show ();
        menualign.show ();
        menubox.add (menualign);
        login_box.add (menubox);
        UnityGreeter.add_style_class (menualign);
        UnityGreeter.add_style_class (menubox);

        menubar = new MenuBar (background, accel_group);
        menubar.show ();
        menualign.add (menubar);
        UnityGreeter.add_style_class (menubar);

        hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        hbox.expand = true;
        hbox.show ();
        login_box.add (hbox);

        var align = new Gtk.Alignment (0.5f, 0.5f, 0.0f, 0.0f);
        align.set_size_request (grid_size, -1);
        align.margin_bottom = MENUBAR_HEIGHT; /* offset for menubar at top */
        align.show ();
        hbox.add (align);

        back_button = new FlatButton ();
        back_button.focus_on_click = false;
        var image = new Gtk.Image.from_file (Path.build_filename (Config.PKGDATADIR, "arrow_left.png", null));
        image.show ();
        back_button.set_size_request (grid_size - GreeterList.BORDER * 2, grid_size - GreeterList.BORDER * 2);
        back_button.add (image);
        back_button.clicked.connect (pop_list);
        align.add (back_button);

        align = new Gtk.Alignment (0.0f, 0.5f, 0.0f, 1.0f);
        align.show ();
        hbox.add (align);

        stack = new ListStack ();
        stack.show ();
        align.add (stack);

        add_user_list ();

        if (UnityGreeter.singleton.test_mode)
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

    public void push_list (GreeterList widget)
    {
        stack.push (widget);

        if (stack.num_children > 1)
            back_button.show ();
    }

    public void pop_list ()
    {
        if (stack.num_children <= 2)
            back_button.hide ();

        stack.pop ();
    }

    public override void size_allocate (Gtk.Allocation allocation)
    {
        base.size_allocate (allocation);

        if (hbox != null)
        {
            hbox.margin_left = get_grid_offset (get_allocated_width ()) + grid_size;
            hbox.margin_right = get_grid_offset (get_allocated_width ());
            hbox.margin_top = get_grid_offset (get_allocated_height ());
            hbox.margin_bottom = get_grid_offset (get_allocated_height ());
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

    private void add_user_list ()
    {
        GreeterList greeter_list;
        greeter_list = new UserList (background, menubar);
        greeter_list.show ();
        UnityGreeter.add_style_class (greeter_list);
        push_list (greeter_list);
    }

    public override bool key_press_event (Gdk.EventKey event)
    {
        var top = stack.top ();

        switch (event.keyval)
        {
        case Gdk.KEY_Escape:
            top.cancel_authentication ();
            break;
        case Gdk.KEY_Page_Up:
        case Gdk.KEY_KP_Page_Up:
            top.scroll (GreeterList.ScrollTarget.START);
            break;
        case Gdk.KEY_Page_Down:
        case Gdk.KEY_KP_Page_Down:
            top.scroll (GreeterList.ScrollTarget.END);
            break;
        case Gdk.KEY_Up:
        case Gdk.KEY_KP_Up:
            top.scroll (GreeterList.ScrollTarget.UP);
            break;
        case Gdk.KEY_Down:
        case Gdk.KEY_KP_Down:
            top.scroll (GreeterList.ScrollTarget.DOWN);
            break;
        case Gdk.KEY_F10:
            menubar.select_first (false);
            break;
        default:
            return base.key_press_event (event);
        }

        return true;
    }

    public void set_keyboard_state ()
    {
        menubar.set_keyboard_state ();
    }
}

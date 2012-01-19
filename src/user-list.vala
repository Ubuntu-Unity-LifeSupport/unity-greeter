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

private int get_grid_offset (int size)
{
    return (int) (size % grid_size) / 2;
}

private class UserEntry
{
    /* Unique name for this entry */
    public string name;

    /* Label to display */
    public Pango.Layout layout;

    /* Background for this user */
    public string background;

    /* True if should be marked as active */
    public bool is_active;

    /* Keyboard layout to use for this user by default */
    public LightDM.Layout keyboard_layout;
}

private class SessionMenuItem : Gtk.RadioMenuItem
{
    public string session_name;
}

public class UserList : Gtk.Container
{
    private int frame_count = 0;

    public Background background;
    private uint change_background_timeout = 0;

    private List<UserEntry> entries = null;
    private UserEntry? selected_entry = null;
    
    private double scroll_target_location;
    private double scroll_start_location;
    private double scroll_location;
    private double scroll_direction;

    private AnimateTimer scroll_timer;

    private List<Gtk.Widget> children;

    private MenuBar menubar;

    private string? error;
    private string? message;

    private Gtk.Box login_box;
    private Gtk.Entry prompt_entry;
    private Gtk.Button login_button;
    private Gtk.Widget prompt_widget_to_show;
    private Gtk.Button options_button;
    private Gtk.Menu options_menu;
    private Gdk.Pixbuf options_pixbuf;
    unowned GLib.SList<SessionMenuItem> session_group = null;

    private bool complete = false;
    
    private int box_width = 7;

    private uint n_above = 3;
    private uint n_below = 3;

    /* Box in the middle taking up three rows */
    private int box_height = 3;

    private int box_x
    {
        get { return get_grid_offset (get_allocated_width ()) + grid_size; }
    }
    
    private int box_y
    {
        get
        {
            var row = (int) (get_allocated_height () / grid_size - box_height) / 2;
            return get_grid_offset (get_allocated_height ()) + row * grid_size;
        }
    }

    public signal void user_selected (string? username);
    public signal void respond_to_prompt (string text);
    public signal void start_session ();

    public string? selected
    {
        get { if (selected_entry == null) return null; return selected_entry.name; }
    }

    public string? session
    {
        get
        {
            foreach (var item in session_group)
            {
                if (item.active)
                    return item.session_name;
            }
            return null;
        }
        set
        {
            foreach (var item in session_group)
            {
                if (item.session_name == value)
                {
                    item.active = true;
                    return;
                }
            }
        }
    }

    public UserList ()
    {
        can_focus = false;

        background = new Background ();
        background.show ();
        add (background);

        menubar = new MenuBar (background);
        menubar.notify["high-contrast"].connect (() => {change_background ();});
        menubar.show ();
        add (menubar);

        login_box = new DashBox (background);
        login_box.show ();
        add (login_box);

        prompt_entry = new Gtk.Entry ();
        prompt_entry.caps_lock_warning = true;
        prompt_entry.has_frame = false;
        var b = Gtk.Border ();
        b.left = 15;
        b.right = 15;
        b.top = 15;
        b.bottom = 15;
        prompt_entry.set_inner_border (b);
        prompt_entry.activate.connect (prompt_entry_activate_cb);
        add (prompt_entry);

        login_button = new Gtk.Button ();
        var label = new Gtk.Label ("<span font_size=\"large\">%s</span>".printf (/* 'Log In' here is the button for logging in. */
                                                                             _("Log In")));
        label.use_markup = true;
        label.show ();
        login_button.add (label);
        login_button.clicked.connect (login_button_clicked_cb);
        add (login_button);

        try {
            options_pixbuf = new Gdk.Pixbuf.from_file (Path.build_filename (Config.PKGDATADIR, "cog.png", null));
        }
        catch (Error e) {
            debug ("Error loading cog image: %s", e.message);
        }

        options_button = new Gtk.Button ();
        options_button.focus_on_click = false;
        options_button.get_accessible ().set_name (_("Session Options"));
        var image = new Gtk.Image.from_pixbuf (options_pixbuf);
        image.show ();
        options_button.relief = Gtk.ReliefStyle.NONE;
        options_button.add (image);
        options_button.clicked.connect (options_button_clicked_cb);
        options_button.show ();
        add (options_button);

        options_menu = new Gtk.Menu ();

        scroll_timer = new AnimateTimer (AnimateTimer.Speed.FAST);
        scroll_timer.animate.connect (scroll_animate_cb);
    }

    private void redraw_user_list ()
    {
        queue_draw_area (box_x, box_y - (int) (n_above + 1) * grid_size,
                         box_width * grid_size,
                         (int) (n_above + 1 + box_height + n_below + 1) * grid_size);
    }

    private void redraw_login_box ()
    {
        queue_draw_area (box_x, box_y, box_width * grid_size, box_height * grid_size);
    }

    public void show_message (string text, bool error = false)
    {
        message = text;
        redraw_login_box ();
    }

    public void show_prompt (string text, bool secret = false)
    {
        login_button.hide ();
        prompt_entry.hide ();
        message = text;
        prompt_entry.text = "";
        prompt_entry.sensitive = true;
        prompt_entry.visibility = !secret;
        if (scroll_timer.is_running)
            prompt_widget_to_show = prompt_entry;
        else
            prompt_entry.show ();
        var accessible = prompt_entry.get_accessible ();
        if (selected_entry.name != null)
            accessible.set_name (_("Enter password for %s").printf (selected_entry.layout.get_text ()));
        else
        {
            if (prompt_entry.visibility)
                accessible.set_name (_("Enter username"));
            else
                accessible.set_name (_("Enter password"));
        }
        prompt_entry.grab_focus ();
        redraw_login_box ();
    }

    public void show_authenticated ()
    {
        prompt_entry.hide ();
        login_button.hide ();
        message = "";
        if (scroll_timer.is_running)
          prompt_widget_to_show = login_button;
        else
          login_button.show();
        var accessible = login_button.get_accessible ();
        accessible.set_name (_("Login as %s").printf (selected_entry.layout.get_text ()));
        login_button.grab_focus ();
        redraw_login_box ();
    }

    public void login_complete ()
    {
        complete = true;
        sensitive = false;

        error = null;
        message = _("Logging in...");

        login_button.hide ();
        prompt_entry.hide ();

        redraw_login_box ();
    }

    public void set_error (string? text)
    {
        error = text;
        redraw_login_box ();
    }

    public void add_session (string name, string label)
    {
        var item = new SessionMenuItem ();
        item.set_group (session_group);
        item.session_name = name;
        item.label = label;
        item.show ();
        options_menu.append (item);
        session_group = (GLib.SList<SessionMenuItem>) item.get_group ();
    }

    private UserEntry? find_entry (string name)
    {
        foreach (var entry in entries)
        {
            if (entry.name == name)
                return entry;
        }

        return null;
    }

    public void add_entry (string name, string label, string? background, LightDM.Layout? keyboard_layout, bool is_active = false)
    {
        var e = find_entry (name);
        if (e == null)
        {
            e = new UserEntry ();
            entries.append (e);
            e.name = name;
        }
        e.layout = create_pango_layout (label);
        e.layout.set_font_description (Pango.FontDescription.from_string ("Ubuntu 16"));
        e.background = background;
        e.keyboard_layout = keyboard_layout;
        e.is_active = is_active;

        if (selected_entry == null)
            select_entry (e, 1.0);
        else
            select_entry (selected_entry, 1.0);

        redraw_user_list ();
    }

    public void set_active_entry (string ?name)
    {
        var e = find_entry (name);
        if (e != null)
            select_entry (e, 1.0);
    }

    public void remove_entry (string? name)
    {
        var entry = find_entry (name);
        if (entry == null)
            return;

        var index = entries.index (entry);
        entries.remove (entry);

        if (entry == selected_entry)
        {
            if (index >= entries.length ())
                index--;
            select_entry (entries.nth_data (index), -1.0);
        }

        redraw_user_list ();
    }

    private void prompt_entry_activate_cb ()
    {
        respond_to_prompt (prompt_entry.text);
        prompt_entry.text = "";
        prompt_entry.sensitive = false;
    }

    private void login_button_clicked_cb ()
    {
        debug ("Start session for %s", selected_entry.name);
        start_session ();
    }

    private void options_menu_position_cb (Gtk.Menu menu, out int x, out int y, out bool push_in)
    {
        Gtk.Allocation button_allocation;
        options_button.get_allocation (out button_allocation);

        get_window ().get_origin (out x, out y);
        x += button_allocation.x;
        y += button_allocation.y + button_allocation.height;
        push_in = true;
    }

    private void options_button_clicked_cb ()
    {
        options_menu.popup (null, null, options_menu_position_cb, 0, Gtk.get_current_event_time ());
    }

    private void scroll_animate_cb (double progress)
    {
        /* Total height of list */
        var h = entries.length ();

        /* How far we have to go in total, either up or down with wrapping */
        var distance = scroll_target_location - scroll_start_location;
        if (scroll_direction * distance < 0)
            distance += scroll_direction * h;

        /* How far we've gone so far */
        distance *= progress;

        /* Go that far and wrap around */
        scroll_location = scroll_start_location + distance;
        if (scroll_location > h)
            scroll_location -= h;
        if (scroll_location < 0)
            scroll_location += h;

        /* And finally, redraw */
        redraw_user_list ();

        /* Stop when we get there */
        if (progress >= 1.0)
            finished_animating ();
    }

    private bool change_background_timeout_cb ()
    {
        string new_background_file;
        if (menubar.high_contrast)
            new_background_file = null;
        else
            new_background_file = selected_entry.background;

        background.current_background = new_background_file;

        change_background_timeout = 0;
        return false;
    }

    private void change_background ()
    {
        /* Set background after user stops scrolling */
        if (frame_count > 0)
        {
            if (change_background_timeout != 0)
                Source.remove (change_background_timeout);
            change_background_timeout = Timeout.add (200, change_background_timeout_cb);
        }
        else
            change_background_timeout_cb ();
    }

    private void finished_animating ()
    {
        if (prompt_widget_to_show != null) {
          prompt_widget_to_show.show ();
          prompt_widget_to_show = null;
        }
        options_button.show ();
    }

    private void select_entry (UserEntry entry, double direction)
    {
        if (get_realized ())
        {
            scroll_target_location = entries.index (entry);
            scroll_start_location = scroll_location;
            scroll_direction = direction;
            if (scroll_location != scroll_target_location)
                scroll_timer.reset ();
        }

        if (selected_entry != entry)
        {
            selected_entry = entry;

            prompt_entry.hide ();
            login_button.hide ();
            options_button.hide ();

            if (get_realized ())
            {
                change_background ();
                user_selected (selected_entry.name);
            }

            menubar.set_layout (selected_entry.keyboard_layout);
        }
    }

    public override void add (Gtk.Widget widget)
    {
        children.append (widget);
        if (get_realized ())
            widget.set_parent_window (get_window ());
        widget.set_parent (this);
    }

    public override void remove (Gtk.Widget widget)
    {
        widget.unparent ();
        children.remove (widget);
    }

    public override void forall_internal (bool include_internal, Gtk.Callback callback)
    {
        foreach (var child in children)
            callback (child);
    }

    public override void realize ()
    {
        change_background ();

        set_realized (true);

        select_entry (selected_entry, 1);

        Gtk.Allocation allocation;
        get_allocation (out allocation);

        var attributes = Gdk.WindowAttr ();
        attributes.window_type = Gdk.WindowType.CHILD;
        attributes.x = allocation.x;
        attributes.y = allocation.y;
        attributes.width = allocation.width;
        attributes.height = allocation.height;
        attributes.wclass = Gdk.WindowWindowClass.OUTPUT;
        attributes.visual = get_visual ();
        attributes.event_mask = Gdk.EventMask.EXPOSURE_MASK | Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK | Gdk.EventMask.KEY_PRESS_MASK;
        int attributes_mask = Gdk.WindowAttributesType.X | Gdk.WindowAttributesType.Y | Gdk.WindowAttributesType.VISUAL;

        var window = new Gdk.Window (get_parent_window (), attributes, attributes_mask);
        set_window (window);
        window.set_user_data (this);

        foreach (var child in children)
            child.set_parent_window (get_window ());
    }

    public override void map ()
    {
        set_mapped (true);

        foreach (var child in children)
            if (child.visible && !child.get_mapped ())
                child.map ();

        get_window ().show ();
    }

    public override void size_allocate (Gtk.Allocation allocation)
    {
        var resized = allocation.height != get_allocated_height () || allocation.width != get_allocated_width ();
        set_allocation (allocation);
       
        if (!get_realized ())
            return;

        get_window ().move_resize (allocation.x, allocation.y, allocation.width, allocation.height);

        if (resized)
            debug ("Resized to %dx%d", get_allocated_width (), get_allocated_height ());

        var child_allocation = Gtk.Allocation ();

        child_allocation.x = 0;
        child_allocation.y = 0;
        child_allocation.width = allocation.width;
        child_allocation.height = allocation.height;
        background.size_allocate (child_allocation);

        child_allocation.x = 0;
        child_allocation.y = 0;
        child_allocation.width = allocation.width;
        child_allocation.height = 32;
        menubar.size_allocate (child_allocation);

        child_allocation.x = box_x + 6;
        child_allocation.y = box_y + 6;
        child_allocation.width = grid_size * box_width - 12;
        child_allocation.height = grid_size * box_height - 12;
        login_box.size_allocate (child_allocation);

        /* Put prompt entry and login button inside login box */
        child_allocation.x = box_x + grid_size / 2;
        child_allocation.y = box_y + grid_size * 2 - grid_size / 2;
        child_allocation.width = grid_size * (box_width - 1);
        child_allocation.height = grid_size;
        prompt_entry.size_allocate (child_allocation);
        login_button.size_allocate (child_allocation);

        child_allocation.x = box_x + box_width * grid_size - grid_size - grid_size / 4;
        child_allocation.y = box_y + grid_size / 4;
        child_allocation.width = grid_size;
        child_allocation.height = grid_size;
        options_button.size_allocate (child_allocation);
    }

    private void draw_entry (Cairo.Context c, UserEntry entry, double alpha = 0.5, bool in_box = false)
    {
        c.save ();
        
        if (menubar.high_contrast || in_box)
            alpha = 1.0;

        if (entry.is_active)
        {
            c.move_to (8, grid_size / 2 + 0.5 - 4);
            c.rel_line_to (5, 4);
            c.rel_line_to (-5, 4);
            c.close_path ();
            c.set_source_rgba (1.0, 1.0, 1.0, alpha);
            c.fill ();
        }

        int w, h;
        entry.layout.get_pixel_size (out w, out h);

        var bw = (box_width - (in_box ? 1.1 : 0.5)) * grid_size;
        if (w > bw)
        {
            var mask = new Cairo.Pattern.linear (0, 0, bw, 0);
            if (in_box)
            {
                mask.add_color_stop_rgba (1.0 - 27.0 / bw, 1.0, 1.0, 1.0, 1.0);
                mask.add_color_stop_rgba (1.0 - 21.6 / bw, 1.0, 1.0, 1.0, 0.5);
            }
            else
                mask.add_color_stop_rgba (1.0 - 64.0 / bw, 1.0, 1.0, 1.0, alpha);
            mask.add_color_stop_rgba (1.0, 1.0, 1.0, 1.0, 0.0);
            c.set_source (mask);
        }
        else
            c.set_source_rgba (1.0, 1.0, 1.0, alpha);

        c.translate (grid_size / 2, grid_size - (grid_size - (h)) / 2 - h);
        c.move_to (0, 0);
        Pango.cairo_show_layout (c, entry.layout);

        c.restore ();

        /* Now draw options button if we're animating in the box */
        if (in_box && scroll_timer.is_running && options_pixbuf != null)
        {
            c.save ();
            var xpadding = (grid_size - options_pixbuf.width) / 2;
            var ypadding = (grid_size - options_pixbuf.height) / 2;
            c.translate (box_width * grid_size - grid_size - grid_size / 4 + xpadding, grid_size / 4 - ypadding);
            Gdk.cairo_set_source_pixbuf (c, options_pixbuf, 0, 0);
            c.paint ();
            c.restore ();
        }
    }

    private void draw_entry_at_position (Cairo.Context c, UserEntry entry,
                                         double position, bool in_box = false)
    {
        c.save ();
        c.translate (0, position * grid_size);
        var alpha = 1.0;
        if (position < 0)
            alpha = 1.0 + position / (n_above + 1);
        else
            alpha = 1.0 - (position - 2) / (n_below + 1);        
        draw_entry (c, entry, alpha, in_box);
        c.restore ();
    }

    public override bool draw (Cairo.Context c)
    {
        if (frame_count == 0)
            debug ("Rendered first frame");

        frame_count++;

        foreach (var child in children)
            propagate_draw (child, c);

        c.save ();

        c.translate (box_x, box_y);

        var border = 4;

        var index = 0;
        foreach (var entry in entries)
        {
            var position = index - scroll_location;

            /* Draw entries above the box */
            var h_above = (double) (n_above + 1) * grid_size;
            c.save ();

            c.rectangle (0, -h_above, box_width * grid_size, h_above);
            c.clip ();
            draw_entry_at_position (c, entry, position);

            c.restore ();

            /* Draw entries in the box */
            if (position > -1 && position < 1 && scroll_timer.is_running)
            {
                c.save ();
                c.translate (0, border);
                c.rectangle (0, border * 2, box_width * grid_size, box_height * grid_size - border * 5);
                c.clip ();

                if (position <= 0) /* top of box, normal pace */
                    draw_entry_at_position (c, entry, position, true);
                else /* bottom of box; pace must put across bottom halfway through animation */
                    draw_entry_at_position (c, entry, position * box_height * 2, true);

                c.restore ();
            }

            /* Draw entries below the box */
            var h_below = (double) (n_below + 1) * grid_size;
            c.save ();

            c.rectangle (0, box_height * grid_size, box_width * grid_size, h_below);
            c.clip ();
            draw_entry_at_position (c, entry, position + box_height - 1);

            c.restore ();

            index++;
        }

        /* Selected item */
        if (selected_entry != null && !scroll_timer.is_running)
        {
            var text_y = border;

            c.save ();
            c.rectangle (border, border, box_width * grid_size - border * 2, box_height * grid_size - border * 2);
            c.clip ();

            c.save ();
            c.translate (0, text_y);
            draw_entry (c, selected_entry, 1.0);
            c.restore ();

            c.restore();
        }

        if ((error != null || message != null) && !scroll_timer.is_running)
        {
            string text;
            if (error == null)
                text = message;
            else
                text = error;

            var layout = create_pango_layout (text);
            layout.set_font_description (Pango.FontDescription.from_string ("Ubuntu 10"));
            int w, h;
            layout.get_pixel_size (out w, out h);

            c.move_to (grid_size / 2, grid_size * 1.25 - h);

            var r = 1.0;
            var g = 1.0;
            var b = 1.0;
            if (error != null)
            {
                r = 1.0;
                g = 0.0;
                b = 0.0;
            }
            var bw = (box_width - 0.5) * grid_size;
            if (w > bw)
            {
                var mask = new Cairo.Pattern.linear (0, 0, bw, 0);
                mask.add_color_stop_rgba (1.0 - 0.5 * grid_size / bw, r, g, b, 1.0);
                mask.add_color_stop_rgba (1.0, r, g, b, 0.0);
                c.set_source (mask);
            }
            else
                c.set_source_rgb (r, g, b);
            Pango.cairo_show_layout (c, layout);
        }

        c.restore ();

        return false;
    }

    public override bool key_press_event (Gdk.EventKey event)
    {
        switch (event.keyval)
        {
        case Gdk.KEY_Page_Up:
            select_entry (entries.nth_data (0), -1.0);
            break;
        case Gdk.KEY_Up:
            var index = entries.index (selected_entry) - 1;
            if (index < 0)
                index = 0;
            select_entry (entries.nth_data (index), -1.0);
            break;
        case Gdk.KEY_Down:
            var index = entries.index (selected_entry) + 1;
            if (index >= (int) entries.length ())
                index = (int) entries.length () - 1;
            select_entry (entries.nth_data (index), 1.0);
            break;
        case Gdk.KEY_Page_Down:
            select_entry (entries.nth_data (entries.length () - 1), 1.0);
            break;
        case Gdk.KEY_F10:
            menubar.select_first (false);
            break;
        default:
            return false;
        }

        return true;
    }

    private bool inside_entry (double x, double y, double entry_y, UserEntry entry)
    {
        int w, h;
        entry.layout.get_pixel_size (out w, out h);

        /* Allow space to the left of the entry */
        w += grid_size / 2;

        /* Round up to whole grid sizes */
        h = grid_size;
        w = ((int) (w + grid_size) / grid_size) * grid_size;

        return x >= 0 && x <= w && y >= entry_y && y <= entry_y + h;
    }

    public override bool button_release_event (Gdk.EventButton event)
    {
        var x = event.x - box_x;
        var y = event.y - box_y;

        /* Total height of list */        
        var h = (double) entries.length () * grid_size;

        var offset = 0.0;
        foreach (var entry in entries)
        {
            var entry_y = -scroll_location * grid_size + offset;

            /* Check entry above the box */
            var h_above = (double) n_above * grid_size;
            if (y < 0 && y > -h_above)
            {
                if (inside_entry (x, y, entry_y, entry) ||
                    inside_entry (x, y, entry_y - h, entry))
                {
                    select_entry (entry, -1.0);
                    return true;
                }
            }

            /* Check entry below the box */
            var below_y = y - box_height * grid_size;
            var h_below = (double) n_below * grid_size;
            if (below_y > 0 && below_y < h_below)
            {
                if (inside_entry (x, below_y, entry_y - grid_size, entry) ||
                    inside_entry (x, below_y, entry_y - grid_size + h, entry))
                {
                    select_entry (entry, 1.0);
                    return true;
                }
            }

            offset += grid_size;
        }

        return false;
    }
}

/*
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
 * Authored by: Robert Ancell <robert.ancell@canonical.com>
 */

private class UserEntry
{
    public int index;

    public string? name;

    /* Label to display */
    public string label;

    public string? background_filename;
    public Cairo.Pattern background_pattern;

    public double y;
    public double target_y;
    public double direction;
    public double width;

    public bool is_active;

    public bool moving
    {
        get { return y != target_y; }
    }
}

private class SessionMenuItem : Gtk.RadioMenuItem
{
    public string session_name;
}

public class UserList : Gtk.Container
{
    public string default_background = "#000000";

    private int grid_size = 42;
    private int grid_x_offset;
    private int grid_y_offset;
    private int box_width = 7;

    private List<UserEntry> entries = null;
    private UserEntry? selected_entry = null;
    private UserEntry? old_selected_entry = null;

    private uint scroll_animate_timer = 0;

    private uint background_animate_timer = 0;
    private double background_alpha;

    private List<Gtk.Widget> children;

    private Gtk.MenuBar menubar;
    private GLib.List<Indicator.Object> indicators = null;
    
    private string? error;
    private string? message;

    private Cairo.FontFace font_face;
    private Cairo.ImageSurface logo_surface;
    private Cairo.Pattern logo_pattern;

    private Gtk.Entry prompt_entry;
    private Gtk.Button login_button;
    private Gtk.Button options_button;
    private Gtk.Menu options_menu;
    unowned GLib.SList<SessionMenuItem> session_group = null;

    private bool complete = false;

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
        background_alpha = 1.0;

        FreeType.Library library;
        FreeType.init (out library);
        FreeType.Face face;
        FreeType.new_face (library, "/usr/share/fonts/truetype/ubuntu-font-family/Ubuntu-R.ttf", 0, out face);
        font_face = Cairo.ft_font_face_create_for_ft_face (face, 0);

        logo_surface = new Cairo.ImageSurface.from_png (Path.build_filename (Config.PKGDATADIR, "logo.png", null));
        logo_pattern = new Cairo.Pattern.for_surface (logo_surface);

        menubar = new Gtk.MenuBar ();

        menubar.draw.connect_after (menubar_draw_cb);
        menubar.pack_direction = Gtk.PackDirection.RTL;
        menubar.show ();
        add (menubar);

        var i = new Gtk.MenuItem.with_label (Posix.utsname ().nodename);
        i.right_justified = true;
        i.show ();
        menubar.append (i);

        prompt_entry = new Gtk.Entry ();
        prompt_entry.invisible_char = '✻';
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
        var label = new Gtk.Label ("<span font_size=\"large\">" + _("Login") + "</span>");
        label.use_markup = true;
        label.show ();
        login_button.add (label);
        login_button.clicked.connect (login_button_clicked_cb);
        add (login_button);

        options_button = new Gtk.Button ();
        var image = new Gtk.Image.from_file (Path.build_filename (Config.PKGDATADIR, "cog.png", null));
        image.show ();
        options_button.relief = Gtk.ReliefStyle.NONE;
        options_button.add (image);
        options_button.clicked.connect (options_button_clicked_cb);
        add (options_button);

        options_menu = new Gtk.Menu ();

        setup_indicators ();
    }

    private Cairo.Context menubar_cairo_context;

    private void draw_child_cb (Gtk.Widget child)
    {
        menubar.propagate_draw (child, menubar_cairo_context);
    }

    private bool menubar_draw_cb (Cairo.Context c)
    {
        draw_background (c);

        menubar_cairo_context = c;
        menubar.forall (draw_child_cb);

        return false;
    }

    async void greeter_set_env (string key, string val)
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

            yield proxy.call ("UpdateActivationEnvironment",
                              new GLib.Variant ("(a{ss})", builder),
                              GLib.DBusCallFlags.NONE, -1, null);
        }
        catch (Error e)
        {
            warning ("Could not get set environment for indicators: %s", e.message);
            return;
        }
    }

    async void setup_indicators ()
    {
        greeter_set_env ("INDICATOR_GREETER_MODE", "1"); // reduced functionality
        greeter_set_env ("GIO_USE_VFS", "local"); // no gvfsd
        greeter_set_env ("RUNNING_UNDER_GDM", "1"); // for gnome-settings-daemon

        load_indicator ("/usr/lib/indicators3/6/libsession.so");
        load_indicator ("/usr/lib/indicators3/6/libdatetime.so");
        load_indicator ("/usr/lib/indicators3/6/libpower.so");
        load_indicator ("/usr/lib/indicators3/6/libsoundmenu.so");
    }

    public void show_prompt (string text, bool secret = false)
    {
        login_button.hide ();
        message = text;
        prompt_entry.text = "";
        prompt_entry.show ();
        prompt_entry.visibility = !secret;
        prompt_entry.grab_focus ();
        queue_draw ();
    }

    public void show_authenticated ()
    {
        prompt_entry.hide ();
        message = "";
        login_button.show ();
        login_button.grab_focus ();
        queue_draw ();
    }

    public void login_complete ()
    {
        complete = true;
        sensitive = false;

        error = null;
        message = _("Logging in...");

        login_button.hide ();
        prompt_entry.hide ();

        queue_draw ();
    }

    public void set_error (string? text)
    {
        error = text;
        queue_draw ();
    }
    
    private void load_indicator (string filename)
    {
        var io = new Indicator.Object.from_file (filename);
        indicators.append (io);
        io.entry_added.connect (indicator_added_cb);
        io.entry_removed.connect (indicator_removed_cb);
        foreach (var entry in io.get_entries ())
            indicator_added_cb (entry);
    }

    private void indicator_added_cb (Indicator.ObjectEntry entry)
    {
        var menuitem = new Gtk.MenuItem ();
        menuitem.show ();

        var hbox = new Gtk.HBox (false, 3);
        menuitem.add (hbox);
        hbox.show ();

        if (entry.image != null)
            hbox.pack_start (entry.image, false, false, 0);
        if (entry.label != null)
            hbox.pack_start (entry.label, false, false, 0);
        if (entry.menu != null)
            menuitem.submenu = entry.menu;

        menubar.insert (menuitem, (int) menubar.get_children ().length () - 1);
    }

    private void indicator_removed_cb (Indicator.ObjectEntry entry)
    {
        // FIXME
    }

    /* Number of entries in the list */
    private uint n_entries
    {
        get { return entries.length (); }
    }

    /* Half above the line, rounding down */
    private uint n_above
    {
        get { return (n_entries - 1) / 2; }
    }

    /* Half below the line, rounding up */
    private uint n_below
    {
        get { return n_entries / 2; }
    }

    /* Box in the middle taking up three rows */
    private int box_height = 3;

    /* Total height of the box and entries */
    private new int height
    {
        get { return ((int) n_entries - 1) + box_height; }
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

    public void add_entry (string? name, string label, string? background = null, bool is_active = false)
    {
        var e = new UserEntry ();
        e.name = name;
        e.label = label;
        e.background_filename = background;
        e.is_active = is_active;
        e.width = 5;
        e.index = (int) n_entries;
        entries.append (e);

        if (selected_entry == null)
            select_entry (e);

        foreach (var entry in entries)
        {
            update_entry_location (entry);
            entry.y = entry.target_y;
        }

        queue_draw ();
    }

    private void prompt_entry_activate_cb ()
    {
        respond_to_prompt (prompt_entry.text);
        prompt_entry.text = "";
    }
    
    private void login_button_clicked_cb ()
    {
        debug ("login %s", selected_entry.name);
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

    private void update_entry_location (UserEntry entry)
    {
        /* Get the number of steps below the selected item */
        var offset = entry.index - selected_entry.index;

        /* If above then place before box */
        if (offset > (int) n_below)
            offset -= (int) n_entries;
        /* If below then place after box */
        else if (offset < - (int) n_above)
            offset += (int) n_entries;

        entry.target_y = offset;

        /* Move towards new location */
        if (entry.target_y >= entry.y)
            entry.direction = 1.0;
        else
            entry.direction = -1.0;
    }

    private bool scroll_animate_cb ()
    {
        var animating = false;
        foreach (var entry in entries)
        {
            if (entry.y != entry.target_y)
            {
                var speed = 0.1;

                var step = entry.target_y - entry.y;
                if (entry.direction < 0)
                    step = -step;
                if (step < 0)
                    step += height;

                /* If close enough finish moving */
                if (step <= speed)
                    entry.y = entry.target_y;
                else
                {
                    entry.y += speed * entry.direction;

                    /* Wrap around */
                    if (entry.direction < 0 && entry.y < - (int) n_above)
                        entry.y += n_entries;
                    if (entry.direction > 0 && entry.y >= n_below)
                        entry.y -= n_entries;

                }
            }

            if (entry.moving)
                animating = true;
        }

        // FIXME: Should just redraw box
        queue_draw ();

        /* Stop when we get there */
        if (!animating)
        {
            scroll_animate_timer = 0;
            debug ("stop scroll animation");
            return false;
        }
        else
            return true;
    }

    private bool background_animate_cb ()
    {
        background_alpha += 0.05;
        if (background_alpha > 1.0)
            background_alpha = 1.0;

        queue_draw ();

        /* Stop when we get there */
        if (background_alpha == 1.0)
        {
            background_animate_timer = 0;
            debug ("stop background animation");
            return false;
        }
        else
            return true;
    }

    private void select_entry (UserEntry entry)
    {
        debug ("select %s", entry.name);

        /* Roll everything in the same direction */
        var direction = 1.0;
        if (selected_entry != null && entry.y > selected_entry.y)
           direction = -1.0;

        old_selected_entry = selected_entry;
        selected_entry = entry;

        prompt_entry.hide ();
        login_button.hide ();

        user_selected (selected_entry.name);

        if (old_selected_entry != null)
        {
            background_alpha = 0.0;
            if (background_animate_timer == 0)
            {
                debug ("start background animation");
                background_animate_timer = Timeout.add (10, background_animate_cb);
            }
        }

        var animate = false;
        foreach (var e in entries)
        {
            update_entry_location (e);
            e.direction = direction;

            /* Move straight there if haven't selected anything previously */
            if (old_selected_entry == null)
                e.y = e.target_y;

            if (e.moving)
                animate = true;
        }

        if (animate && scroll_animate_timer == 0)
        {
            debug ("start scroll animation");
            scroll_animate_timer = Timeout.add (10, scroll_animate_cb);
        }
    }

    private UserEntry? get_entry_by_index (int index)
    {
        foreach (var entry in entries)
        {
            if (entry.index == index)
                return entry;
        }

        return null;
    }

    private void select_prev_entry ()
    {
        var index = selected_entry.index - 1;
        if (index < 0)
            index += (int) n_entries;
        select_entry (get_entry_by_index (index));
    }

    private void select_next_entry ()
    {
        var index = selected_entry.index + 1;
        if (index >= (int) n_entries)
            index -= (int) n_entries;
        select_entry (get_entry_by_index (index));
    }

    private void get_selected_location (out int x, out int y)
    {
        x = grid_x_offset + grid_size;
        y = grid_y_offset + (get_allocated_height () - box_height * grid_size) / 2;
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
        set_realized (true);

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
        
        if (get_realized ())
            get_window ().move_resize (allocation.x, allocation.y, allocation.width, allocation.height);

        grid_x_offset = (int) (allocation.width % grid_size) / 2;
        grid_y_offset = (int) (allocation.height % grid_size) / 2;

        Gtk.Requisition natural_size;
        menubar.get_preferred_size (null, out natural_size);
        var child_allocation = Gtk.Allocation ();
        natural_size.height = 32;
        natural_size.width = get_allocated_width ();
        child_allocation.x = 0;
        child_allocation.y = 0;
        child_allocation.width = natural_size.width;
        child_allocation.height = natural_size.height;
        menubar.size_allocate (child_allocation);

        /* Put prompt entry and login button inside login box */
        int base_x, base_y;
        get_selected_location (out base_x, out base_y);
        child_allocation.x = base_x + grid_size / 2;
        child_allocation.y = base_y + grid_size * 2 - grid_size / 2;
        child_allocation.width = grid_size * (box_width - 1);
        child_allocation.height = grid_size;
        prompt_entry.size_allocate (child_allocation);
        login_button.size_allocate (child_allocation);

        child_allocation.x = base_x + box_width * grid_size - grid_size - grid_size / 4;
        child_allocation.y = base_y + grid_size / 4;
        child_allocation.width = grid_size;
        child_allocation.height = grid_size;
        options_button.size_allocate (child_allocation);
        options_button.show ();

        /* Regenerate backgrounds */
        if (resized)
        {
            foreach (var entry in entries)
                entry.background_pattern = null;
        }
    }

    private void draw_entries (Cairo.Context c)
    {
        foreach (var entry in entries)
        {
            c.save ();
            c.translate (0, entry.y * grid_size);

            if (entry.is_active)
            {
                c.move_to (8, grid_size / 2 + 0.5 - 4);
                c.rel_line_to (5, 4);
                c.rel_line_to (-5, 4);
                c.close_path ();
                c.set_source_rgba (1.0, 1.0, 1.0, 0.5);
                c.fill ();
            }

            c.set_font_size (0.5 * grid_size);
            Cairo.TextExtents extents;
            c.text_extents (entry.label, out extents);
            c.move_to (grid_size / 2, grid_size - (grid_size - (extents.height)) / 2);
            c.set_source_rgba (1.0, 1.0, 1.0, 0.5);
            c.show_text (entry.label);

            c.restore ();
        }
    }

    private Cairo.Pattern make_background (string? filename)
    {
        if (filename == null)
            filename = default_background;

        debug ("making background %s at %dx%d", filename, get_allocated_width (), get_allocated_height ());

        Gdk.Color color;
        if (Gdk.Color.parse (filename, out color))
        {
            return new Cairo.Pattern.rgb (color.red / 65535.0, color.green / 65535.0, color.blue / 65535.0);
        }

        Gdk.Pixbuf orig_image;
        try
        {
            orig_image = new Gdk.Pixbuf.from_file (filename);
        }
        catch (Error e)
        {
            debug ("Error loading background: %s", e.message);
            return new Cairo.Pattern.rgb (0, 0, 0);
        }

        var target_aspect = (double) get_allocated_width () / get_allocated_height ();
        var aspect = (double) orig_image.width / orig_image.height;
        double scale, offset_x = 0, offset_y = 0;
        if (aspect > target_aspect)
        {
            /* Fit height and trim sides */
            scale = (double) get_allocated_height () / orig_image.height;
            offset_x = (orig_image.width * scale - get_allocated_width ()) / 2;
        }
        else
        {
            /* Fit width and trim top and bottom */
            scale = (double) get_allocated_width () / orig_image.width;
            offset_y = (orig_image.height * scale - get_allocated_height ()) / 2;
        }

        var image = new Gdk.Pixbuf (orig_image.colorspace, orig_image.has_alpha, orig_image.bits_per_sample, get_allocated_width (), get_allocated_height ());
        orig_image.scale (image, 0, 0, get_allocated_width (), get_allocated_height (), -offset_x, -offset_y, scale, scale, Gdk.InterpType.BILINEAR);

        /* Overlay grid */
        var overlay_surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, grid_size, grid_size);
        var oc = new Cairo.Context (overlay_surface);
        oc.rectangle (0, 0, 1, 1);
        oc.rectangle (grid_size - 1, 0, 1, 1);
        oc.rectangle (0, grid_size - 1, 1, 1);
        oc.rectangle (grid_size - 1, grid_size - 1, 1, 1);
        oc.set_source_rgba (1.0, 1.0, 1.0, 0.25);
        oc.fill ();
        var overlay = new Cairo.Pattern.for_surface (overlay_surface);
        var matrix = Cairo.Matrix.identity ();
        matrix.translate (-grid_x_offset, -grid_y_offset);
        overlay.set_matrix (matrix);
        overlay.set_extend (Cairo.Extend.REPEAT);

        /* Create background */
        var surface = new Cairo.ImageSurface (Cairo.Format.RGB24, get_allocated_width (), get_allocated_height ());
        var bc = new Cairo.Context (surface);
        Gdk.cairo_set_source_pixbuf (bc, image, 0, 0);
        bc.paint ();

        /* Draw overlay */
        bc.set_source (overlay);
        bc.rectangle (grid_size - 1, grid_size - 1, get_allocated_width () - grid_size * 2 + 2, get_allocated_height () - grid_size * 2 + 2);
        bc.fill ();
        
        /* Mask out dots under logo */
        bc.rectangle (0, get_allocated_height () - logo_surface.get_height (), logo_surface.get_width (), logo_surface.get_height ());
        Gdk.cairo_set_source_pixbuf (bc, image, 0, 0);
        bc.fill ();

        var pattern = new Cairo.Pattern.for_surface (surface);
        pattern.set_extend (Cairo.Extend.REPEAT);

        return pattern;
    }

    public Cairo.Pattern get_background ()
    {
        return get_background_for_user (selected_entry);
    }

    private Cairo.Pattern get_background_for_user (UserEntry? entry)
    {
        if (entry == null)
            return new Cairo.Pattern.rgb (0, 0, 0);

        if (entry.background_pattern == null)
            entry.background_pattern = make_background (entry.background_filename);
        return entry.background_pattern;
    }
    
    private void draw_background (Cairo.Context c)
    {
        if (background_alpha == 1.0)
        {
            c.set_source (get_background_for_user (selected_entry));
            c.paint ();
        }
        else
        {
            /* Draw old background */
            c.set_source (get_background_for_user (old_selected_entry));
            c.paint ();

            /* Draw new background */
            c.set_source (get_background_for_user (selected_entry));
            c.paint_with_alpha (background_alpha);
        }
    }

    public override bool draw (Cairo.Context c)
    {
        draw_background (c);

        c.set_font_face (font_face);

        /* Logo */
        c.save ();
        c.translate (0, get_allocated_height () - logo_surface.get_height ());
        c.set_source (logo_pattern);
        c.rectangle (0, 0, logo_surface.get_width (), logo_surface.get_height ());
        c.fill ();
        c.restore ();

        int base_x, base_y;
        get_selected_location (out base_x, out base_y);

        c.save ();
        c.translate (base_x, base_y);

        /* Draw entries above the box */
        c.save ();
        c.rectangle (0, -n_above * grid_size, box_width * grid_size, n_above * grid_size);
        c.clip ();
        draw_entries (c);
        c.translate (0, -n_entries * grid_size);
        draw_entries (c);
        c.restore ();

        /* Draw entries below the box */
        c.save ();
        c.rectangle (0, box_height * grid_size, box_width * grid_size, n_below * grid_size);
        c.clip ();
        c.translate (0, (box_height - 1) * grid_size);
        draw_entries (c);
        c.translate (0, n_entries * grid_size);
        draw_entries (c);
        c.restore ();

        /* Draw box */
        var border = 5;
        var box_w = box_width * grid_size - border * 2;
        var box_h = box_height * grid_size - border * 2;
        var box_r = 0.2 * grid_size;
        cairo_rounded_rectangle (c,
                                 border + 0.5, border + 0.5,
                                 box_w - 1, box_h - 1,
                                 box_r);
        c.set_source_rgba (0.0, 0.0, 0.0, 0.4);
        c.fill_preserve ();
        c.set_line_width (1.0);
        c.set_source_rgba (1.0, 1.0, 1.0, 0.25);
        c.stroke ();

        cairo_rounded_rectangle (c,
                                 border + 0.5 + 2, border + 0.5 + 2,
                                 box_w - 5, box_h - 5,
                                 box_r - 2);
        c.stroke ();

        /* Selected item */
        if (selected_entry != null)
        {
            Cairo.TextExtents extents;
            c.set_font_size (0.5 * grid_size);
            c.text_extents (selected_entry.label, out extents);
            var text_y = grid_size - (grid_size - border - extents.height) / 4;

            if (selected_entry.is_active)
            {
                c.move_to (8, text_y - extents.height / 2 + 0.5 - 4);
                c.rel_line_to (5, 4);
                c.rel_line_to (-5, 4);
                c.close_path ();
                c.set_source_rgb (1.0, 1.0, 1.0);
                c.fill ();
            }
            c.move_to (grid_size / 2, text_y);
            c.set_source_rgb (1.0, 1.0, 1.0);
            c.show_text (selected_entry.label);
        }

        if (error != null || message != null)
        {
            Cairo.TextExtents extents;

            string text;
            if (error == null)
                text = message;
            else
                text = error;

            c.set_font_size (0.3 * grid_size);
            c.text_extents (text, out extents);
            c.move_to (grid_size / 2, grid_size * 1.25);
            if (error != null)
                c.set_source_rgb (1.0, 0.0, 0.0);
            else
                c.set_source_rgb (1.0, 1.0, 1.0);
            c.show_text (text);
        }

        c.restore ();

        foreach (var child in children)
            propagate_draw (child, c);

        return false;
    }

    private void cairo_rounded_rectangle (Cairo.Context c, double x, double y, double width, double height, double radius)
    {
        var w = width - radius * 2;
        var h = height - radius * 2;
        var kappa = 0.5522847498 * radius;
        c.move_to (x + radius, y);
        c.rel_line_to (w, 0);
        c.rel_curve_to (kappa, 0, radius, radius - kappa, radius, radius);
        c.rel_line_to (0, h);
        c.rel_curve_to (0, kappa, kappa - radius, radius, -radius, radius);
        c.rel_line_to (-w, 0);
        c.rel_curve_to (-kappa, 0, -radius, kappa - radius, -radius, -radius);
        c.rel_line_to (0, -h);
        c.rel_curve_to (0, -kappa, radius - kappa, -radius, radius, -radius);
    }

    // FIXME: Don't seem to be defined in Vala
    private const uint KEY_Up = 0xff52;
    private const uint KEY_Down = 0xff54;

    public override bool key_press_event (Gdk.EventKey event)
    {
        switch (event.keyval)
        {
        case KEY_Up:
            select_prev_entry ();
            break;
        case KEY_Down:
            select_next_entry ();
            break;
        default:
            return false;
        }

        return true;
    }

    public override bool button_release_event (Gdk.EventButton event)
    {
        int base_x, base_y;
        get_selected_location (out base_x, out base_y);
        foreach (var entry in entries)
        {
            var y = entry.y;
            if (y > 0)
                y += box_height - 1;

            if (event.x >= base_x &&
                event.x <= base_x + entry.width * grid_size &&
                event.y >= base_y + y * grid_size &&
                event.y <= base_y + (y + 1) * grid_size)
            {
                select_entry (entry);
                return true;
            }
        }

        return false;
    }
}

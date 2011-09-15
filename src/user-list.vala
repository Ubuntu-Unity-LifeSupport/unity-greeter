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

private class AnimateTimer
{
    private Timer timer;
    private uint timeout = 0;
    private double last_timestep;

    public signal void animate (double timestep);

    private bool animate_cb ()
    {
        var t = timer.elapsed ();
        var timestep = t - last_timestep;
        last_timestep = t;

        animate (timestep);

        return true;
    }
    
    public bool is_running { get { return timeout != 0; } }

    public void reset ()
    {
        stop ();
        last_timestep = 0.0;
        timer = new Timer ();
        timeout = Timeout.add (10, animate_cb);
    }
    
    public void stop ()
    {
        if (timeout != 0)
            Source.remove (timeout);
        timeout = 0;
    }
}

private class UserEntry
{
    /* Unique name for this entry */
    public string? name;

    /* Label to display */
    public Pango.Layout layout;

    /* Background for this user */
    public Background background;

    /* True if should be marked as active */
    public bool is_active;
}

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
            show();
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

private class SessionMenuItem : Gtk.RadioMenuItem
{
    public string session_name;
}

public class Background
{
    public string filename;
    public int width;
    public int height;
    public int grid_size;
    public int grid_x_offset;
    public int grid_y_offset;
    public Cairo.Surface logo_surface;
    public Cairo.Pattern logo_pattern;

    public Cairo.Pattern pattern;

    private unowned Thread<Cairo.Pattern> thread;
    
    public signal void loaded ();
    
    public Background (string filename)
    {
        this.filename = filename;
    }

    public bool load ()
    {
        if (pattern != null)
            return true;

        Gdk.Color color;
        if (Gdk.Color.parse (filename, out color))
        {
            pattern = new Cairo.Pattern.rgb (color.red / 65535.0, color.green / 65535.0, color.blue / 65535.0);
            return true;
        }

        if (thread != null)
            return false;

        debug ("Making background %s at %dx%d", filename, width, height);
        try
        {
            thread = Thread<Cairo.Pattern>.create<Cairo.Pattern> (render, true);
        }
        catch (ThreadError e)
        {
            pattern = new Cairo.Pattern.rgb (0, 0, 0);            
            return true;
        }

        return false;
    }
    
    private bool ready_cb ()
    {
        debug ("Render of background %s at %dx%d complete", filename, width, height);

        pattern = thread.join ();
        loaded ();

        return false;
    }

    private Cairo.Pattern render ()
    {
        Gdk.Pixbuf orig_image;
        try
        {
            orig_image = new Gdk.Pixbuf.from_file (filename);
        }
        catch (Error e)
        {
            debug ("Error loading background: %s", e.message);
            var pattern = new Cairo.Pattern.rgb (0, 0, 0);
            Gdk.threads_add_idle (ready_cb);
            return pattern;
        }

        var target_aspect = (double) width / height;
        var aspect = (double) orig_image.width / orig_image.height;
        double scale, offset_x = 0, offset_y = 0;
        if (aspect > target_aspect)
        {
            /* Fit height and trim sides */
            scale = (double) height / orig_image.height;
            offset_x = (orig_image.width * scale - width) / 2;
        }
        else
        {
            /* Fit width and trim top and bottom */
            scale = (double) width / orig_image.width;
            offset_y = (orig_image.height * scale - height) / 2;
        }

        var image = new Gdk.Pixbuf (orig_image.colorspace, orig_image.has_alpha, orig_image.bits_per_sample, width, height);
        orig_image.scale (image, 0, 0, width, height, -offset_x, -offset_y, scale, scale, Gdk.InterpType.BILINEAR);

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
        var surface = new Cairo.ImageSurface (Cairo.Format.RGB24, width, height);
        var bc = new Cairo.Context (surface);
        Gdk.cairo_set_source_pixbuf (bc, image, 0, 0);
        bc.paint ();

        /* Draw overlay */
        bc.set_source (overlay);
        bc.rectangle (grid_size - 1, grid_size - 1, width - grid_size * 2 + 2, height - grid_size * 2 + 2);
        bc.fill ();

        /* Draw logo */
        if (logo_surface != null)
        {
            bc.save ();
            var y = (int) (height / grid_size - 2) * grid_size + grid_y_offset;
            bc.translate (grid_x_offset, y);
            bc.set_source (logo_pattern);
            bc.paint_with_alpha (0.5);
            bc.restore ();
        }

        var pattern = new Cairo.Pattern.for_surface (surface);
        pattern.set_extend (Cairo.Extend.REPEAT);

        Gdk.threads_add_idle (ready_cb);
        
        return pattern;
    }
}

private class IndicatorLoader
{
    public Indicator.Object indicator_object;

    private string filename;
    private unowned Thread<Indicator.Object> thread;

    public signal void loaded ();

    public IndicatorLoader (string filename)
    {
        this.filename = filename;
    }

    public void load ()
    {
        debug ("Loading indicator %s", filename);
        
        try
        {
            thread = Thread<Indicator.Object>.create<Indicator.Object> (load_indicator, true);
        }
        catch (ThreadError e)
        {
        }
    }
    
    private bool ready_cb ()
    {
        debug ("Indicator %s loaded", filename);

        indicator_object = thread.join ();
        loaded ();

        return false;
    }

    private Indicator.Object load_indicator ()
    {
        var o = new Indicator.Object.from_file (filename);
        Gdk.threads_add_idle (ready_cb);
        return o;
    }
}

public class UserList : Gtk.Container
{
    private string default_theme_name;

    private int frame_count = 0;

    private Timer draw_timer = null;
    private uint draw_timeout = 0;
    private int draw_count = 0;
    
    private int width;
    private int height;

    private int grid_size = 42;
    private int grid_x_offset;
    private int grid_y_offset;
    private int box_width = 7;

    private HashTable<string, Background> backgrounds;
    private Background background;
    private Background old_background;
    private uint change_background_timeout = 0;

    private List<UserEntry> entries = null;
    private UserEntry? selected_entry = null;
    
    private double scroll_target_location;
    private double scroll_location;
    private double scroll_direction;

    private AnimateTimer scroll_timer;

    private AnimateTimer background_timer;
    private double background_alpha;

    private List<Gtk.Widget> children;

    private Gtk.MenuBar menubar;
    private Cairo.Context menubar_cairo_context;
    private List<IndicatorLoader> indicators = null;
    private Gtk.CheckMenuItem high_contrast_item;

    private Gtk.Socket? keyboard_socket = null;

    private string? error;
    private string? message;

    private Cairo.ImageSurface? logo_surface = null;
    private Cairo.Pattern? logo_pattern;

    private Cairo.ImageSurface? box_surface = null;
    private Cairo.Pattern? box_pattern;

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

    public UserList (int width, int height)
    {
        this.width = width;
        this.height = height;
        grid_x_offset = (int) (width % grid_size) / 2;
        grid_y_offset = (int) (height % grid_size) / 2;

        can_focus = false;
        background_alpha = 1.0;

        Gtk.Settings.get_default ().get ("gtk-theme-name", out default_theme_name);

        menubar = new Gtk.MenuBar ();
        menubar.draw.connect_after (menubar_draw_cb);
        menubar.pack_direction = Gtk.PackDirection.RTL;
        menubar.show ();
        add (menubar);

        var label = new Gtk.Label (Posix.utsname ().nodename);
        label.show ();
        var hostname_item = new Gtk.MenuItem ();
        hostname_item.add (label);
        hostname_item.sensitive = false;
        hostname_item.right_justified = true;
        hostname_item.show ();
        menubar.append (hostname_item);

        /* Hack to get a label showing on the menubar */
        label.ensure_style ();
        label.modify_fg (Gtk.StateType.INSENSITIVE, label.get_style ().fg[Gtk.StateType.NORMAL]);

        prompt_entry = new Gtk.Entry ();
        prompt_entry.invisible_char = '✻';
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
        label = new Gtk.Label ("<span font_size=\"large\">" + _("Login") + "</span>");
        label.use_markup = true;
        label.show ();
        login_button.add (label);
        login_button.clicked.connect (login_button_clicked_cb);
        add (login_button);

        options_button = new Gtk.Button ();
        options_button.focus_on_click = false;
        options_button.get_accessible ().set_name (_("Session Options"));
        var image = new Gtk.Image.from_file (Path.build_filename (Config.PKGDATADIR, "cog.png", null));
        image.show ();
        options_button.relief = Gtk.ReliefStyle.NONE;
        options_button.add (image);
        options_button.clicked.connect (options_button_clicked_cb);
        add (options_button);

        options_menu = new Gtk.Menu ();

        draw_timer = new Timer ();

        box_surface = new Cairo.ImageSurface.from_png (Path.build_filename (Config.PKGDATADIR, "dialog_background.png", null));
        box_pattern = new Cairo.Pattern.for_surface (box_surface);

        backgrounds = new HashTable<string?, Background> (str_hash, str_equal);
        old_background = background = new Background ("#000000");

        scroll_timer = new AnimateTimer ();
        scroll_timer.animate.connect (scroll_animate_cb);
        background_timer = new AnimateTimer ();
        background_timer.animate.connect (background_animate_cb);

        setup_indicators ();
    }

    public void set_logo (string logo_path)
    {
        if (FileUtils.test (logo_path, FileTest.EXISTS))
        {
            logo_surface = new Cairo.ImageSurface.from_png (logo_path);
            logo_pattern = new Cairo.Pattern.for_surface (logo_surface);
        }
        else
        {
            logo_surface = null;
            logo_pattern = null;
        }
    }

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

    void greeter_set_env (string key, string val)
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

    void setup_indicators ()
    {
        /* Set indicators to run with reduced functionality */
        greeter_set_env ("INDICATOR_GREETER_MODE", "1");

        /* Don't allow virtual file systems? */
        greeter_set_env ("GIO_USE_VFS", "local");
        greeter_set_env ("GVFS_DISABLE_FUSE", "1");

        /* Hint to have gnome-settings-daemon run in greeter mode */
        greeter_set_env ("RUNNING_UNDER_GDM", "1");

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
        menubar.insert (a11y_item, (int) menubar.get_children ().length () - 1);

        load_indicator ("/usr/lib/indicators3/6/libsession.so");
        load_indicator ("/usr/lib/indicators3/6/libdatetime.so");
        load_indicator ("/usr/lib/indicators3/6/libpower.so");
        load_indicator ("/usr/lib/indicators3/6/libsoundmenu.so");
    }

    private void keyboard_toggled_cb (Gtk.CheckMenuItem item)
    {
        if (keyboard_socket == null)
        {
            Pid onboard_pid;
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
                                                out onboard_pid,
                                                null,
                                                out onboard_stdout_fd,
                                                null);
                var f = FileStream.fdopen (onboard_stdout_fd, "r");
                var stdout_text = new char[1024];
                f.gets (stdout_text);
                var id = int.parse ((string) stdout_text);

                keyboard_socket = new Gtk.Socket ();
                add (keyboard_socket);
                keyboard_socket.set_size_request (800, 200);
                Gtk.socket_add_id (keyboard_socket, id);
            }
            catch (Error e)
            {
                warning ("Error setting up keyboard: %s", e.message);
            }
        }

        if (keyboard_socket != null)
            keyboard_socket.visible = item.active;
    }

    private void high_contrast_toggled_cb (Gtk.CheckMenuItem item)
    {
        var settings = Gtk.Settings.get_default ();
        if (item.active)
            settings.set ("gtk-theme-name", "HighContrastInverse");
        else
            settings.set ("gtk-theme-name", default_theme_name);
        queue_draw ();
    }

    private void screen_reader_toggled_cb (Gtk.CheckMenuItem item)
    {
        var settings = new Settings ("org.gnome.desktop.a11y.applications");
        settings.set_boolean ("screen-reader-enabled", item.active);
        settings = new Settings ("org.gnome.desktop.interface");
        settings.set_boolean ("toolkit-accessibility", item.active);
    }

    public void show_prompt (string text, bool secret = false)
    {
        login_button.hide ();
        message = text;
        prompt_entry.text = "";
        prompt_entry.show ();
        prompt_entry.visibility = !secret;
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
        queue_draw ();
    }

    public void show_authenticated ()
    {
        prompt_entry.hide ();
        message = "";
        login_button.show ();
        var accessible = login_button.get_accessible ();
        accessible.set_name (_("Login as %s").printf (selected_entry.layout.get_text ()));
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
        var loader = new IndicatorLoader (filename);
        indicators.append (loader);
        loader.loaded.connect (indicator_loaded_cb);
        loader.load ();
    }

    private void indicator_loaded_cb (IndicatorLoader loader)
    {
        var io = loader.indicator_object;

        io.entry_added.connect (indicator_added_cb);
        io.entry_removed.connect (indicator_removed_cb);
        foreach (var entry in io.get_entries ())
            indicator_added_cb (io, entry);
    }

    private uint get_indicator_index (Indicator.Object object)
    {
        uint index = 0;

        foreach (var loader in indicators)
        {
            if (loader.indicator_object == object)
                return index;
            index++;
        }

        return index;
    }

    private Indicator.Object? get_indicator_object_from_entry (Indicator.ObjectEntry entry)
    {
        foreach (var loader in indicators)
        {
            if (loader.indicator_object == null)
                continue;

            foreach (var e in loader.indicator_object.get_entries ())
            {
                if (e == entry)
                    return loader.indicator_object;
            }
        }

        return null;
    }

    private void indicator_added_cb (Indicator.Object object, Indicator.ObjectEntry entry)
    {
        var index = get_indicator_index (object);
        var pos = 0;
        foreach (var child in menubar.get_children ())
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
        menubar.insert (menuitem, pos);
    }

    private void indicator_removed_cb (Indicator.Object object, Indicator.ObjectEntry entry)
    {
        debug ("Removing indicator object %p", entry);

        foreach (var child in menubar.get_children ())
        {
            var menuitem = (IndicatorMenuItem) child;
            if (menuitem.entry == entry)
            {
                menubar.remove (child);
                return;
            }
        }

        warning ("Indicator object %p not in menubar", entry);
    }

    /* Half above the line, rounding down */
    private uint n_above
    {
        get { return (entries.length () - 1) / 2; }
    }

    /* Half below the line, rounding up */
    private uint n_below
    {
        get { return entries.length () / 2; }
    }

    /* Box in the middle taking up three rows */
    private int box_height = 3;

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

    private UserEntry? find_entry (string? name)
    {
        foreach (var entry in entries)
        {
            if (entry.name == name)
                return entry;
        }

        return null;
    }

    public void add_entry (string? name, string label, string background, bool is_active = false)
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
        e.background = make_background (background);
        e.background.loaded.connect (background_loaded_cb);
        e.is_active = is_active;

        if (selected_entry == null)
            select_entry (e, 1.0);
        else
            select_entry (selected_entry, 1.0);

        queue_draw ();
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

        queue_draw ();
    }

    private void prompt_entry_activate_cb ()
    {
        respond_to_prompt (prompt_entry.text);
        prompt_entry.text = "";
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

    private void scroll_animate_cb (double timestep)
    {
        if (scroll_location != scroll_target_location)
        {
            var speed = 5.0;

            var delta = timestep * speed;

            /* Total height of list */
            var h = (double) entries.length ();

            var distance = scroll_target_location - scroll_location;
            if (scroll_direction < 0.0)
                distance = -distance;
            if (distance < 0)
                distance += h;

            /* If close enough finish moving */
            if (distance <= delta)
                scroll_location = scroll_target_location;
            else
            {
                scroll_location += delta * scroll_direction;

                /* Wrap around */
                if (scroll_location > h)
                    scroll_location -= h;
                if (scroll_location < 0)
                    scroll_location += h;
             }

            queue_draw ();
        }

        /* Stop when we get there */        
        if (scroll_location == scroll_target_location)
        {
            debug ("Stop scroll animation");
            scroll_timer.stop ();
        }
    }

    private void background_animate_cb (double timestep)
    {
        var speed = 5.0;

        background_alpha += timestep * speed;
        if (background_alpha > 1.0)
            background_alpha = 1.0;

        queue_draw ();

        /* Stop when we get there */
        if (background_alpha == 1.0)
        {
            debug ("Stop background animation");
            old_background = background;
            background_timer.stop ();
        }
    }
    
    private bool change_background_timeout_cb ()
    {
        if (background != selected_entry.background)
        {
            debug ("Change background");

            if (frame_count > 0)
                background_alpha = 0.0;
            old_background = background;
            background = selected_entry.background;
            queue_draw ();
        }

        change_background_timeout = 0;
        return false;
    }

    private void select_entry (UserEntry entry, double direction)
    {
        debug ("Select %s", entry.name);

        selected_entry = entry;

        prompt_entry.hide ();
        login_button.hide ();

        /* Set background after user stops scrolling */
        if (frame_count > 0)
        {
            if (change_background_timeout != 0)
                Source.remove (change_background_timeout);
            change_background_timeout = Timeout.add (200, change_background_timeout_cb);
        }
        else
            change_background_timeout_cb ();

        user_selected (selected_entry.name);

        scroll_target_location = entries.index (entry);
        scroll_direction = direction;
        /* Move straight there if not drawn yet */
        if (frame_count == 0)
            scroll_location = scroll_target_location;

        if (scroll_location != scroll_target_location && !scroll_timer.is_running)
        {
            debug ("Start scroll animation");
            scroll_timer.reset ();
        }
    }

    private void select_prev_entry ()
    {
        var index = entries.index (selected_entry) - 1;
        if (index < 0)
            index += (int) entries.length ();
        select_entry (entries.nth_data (index), -1.0);
    }

    private void select_next_entry ()
    {
        var index = entries.index (selected_entry) + 1;
        if (index >= (int) entries.length ())
            index -= (int) entries.length ();
        select_entry (entries.nth_data (index), 1.0);
    }

    private void get_selected_location (out int x, out int y)
    {
        x = grid_x_offset + grid_size;
        var row = (int) (get_allocated_height () / grid_size - box_height) / 2;
        y = grid_y_offset + row * grid_size;
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

        /* Put keyboard at the bottom of the screen */
        if (keyboard_socket != null)
        {
            child_allocation.x = 0;
            child_allocation.y = allocation.height - 200;
            child_allocation.width = allocation.width;
            child_allocation.height = 200;
            keyboard_socket.size_allocate (child_allocation);
        }

        /* Regenerate backgrounds */
        if (resized)
        {
            debug ("Regenerating backgrounds");
            backgrounds.remove_all ();
        }
    }

    private void draw_entry (Cairo.Context c, UserEntry entry, double alpha = 0.5)
    {
        c.save ();
        
        // Disable carousel fading - it will need a FFE
        alpha = 0.5;

        if (entry.is_active)
        {
            c.move_to (8, grid_size / 2 + 0.5 - 4);
            c.rel_line_to (5, 4);
            c.rel_line_to (-5, 4);
            c.close_path ();
            c.set_source_rgba (1.0, 1.0, 1.0, alpha);
            c.fill ();
        }

        var mask = new Cairo.Pattern.linear (0, 0, grid_size * box_width, 0);
        var left = 1.0 - 2.0 / 7;
        mask.add_color_stop_rgba (left, 1.0, 1.0, 1.0, alpha);
        mask.add_color_stop_rgba (left + 64.0 / (grid_size * box_width), 1.0, 1.0, 1.0, 0.0);
        c.set_source (mask);

        int w, h;
        entry.layout.get_pixel_size (out w, out h);
        c.translate (grid_size / 2, grid_size - (grid_size - (h)) / 2 - h);
        c.move_to (0, 0);
        Pango.cairo_show_layout (c, entry.layout);

        c.restore ();
    }

    private void background_loaded_cb (Background b)
    {
        queue_draw ();
    }

    private Background make_background (string filename)
    {
        var b = backgrounds.lookup (filename);
        if (b == null)
        {
            b = new Background (filename);
            b.width = width;
            b.height = height;
            b.grid_size = grid_size;
            b.grid_x_offset = grid_x_offset;
            b.grid_y_offset = grid_y_offset;
            b.logo_surface = logo_surface;
            b.logo_pattern = logo_pattern;

            backgrounds.insert (filename, b);
        }

        return b;
    }
    
    public Background get_background ()
    {
        if (selected_entry != null)
            return selected_entry.background;
        else
            return make_background ("#000000");
    }

    private void draw_background (Cairo.Context c)
    {
        /* Fade to this background when loaded */
        if (background.load () && background != old_background && !background_timer.is_running)
        {
            debug ("Start background animation");
            background_timer.reset ();
        }

        c.set_source_rgb (0, 0, 0);

        if (high_contrast_item.active)
            c.paint ();

        /* Draw old background */
        if (background_alpha < 1.0)
        {
            if (old_background.load ())
                c.set_source (old_background.pattern);
            c.paint ();
        }

        /* Draw new background */
        if (background.load () && background_alpha > 0.0)
        {
            c.set_source (background.pattern);
            c.paint_with_alpha (background_alpha);
        }
    }

    private bool draw_expire_cb ()
    {
        var elapsed = draw_timer.elapsed ();
        debug ("Drew %d frames in %.1f seconds (%f fps)", draw_count, elapsed, draw_count / elapsed);

        draw_timer = null;
        draw_count = 0;
        draw_timeout = 0;

        return false;
    }

    public override bool draw (Cairo.Context c)
    {
        if (frame_count == 0)
            debug ("Rendered first frame");

        if (draw_timeout != 0)
            Source.remove (draw_timeout);
        if (draw_timer == null)
            draw_timer = new Timer ();
        draw_timeout = Timeout.add (100, draw_expire_cb);
        draw_count++;

        frame_count++;

        draw_background (c);

        c.save ();

        int base_x, base_y;
        get_selected_location (out base_x, out base_y);
        c.translate (base_x, base_y);

        var index = 0;
        foreach (var entry in entries)
        {
            /* Draw entries above the box */
            var h_above = (double) n_above * grid_size;
            c.save ();
            c.rectangle (0, -h_above, box_width * grid_size, h_above);
            c.clip ();

            c.translate (0, index * grid_size - scroll_location * grid_size);
            var alpha = 1.0 - (scroll_location - index) / (n_above + 1);
            draw_entry (c, entry, alpha);

            c.translate (0, -entries.length () * grid_size);
            alpha = 1.0 - ((scroll_location - (index - (int) entries.length ())) / (n_above + 1));
            draw_entry (c, entry, alpha);

            c.restore ();

            /* Draw entries below the box */
            var h_below = (double) n_below * grid_size;
            c.save ();
            c.rectangle (0, box_height * grid_size, box_width * grid_size, h_below);
            c.clip ();

            c.translate (0, index * grid_size - scroll_location * grid_size);
            c.translate (0, (box_height - 1) * grid_size);
            alpha = 1.0 - (index - scroll_location) / (n_below + 1);
            draw_entry (c, entry, alpha);

            c.translate (0, entries.length () * grid_size);
            alpha = 1.0 - ((index + (int) entries.length ()) - scroll_location) / (n_below + 1);
            draw_entry (c, entry, alpha);

            c.restore ();

            index++;
        }

        /* Draw box */
        c.save ();
        var border = 4;
        c.translate (-border, -border);
        c.set_source (box_pattern);
        c.paint ();
        c.restore ();

        /* Selected item */
        if (selected_entry != null)
        {
            int w, h;
            selected_entry.layout.get_pixel_size (out w, out h);
            var text_y = grid_size - (grid_size - border - h) / 4 - h;

            if (selected_entry.is_active)
            {
                c.move_to (8, text_y + h / 2 + 0.5 - 4);
                c.rel_line_to (5, 4);
                c.rel_line_to (-5, 4);
                c.close_path ();
                c.set_source_rgb (1.0, 1.0, 1.0);
                c.fill ();
            }

            c.move_to (grid_size / 2, text_y);
            var mask = new Cairo.Pattern.linear (0, 0, grid_size * box_width, 0);
            var left = 1.0 - 2.0 / 7;
            mask.add_color_stop_rgba (left, 1.0, 1.0, 1.0, 1.0);
            mask.add_color_stop_rgba (left + 5.4 / (grid_size * box_width), 1.0, 1.0, 1.0, 0.5);
            mask.add_color_stop_rgba (left + 27.0 / (grid_size * box_width), 1.0, 1.0, 1.0, 0.0);
            c.set_source (mask);
            Pango.cairo_show_layout (c, selected_entry.layout);
        }

        if (error != null || message != null)
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
            if (error != null)
                c.set_source_rgb (1.0, 0.0, 0.0);
            else
                c.set_source_rgb (1.0, 1.0, 1.0);
            Pango.cairo_show_layout (c, layout);
        }

        c.restore ();

        foreach (var child in children)
            propagate_draw (child, c);

        return false;
    }

    public override bool key_press_event (Gdk.EventKey event)
    {
        switch (event.keyval)
        {
        case Gdk.KEY_Up:
            debug ("Up pressed");
            select_prev_entry ();
            break;
        case Gdk.KEY_Down:
            debug ("Down pressed");
            select_next_entry ();
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
        int base_x, base_y;
        get_selected_location (out base_x, out base_y);

        var x = event.x - base_x;
        var y = event.y - base_y;

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

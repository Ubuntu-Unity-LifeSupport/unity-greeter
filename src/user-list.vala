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

public class UserEntry
{
    /* Unique name for this entry */
    public string name;

    /* Label to display */
    public Pango.Layout layout;

    /* Background for this user */
    public string background;

    /* True if should be marked as active */
    public bool is_active;

    /* True if have messages */
    public bool has_messages;

    /* Keyboard layouts to use for this user by default */
    public List <LightDM.Layout> keyboard_layouts;

    /* Default session for this user */
    public string session;

    /* Cached cairo surfaces */
    public Cairo.Surface label_in_box_surface;
    public Cairo.Surface label_out_of_box_surface;
}

private class AuthenticationMessage
{
    public Pango.Layout layout;
    public bool is_error;
    
    public AuthenticationMessage (Pango.Layout layout, bool is_error)
    {
        this.layout = layout;
        this.is_error = is_error;
    }
}

public class UserList : Gtk.EventBox
{
    public Background background;
    public MenuBar menubar;
    public UserEntry? selected_entry {get; private set; default = null;}

    private bool _offer_guest = false;
    public bool offer_guest
    {
        get { return _offer_guest; }
        set
        {
            _offer_guest = value;
            if (value)
                add_entry ("*guest", _("Guest Session"));
            else
                remove_entry ("*guest");
        }
    }

    private bool _always_show_manual = false;
    public bool always_show_manual
    {
        get { return _always_show_manual; }
        set
        {
            _always_show_manual = value;
            if (value)
                add_manual_entry ();
            else if (have_users ())
                remove_entry ("*other");
        }
    }

    private List<UserEntry> entries = null;

    private Gdk.Pixbuf message_pixbuf;
    
    private double scroll_target_location;
    private double scroll_start_location;
    private double scroll_location;
    private double scroll_direction;

    private AnimateTimer scroll_timer;

    /* Authentication messages to show */
    private List<AuthenticationMessage> messages = null;

    private Gtk.Fixed fixed;
    private Gtk.Box login_box;
    private DashEntry prompt_entry;
    private DashButton login_button;
    private Fadable prompt_widget_to_show;
    private Gtk.Button session_button;
    private CachedImage session_image;
    private SessionChooser session_chooser;
 
    private enum Mode
    {
        LOGIN,
        TRANSFORM_TO_LOGIN_HIDE,
        TRANSFORM_TO_LOGIN_SHOW,
        SCROLLING,
        SESSIONS,
        TRANSFORM_TO_SESSIONS_HIDE,
    }
    private Mode mode = Mode.LOGIN;

    private bool complete = false;

    private int border = 4;
    private int box_width = 7;

    private uint n_above = 4;
    private uint n_below = 4;

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
    public signal void user_displayed_start ();
    public signal void user_displayed_done ();
    public signal void respond_to_prompt (string text);
    public signal void start_session ();

    public string? selected
    {
        get { if (selected_entry == null) return null; return selected_entry.name; }
    }
    
    private string? _manual_username = null;
    public string? manual_username
    { 
        get { return _manual_username; }
        set
        {
            _manual_username = value;
            if (find_entry ("*other") != null)
                add_manual_entry ();
        }
    }
    
    public string default_session = "ubuntu";

    private string? _session = null;
    public string? session
    {
        get
        {
            return _session;
        }
        set
        {
            _session = value;
            session_image.set_from_pixbuf (get_badge ());
        }
    }

    private Gdk.Pixbuf? last_session_badge = null;

    public UserList (Background bg, MenuBar mb)
    {
        background = bg;
        menubar = mb;
        can_focus = false;
        visible_window = false;

        fixed = new Gtk.Fixed ();
        fixed.show ();
        add (fixed);

        login_box = new DashBox (background);
        login_box.show ();
        add_with_class (login_box);

        session_chooser = new SessionChooser ();
        session_chooser.session_clicked.connect (session_clicked_cb);
        session_chooser.fade_done.connect (session_fade_done_cb);
        session_chooser.show ();
        UnityGreeter.add_style_class (session_chooser);

        prompt_entry = new DashEntry ();
        prompt_entry.caps_lock_warning = true;

        prompt_entry.activate.connect (prompt_entry_activate_cb);
        add_with_class (prompt_entry);

        login_button = new DashButton ("");
        login_button.clicked.connect (login_button_clicked_cb);
        add_with_class (login_button);

        try
        {
            message_pixbuf = new Gdk.Pixbuf.from_file (Path.build_filename (Config.PKGDATADIR, "message.png", null));
        }
        catch (Error e)
        {
            debug ("Error loading message image: %s", e.message);
        }

        session_button = new Gtk.Button ();
        session_button.focus_on_click = false;
        session_button.get_accessible ().set_name (_("Session Options"));
        session_image = new CachedImage (get_badge ());
        session_image.show ();
        session_button.relief = Gtk.ReliefStyle.NONE;
        session_button.add (session_image);
        session_button.clicked.connect (session_button_clicked_cb);
        session_button.show ();
        add_with_class (session_button);

        scroll_timer = new AnimateTimer (AnimateTimer.ease_out_quint, AnimateTimer.FAST);
        scroll_timer.animate.connect (scroll_animate_cb);

        // Start with manual entry, because no users have been added yet.
        // It will be auto-removed when those are added (unless we're told to
        // always show a manual entry).
        add_manual_entry ();
    }

    public enum ScrollTarget
    {
        START,
        END,
        UP,
        DOWN,
    }

    public void cancel_authentication ()
    {
        user_selected (selected_entry.name);
    }

    public void scroll (ScrollTarget target)
    {
        if (mode != Mode.LOGIN && mode != Mode.SCROLLING)
            return;

        switch (target)
        {
        case ScrollTarget.START:
            select_entry (entries.nth_data (0), -1.0);
            break;
        case ScrollTarget.END:
            select_entry (entries.nth_data (entries.length () - 1), 1.0);
            break;
        case ScrollTarget.UP:
            var index = entries.index (selected_entry) - 1;
            if (index < 0)
                index = 0;
            select_entry (entries.nth_data (index), -1.0);
            break;
        case ScrollTarget.DOWN:
            var index = entries.index (selected_entry) + 1;
            if (index >= (int) entries.length ())
                index = (int) entries.length () - 1;
            select_entry (entries.nth_data (index), 1.0);
            break;
        }
    }

    private void add_with_class (Gtk.Widget widget)
    {
        fixed.add (widget);
        UnityGreeter.add_style_class (widget);
    }

    private void redraw_user_list ()
    {
        var y = box_y - (int) (n_above + 1) * grid_size;
        var height = (int) (n_above + 1 + box_height + n_below + 1) * grid_size;
        Gtk.Allocation allocation;
        get_allocation (out allocation);
        queue_draw_area (allocation.x + box_x, allocation.y + y, box_width * grid_size, height);
    }

    private void redraw_login_box ()
    {
        Gtk.Allocation allocation;
        login_box.get_allocation (out allocation);
        queue_draw_area (allocation.x, allocation.y, allocation.width, allocation.height);
    }

    public void show_message (string text, bool is_error = false)
    {
        var layout = create_pango_layout (text);
        layout.set_font_description (Pango.FontDescription.from_string ("Ubuntu 10"));
        messages.append (new AuthenticationMessage (layout, is_error));
        redraw_login_box ();
    }

    public bool have_messages ()
    {
        return messages != null;
    }

    public void clear_messages ()
    {
        messages = new List<AuthenticationMessage> ();
        redraw_login_box ();    
    }

    public void show_prompt (string text, bool secret = false)
    {
        login_button.hide ();
        prompt_entry.hide ();
        if (text.contains ("\n"))
        {
            show_message (text);
            prompt_entry.constant_placeholder_text = "";
        }
        else
        {
            /* Strip trailing colon if present (also handle CJK version) */
            var placeholder = text;
            if (placeholder.has_suffix (":") || placeholder.has_suffix ("："))
            {
                var len = placeholder.char_count ();
                placeholder = placeholder.substring (0, placeholder.index_of_nth_char (len - 1));
            }
            prompt_entry.constant_placeholder_text = placeholder;
        }
        prompt_entry.text = "";
        prompt_entry.sensitive = true;
        prompt_entry.visibility = !secret;
        if (mode == Mode.SCROLLING)
            prompt_widget_to_show = prompt_entry;
        else
            prompt_entry.show ();
        var accessible = prompt_entry.get_accessible ();
        if (selected_entry != null && selected_entry.name != null)
            accessible.set_name (_("Enter password for %s").printf (selected_entry.layout.get_text ()));
        else
        {
            if (prompt_entry.visibility)
                accessible.set_name (_("Enter username"));
            else
                accessible.set_name (_("Enter password"));
        }
        focus_prompt ();
        redraw_login_box ();
    }

    public void focus_prompt ()
    {
        prompt_entry.grab_focus ();
    }

    public void show_authenticated (bool successful = true)
    {
        prompt_entry.hide ();
        login_button.hide ();
        var accessible = login_button.get_accessible ();
        if (successful)
        {
            accessible.set_name (_("Login as %s").printf (selected_entry.layout.get_text ()));
            /* 'Log In' here is the button for logging in. */
            login_button.text = _("Log In");
        }
        else
        {
            accessible.set_name (_("Retry").printf (selected_entry.layout.get_text ()));
            login_button.text = _("Retry");
        }
        if (mode == Mode.SCROLLING)
            prompt_widget_to_show = login_button;
        else
            login_button.show ();
        login_button.grab_focus ();
        redraw_login_box ();
    }

    public void login_complete ()
    {
        complete = true;
        sensitive = false;

        clear_messages ();
        show_message (_("Logging in..."));

        login_button.hide ();
        prompt_entry.hide ();

        redraw_login_box ();
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

    public void add_entry (string name, string label, string? background = null, List <LightDM.Layout>? keyboard_layouts = null, bool is_active = false, bool has_messages = false, string? session = null)
    {
        var e = find_entry (name);
        if (e == null)
        {
            e = new UserEntry ();
            e.name = name;
        }
        else
            entries.remove (e);
        e.layout = create_pango_layout (label);
        e.layout.set_font_description (Pango.FontDescription.from_string ("Ubuntu 16"));
        e.background = background;
        e.keyboard_layouts = keyboard_layouts.copy ();
        e.is_active = is_active;
        e.has_messages = has_messages;
        e.session = session;
        entries.insert_sorted (e, compare_entry);

        if (selected_entry == null)
            select_entry (e, 1.0);
        else
            select_entry (selected_entry, 1.0);

        /* Remove manual option when have users */
        if (have_users () && !always_show_manual)
            remove_entry ("*other");

        redraw_user_list ();
    }

    private static int compare_entry (UserEntry a, UserEntry b)
    {
        if (a.name.has_prefix ("*") || b.name.has_prefix ("*"))
        {
           /* Special entries go after normal ones */
           if (!a.name.has_prefix ("*"))
               return -1;
           if (!b.name.has_prefix ("*"))
               return 1;

           /* Manual comes before guest */
           if (a.name == "*other")
               return -1;
           if (a.name == "*guest")
               return 1;
        }

        /* Alphabetical by label */
        return a.layout.get_text ().ascii_casecmp (b.layout.get_text ());
    }
    
    private bool have_users ()
    {
        foreach (var e in entries)
        {
            if (!e.name.has_prefix ("*"))
                return true;
        }
        return false;
    }

    private void add_manual_entry ()
    {
        var text = manual_username;
        if (text == null)
            text = _("Login");
        add_entry ("*other", text);
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

        /* Show a manual login if no users */
        if (!have_users ())
            add_manual_entry ();

        /* Select previous entry if the selected one was removed */
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
        prompt_entry.sensitive = false;
        respond_to_prompt (prompt_entry.text);
    }

    private void login_button_clicked_cb ()
    {
        debug ("Start session for %s", selected_entry.name);
        start_session ();
    }

    private void session_button_clicked_cb ()
    {
        return_if_fail (mode == Mode.LOGIN);
        mode = Mode.TRANSFORM_TO_SESSIONS_HIDE;
        scroll_timer.reset (AnimateTimer.INSTANT);
    }

    private void session_clicked_cb (string? session)
    {
        return_if_fail (mode == Mode.SESSIONS);

        mode = Mode.TRANSFORM_TO_LOGIN_HIDE;
        session_chooser.fade_out ();

        if (session != null)
            this.session = session;
    }

    private void session_fade_done_cb ()
    {
        /* Either a fade in into SESSIONS mode or a fade out from SESSIONS mode */
        if (mode == Mode.TRANSFORM_TO_LOGIN_HIDE)
        {
            login_box.remove (session_chooser);
            mode = Mode.TRANSFORM_TO_LOGIN_SHOW;
            scroll_timer.reset (AnimateTimer.INSTANT);

            if (prompt_widget_to_show != null)
            {
                prompt_widget_to_show.show ();
                prompt_widget_to_show.grab_focus ();
            }
            session_button.show ();
        }
    }

    private void scroll_animate_cb (double progress)
    {
        switch (mode)
        {
        case Mode.SCROLLING:
            animate_scrolling (progress);
            break;
        case Mode.TRANSFORM_TO_SESSIONS_HIDE:
            animate_to_sessions_hide (progress);
            break;
        case Mode.TRANSFORM_TO_LOGIN_SHOW:
            animate_to_login (progress);
            break;
        }
    }

    private void animate_to_sessions_hide (double progress)
    {
        allocate_login_box ();

        /* Stop when we get there */
        if (progress >= 1.0)
            finished_to_sessions_hide ();

        redraw_user_list ();
    }

    private void finished_to_sessions_hide ()
    {
        login_box.add (session_chooser);

        /* Hide the other login_box widgets while sessions is visible, to
           avoid confusing tab-navigation chain.  This would be easier if these
           were in a proper widget hierarchy, but since they are all just
           floating around in a GtkFixed, we have to work a little harder. */
        if (prompt_entry.visible)
            prompt_widget_to_show = prompt_entry;
        else if (login_button.visible)
            prompt_widget_to_show = login_button;
        prompt_entry.hide ();
        login_button.hide ();
        session_button.hide ();

        session_chooser.fade_in ();
        session_chooser.child_focus (Gtk.DirectionType.TAB_FORWARD);
        mode = Mode.SESSIONS;
    }

    private void animate_to_login (double progress)
    {
        allocate_login_box ();

        /* Stop when we get there */
        if (progress >= 1.0)
            finished_to_login ();

        redraw_user_list ();
    }

    private void finished_to_login ()
    {
        mode = Mode.LOGIN;
    }

    private void animate_scrolling (double progress)
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

        if (progress >= 0.975 && prompt_widget_to_show != null)
        {
            prompt_widget_to_show.fade_in ();
            prompt_widget_to_show = null;
            user_displayed_start ();
        }

        /* Stop when we get there */
        if (progress >= 1.0)
            finished_scrolling ();
    }

    private void finished_scrolling ()
    {
        session_button.show ();
        user_displayed_done ();
        mode = Mode.LOGIN;
    }

    private void select_entry (UserEntry entry, double direction)
    {
        last_session_badge = get_badge ();

        if (!get_realized ())
        {
            /* Just note it for the future if we haven't been realized yet */
            selected_entry = entry;
            session = entry.session;
            return;
        }

        if (scroll_target_location != entries.index (entry))
        {
            var new_target = entries.index (entry);
            var new_direction = direction;
            var new_start = scroll_location;

            if (scroll_location != new_target)
            {
                var new_distance = new_direction * (new_target - new_start);
                // Base rate is 350 (250 + 100).  If we find ourselves going further, slow down animation
                scroll_timer.reset (250 + int.min((int)(100 * (new_distance)), 500));

                if (prompt_entry.visible)
                    prompt_widget_to_show = prompt_entry;
                else if (login_button.visible)
                    prompt_widget_to_show = login_button;

                prompt_entry.hide ();
                login_button.hide ();
                session_button.hide ();

                mode = Mode.SCROLLING;
            }

            scroll_target_location = new_target;
            scroll_direction = new_direction;
            scroll_start_location = new_start;
        }

        if (selected_entry != entry)
        {
            selected_entry = entry;
            session = entry.session;
            user_selected (selected_entry.name);

            if (mode == Mode.LOGIN)
                user_displayed_done (); /* didn't need to move, make sure we trigger side effects */
        }
    }
    
    private Gdk.Pixbuf? get_badge ()
    {
        if (session == null)
            return SessionChooser.get_badge (default_session);
        else
            return SessionChooser.get_badge (session);    
    }

    public override void realize ()
    {
        base.realize ();

        var saved_entry = selected_entry;
        selected_entry = null;
        select_entry (saved_entry, 1);
    }

    private int round_up_to_grid_size (int size)
    {
        if (size % grid_size == 0)
            return size;
        else
            return (size / grid_size + 1) * grid_size;
    }

    private void allocate_login_box ()
    {
        Gtk.Allocation allocation;
        get_allocation (out allocation);

        var child_allocation = Gtk.Allocation ();
        child_allocation.x = allocation.x + box_x + 6;
        child_allocation.y = allocation.y + box_y + 6;
        child_allocation.width = grid_size * box_width - 12;
        child_allocation.height = grid_size * box_height - 6;

        Gtk.Requisition session_request;
        session_chooser.get_preferred_size (null, out session_request);
        var session_height = round_up_to_grid_size (session_request.height + 12);
        if ((session_height / grid_size) % 2 == 0)
            session_height += grid_size; /* make sure we expand equally top and bottom */
        session_height -= 12;
        session_height = int.max (session_height, child_allocation.height);
        var session_distance = session_height - child_allocation.height;

        switch (mode)
        {
        case Mode.TRANSFORM_TO_SESSIONS_HIDE:
            child_allocation.height += (int) (scroll_timer.progress * session_distance);
            child_allocation.y -= (int) (scroll_timer.progress * session_distance) / 2;
            break;
        case Mode.SESSIONS:
        case Mode.TRANSFORM_TO_LOGIN_HIDE:
            child_allocation.height = session_height;
            child_allocation.y -= session_distance / 2;
            break;
        case Mode.TRANSFORM_TO_LOGIN_SHOW:
            child_allocation.height = session_height - (int) (scroll_timer.progress * session_distance);
            child_allocation.y -= (int) ((1.0 - scroll_timer.progress) * session_distance) / 2;
            break;
        }

        login_box.size_allocate (child_allocation);
    }

    public override void size_allocate (Gtk.Allocation allocation)
    {
        base.size_allocate (allocation);

        if (!get_realized ())
            return;

        allocate_login_box ();

        var child_allocation = Gtk.Allocation ();

        /* Put prompt entry and login button inside login box */
        child_allocation.x = allocation.x + box_x + grid_size / 2;
        child_allocation.y = allocation.y + box_y + grid_size * 2 - grid_size / 2;
        child_allocation.width = grid_size * (box_width - 1);
        child_allocation.height = grid_size;
        prompt_entry.size_allocate (child_allocation);
        login_button.size_allocate (child_allocation);

        child_allocation.x = allocation.x + box_x + box_width * grid_size - grid_size - grid_size / 4;
        child_allocation.y = allocation.y + box_y + grid_size / 4;
        child_allocation.width = grid_size;
        child_allocation.height = grid_size;
        session_button.size_allocate (child_allocation);
    }

    private Cairo.Surface entry_ensure_label_surface (UserEntry entry, Cairo.Context orig_c, bool in_box)
    {
        if (in_box && entry.label_in_box_surface != null)
            return entry.label_in_box_surface;
        else if (!in_box && entry.label_out_of_box_surface != null)
            return entry.label_out_of_box_surface;

        int w, h;
        entry.layout.get_pixel_size (out w, out h);

        var bw = (box_width - (in_box ? 1.5 : 0.5)) * grid_size;

        var surface = new Cairo.Surface.similar (orig_c.get_target (), Cairo.Content.COLOR_ALPHA, (int)(bw+1), h);
        var c = new Cairo.Context (surface);

        if (w > bw)
        {
            var mask = new Cairo.Pattern.linear (0, 0, bw, 0);
            if (in_box)
            {
                mask.add_color_stop_rgba (1.0 - 27.0 / bw, 1.0, 1.0, 1.0, 1.0);
                mask.add_color_stop_rgba (1.0 - 21.6 / bw, 1.0, 1.0, 1.0, 0.5);
            }
            else
                mask.add_color_stop_rgba (1.0 - 64.0 / bw, 1.0, 1.0, 1.0, 1.0);
            mask.add_color_stop_rgba (1.0, 1.0, 1.0, 1.0, 0.0);
            c.set_source (mask);
        }
        else
            c.set_source_rgba (1.0, 1.0, 1.0, 1.0);

        Pango.cairo_show_layout (c, entry.layout);

        if (in_box)
            entry.label_in_box_surface = surface;
        else
            entry.label_out_of_box_surface = surface;

        return surface;
    }

    private void draw_entry (Cairo.Context c, UserEntry entry, double alpha = 0.5, bool in_box = false, Gdk.Pixbuf? badge = null)
    {
        c.save ();
        
        if (menubar.high_contrast || in_box)
            alpha = 1.0;

        if (entry.is_active)
        {
            c.move_to (8, grid_size / 2 + 0.5 - 4 + border);
            c.rel_line_to (5, 4);
            c.rel_line_to (-5, 4);
            c.close_path ();
            c.set_source_rgba (1.0, 1.0, 1.0, alpha);
            c.fill ();
        }

        int w, h;
        entry.layout.get_pixel_size (out w, out h);

        var label_x = grid_size / 2;
        var label_y = (grid_size - h) / 2 + border;
        var label_surface = entry_ensure_label_surface (entry, c, in_box);
        c.set_source_surface (label_surface, label_x, label_y);
        c.paint_with_alpha (alpha);

        var bw = (int) ((box_width - (in_box ? 1.5 : 0.5)) * grid_size);
        if (entry.has_messages && (!in_box || label_x + w + 6 + message_pixbuf.get_width () < bw))
        {
            c.translate (label_x + w + 6, label_y + (h - message_pixbuf.get_height ()) / 2);
            var surface = CachedImage.get_cached_surface (c, message_pixbuf);
            c.set_source_surface (surface, 0, 0);
            c.paint_with_alpha (alpha);
        }

        c.restore ();

        /* Now draw session button if we're animating in the box */
        if (in_box && mode == Mode.SCROLLING && badge != null)
        {
            c.save ();
            var xpadding = (grid_size - badge.width) / 2;
            /* FIXME: The 18px offset here is because the visual assets changed size from 40px to 22px.  It should be fixed properly somewhere... */
            var ypadding = (grid_size - badge.height) / 2 - 18;
            c.translate (box_width * grid_size - grid_size - grid_size / 4 + xpadding, grid_size / 4 - ypadding - border);
            var surface = CachedImage.get_cached_surface (c, badge);
            c.set_source_surface (surface, 0, 0);
            c.paint ();
            c.restore ();
        }
    }

    private void draw_entry_at_position (Cairo.Context c, UserEntry entry, double position, bool in_box = false, Gdk.Pixbuf? badge = null)
    {
        c.save ();
        c.translate (0, position * grid_size);
        var alpha = 1.0;
        if (position < 0)
            alpha = 1.0 + position / (n_above + 1);
        else
            alpha = 1.0 - (position - 2) / (n_below + 1);
        draw_entry (c, entry, alpha, in_box, badge);
        c.restore ();
    }

    public override bool draw (Cairo.Context c)
    {
        var max_alpha = 1.0;
        if (mode == Mode.TRANSFORM_TO_SESSIONS_HIDE)
            max_alpha = 1.0 - scroll_timer.progress;
        else if (mode == Mode.TRANSFORM_TO_LOGIN_SHOW)
            max_alpha = scroll_timer.progress;

        c.save ();
        fixed.propagate_draw (login_box, c); /* Always full alpha */
        c.restore ();

        if (mode == Mode.LOGIN ||
            mode == Mode.SCROLLING ||
            mode == Mode.TRANSFORM_TO_SESSIONS_HIDE ||
            mode == Mode.TRANSFORM_TO_LOGIN_SHOW)
        {
            c.save ();
            c.push_group ();

            draw_names (c, NameLocation.OUTSIDE_BOX);
            draw_box_contents (c);
            draw_names (c, NameLocation.INSIDE_BOX);

            c.pop_group_to_source ();
            c.paint_with_alpha (max_alpha);
            c.restore ();
        }

        return false;
    }

    private enum NameLocation
    {
        INSIDE_BOX,
        OUTSIDE_BOX,
    }
    private void draw_names (Cairo.Context c, NameLocation where)
    {
        c.save ();
        c.translate (box_x, box_y);

        var index = 0;
        foreach (var entry in entries)
        {
            var position = index - scroll_location;

            /* Draw entries above the box */
            if (where == NameLocation.OUTSIDE_BOX && position < 0 && position > -1 * (int)(n_above + 1))
            {
                var h_above = (double) (n_above + 1) * grid_size;
                c.save ();

                c.rectangle (0, -h_above, box_width * grid_size, h_above);
                c.clip ();
                draw_entry_at_position (c, entry, position);

                c.restore ();
            }

            /* Draw entries in the box */
            if (where == NameLocation.INSIDE_BOX && position > -1 && position < 1 && mode == Mode.SCROLLING)
            {
                c.save ();
                c.translate (0, border);
                c.rectangle (border, border * 2, box_width * grid_size - border * 2, box_height * grid_size - border * 2);
                c.clip ();

                var badge = last_session_badge;
                if (entry == selected_entry)
                    badge = get_badge ();

                if (position <= 0) /* top of box, normal pace */
                    draw_entry_at_position (c, entry, position, true, badge);
                else /* bottom of box; pace must put across bottom halfway through animation */
                    draw_entry_at_position (c, entry, position * box_height * 2, true, badge);

                c.restore ();
            }

            /* Draw entries below the box */
            if (where == NameLocation.OUTSIDE_BOX && position > 0 && position < n_below + 1)
            {
                var h_below = (double) (n_below + 1) * grid_size;
                c.save ();

                c.rectangle (0, box_height * grid_size, box_width * grid_size, h_below);
                c.clip ();
                draw_entry_at_position (c, entry, position + box_height - 1);

                c.restore ();
            }

            index++;
        }

        c.restore ();
    }

    private void draw_box_contents (Cairo.Context c)
    {
        foreach (var child in fixed.get_children ())
        {
            if (child != login_box)
                fixed.propagate_draw (child, c);
        }

        c.save ();

        c.translate (box_x, box_y);

        /* Selected item */
        if (selected_entry != null && mode != Mode.SCROLLING)
        {
            c.save ();

            c.rectangle (border, border, box_width * grid_size - border * 2, box_height * grid_size - border * 2);
            c.clip ();
            c.translate (0, border);
            draw_entry (c, selected_entry, 1.0, true);

            c.restore ();
        }

        if (mode != Mode.SCROLLING)
        {
            var vertical_offset = 0.0;
            foreach (var m in messages)
            {
                int w, h;
                m.layout.get_pixel_size (out w, out h);
                vertical_offset += h;
            }

            foreach (var m in messages)
            {
                int w, h;
                m.layout.get_pixel_size (out w, out h);

                c.move_to (grid_size / 2, grid_size * 1.25 - vertical_offset + border);
                vertical_offset -= h;

                var r = 1.0;
                var g = 1.0;
                var b = 1.0;
                if (m.is_error)
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
                Pango.cairo_show_layout (c, m.layout);
            }
        }

        c.restore ();
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
        if (mode != Mode.LOGIN)
            return false;

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
            if (entry_y < 0 && y < 0 && y > -h_above)
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
            if (entry_y > 0 && below_y > 0 && below_y < h_below)
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

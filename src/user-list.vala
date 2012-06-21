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

    /* Label text */
    public string label;

    /* Name widget */
    public PromptBox prompt_box;

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

    private Gtk.Fixed fixed;
    private DashBox login_box;
    private PromptBox prompt_widget_to_show;
    private SessionChooser session_chooser;
 
    private enum Mode
    {
        LOGIN,
        SCROLLING,
    }
    private Mode mode = Mode.LOGIN;

    private bool complete = false;

    public static const int BORDER = 6;
    public static const int BOX_WIDTH = 7;

    private uint n_above = 4;
    private uint n_below = 4;

    /* Box in the middle taking up three rows */
    public static const int BOX_HEIGHT = 3;

    private int box_x
    {
        get { return get_grid_offset (get_allocated_width ()) + grid_size; }
    }
    
    private int box_y
    {
        get
        {
            var row = (int) (get_allocated_height () / grid_size - BOX_HEIGHT) / 2;
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

    private string _default_session = "ubuntu";
    public string default_session
    {
        get
        {
            return _default_session;
        }
        set
        {
            _default_session = value;
            if (selected_entry != null)
                selected_entry.prompt_box.set_options_image (get_badge ());
        }
    }

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
            if (selected_entry != null)
                selected_entry.prompt_box.set_options_image (get_badge ());
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
        login_box.notify["base-alpha"].connect (() => {queue_draw ();});
        login_box.show ();
        add_with_class (login_box);

        session_chooser = new SessionChooser ();
        session_chooser.session_clicked.connect (session_clicked_cb);
        session_chooser.show ();
        UnityGreeter.add_style_class (session_chooser);

        try
        {
            message_pixbuf = new Gdk.Pixbuf.from_file (Path.build_filename (Config.PKGDATADIR, "message.png", null));
        }
        catch (Error e)
        {
            debug ("Error loading message image: %s", e.message);
        }

        scroll_timer = new AnimateTimer (AnimateTimer.ease_out_quint, AnimateTimer.FAST);
        scroll_timer.animate.connect (animate_scrolling);

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
        if (login_box.has_content)
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

    private void redraw_login_box ()
    {
        Gtk.Allocation allocation;
        login_box.get_allocation (out allocation);
        queue_draw_area (allocation.x, allocation.y, allocation.width, allocation.height);
    }

    public void show_message (string text, bool is_error = false)
    {
        selected_entry.prompt_box.add_message (text, is_error);
    }

    public bool have_messages ()
    {
        return selected_entry.prompt_box.has_messages;
    }

    public void clear_messages ()
    {
        selected_entry.prompt_box.clear ();
    }

    public void show_prompt (string text, bool secret = false)
    {
        string accessible_text = null;
        if (selected_entry != null && selected_entry.name != null)
            accessible_text = _("Enter password for %s").printf (selected_entry.label);
        selected_entry.prompt_box.add_prompt (text, accessible_text, secret);

        if (mode == Mode.SCROLLING)
            prompt_widget_to_show = selected_entry.prompt_box;
        else
            selected_entry.prompt_box.show_prompts ();

        focus_prompt ();
        redraw_login_box ();
    }

    public void focus_prompt ()
    {
        selected_entry.prompt_box.sensitive = true;
        selected_entry.prompt_box.grab_focus ();
    }

    public void show_authenticated (bool successful = true)
    {
        if (successful)
        {
            /* 'Log In' here is the button for logging in. */
            selected_entry.prompt_box.add_button (_("Log In"),
                                                  _("Login as %s").printf (selected_entry.label));
        }
        else
        {
            selected_entry.prompt_box.add_button (_("Retry"),
                                                  _("Retry as %s").printf (selected_entry.label));
        }

        if (mode == Mode.SCROLLING)
            prompt_widget_to_show = selected_entry.prompt_box;
        else
            selected_entry.prompt_box.show_prompts ();

        focus_prompt ();
        redraw_login_box ();
    }

    public void login_complete ()
    {
        complete = true;
        sensitive = false;

        selected_entry.prompt_box.clear ();
        selected_entry.prompt_box.add_message (_("Logging in..."), false);

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
        e.label = label;
        e.background = background;
        e.keyboard_layouts = keyboard_layouts.copy ();
        e.is_active = is_active;
        e.has_messages = has_messages;
        e.session = session;

        e.prompt_box = new PromptBox ();
        e.prompt_box.expand = true;
        e.prompt_box.set_name (label);
        e.prompt_box.set_show_message_icon (has_messages);
        e.prompt_box.set_is_active (is_active);
        e.prompt_box.respond.connect (prompt_box_respond_cb);
        e.prompt_box.login.connect (prompt_box_login_cb);
        e.prompt_box.show_options.connect (prompt_box_show_options_cb);
        e.prompt_box.set_size_request (grid_size * BOX_WIDTH - BORDER * 2, -1);
        add_with_class (e.prompt_box);

        entries.insert_sorted (e, compare_entry);

        if (selected_entry == null)
            select_entry (e, 1.0);
        else
            select_entry (selected_entry, 1.0);

        /* Remove manual option when have users */
        if (have_users () && !always_show_manual)
            remove_entry ("*other");

        queue_draw ();
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
        return a.label.ascii_casecmp (b.label);
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
        entry.prompt_box.destroy ();
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

        queue_draw ();
    }

    private void prompt_box_respond_cb (string response)
    {
        selected_entry.prompt_box.sensitive = false;
        respond_to_prompt (response);
    }

    private void prompt_box_login_cb ()
    {
        debug ("Start session for %s", selected_entry.name);
        start_session ();
    }

    private void prompt_box_show_options_cb ()
    {
        login_box.push (session_chooser);
    }

    private void session_clicked_cb (string? session)
    {
        login_box.pop ();

        if (session != null)
            this.session = session;
    }

    private int get_login_box_height ()
    {
        int height;
        login_box.get_preferred_height (null, out height);
        return height;
    }

    /* guaranteed to return an odd number */
    private int get_login_box_height_grids ()
    {
        int height = get_login_box_height ();
        return height / grid_size + 1; /* +1 because we'll be slightly under due to BORDER */
    }

    private int get_login_box_x ()
    {
        return box_x + BORDER;
    }

    private int get_login_box_y ()
    {
        //int height = get_login_box_height_grids ();

        /* Normal box_y is based on BOX_HEIGHT boxes.  Modify as we need */
        //return box_y + BORDER - (height - BOX_HEIGHT) / 2 * grid_size;
        return box_y + BORDER;
    }

    private int get_position_y (double position)
    {
        double grid_number = position;

        if (position >= 0.0 && position < 1.0)
        {
            var grids = get_login_box_height_grids ();
            grid_number = position * grids; /* scaled to height of login box */
        }
        else if (position >= 1.0)
        {
            var grids = get_login_box_height_grids ();
            grid_number = position + grids - 1.0;
        }

        return get_login_box_y () + (int)(grid_number * grid_size);
    }

    private void move_entry (UserEntry entry, double position)
    {
        var alpha = 1.0;
        if (position < 0)
            alpha = 1.0 + position / (n_above + 1);
        else
            alpha = 1.0 - position / (n_below + 1);
        entry.prompt_box.set_alpha (alpha);

        var child_allocation = Gtk.Allocation ();
        child_allocation.width = grid_size * BOX_WIDTH - BORDER * 2;
        entry.prompt_box.get_preferred_height_for_width (child_allocation.width, null, out child_allocation.height);
        child_allocation.x = get_login_box_x ();
        child_allocation.y = get_position_y (position);
        fixed.move (entry.prompt_box, child_allocation.x, child_allocation.y);
        entry.prompt_box.size_allocate (child_allocation);

        entry.prompt_box.show ();
    }

    private void move_names ()
    {
        var index = 0;
        foreach (var entry in entries)
        {
            var position = index - scroll_location;

            entry.prompt_box.hide (); // hide by default

            /* Draw entries above the box */
            if (position <= -1 && position > -1 * (int)(n_above + 1))
                move_entry (entry, position);

            /* Draw entries in the box */
            if (position > -1 && position < 1 && mode == Mode.SCROLLING)
                move_entry (entry, position);

            /* Draw entries below the box */
            if (position >= 1 && position < n_below + 1)
                move_entry (entry, position);

            index++;
        }
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

        move_names ();

        /* And finally, redraw */
        queue_draw ();

        if (progress >= 0.975 && prompt_widget_to_show != null)
        {
            setup_prompt_box ();
            prompt_widget_to_show.fade_in_prompts ();
            prompt_widget_to_show = null;
            user_displayed_start ();
        }

        /* Stop when we get there */
        if (progress >= 1.0)
            finished_scrolling ();
    }

    private void finished_scrolling ()
    {
        user_displayed_done ();
        mode = Mode.LOGIN;
        login_box.set_base (selected_entry.prompt_box);
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

                mode = Mode.SCROLLING;
            }

            scroll_target_location = new_target;
            scroll_direction = new_direction;
            scroll_start_location = new_start;

            login_box.set_base (null);
        }

        if (selected_entry != entry)
        {
            if (selected_entry != null)
            {
                selected_entry.prompt_box.clear ();
            }

            selected_entry = entry;
            session = entry.session;
            setup_prompt_box ();
            user_selected (selected_entry.name);

            if (mode == Mode.LOGIN)
            {
                /* don't need to move, but make sure we trigger the same side effects */
                scroll_timer.reset (0);
                mode = Mode.SCROLLING;
            }
        }
    }

    private void setup_prompt_box ()
    {
        selected_entry.prompt_box.set_name (selected_entry.label);
        selected_entry.prompt_box.set_show_message_icon (selected_entry.has_messages);
        selected_entry.prompt_box.set_is_active (selected_entry.is_active);
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

    private void allocate_login_box ()
    {
        Gtk.Allocation allocation;
        get_allocation (out allocation);

        var child_allocation = Gtk.Allocation ();
        login_box.get_preferred_width (null, out child_allocation.width);
        login_box.get_preferred_height (null, out child_allocation.height);
        child_allocation.x = allocation.x + get_login_box_x ();
        child_allocation.y = allocation.y + get_login_box_y ();
        fixed.move (login_box, child_allocation.x, child_allocation.y);
        login_box.size_allocate (child_allocation);

        foreach (var entry in entries)
        {
            entry.prompt_box.set_zone (login_box);
        }
    }

    public override void size_allocate (Gtk.Allocation allocation)
    {
        base.size_allocate (allocation);

        if (!get_realized ())
            return;

        allocate_login_box ();
    }

    public override bool draw (Cairo.Context c)
    {
        c.save ();
        fixed.propagate_draw (login_box, c); /* Always full alpha */
        c.restore ();

        if (login_box.base_alpha != 0.0)
        {
            c.save ();
            c.push_group ();

            c.rectangle (box_x + BORDER, box_y - n_above * grid_size, grid_size * BOX_WIDTH - BORDER * 2, grid_size * (n_above + n_below + BOX_HEIGHT));
            c.clip ();

            foreach (var child in fixed.get_children ())
            {
                if (child != login_box)
                    fixed.propagate_draw (child, c);
            }

            c.pop_group_to_source ();
            c.paint_with_alpha (login_box.base_alpha);
            c.restore ();
        }

        return false;
    }

    private bool inside_entry (double x, double y, double entry_y, UserEntry entry)
    {
        int w, h;
        w = entry.prompt_box.get_allocated_width ();
        h = entry.prompt_box.get_allocated_height ();

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
            var below_y = y - BOX_HEIGHT * grid_size;
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

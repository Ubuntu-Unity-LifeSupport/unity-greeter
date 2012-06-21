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

public class PromptBox : FadableBox
{
    public signal void respond (string response);
    public signal void login ();
    public signal void show_options ();

    public bool has_messages {get; private set; default = false;}

    private Gtk.Fixed fixed;
    private Gtk.Widget zone; /* when overlapping zone we are fully expanded */

    /* Expanded widgets */
    private Gtk.Grid box_grid;
    private ActiveIndicator active_indicator;
    private FadingLabel name_label;
    private Gtk.Button option_button;
    private CachedImage option_image;
    private CachedImage message_image;

    /* Condensed widgets */
    private Gtk.Grid small_box_grid;
    private ActiveIndicator small_active_indicator;
    private FadingLabel small_name_label;
    private CachedImage small_message_image;

    private static const int COL_ACTIVE        = 0;
    private static const int COL_CONTENT       = 1;
    private static const int COL_SPACER        = 2;

    private static const int ROW_NAME          = 0;
    private static const int COL_NAME_LABEL    = 0;
    private static const int COL_NAME_MESSAGE  = 1;
    private static const int COL_NAME_OPTIONS  = 2;

    private static const int COL_ENTRIES_START = 1;
    private static const int COL_ENTRIES_END   = 1;
    private static const int COL_ENTRIES_WIDTH = 1;
    private static const int ROW_ENTRIES_START = 1;

    private int last_row;

    construct
    {
        expand = true;
        orientation = Gtk.Orientation.VERTICAL;

        fixed = new Gtk.Fixed ();
        fixed.show ();
        add (fixed);

        /* Create fully expanded version of ourselves */
        var name_grid = new Gtk.Grid ();
        name_grid.column_spacing = 4;
        name_grid.hexpand = true;

        box_grid = new Gtk.Grid ();
        box_grid.column_spacing = 4;
        box_grid.row_spacing = 3;
        box_grid.expand = true;

        /** Grid layout:
          0 1     2      3 4
          > Name  M      S <
            Message.......
            Entry.........
         */

        active_indicator = new ActiveIndicator ();
        active_indicator.valign = Gtk.Align.CENTER;
        active_indicator.show ();
        box_grid.attach (active_indicator, COL_ACTIVE, ROW_NAME, 1, 1);

        // Add a second one on right just for equal-spacing purposes
        var dummy_indicator = new ActiveIndicator ();
        dummy_indicator.show ();
        box_grid.attach (dummy_indicator, COL_SPACER, ROW_NAME, 1, 1);

        name_label = new FadingLabel ("");
        name_label.override_font (Pango.FontDescription.from_string ("Ubuntu 16"));
        name_label.override_color (Gtk.StateFlags.NORMAL, {1.0f, 1.0f, 1.0f, 1.0f});
        name_label.xalign = 0.0f;
        name_label.show ();
        name_grid.attach (name_label, COL_NAME_LABEL, ROW_NAME, 1, 1);

        message_image = new CachedImage (null);
        try
        {
            message_image.pixbuf = new Gdk.Pixbuf.from_file (Path.build_filename (Config.PKGDATADIR, "message.png", null));
        }
        catch (Error e)
        {
            debug ("Error loading message image: %s", e.message);
        }
        message_image.valign = Gtk.Align.CENTER;
        name_grid.attach (message_image, COL_NAME_MESSAGE, ROW_NAME, 1, 1);

        option_button = new Gtk.Button ();
        option_button.expand = true;
        option_button.halign = Gtk.Align.END;
        option_button.focus_on_click = false;
        option_button.relief = Gtk.ReliefStyle.NONE;
        option_button.get_accessible ().set_name (_("Session Options"));
        option_button.clicked.connect (option_button_clicked_cb);
        option_image = new CachedImage (null);
        option_image.show ();
        UnityGreeter.add_style_class (option_button);
        option_button.add (option_image);
        name_grid.attach (option_button, COL_NAME_OPTIONS, ROW_NAME, 1, 1);

        name_grid.show ();
        box_grid.show ();
        box_grid.attach (name_grid, COL_CONTENT, ROW_NAME, 1, 1);
        fixed.add (box_grid);

        /* Now prep small versions of the above normal widgets.  These are
           used when scrolling outside of the main dash box. */
        small_box_grid = new Gtk.Grid ();
        small_box_grid.column_spacing = 4;
        small_box_grid.row_spacing = 6;
        small_box_grid.hexpand = true;

        small_active_indicator = new ActiveIndicator ();
        small_active_indicator.valign = Gtk.Align.CENTER;
        small_active_indicator.show ();
        small_box_grid.attach (small_active_indicator, 0, 0, 1, 1);

        small_name_label = new FadingLabel ("");
        small_name_label.override_font (Pango.FontDescription.from_string ("Ubuntu 16"));
        small_name_label.override_color (Gtk.StateFlags.NORMAL, {1.0f, 1.0f, 1.0f, 1.0f});
        small_name_label.xalign = 0.0f;
        small_name_label.show ();
        small_box_grid.attach (small_name_label, 1, 0, 1, 1);

        small_message_image = new CachedImage (null);
        small_message_image.pixbuf = message_image.pixbuf;
        small_message_image.valign = Gtk.Align.CENTER;
        small_box_grid.attach (small_message_image, 2, 0, 1, 1);

        // Add a second indicator on right just for equal-spacing purposes
        var small_dummy_indicator = new ActiveIndicator ();
        small_dummy_indicator.show ();
        small_box_grid.attach (small_dummy_indicator, 3, 0, 1, 1);

        small_box_grid.show ();
        fixed.add (small_box_grid);

        last_row = 0;
    }

    public void set_zone (Gtk.Widget zone)
    {
        this.zone = zone;
        queue_draw ();
    }

    public void set_name (string name)
    {
        name_label.label = name;
        small_name_label.label = name;
    }

    public void set_options_image (Gdk.Pixbuf? image)
    {
        option_image.pixbuf = image;

        if (image == null)
            option_button.hide ();
        else
            option_button.show ();
    }

    private void option_button_clicked_cb (Gtk.Button button)
    {
        show_options ();
    }

    public void set_show_message_icon (bool show)
    {
        message_image.visible = show;
        small_message_image.visible = show;
    }

    public void set_is_active (bool active)
    {
        active_indicator.active = active;
        small_active_indicator.active = active;
    }

    private void foreach_prompt_widget (Gtk.Callback cb)
    {
        foreach (var w in box_grid.get_children ())
        {
            if (w.get_data<Gtk.Widget> ("prompt-box-widget") != null)
                cb (w);
        }
    }

    public void clear ()
    {
        foreach_prompt_widget ((w) => {w.destroy ();});
        last_row = 0;
        has_messages = false;
    }

    public void fade_in_prompts ()
    {
        show ();
        foreach_prompt_widget ((w) =>
        {
            var f = w as Fadable;
            if (f != null)
                f.fade_in ();
            else
                w.show ();
        });
    }

    public void show_prompts ()
    {
        show ();
        foreach_prompt_widget ((w) =>
        {
            w.show ();
        });
    }

    public void add_message (string text, bool is_error)
    {
        var label = new FadingLabel (text);

        label.override_font (Pango.FontDescription.from_string ("Ubuntu 10"));

        Gdk.RGBA color;
        if (is_error)
            color = {1.0f, 0.0f, 0.0f, 1.0f};
        else
            color = {1.0f, 1.0f, 1.0f, 1.0f};
        label.override_color (Gtk.StateFlags.NORMAL, color);

        label.xalign = 0.0f;

        label.set_data ("prompt-box-widget", this);
        UnityGreeter.add_style_class (label);

        last_row += 1;
        box_grid.attach (label, COL_ENTRIES_START, last_row, COL_ENTRIES_WIDTH, 1);

        has_messages = true;
    }

    public void add_prompt (string text, string? accessible_text, bool is_secret)
    {
        var entry = new DashEntry ();

        if (text.contains ("\n"))
        {
            add_message (text, false);
            entry.constant_placeholder_text = "";
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
            entry.constant_placeholder_text = placeholder;
        }

        var accessible = entry.get_accessible ();
        if (accessible_text != null)
            accessible.set_name (accessible_text);
        else
            accessible.set_name (text);

        if (is_secret)
        {
            entry.visibility = false;
            entry.caps_lock_warning = true;
        }

        entry.activate.connect (entry_activate_cb);

        entry.set_data ("prompt-box-widget", this);
        UnityGreeter.add_style_class (entry);

        last_row += 1;
        box_grid.attach (entry, COL_ENTRIES_START, last_row, COL_ENTRIES_WIDTH, 1);

        if (last_row == 1)
            entry.margin_top = 19;
    }

    private void entry_activate_cb (Gtk.Entry entry)
    {
        respond (entry.text);
    }

    public void add_button (string text, string? accessible_text)
    {
        var button = new DashButton (text);

        var accessible = button.get_accessible ();
        accessible.set_name (accessible_text);

        button.clicked.connect (button_clicked_cb);

        button.set_data ("prompt-box-widget", this);
        UnityGreeter.add_style_class (button);

        last_row += 1;
        box_grid.attach (button, COL_ENTRIES_START, last_row, COL_ENTRIES_WIDTH, 1);

        if (last_row == 1)
            button.margin_top = 22;
    }

    private void button_clicked_cb (Gtk.Button button)
    {
        login ();
    }

    public override void grab_focus ()
    {
        bool done = false;
        foreach_prompt_widget ((w) =>
        {
            if (!done && (w is Gtk.Entry || w is Gtk.Button))
            {
                w.grab_focus ();
                done = true;
            }
        });
    }

    public override void size_allocate (Gtk.Allocation allocation)
    {
        base.size_allocate (allocation);
        box_grid.size_allocate (allocation);
        small_box_grid.size_allocate (allocation);
    }

    public override bool draw (Cairo.Context c)
    {
        /* Draw either small or normal version of ourselves, depending on where
           our allocation put us relative to our zone */
        int x, y;
        zone.translate_coordinates (this, 0, 0, out x, out y);

        Gtk.Allocation alloc, zone_alloc;
        this.get_allocation (out alloc);
        zone.get_allocation (out zone_alloc);

        // Draw main grid only in that area
        c.save ();
        c.rectangle (x, y, zone_alloc.width, zone_alloc.height);
        c.clip ();
        fixed.propagate_draw (box_grid, c);
        c.restore ();

        // Do actual drawing
        c.save ();
        if (y > 0)
            c.rectangle (x, 0, zone_alloc.width, y);
        else
            c.rectangle (x, y + zone_alloc.height, zone_alloc.width, -y);
        c.clip ();
        fixed.propagate_draw (small_box_grid, c);
        small_box_grid.draw (c);
        c.restore ();

        return false;
    }
}

private class ActiveIndicator : Gtk.Label
{
    public static const int SIZE = grid_size / 4;

    public bool active {get; set;}

    construct
    {
        notify["active"].connect (() => {queue_draw ();});
    }

    public override void get_preferred_width (out int min, out int nat)
    {
        min = SIZE;
        nat = min;
    }

    public override void get_preferred_height (out int min, out int nat)
    {
        min = SIZE;
        nat = min;
    }

    public override bool draw (Cairo.Context c)
    {
        if (!active)
            return false;

        c.move_to (0, 0);
        c.rel_line_to (5, 4);
        c.rel_line_to (-5, 4);
        c.close_path ();
        c.set_source_rgb (1.0, 1.0, 1.0);
        c.fill ();
        return false;
    }
}

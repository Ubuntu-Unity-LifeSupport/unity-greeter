/* -*- Mode: Vala; indent-tabs-mode: nil; tab-width: 4 -*-
 *
 * Copyright (C) 2012 Canonical Ltd
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
 * Authors: Michael Terry <michael.terry@canonical.com>
 */

/* Vala's vapi for gtk3 is broken for lookup_color (it forgets the out keyword) */
[CCode (cheader_filename = "gtk/gtk.h")]
extern bool gtk_style_context_lookup_color (Gtk.StyleContext ctx, string color_name, out Gdk.RGBA color);

public class DashEntry : Gtk.Entry, Fadable
{
    public string constant_placeholder_text {get; set;}

    protected FadeTracker fade_tracker {get; protected set;}

    construct
    {
        fade_tracker = new FadeTracker (this);

        set_icon_activatable (Gtk.EntryIconPosition.SECONDARY, true);

        changed.connect (changed_cb);
        icon_press.connect (icon_press_cb);

        override_font (Pango.FontDescription.from_string ("Ubuntu 14"));
    }

    public override bool draw (Cairo.Context c)
    {
        c.save ();
        c.push_group ();
        base.draw (c);
        c.pop_group_to_source ();
        c.paint_with_alpha (fade_tracker.alpha);
        c.restore ();

        /* Now draw the prompt text */
        if (get_text_length () == 0 && constant_placeholder_text.length > 0)
            draw_prompt_text (c);

        return false;
    }

    private void draw_prompt_text (Cairo.Context c)
    {
        /* Position text */
        int x, y;
        get_layout_offsets (out x, out y);
        c.move_to (x, y);

        /* Set foreground color */
        var fg = Gdk.RGBA ();
        var context = get_style_context ();
        if (!gtk_style_context_lookup_color (context, "placeholder_text_color", out fg))
            fg.parse ("#ccc");
        c.set_source_rgba (fg.red, fg.green, fg.blue, fg.alpha);

        /* Draw text */
        var layout = create_pango_layout (constant_placeholder_text);
        layout.set_font_description (Pango.FontDescription.from_string ("Ubuntu 16"));
        Pango.cairo_show_layout (c, layout);
    }

    private void changed_cb ()
    {
        enable_arrow (get_text_length () != 0);
    }

    private void icon_press_cb ()
    {
        activate ();
    }

    private void enable_arrow (bool enabled)
    {
        if (enabled)
        {
            var file = File.new_for_path (Path.build_filename (Config.PKGDATADIR, "arrow_right.png", null));
            var icon = new FileIcon (file);
            set_icon_from_gicon (Gtk.EntryIconPosition.SECONDARY, icon);
        }
        else
        {
            set_icon_from_gicon (Gtk.EntryIconPosition.SECONDARY, null);
        }
    }
}

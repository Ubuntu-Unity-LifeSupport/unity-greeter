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

/* Vala's vapi for gtk3 is broken for get_icon_area (it forgets the out keyword) */
[CCode (cheader_filename = "gtk/gtk.h")]
extern void gtk_entry_get_icon_area (Gtk.Entry entry, Gtk.EntryIconPosition icon_pos, out Gdk.Rectangle icon_area);

public class DashEntry : Gtk.Entry, Fadable
{
    public static string font = "Ubuntu 14";
    public signal void respond ();

    public string constant_placeholder_text { get; set; }
    public bool can_respond { get; set; default = true; }

    private bool _did_respond;
    public bool did_respond
    {
        get
        {
            return _did_respond;
        }
        set
        {
            _did_respond = value;
            if (value)
                set_state_flags (Gtk.StateFlags.ACTIVE, false);
            else
                unset_state_flags (Gtk.StateFlags.ACTIVE);
            update_arrow ();
        }
    }

    private static const string NO_BORDER_CLASS = "unity-greeter-no-border";

    protected FadeTracker fade_tracker { get; protected set; }
    private Gdk.Rectangle icon_area;

    construct
    {
        fade_tracker = new FadeTracker (this);

        notify["can-respond"].connect (update_arrow);
        changed.connect (update_arrow);
        icon_press.connect (icon_press_cb);

        override_font (Pango.FontDescription.from_string (font));

        // We add the styles and classes we need for normal operation of the
        // spinner animation.  These are always "on" and we just turn them off
        // right before drawing our parent class's draw function.  This is done
        // opt-out like that rather than just turning the styles on when we
        // need to draw the spinner because the animation doesn't work right
        // otherwise.  See the draw() function for how we turn it off.
        var style_ctx = get_style_context ();
        var no_border_provider = new Gtk.CssProvider ();
        try
        {
            var css = ".%s {border: 0px;}".printf (NO_BORDER_CLASS);
            no_border_provider.load_from_data (css, -1);
        }
        catch (Error e)
        {
            debug ("Internal error loading spinner style: %s", e.message);
        }
        style_ctx.add_provider (no_border_provider,
                                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        style_ctx.add_class (NO_BORDER_CLASS);
        style_ctx.add_class (Gtk.STYLE_CLASS_SPINNER);
    }

    public override bool draw (Cairo.Context c)
    {
        var style_ctx = get_style_context ();

        // See construct method for explanation of why we remove classes
        style_ctx.save ();
        style_ctx.remove_class (Gtk.STYLE_CLASS_SPINNER);
        style_ctx.remove_class (NO_BORDER_CLASS);
        c.save ();
        c.push_group ();
        base.draw (c);
        c.pop_group_to_source ();
        c.paint_with_alpha (fade_tracker.alpha);
        c.restore ();
        style_ctx.restore ();

        /* Now draw the prompt text */
        if (get_text_length () == 0 && constant_placeholder_text.length > 0)
            draw_prompt_text (c);

        /* Draw activity spinner if we need to */
        if (did_respond)
            draw_spinner (c);

        return false;
    }

    private void draw_spinner (Cairo.Context c)
    {
        Gtk.Allocation allocation;
        get_allocation (out allocation);
        int spinner_side = allocation.height / 2;
        int margin = (allocation.height - spinner_side) / 2;

        var style_ctx = get_style_context ();
        style_ctx.render_activity (c,
                                   allocation.width - spinner_side - margin,
                                   margin,
                                   spinner_side,
                                   spinner_side);
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
            fg.parse ("#888");
        c.set_source_rgba (fg.red, fg.green, fg.blue, fg.alpha);

        /* Draw text */
        var layout = create_pango_layout (constant_placeholder_text);
        layout.set_font_description (Pango.FontDescription.from_string ("Ubuntu 13"));
        Pango.cairo_show_layout (c, layout);
    }

    public override void activate ()
    {
        base.activate ();
        if (can_respond)
        {
            did_respond = true;
            respond ();
        }
        else
        {
            get_toplevel ().child_focus (Gtk.DirectionType.TAB_FORWARD);
        }
    }

    private void icon_press_cb ()
    {
        activate ();
    }

    private void update_arrow ()
    {
        show_arrow (get_text_length () != 0);
    }

    protected void show_arrow (bool visible)
    {
        if (visible && can_respond && !did_respond)
        {
            var file = File.new_for_path (Path.build_filename (Config.PKGDATADIR, "arrow_right.png", null));
            var icon = new FileIcon (file);
            set_icon_from_gicon (Gtk.EntryIconPosition.SECONDARY, icon);
            set_icon_activatable (Gtk.EntryIconPosition.SECONDARY, true);

            /* Save icon area for later use by spinner.  Save it here instead of
             * calling it each draw because GtkEntry will return 0 width areas
             * if we hide the icon. */
            gtk_entry_get_icon_area (this, Gtk.EntryIconPosition.SECONDARY, out icon_area);
        }
        else
        {
            set_icon_from_gicon (Gtk.EntryIconPosition.SECONDARY, null);
        }
    }
}

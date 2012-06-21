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
 * Authored by: Michael Terry <michael.terry@canonical.com>
 */

public class DashBox : Gtk.Box
{
    public Background? background {get; construct; default = null;}

    public bool has_content {get; private set; default = false;}
    public double base_alpha {get; private set; default = 1.0;}

    private enum Mode
    {
        NORMAL,
        PUSH_FADE_OUT,
        PUSH_FADE_IN,
        POP_FADE_OUT,
        POP_FADE_IN,
    }

    private Gtk.Widget pushed;
    private Gtk.Widget orig;
    private FadeTracker orig_tracker;
    private int orig_height;
    private Mode mode;
    private FadableBox fader;

    public DashBox (Background bg)
    {
        Object (background: bg);
    }

    construct
    {
        fader = new FadableBox ();
        fader.show ();
        fader.fade_done.connect (fade_done_cb);
        add (fader);
        mode = Mode.NORMAL;
    }

    // Does not actually add w to this widget, as doing so would potentially
    // mess with w's placement.
    public void set_base (Gtk.Widget? w)
    {
        return_if_fail (pushed == null);
        return_if_fail (mode == Mode.NORMAL);

        orig = w;

        if (orig != null)
        {
            orig_tracker = new FadeTracker (orig);
            orig_tracker.notify["alpha"].connect (() =>
            {
                base_alpha = orig_tracker.alpha;
                queue_draw ();
            });
            orig_tracker.done.connect (fade_done_cb);
            base_alpha = orig_tracker.alpha;
        }
        else
        {
            orig_tracker = null;
            base_alpha = 1.0;
        }

        queue_resize ();
    }

    public void push (Gtk.Widget w)
    {
        /* This isn't designed to push more than one widget at a time yet */
        return_if_fail (pushed == null);
        return_if_fail (orig != null);
        return_if_fail (mode == Mode.NORMAL);

        get_preferred_height (null, out orig_height);
        pushed = w;
        mode = Mode.PUSH_FADE_OUT;
        has_content = true;
        orig_tracker.reset (FadeTracker.Mode.FADE_OUT);
        queue_resize ();
    }

    public void pop ()
    {
        return_if_fail (pushed != null);
        return_if_fail (orig != null);
        return_if_fail (mode == Mode.NORMAL);

        mode = Mode.POP_FADE_OUT;
        fader.fade_out ();
    }

    private void fade_done_cb ()
    {
        switch (mode)
        {
        case Mode.PUSH_FADE_OUT:
            mode = Mode.PUSH_FADE_IN;
            pushed.show ();
            fader.add (pushed);
            fader.fade_in ();
            break;
        case Mode.PUSH_FADE_IN:
            mode = Mode.NORMAL;
            pushed.grab_focus ();
            break;
        case Mode.POP_FADE_OUT:
            mode = Mode.POP_FADE_IN;
            fader.remove (pushed);
            orig_tracker.reset (FadeTracker.Mode.FADE_IN);
            break;
        case Mode.POP_FADE_IN:
            mode = Mode.NORMAL;
            pushed = null;
            has_content = false;
            queue_resize ();
            break;
        }
    }

    private int round_to_grid (int size)
    {
        var num_grids = size / grid_size;
        var remainder = size % grid_size;
        if (remainder > 0)
            num_grids += 1;
        if (num_grids % 2 == 0) /* always return odd number of grids */
            num_grids += 1;
        return num_grids * grid_size;
    }

    public override void get_preferred_height (out int min, out int nat)
    {
        if (orig == null)
        {
            min = grid_size * UserList.BOX_HEIGHT - UserList.BORDER * 2;
            nat = grid_size * UserList.BOX_HEIGHT - UserList.BORDER * 2;
        }
        else
        {
            if (pushed == null)
                orig.get_preferred_height (out min, out nat);
            else
                pushed.get_preferred_height (out min, out nat);
            min = round_to_grid (min) - UserList.BORDER * 2;
            nat = round_to_grid (nat) - UserList.BORDER * 2;
        }
    }

    public override void get_preferred_width (out int min, out int nat)
    {
        min = grid_size * UserList.BOX_WIDTH - UserList.BORDER * 2;
        nat = grid_size * UserList.BOX_WIDTH - UserList.BORDER * 2;
    }

    public override bool draw (Cairo.Context c)
    {
        if (background != null)
        {
            int x, y;
            background.translate_coordinates (this, 0, 0, out x, out y);
            c.save ();
            c.translate (x, y);
            background.draw_full (c, Background.DrawFlags.NONE);
            c.restore ();
        }

        /* Draw darker background with a rounded border */
        var box_r = 0.2 * grid_size;
        int box_y = 0;
        int box_w;
        int box_h;
        get_preferred_width (null, out box_w);
        get_preferred_height (null, out box_h);

        if (mode == Mode.PUSH_FADE_OUT)
        {
            /* Grow dark bg to fit new pushed object */
            var new_box_h = box_h - (int) ((box_h - orig_height) * base_alpha);
            box_y = (box_h - new_box_h) / 2;
            box_h = new_box_h;
        }
        else if (mode == Mode.POP_FADE_IN)
        {
            /* Shrink dark bg to fit orig */
            var new_box_h = box_h - (int) ((box_h - orig_height) * base_alpha);
            box_y = (box_h - new_box_h) / 2;
            box_h = new_box_h;
        }

        c.save ();

        cairo_rounded_rectangle (c, 0, box_y, box_w, box_h, box_r);

        c.set_source_rgba (0.1, 0.1, 0.1, 0.4);
        c.fill_preserve ();

        c.set_source_rgba (0.4, 0.4, 0.4, 0.4);
        c.set_line_width (1);
        c.stroke ();

        c.restore ();
        
        return base.draw (c);
    }

    private void cairo_rounded_rectangle (Cairo.Context c, double x, double y,
                                          double width, double height,
                                          double radius)
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
}

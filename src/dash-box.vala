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

    public DashBox (Background bg)
    {
        Object (background: bg);
    }

    construct
    {
        orientation = Gtk.Orientation.VERTICAL;
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

        c.save ();

        Gtk.Allocation allocation;
        get_allocation (out allocation);

        /* Draw darker background with a rounded border */
        var box_w = allocation.width;
        var box_h = allocation.height;
        var box_r = 0.2 * grid_size;
        cairo_rounded_rectangle (c, 0, 0, box_w, box_h, box_r);

        c.set_source_rgba (0.1, 0.1, 0.1, 0.4);
        c.fill_preserve ();

        c.set_source_rgba (0.4, 0.4, 0.4, 0.4);
        c.set_line_width (1);
        c.stroke ();

        c.restore ();

        return base.draw(c);
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

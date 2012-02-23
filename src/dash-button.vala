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

public class DashButton : Gtk.Button, Fadable
{
    public string text {get; construct; default = "";}
    protected FadeTracker fade_tracker {get; protected set;}

    public DashButton (string text)
    {
        Object (text: text);
    }

    construct
    {
        fade_tracker = new FadeTracker (this);

        var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        var sizes = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);

        // add blank label to match chevron
        var label = new Gtk.Label ("");
        sizes.add_widget (label);
        hbox.add (label);

        // add text
        label = new Gtk.Label ("<span font_size=\"large\">%s</span>".printf (text));
        label.use_markup = true;
        label.hexpand = true;
        label.halign = Gtk.Align.CENTER;
        hbox.add (label);

        // add chevron
        var image = new Gtk.Image.from_file (Path.build_filename (Config.PKGDATADIR, "arrow_right.png", null));
        sizes.add_widget (image);
        hbox.add (image);

        hbox.show_all ();
        add (hbox);
    }

    public override bool draw (Cairo.Context c)
    {
        c.push_group ();
        base.draw (c);
        c.pop_group_to_source ();
        c.paint_with_alpha (fade_tracker.alpha);
        return false;
    }
}

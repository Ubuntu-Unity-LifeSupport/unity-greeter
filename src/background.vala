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

class BackgroundLoader
{
    public string filename {get; private set;}
    public Cairo.Surface logo {get; set;}

    public int[] widths;
    public int[] heights;
    public Cairo.Pattern[] patterns;

    private Cairo.Surface target_surface;
    private bool draw_grid;
    private unowned Thread<void*> thread;
    private Gdk.Pixbuf[] images;
    private bool finished;
    private uint ready_id;

    public signal void loaded ();

    public BackgroundLoader (Cairo.Surface target_surface, string filename, int[] widths, int[] heights, bool draw_grid)
    {
        this.target_surface = target_surface;
        this.filename = filename;
        this.widths = widths;
        this.heights = heights;
        patterns = new Cairo.Pattern[widths.length];
        images = new Gdk.Pixbuf[widths.length];
        this.draw_grid = draw_grid;
    }

    public bool load ()
    {
        /* Already loaded */
        if (finished)
            return true;

        /* Currently loading */
        if (thread != null)
            return false;

        var text = "Making background %s at %dx%d".printf (filename, widths[0], heights[0]);
        for (var i = 1; i < widths.length; i++)
            text += ",%dx%d".printf (widths[i], heights[i]);
        debug (text);

        var color = Gdk.RGBA ();
        if (color.parse (filename))
        {
            var pattern = new Cairo.Pattern.rgba (color.red, color.green, color.blue, color.alpha);
            for (var i = 0; i < widths.length; i++)
                patterns[i] = pattern;
            finished = true;
            debug ("Render of background %s complete", filename);
            return true;
        }
        else
        {
            try
            {
                thread = Thread<void*>.create<void*> (load_and_scale, true);
            }
            catch (ThreadError e)
            {
                finished = true;
                return true;
            }
        }

        return false;
    }
    
    public Cairo.Pattern? get_pattern (int width, int height)
    {
        for (var i = 0; i < widths.length; i++)
        {
            if (widths[i] == width && heights[i] == height)
                return patterns[i];
        }
        return null;
    }

    ~Background ()
    {
        if (ready_id > 0)
            Source.remove (ready_id);
        ready_id = 0;
    }

    private bool ready_cb ()
    {
        debug ("Render of background %s complete", filename);

        thread.join ();
        thread = null;
        finished = true;

        for (var i = 0; i < widths.length; i++)
        {
            patterns[i] = create_pattern (images[i]);
            images[i] = null;
        }

        loaded ();

        return false;
    }

    private void* load_and_scale ()
    {
        try
        {
            var image = new Gdk.Pixbuf.from_file (filename);
            for (var i = 0; i < widths.length; i++)
                images[i] = scale (image, widths[i], heights[i]);
        }
        catch (Error e)
        {
            debug ("Error loading background: %s", e.message);
        }

        ready_id = Gdk.threads_add_idle (ready_cb);

        return null;
    }
    
    private Gdk.Pixbuf? scale (Gdk.Pixbuf? image, int width, int height)
    {
        var target_aspect = (double) width / height;
        var aspect = (double) image.width / image.height;
        double scale, offset_x = 0, offset_y = 0;
        if (aspect > target_aspect)
        {
            /* Fit height and trim sides */
            scale = (double) height / image.height;
            offset_x = (image.width * scale - width) / 2;
        }
        else
        {
            /* Fit width and trim top and bottom */
            scale = (double) width / image.width;
            offset_y = (image.height * scale - height) / 2;
        }

        var scaled_image = new Gdk.Pixbuf (image.colorspace, image.has_alpha, image.bits_per_sample, width, height);
        image.scale (scaled_image, 0, 0, width, height, -offset_x, -offset_y, scale, scale, Gdk.InterpType.BILINEAR);

        return scaled_image;
    }

    private Cairo.Pattern? create_pattern (Gdk.Pixbuf image)
    {
        var grid_x_offset = get_grid_offset (image.width);
        var grid_y_offset = get_grid_offset (image.height);

        /* Create background */
        var surface = new Cairo.Surface.similar (target_surface, Cairo.Content.COLOR, image.width, image.height);
        var bc = new Cairo.Context (surface);
        Gdk.cairo_set_source_pixbuf (bc, image, 0, 0);

        bc.paint ();

        /* Draw logo */
        if (logo != null)
        {
            bc.save ();
            var y = (int) (image.height / grid_size - 2) * grid_size + grid_y_offset;
            bc.translate (grid_x_offset, y);
            bc.set_source_surface (logo, 0, 0);
            bc.paint_with_alpha (0.5);
            bc.restore ();
        }

        var pattern = new Cairo.Pattern.for_surface (surface);
        pattern.set_extend (Cairo.Extend.REPEAT);
       
        return pattern;
    }
}

public class Monitor
{
    public int x;
    public int y;
    public int width;
    public int height;

    public Monitor (int x, int y, int width, int height)
    {
        this.x = x;
        this.y = y;
        this.width = width;
        this.height = height;
    }
}

public class Background : Gtk.Fixed
{
    public enum DrawFlags
    {
        NONE,
        GRID,
    }

    public string default_background {get; set; default = "#2C001E";}
    public string? current_background {get; set; default = null;}
    public bool draw_grid {get; set; default = true;}
    public double alpha {get; private set; default = 1.0;}

    private Cairo.Surface target_surface;

    private List<Monitor> monitors = null;
    private Monitor? active_monitor = null;

    private AnimateTimer timer;

    private BackgroundLoader current;
    private BackgroundLoader old;

    private HashTable<string, BackgroundLoader> loaders;

    private Cairo.Surface? version_logo_surface = null;
    private int version_logo_width;
    private int version_logo_height;
    private Cairo.Surface? background_logo_surface = null;
    private int background_logo_width;
    private int background_logo_height;

    public Background (Cairo.Surface target_surface)
    {
        this.target_surface = target_surface;
        timer = new AnimateTimer (AnimateTimer.INSTANT);
        timer.animate.connect (animate_cb);

        loaders = new HashTable<string?, BackgroundLoader> (str_hash, str_equal);

        notify["current-background"].connect (() => {reload ();});
    }

    public void set_logo (string version_logo, string background_logo)
    {
        version_logo_surface = load_image (version_logo, out version_logo_width, out version_logo_height);
        background_logo_surface = load_image (background_logo, out background_logo_width, out background_logo_height);
    }

    private Cairo.Surface? load_image (string filename, out int width, out int height)
    {
        width = height = 0;
        try
        {
            var image = new Gdk.Pixbuf.from_file (filename);
            width = image.width;
            height = image.height;
            var surface = new Cairo.Surface.similar (target_surface, Cairo.Content.COLOR_ALPHA, image.width, image.height);
            var c = new Cairo.Context (surface);
            Gdk.cairo_set_source_pixbuf (c, image, 0, 0);
            c.paint ();
            return surface;
        }
        catch (Error e)
        {
            debug ("Failed to load background component %s: %s", filename, e.message);
        }

        return null;
    }

    public void set_monitors (List<Monitor> monitors)
    {
        this.monitors = new List<Monitor> ();
        foreach (var m in monitors)
            this.monitors.append (m);
        queue_draw ();
    }
    
    public void set_active_monitor (Monitor? monitor)
    {
        active_monitor = monitor;
    }

    public override void size_allocate (Gtk.Allocation allocation)
    {
        var resized = allocation.height != get_allocated_height () || allocation.width != get_allocated_width ();

        base.size_allocate (allocation);

        /* Regenerate backgrounds */
        if (resized)
        {
            debug ("Regenerating backgrounds");
            loaders.remove_all ();
            load_background (null);
            reload ();
        }
    }

    public override bool draw (Cairo.Context c)
    {
        var flags = DrawFlags.NONE;
        if (draw_grid)
            flags |= DrawFlags.GRID;
        draw_full (c, flags);
        return base.draw (c);
    }

    public void draw_full (Cairo.Context c, DrawFlags flags)
    {
        c.save ();

        /* Test whether we ran into an error loading this background */
        if (current == null || (current.load () && current.patterns[0] == null))
        {
            /* We couldn't load it, so swap it out for the default background
               and remember that choice */
            var new_background = load_background (null);
            if (current != null)
                loaders.insert (current.filename, new_background);
            if (old == current)
                old = new_background;
            current = new_background;
        }

        /* Fade to this background when loaded */
        if (current.load () && current != old && !timer.is_running)
        {
            alpha = 0.0;
            timer.reset ();
        }

        c.set_source_rgba (0.0, 0.0, 0.0, 0.0);
        var old_painted = false;

        /* Draw old background */
        if (old != null && old.load () && (alpha < 1.0 || !current.load ()))
        {
            draw_background (c, old, 1.0);
            old_painted = true;
        }

        /* Draw new background */
        if (current.load () && alpha > 0.0)
            draw_background (c, current, old_painted ? alpha : 1.0);

        c.restore ();

        if ((flags & DrawFlags.GRID) != 0)
            overlay_grid (c);
    }

    private void draw_background (Cairo.Context c, BackgroundLoader background, double alpha)
    {
        foreach (var monitor in monitors)
        {
            var pattern = background.get_pattern (monitor.width, monitor.height);
            if (pattern == null)
                continue;

            c.save ();
            pattern = background.get_pattern (monitor.width, monitor.height);
            var matrix = Cairo.Matrix.identity ();
            matrix.translate (-monitor.x, -monitor.y);
            pattern.set_matrix (matrix);
            c.set_source (pattern);
            c.rectangle (monitor.x, monitor.y, monitor.width, monitor.height);
            c.clip ();
            c.paint_with_alpha (alpha);
            c.restore ();

            if (monitor != active_monitor && background_logo_surface != null)
            {
                var width = background_logo_width;
                var height = background_logo_height;

                c.save ();
                pattern = new Cairo.Pattern.for_surface (background_logo_surface);
                matrix = Cairo.Matrix.identity ();
                var x = monitor.x + (monitor.width - width) / 2;
                var y = monitor.y + (monitor.height - height) / 2;
                matrix.translate (-x, -y);
                pattern.set_matrix (matrix);
                c.set_source (pattern);
                c.rectangle (x, y, width, height);
                c.clip ();
                c.paint_with_alpha (alpha);
                c.restore ();
            }
        }
    }

    private void animate_cb (double progress)
    {
        alpha = progress;

        queue_draw ();

        /* Stop when we get there */
        if (alpha >= 1.0)
            old = current;
    }

    private void reload ()
    {
        if (get_realized ())
        {
            var new_background = load_background (current_background);

            if (current != new_background)
            {
                old = current;
                current = new_background;
            }

            queue_draw ();
        }
    }

    private BackgroundLoader load_background (string? filename)
    {
        if (filename == null)
            filename = default_background;

        var b = loaders.lookup (filename);
        if (b == null)
        {
            /* Load required sizes to draw background */
            var widths = new int[monitors.length ()];
            var heights = new int[monitors.length ()];
            var n_sizes = 0;
            foreach (var monitor in monitors)
            {
                if (monitor_is_unique_size (monitor))
                {
                    widths[n_sizes] = monitor.width;
                    heights[n_sizes] = monitor.height;
                    n_sizes++;
                }
            }
            widths.resize (n_sizes);
            heights.resize (n_sizes);

            b = new BackgroundLoader (target_surface, filename, widths, heights, draw_grid);
            b.logo = version_logo_surface;
            b.loaded.connect (() => {reload();});
            b.load ();
            loaders.insert (filename, b);
        }

        return b;
    }

    /* Check if a monitor has a unique size */
    private bool monitor_is_unique_size (Monitor monitor)
    {
        foreach (var m in monitors)
        {
            if (m == monitor)
                break;
            else if (m.width == monitor.width && m.height == monitor.height)
                return false;
        }

        return true;
    }

    private void overlay_grid (Cairo.Context c)
    {
        var width = get_allocated_width ();
        var height = get_allocated_height ();
        var grid_x_offset = get_grid_offset (width);
        var grid_y_offset = get_grid_offset (height);

        /* Overlay grid */
        var overlay_surface = new Cairo.Surface.similar (target_surface, Cairo.Content.COLOR_ALPHA, grid_size, grid_size);
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

        /* Draw overlay */
        c.save ();
        c.set_source (overlay);
        c.rectangle (0, 0, width, height);
        c.fill ();
        c.restore ();
    }
}

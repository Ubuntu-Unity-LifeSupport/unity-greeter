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

private class AnimateTimer : Object
{
    public enum Speed
    {
        INSTANT, /* Good for animations that don't convey any information */
        FAST, /* Good for animations that convey duplicated information (e.g. scrolling) */
        NORMAL,
        SLOW, /* Good for animations that convey information that is only presented in the animation */
    }

    public Speed speed {get; construct;}
    public bool is_running { get { return timeout != 0; } }

    /* progress is from 0.0 to 1.0 */
    public signal void animate (double progress);

    public AnimateTimer (Speed speed)
    {
        Object (speed: speed);
    }

    public void reset ()
    {
        stop ();
        timeout = Timeout.add (16, animate_cb);

        start_time = GLib.get_monotonic_time ();

        /* The following are the same intervals that Unity uses */
        switch (speed)
        {
        default:
        case Speed.INSTANT:
            length =  150 * TimeSpan.MILLISECOND;
            break;
        case Speed.FAST:
            length =  250 * TimeSpan.MILLISECOND;
            break;
        case Speed.NORMAL:
            length =  500 * TimeSpan.MILLISECOND;
            break;
        case Speed.SLOW:
            length = 1000 * TimeSpan.MILLISECOND;
            break;
        }
    }

    public void stop ()
    {
        if (timeout != 0)
            Source.remove (timeout);
        timeout = 0;
    }

    private uint timeout = 0;
    private TimeSpan start_time = 0;
    private TimeSpan length = 0;

    private bool animate_cb ()
    {
        var time = normalize_time ();
        var progress = normalize_progress (time);

        animate (progress);

        if (progress >= 1.0)
        {
            timeout = 0;
            return false;
        }
        else
            return true;
    }

    /* Returns 0.0 to 1.0 where 1.0 is at or past end_time */
    private double normalize_time ()
    {
        var now = GLib.get_monotonic_time ();
        return (((double)(now - start_time)) / length).clamp (0.0, 1.0);
    }

    /* Returns 0.0 to 1.0 where 1.0 is done.
       time is normalized time from 0.0 to 1.0. */
    private double normalize_progress (double time)
    {
        /* Use a sine wave function similar to what Unity uses.  They call it
           'easing' and is designed to make the animation start and end slower
           than in the middle. */
        return ((-1 * Math.cos (Math.PI * time) + 1) / 2).clamp (0.0, 1.0);
    }
}


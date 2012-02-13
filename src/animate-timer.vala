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
    /* The following are the same intervals that Unity uses */
    public static const int INSTANT = 150; /* Good for animations that don't convey any information */
    public static const int FAST =    250; /* Good for animations that convey duplicated information */
    public static const int NORMAL =  500;
    public static const int SLOW =   1000; /* Good for animations that convey information that is only presented in the animation */

    /* speed is in milliseconds */
    public int speed {get; set;}
    public bool is_running { get { return timeout != 0; } }
    public double progress {get; private set;}

    /* progress is from 0.0 to 1.0 */
    public signal void animate (double progress);

    /* speed is in milliseconds */
    public AnimateTimer (int speed)
    {
        Object (speed: speed);
    }

    /* temp_speed is in milliseconds */
    public void reset (int temp_speed = 0)
    {
        stop ();

        timeout = Timeout.add (16, animate_cb);
        start_time = 0;
        extra_time = 0;
        extra_progress = 0;

        if (temp_speed == 0)
            temp_speed = speed;

        length = temp_speed * TimeSpan.MILLISECOND;
    }

    /* This tells us the consumer of our progress reports is changing the
       goalposts on us.  So we need to adjust our reports accordingly.
       'extra_progress' is how much progress is being added to the animation.
     */
    public bool extend (double new_progress)
    {
        /* As an example, say a consumer is animating from point A to point C in
           150ms.  This is two points to cover, and at 75ms, they will be 0.5 done.

           Now, they extend it to point D.  This adds an extra point, which is half
           the original progress.  So now they call extend (0.5).

           We extend in the middle, so we need the slope at halfway through our
           progress function.  That is a constant we have (see calculate_progress
           for details).  So we'd need to add the same amount of normalized time
           to our process as progress, which is 0.5 / HALFWAY_VELOCITY = 0.318 in
           this example.  Which is (length * 0.318) = 47.7ms more time to add.

           Now we have 197.7ms as length of our animation.  Which changes the
           progress values we give out.  We further need to adjust our progress
           function to take this 'pause' in the middle of the function into
           account.
        */

        if (progress > HALFWAY_PROGRESS)
            return false;

        extra_progress += new_progress;
        extra_time = (TimeSpan)(length * extra_progress / HALFWAY_VELOCITY);
        return true;
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
    private TimeSpan extra_time = 0;
    private double extra_progress = 0.0;

    /* Derivative of our easing function at 0.5 (the halfway point).
       See calculate_progress() for functions. */
    private static const double HALFWAY_VELOCITY = 1.5708;

    /* The y value of our easing function at 0.5 (the halway point) */
    private static const double HALFWAY_PROGRESS = 0.75;

    private bool animate_cb ()
    {
        if (start_time == 0)
            start_time = GLib.get_monotonic_time ();

        progress = calculate_progress (GLib.get_monotonic_time ());
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
    private double normalize_time (TimeSpan now)
    {
        var total = length;
        var halfway = start_time + length / 2;
        if (now > halfway)
            now -= extra_time;

        return (((double)(now - start_time)) / total).clamp (0.0, 1.0);
    }

    /* Incoming progress count is original, un-extra-time enhanced progress */
    private double normalize_progress (double p)
    {
        /* So without extra time, progress goes from 0.0 to 1.0.  But with
           extra time, the beginning and end want to keep the same function,
           just squeezed into a smaller place in the graph.  So we figure out
           that mapping here. */
        var extra_mapped = extra_progress / (1.0 + extra_progress);
        var half_mapped = HALFWAY_PROGRESS / (1.0 + extra_progress);
        if (p < HALFWAY_PROGRESS)
            return p * (half_mapped / HALFWAY_PROGRESS);
        else
        {
            var end = 1.0 - half_mapped - extra_mapped;
            return (p - HALFWAY_PROGRESS) * (end / (1 - HALFWAY_PROGRESS)) + half_mapped + extra_mapped;
        }
    }

    /* Returns 0.0 to 1.0 where 1.0 is done.
       time is not normalized yet! */
    private double calculate_progress (TimeSpan time)
    {
        /* Use a sine wave function similar to what Unity uses.  They call it
           'easing' and is designed to make the animation start and end slower
           than in the middle. 

           ((1 - Math.cos (Math.PI * time)) / 2) is the basic sine curve for
           easing, used by Unity and others.  By squaring that and reversing
           the curve (by using 1 - x and 1 - y), we get a more exaggerated
           slowdown.

           For clarity, here is the whole function:
            y = 1 - ((1 - cos (pi * (1 - x))) / 2) ^ 2

           Here is the derivative of that function (useful for calculating
           slope at a given point, used elsewhere in this class):
            y = (pi * (cos (pi * (x - 1)) - 1)) * sin (pi * (x - 1)) / 2 

           */

        /* But due to the ability to add extra time into the equation, we
           are actually three functions:
           1) x=[0,A) = normal
           2) x=[A,B] = halfway slope
           3) x=(B,1.0] = picks up where first function left off */

        var y = 0.0;
        var orig_half_point = start_time + length / 2;

        if (time > start_time + length + extra_time)
        {
            y = 1.0;
        }
        else if (time < orig_half_point)
        {
            var x = normalize_time (time);
            y = easing_function (x);
            y = normalize_progress (y);
        }
        else if (time < orig_half_point + extra_time)
        {
            var xpercent = (time - orig_half_point) / (double)extra_time;
            y = (xpercent * extra_progress + HALFWAY_PROGRESS) / (1.0 + extra_progress);
        }
        else
        {
            var x = normalize_time (time);
            y = easing_function (x);
            y = normalize_progress (y);
        }

        return y.clamp (0.0, 1.0);
    }

    private double easing_function (double x)
    {
        var y = (1 - Math.cos (Math.PI * (1.0 - x))) / 2;
        y = y * y;
        y = 1.0 - y;
        return y;
    }
}


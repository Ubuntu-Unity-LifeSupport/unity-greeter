/* -*- Mode: Vala; indent-tabs-mode: nil; tab-width: 4 -*-
 *
 * Copyright (C) 2011 Canonical Ltd
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
 * Authored by: Robert Ancell <robert.ancell@canonical.com>
 */

public const int grid_size = 40;

public class UnityGreeter
{
    static bool show_version = false;
    public static bool test_mode = false;
    public static const OptionEntry[] options =
    {
        { "version", 'v', 0, OptionArg.NONE, ref show_version,
          /* Help string for command line --version flag */
          N_("Show release version"), null },
        { "test-mode", 0, 0, OptionArg.NONE, ref test_mode,
          /* Help string for command line --test-mode flag */
          N_("Run in test mode"), null },
        { null }
    };

    private static Timer log_timer;

    private static string state_file;
    private static KeyFile state;

    private static Cairo.XlibSurface background_surface;

    private SettingsDaemon settings_daemon;

    private static MainWindow main_window;

    public static LightDM.Greeter greeter;

    private Canberra.Context canberra_context;

    public UnityGreeter ()
    {
        greeter = new LightDM.Greeter ();
        var connected = false;
        try
        {
            connected = greeter.connect_sync ();
        }
        catch (Error e)
        {
            warning ("Failed to connect to LightDM daemon");
        }
        if (!connected && !test_mode)
            Posix.exit (Posix.EXIT_FAILURE);

        if (!test_mode)
        {
            settings_daemon = new SettingsDaemon ();
            settings_daemon.start ();
        }

        var state_dir = Path.build_filename (Environment.get_user_cache_dir (), "unity-greeter");
        DirUtils.create_with_parents (state_dir, 0775);

        state_file = Path.build_filename (state_dir, "state");
        state = new KeyFile ();
        try
        {
            state.load_from_file (state_file, KeyFileFlags.NONE);
        }
        catch (Error e)
        {
            if (!(e is FileError.NOENT))
                warning ("Failed to load state from %s: %s\n", state_file, e.message);
        }

        main_window = new MainWindow ();

        start_fake_wm ();
        Gdk.threads_add_idle (ready_cb);
    }

    public static string? get_state (string key)
    {
        try
        {
            return state.get_value ("greeter", key);
        }
        catch (Error e)
        {
            return null;
        }
    }

    public static void set_state (string key, string value)
    {
        state.set_value ("greeter", key, value);
        var data = state.to_data ();
        try
        {
            FileUtils.set_contents (state_file, data);
        }
        catch (Error e)
        {
            debug ("Failed to write state: %s", e.message);
        }
    }

    public static void push_list (GreeterList widget)
    {
        main_window.push_list (widget);
    }

    public static void pop_list ()
    {
        main_window.pop_list ();
    }

    public static void add_style_class (Gtk.Widget widget)
    {
        /* Add style context class lightdm-user-list */
        var ctx = widget.get_style_context ();
        ctx.add_class ("lightdm");
    }

    public static LightDM.Layout? get_layout_by_name (string name)
    {
        foreach (var layout in LightDM.get_layouts ())
        {
            if (layout.name == name)
                return layout;
        }
        return null;
    }

    public static void start_session (string? session)
    {
        /* Set the background */
        refresh_background (Gdk.Screen.get_default (), background_surface);

        if (UnityGreeter.test_mode)
        {
                debug ("Successfully logged in!  Quitting...");
                Gtk.main_quit ();
        }
        else
        {
            try
            {
                UnityGreeter.greeter.start_session_sync (session);
            }
            catch (Error e)
            {
                warning ("Failed to start session: %s", e.message);
            }
        }
    }

    private bool ready_cb ()
    {
        debug ("starting system-ready sound");

        /* Launch canberra */
        Canberra.Context.create (out canberra_context);

        if (UGSettings.get_boolean (UGSettings.KEY_PLAY_READY_SOUND))
            canberra_context.play (0,
                                   Canberra.PROP_CANBERRA_XDG_THEME_NAME,
                                   "ubuntu",
                                   Canberra.PROP_EVENT_ID,
                                   "system-ready");

        return false;
    }

    public void show ()
    {
        debug ("Showing main window");
        main_window.show ();
        main_window.get_window ().focus (Gdk.CURRENT_TIME);
        main_window.set_keyboard_state ();
    }

    private static Gdk.FilterReturn focus_upon_map (Gdk.XEvent gxevent, Gdk.Event event)
    {
        var xevent = (X.Event*)gxevent;
        if (xevent.type == X.EventType.MapNotify)
        {
            var display = Gdk.Display.get_default ();
            var xwin = xevent.xmap.window;
            var win = Gdk.X11Window.foreign_new_for_display (display, xwin);

            /* Check to see if this window is our onboard window, since we don't want to focus it. */
            X.Window keyboard_xid = 0;
            if (main_window.menubar.keyboard_window != null)
                keyboard_xid = Gdk.X11Window.get_xid (main_window.menubar.keyboard_window.get_window ());

            if (xwin != keyboard_xid && win.get_type_hint() != Gdk.WindowTypeHint.NOTIFICATION)
            {
                win.focus (Gdk.CURRENT_TIME);

                /* Make sure to keep keyboard above */
                if (main_window.menubar.keyboard_window != null)
                    main_window.menubar.keyboard_window.get_window ().raise ();
            }
        }
        return Gdk.FilterReturn.CONTINUE;
    }

    private void start_fake_wm ()
    {
        /* We want new windows (e.g. the shutdown dialog) to gain focus.
           We don't really need anything more than that (don't need alt-tab
           since any dialog should be "modal" or at least dealt with before
           continuing even if not actually marked as modal) */
        var root = Gdk.get_default_root_window ();
        root.set_events (root.get_events () | Gdk.EventMask.SUBSTRUCTURE_MASK);
        root.add_filter (focus_upon_map);
    }

    private static Cairo.XlibSurface? create_root_surface (Gdk.Screen screen)
    {
        var visual = screen.get_system_visual ();

        unowned X.Display display = Gdk.X11Display.get_xdisplay (screen.get_display ());

        var pixmap = X.CreatePixmap (display,
                                     Gdk.X11Window.get_xid (screen.get_root_window ()),
                                     screen.width (),
                                     screen.height (),
                                     visual.get_depth ());

        /* Convert into a Cairo surface */
        var surface = new Cairo.XlibSurface (display,
                                             pixmap,
                                             Gdk.X11Visual.get_xvisual (visual),
                                             screen.width (), screen.height ());

        return surface;
    }

    private static void refresh_background (Gdk.Screen screen, Cairo.XlibSurface surface)
    {
        Gdk.flush ();

        unowned X.Display display = Gdk.X11Display.get_xdisplay (screen.get_display ());

        /* Ensure Cairo has actually finished its drawing */
        surface.flush ();
        /* Use this pixmap for the background */
        X.SetWindowBackgroundPixmap (display,
                                     Gdk.X11Window.get_xid (screen.get_root_window ()),
                                     surface.get_drawable ());

        X.ClearWindow (display, Gdk.X11Window.get_xid (screen.get_root_window ()));
    }

    private static void log_cb (string? log_domain, LogLevelFlags log_level, string message)
    {
        string prefix;
        switch (log_level & LogLevelFlags.LEVEL_MASK)
        {
        case LogLevelFlags.LEVEL_ERROR:
            prefix = "ERROR:";
            break;
        case LogLevelFlags.LEVEL_CRITICAL:
            prefix = "CRITICAL:";
            break;
        case LogLevelFlags.LEVEL_WARNING:
            prefix = "WARNING:";
            break;
        case LogLevelFlags.LEVEL_MESSAGE:
            prefix = "MESSAGE:";
            break;
        case LogLevelFlags.LEVEL_INFO:
            prefix = "INFO:";
            break;
        case LogLevelFlags.LEVEL_DEBUG:
            prefix = "DEBUG:";
            break;
        default:
            prefix = "LOG:";
            break;
        }

        stderr.printf ("[%+.2fs] %s %s\n", log_timer.elapsed (), prefix, message);
    }

    public static int main (string[] args)
    {
        /* Protect memory from being paged to disk, as we deal with passwords */
        Posix.mlockall (Posix.MCL_CURRENT | Posix.MCL_FUTURE);

        /* Disable the stupid global menubar */
        Environment.unset_variable ("UBUNTU_MENUPROXY");

        /* Initialize i18n */
        Intl.setlocale (LocaleCategory.ALL, "");
        Intl.bindtextdomain (Config.GETTEXT_PACKAGE, Config.LOCALEDIR);
        Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (Config.GETTEXT_PACKAGE);

        /* Set up the accessibility stack, in case the user needs it for screen reading etc. */
        Environment.set_variable ("GTK_MODULES", "atk-bridge", false);

        Pid atspi_pid = 0;

        try
        {
            string[] argv;

            Shell.parse_argv ("/usr/lib/at-spi2-core/at-spi-bus-launcher --launch-immediately", out argv);
            Process.spawn_async (null,
                                 argv,
                                 null,
                                 SpawnFlags.SEARCH_PATH,
                                 null,
                                 out atspi_pid);
        }
        catch (Error e)
        {
            warning ("Error starting the at-spi registry: %s", e.message);
        }

        Gtk.init (ref args);

        log_timer = new Timer ();
        Log.set_default_handler (log_cb);

        debug ("Starting unity-greeter %s UID=%d LANG=%s", Config.VERSION, (int) Posix.getuid (), Environment.get_variable ("LANG"));

        /* Set the cursor to not be the crap default */
        debug ("Setting cursor");
        Gdk.get_default_root_window ().set_cursor (new Gdk.Cursor (Gdk.CursorType.LEFT_PTR));

        /* Prepare to set the background */
        debug ("Creating background surface");
        background_surface = create_root_surface (Gdk.Screen.get_default ());

        debug ("Loading command line options");
        var c = new OptionContext (/* Arguments and description for --help text */
                                   _("- Unity Greeter"));
        c.add_main_entries (options, Config.GETTEXT_PACKAGE);
        c.add_group (Gtk.get_option_group (true));
        try
        {
            c.parse (ref args);
        }
        catch (Error e)
        {
            stderr.printf ("%s\n", e.message);
            stderr.printf (/* Text printed out when an unknown command-line argument provided */
                           _("Run '%s --help' to see a full list of available command line options."), args[0]);
            stderr.printf ("\n");
            return Posix.EXIT_FAILURE;
        }
        if (show_version)
        {
            /* Note, not translated so can be easily parsed */
            stderr.printf ("unity-greeter %s\n", Config.VERSION);
            return Posix.EXIT_SUCCESS;
        }

        if (test_mode)
            debug ("Running in test mode");

        if (!test_mode)
        {
            /* Make nm-applet hide items the user does not have permissions to interact with */
            Environment.set_variable ("NM_APPLET_HIDE_POLICY_ITEMS", "1", true);

            try
            {
                Process.spawn_command_line_async ("nm-applet");
            }
            catch (Error e)
            {
                warning ("Error starting nm-applet: %s", e.message);
            }
        }

        /* Set GTK+ settings */
        debug ("Setting GTK+ settings");
        var settings = Gtk.Settings.get_default ();
        var value = UGSettings.get_string (UGSettings.KEY_THEME_NAME);
        if (value != "")
            settings.set ("gtk-theme-name", value, null);
        value = UGSettings.get_string (UGSettings.KEY_ICON_THEME_NAME);
        if (value != "")
            settings.set ("gtk-icon-theme-name", value, null);
        value = UGSettings.get_string (UGSettings.KEY_FONT_NAME);
        if (value != "")
            settings.set ("gtk-font-name", value, null);
        var double_value = UGSettings.get_double (UGSettings.KEY_XFT_DPI);
        if (double_value != 0.0)
            settings.set ("gtk-xft-dpi", (int) (1024 * double_value), null);
        var boolean_value = UGSettings.get_boolean (UGSettings.KEY_XFT_ANTIALIAS);
        settings.set ("gtk-xft-antialias", boolean_value, null);
        value = UGSettings.get_string (UGSettings.KEY_XFT_HINTSTYLE);
        if (value != "")
            settings.set ("gtk-xft-hintstyle", value, null);
        value = UGSettings.get_string (UGSettings.KEY_XFT_RGBA);
        if (value != "")
            settings.set ("gtk-xft-rgba", value, null);

        debug ("Creating Unity Greeter");
        var greeter = new UnityGreeter ();

        debug ("Showing greeter");
        greeter.show ();

        debug ("Starting main loop");
        Gtk.main ();

        if (atspi_pid != 0)
        {
            Posix.kill (atspi_pid, Posix.SIGKILL);
            int status;
            Posix.waitpid (atspi_pid, out status, 0);
            atspi_pid = 0;
        }

        return Posix.EXIT_SUCCESS;
    }
}

/*
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

public class UnityGreeter
{
    static bool show_version = false;
    static bool test_mode = false;
    public static const OptionEntry[] options =
    {
        { "version", 'v', 0, OptionArg.NONE, ref show_version,
          /* Help string for command line --version flag */
          N_("Show release version"), null},
        { "test-mode", 0, 0, OptionArg.NONE, ref test_mode,
          /* Help string for command line --test-mode flag */
          N_("Run in test mode"), null},
        { null }
    };

    private static Timer log_timer;

    private static KeyFile config;
    
    private static Cairo.Surface background_surface;

    private SettingsDaemon settings_daemon;

    private string default_background;
    private UserList user_list;

    private Gtk.Window main_window;
    private LightDM.Greeter greeter;
    private bool prompted = false;

    /* User to authenticate against */
    private string ?authenticate_user = null;

    private string? test_username = null;
    private bool test_is_authenticated = false;

    public UnityGreeter ()
    {
        greeter = new LightDM.Greeter ();
        greeter.show_message.connect (show_message_cb);
        greeter.show_prompt.connect (show_prompt_cb);
        greeter.authentication_complete.connect (authentication_complete_cb);
        if (!test_mode)
        {
            try
            {
                greeter.connect_sync ();
            }
            catch (Error e)
            {
                warning ("Failed to connect to LightDM daemon");
                Posix.exit (Posix.EXIT_FAILURE);
            }
        }

        if (!test_mode)
        {
            settings_daemon = new SettingsDaemon ();
            settings_daemon.start ();
        }

        default_background = get_config_value ("greeter", "background", "#000000");

        main_window = new Gtk.Window ();
        main_window.get_accessible ().set_name (_("Login Screen"));
        main_window.has_resize_grip = false;

        var x = 0;
        var y = 0;
        var width = 1024;
        var height = 600;
        if (!test_mode)
        {
            Gdk.Rectangle geometry;
            var screen = main_window.get_screen ();
            screen.get_monitor_geometry (screen.get_primary_monitor (), out geometry);
            debug ("Monitor is %dx%d pixels at %d,%d", geometry.width, geometry.height, geometry.x, geometry.y);
            x = geometry.x;
            y = geometry.y;
            width = geometry.width;
            height = geometry.height;
        }
        main_window.set_default_size (width, height);
        main_window.move (x, y);

        user_list = new UserList (width, height);
        main_window.add (user_list);
        user_list.user_selected.connect (user_selected_cb);
        user_list.respond_to_prompt.connect (respond_to_prompt_cb);
        user_list.start_session.connect (start_session_cb);
        user_list.set_logo (get_config_value ("greeter", "logo", Path.build_filename (Config.PKGDATADIR, "logo.png", null)));
        user_list.show ();

        foreach (var session in LightDM.get_sessions ())
        {
            debug ("Adding session %s (%s)", session.key, session.name);
            user_list.add_session (session.key, session.name);
        }

        if (test_mode)
        {
            user_list.add_entry ("alice", "Alice User", "/usr/share/backgrounds/Berries_by_Orb9220.jpg", true);
            user_list.add_entry ("bob", "Bob User", "/usr/share/backgrounds/White_flowers_by_Garuna_bor-bor.jpg");
            user_list.add_entry ("carol", "Carol User", "/usr/share/backgrounds/Bird_by_Magnus.jpg");
            user_list.add_entry ("*guest", _("Guest Session"), default_background, true);
            user_list.add_entry (null, _("Other..."), default_background);

            user_list.add_session ("gnome", "Ubuntu");
            user_list.add_session ("gnome-shell", "GNOME");
            user_list.add_session ("kde", "KDE");
            user_list.session = "gnome";

            user_list.set_active_entry ("bob");
        }
        else
        {
            if (!greeter.hide_users_hint)
            {
                var users = LightDM.UserList.get_instance ();
                users.user_added.connect (user_added_cb);
                users.user_changed.connect (user_added_cb);
                users.user_removed.connect (user_removed_cb);
                foreach (var user in users.users)
                    user_added_cb (user);
            }

            if (greeter.has_guest_account_hint)
            {
                debug ("Adding guest account entry");
                user_list.add_entry ("*guest", _("Guest Session"), default_background);
            }

            user_list.add_entry (null, _("Other..."), default_background);

            if (greeter.select_user_hint != null)
                user_list.set_active_entry (greeter.select_user_hint);
        }
    }

    private void user_added_cb (LightDM.User user)
    {
        debug ("Adding/updating user %s (%s)", user.name, user.real_name);

        var label = user.real_name;
        if (user.real_name == "")
            label = user.name;
        user_list.add_entry (user.name, label, default_background, user.logged_in);
    }

    private void user_removed_cb (LightDM.User user)
    {
        debug ("Removing user %s", user.name);
        user_list.remove_entry (user.name);
    }

    private void background_loaded_cb (Background background)
    {
        debug ("Showing main window");
        main_window.show ();

        /* Explicitly give this window focus, don't know why we need this but
         * the Gtk.Entry cursors don't blink wihtout it */
        var event = new Gdk.Event (Gdk.EventType.FOCUS_CHANGE);
        event.focus_change.type = Gdk.EventType.FOCUS_CHANGE;
        event.focus_change.in = 1;
        event.focus_change.window = main_window.get_window ();
        if (event.focus_change.window != null)
            event.focus_change.window.ref ();
        main_window.send_focus_change (event);
    }

    public void show ()
    {
        /* Load the background */
        var background = user_list.get_background ();
        background.loaded.connect (background_loaded_cb);
        if (background.load ())
            background_loaded_cb (background);
    }

    private void show_message_cb (string text, LightDM.MessageType type)
    {
    }

    private void show_prompt_cb (string text, LightDM.PromptType type)
    {
        prompted = true;
        user_list.show_prompt (text, type == LightDM.PromptType.SECRET);
    }

    private void background_loaded2_cb (Background background)
    {
        /* Set the background */
        var c = new Cairo.Context (background_surface);
        c.set_source (background.pattern);
        c.paint ();
        c = null;
        refresh_background (Gdk.Screen.get_default ());

        try
        {
            greeter.start_session_sync (user_list.session);
        }
        catch (Error e)
        {
            warning ("Failed to start session: %s", e.message);
        }
    }

    private void authentication_complete_cb ()
    {
        bool is_authenticated;
        if (test_mode)
            is_authenticated = test_is_authenticated;
        else
            is_authenticated = greeter.is_authenticated;

        if (is_authenticated)
        {
            /* Login immediately if prompted */
            if (prompted)
            {
                user_list.login_complete ();
                if (test_mode)
                    user_list.login_complete ();
                else
                {
                    var background = user_list.get_background ();
                    background.loaded.connect (background_loaded2_cb);
                    if (background.load ())
                        background_loaded2_cb (background);
                }
            }
            else
            {
                prompted = true;
                user_list.show_authenticated ();
            }
        }
        else
        {
            if (prompted)
            {
                user_list.set_error (_("Invalid password, please try again"));
                start_authentication ();
            }
            else
            {
                user_list.set_error (_("Failed to authenticate"));
                user_list.show_authenticated ();
            }
        }
    }

    private void user_selected_cb (string? username)
    {
        debug ("start authentication %s", username);
        // FIXME: Need to handle unprompted login where username comes later
        if (!test_mode)
        {
            user_list.session = greeter.default_session_hint;
            if (username != null)
            {
                var user = LightDM.UserList.get_instance ().get_user_by_name (username);
                if (user != null)
                    user_list.session = user.session;
            }
        }
        user_list.set_error (null);
        start_authentication ();
    }

    private void update_other_label ()
    {
        if (!greeter.hide_users_hint)
            return;

        var text = _("User");
        
        if (test_mode)
        {
            if (user_list.selected == null && test_username != null)
                text = test_username;
        }
        else
        {
            if (user_list.selected == null && greeter.authentication_user != null)
                text = greeter.authentication_user;
        }

        user_list.add_entry (null, text, default_background);
    }
   
    private void start_authentication ()
    {
        prompted = false;

        if (test_mode)
        {
            test_username = null;
            test_is_authenticated = false;

            if (user_list.selected == null)
            {
                if (authenticate_user != null)
                {
                    test_username = authenticate_user;
                    authenticate_user = null;
                    show_prompt_cb (_("Password:"), LightDM.PromptType.SECRET);
                }
                else
                    show_prompt_cb (_("Username:"), LightDM.PromptType.QUESTION);
            }
            else if (user_list.selected == "*guest" || user_list.selected == "bob")
            {
                test_is_authenticated = true;
                authentication_complete_cb ();
            }
            else
            {
                test_username = user_list.selected;
                show_prompt_cb (_("Password:"), LightDM.PromptType.SECRET);
            }
        }
        else
        {
            if (user_list.selected == null)
            {
                greeter.authenticate (authenticate_user);
                authenticate_user = null;
            }
            else if (user_list.selected == "*guest")
                greeter.authenticate_as_guest ();
            else
                greeter.authenticate (user_list.selected);
        }

        update_other_label ();
    }

    private void respond_to_prompt_cb (string text)
    {
        user_list.set_error (null);

        if (test_mode)
        {
            debug ("response %s", text);
            if (test_username == null)
            {
                debug ("username=%s", text);
                test_username = text;
                show_prompt_cb (_("Password:"), LightDM.PromptType.SECRET);
            }
            else
            {
                test_is_authenticated = text == "password";
                authentication_complete_cb ();
            }
        }
        else
            greeter.respond (text);

        update_other_label ();
    }

    private void start_session_cb ()
    {
        var is_authenticated = false;
        if (test_mode)
            is_authenticated = test_is_authenticated;
        else
            is_authenticated = greeter.is_authenticated;

        /* Finish authentication (again) or restart it */
        if (is_authenticated)
            authentication_complete_cb ();
        else
            start_authentication ();
    }

    public static string? get_config_value (string group_name, string key, string? default = null)
    {
        try
        {
            return config.get_value (group_name, key);
        }
        catch (Error e)
        {
            if (!(e is KeyFileError.KEY_NOT_FOUND || e is KeyFileError.GROUP_NOT_FOUND))
                warning ("Error reading configuration item %s:%s: %s", group_name, key, e.message);
            return default;
        }
    }

    private static Cairo.Surface? create_root_surface (Gdk.Screen screen)
    {
        var visual = screen.get_system_visual ();

        /* Open a new connection so with Retain Permanent so the pixmap remains when the greeter quits */
        Gdk.flush ();
        var display = new X.Display (screen.get_display ().get_name ());
        if (display == null)
        {
            warning ("Failed to create root pixmap");
            return null;
        }
        display.set_close_down_mode (X.RetainPermanent);
        var pixmap = X.CreatePixmap (display,
                                     Gdk.X11Window.get_xid (screen.get_root_window ()),
                                     screen.width (),
                                     screen.height (),
                                     visual.get_depth ());

        /* Convert into a Cairo surface */
        unowned X.Display xdisplay = Gdk.X11Display.get_xdisplay (screen.get_display ());
        var surface = new Cairo.XlibSurface (xdisplay,
                                             pixmap,
                                             Gdk.X11Visual.get_xvisual (visual),
                                             screen.width (), screen.height ());

        /* Use this pixmap for the background */
        X.SetWindowBackgroundPixmap (xdisplay,
                                     Gdk.X11Window.get_xid (screen.get_root_window ()),
                                     surface.get_drawable ());


        return surface;  
    }

    private void refresh_background (Gdk.Screen screen)
    {
        Gdk.flush ();
        X.ClearWindow (Gdk.X11Display.get_xdisplay (screen.get_display ()), Gdk.X11Window.get_xid (screen.get_root_window ()));
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
        /* Disable the stupid global menubar */
        Environment.unset_variable ("UBUNTU_MENUPROXY");

        /* Initialize i18n */
        Intl.bindtextdomain (Config.GETTEXT_PACKAGE, Config.LOCALEDIR);
        Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (Config.GETTEXT_PACKAGE);

        Gtk.init (ref args);

        log_timer = new Timer ();
        Log.set_default_handler (log_cb);

        debug ("Starting unity-greeter %s", Config.VERSION);

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

        debug ("Loading configuration from %s", Config.CONFIG_FILE);
        config = new KeyFile ();
        try
        {
            config.load_from_file (Config.CONFIG_FILE, KeyFileFlags.NONE);
        }
        catch (Error e)
        {
            if (!(e is FileError.NOENT))
                warning ("Failed to load configuration from %s: %s\n", Config.CONFIG_FILE, e.message);
        }

        /* Set GTK+ settings */
        debug ("Setting GTK+ settings");
        var settings = Gtk.Settings.get_default ();
        var value = get_config_value ("greeter", "theme-name");
        if (value != null)
            settings.set ("gtk-theme-name", value, null);
        value = get_config_value ("greeter", "icon-theme-name");
        if (value != null)
            settings.set ("gtk-icon-theme-name", value, null);
        value = get_config_value ("greeter", "font-name");
        if (value != null)
            settings.set ("gtk-font-name", value, null);
        value = get_config_value ("greeter", "xft-dpi");
        if (value != null)
            settings.set ("gtk-xft-dpi", (int) (1024 * double.parse (value)), null);
        value = get_config_value ("greeter", "xft-antialias");
        if (value != null)
            settings.set ("gtk-xft-antialias", strcmp (value, "true") == 0, null);
        value = get_config_value ("greeter", "xft-hintstyle");
        if (value != null)
            settings.set ("gtk-xft-hintstyle", value, null);
        value = get_config_value ("greeter", "xft-rgba");
        if (value != null)
            settings.set ("gtk-xft-rgba", value, null);

        debug ("Creating Unity Greeter");
        var greeter = new UnityGreeter ();

        debug ("Showing greeter");
        greeter.show ();

        debug ("Starting main loop");
        Gtk.main ();

        return Posix.EXIT_SUCCESS;
    }
}

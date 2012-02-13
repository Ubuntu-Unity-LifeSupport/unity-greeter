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
          N_("Show release version"), null},
        { "test-mode", 0, 0, OptionArg.NONE, ref test_mode,
          /* Help string for command line --test-mode flag */
          N_("Run in test mode"), null},
        { null }
    };

    private static Timer log_timer;

    private File state_file;
    private KeyFile state;

    private static Cairo.Surface background_surface;

    private SettingsDaemon settings_daemon;

    private MainWindow main_window;
    public UserList user_list;

    private LightDM.Greeter greeter;
    private bool prompted = false;
    private bool have_session = false;

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

        state_file = File.new_for_path (Path.build_filename (state_dir, "state"));
        state = new KeyFile ();
        try
        {
            state.load_from_file (state_file.get_path (), KeyFileFlags.NONE);
        }
        catch (Error e)
        {
            if (!(e is FileError.NOENT))
                warning ("Failed to load state from %s: %s\n", state_file.get_path (), e.message);
        }
        var last_user = "";
        try
        {
            last_user = state.get_value ("greeter", "last-user");
        }
        catch (Error e) {}

        main_window = new MainWindow ();
        user_list = main_window.user_list;

        foreach (var session in LightDM.get_sessions ())
        {
            debug ("Adding session %s (%s)", session.key, session.name);
            user_list.add_session (session.key, session.name);
        }

        if (test_mode)
        {
            user_list.add_entry ("alice", "가나다라마", "/usr/share/backgrounds/Darkening_Clockwork_by_Matt_Katzenberger.jpg", make_layout_list ("kr"), true);
            user_list.add_entry ("chris", "Christopher Halse Rogers!!!!!!!!!!!!!!!", "/usr/share/backgrounds/Darkening_Clockwork_by_Matt_Katzenberger.jpg", null, true);
            user_list.add_entry ("jorge", "Jorge O Castro", "/usr/share/backgrounds/PurpleDancers_by_Emilio_Merlino.jpg", make_layout_list ("us"));
            user_list.add_entry ("ken", "Ken VanDine", "/usr/share/backgrounds/Small_flowers_by_Dariusz_Duma.jpg", make_layout_list ("uk;us"));
            user_list.add_entry ("matthew", "Matthew Paul Thomas", "/usr/share/backgrounds/Not_Alone_by_Deacon_MacMillan.jpg", make_layout_list ("gb"));
            user_list.add_entry ("otto", "Otto Greenslade", "/usr/share/backgrounds/Mount_Snowdon,_Wales_by_Adam_Vellender.jpg", make_layout_list ("gb"));
            user_list.add_entry ("pitti", "Martin Pitt", "/usr/share/backgrounds/Stalking_Ocelot_by_Sayantan_Chaudhuri.jpg", make_layout_list ("de\tdvorak;us"));
            user_list.add_entry ("desrt", "Ryan Lortie", "/usr/share/backgrounds/Power_of_Words_by_Antonio_Litterio.jpg", make_layout_list ("ca"));
            user_list.add_entry ("*guest", _("Guest Session"), null, null, true);

            user_list.add_session ("gnome", "Ubuntu");
            user_list.add_session ("gnome-shell", "GNOME");
            user_list.add_session ("kde", "KDE");

            if (last_user != null)
                user_list.set_active_entry (last_user);
        }
        else
        {
            if (greeter.hide_users_hint)
                user_list.add_entry ("*other", _("Login"), null, null);
            else
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
                user_list.add_entry ("*guest", _("Guest Session"), null, null);
            }

            if (greeter.select_user_hint != null)
                user_list.set_active_entry (greeter.select_user_hint);
            else if (last_user != null)
                user_list.set_active_entry (last_user);
        }

        user_list.user_selected.connect (user_selected_cb);
        user_list.respond_to_prompt.connect (respond_to_prompt_cb);
        user_list.start_session.connect (start_session_cb);
        user_selected_cb (user_list.selected);

        start_fake_wm ();
    }

    public static void add_style_class (Gtk.Widget widget)
    {
        /* Add style context class lightdm-user-list */
        var ctx = widget.get_style_context ();
        ctx.add_class ("lightdm");
    }

    private List <LightDM.Layout> make_layout_list (string names)
    {
        var names_split = names.split (";");

        var layouts = new List <LightDM.Layout> ();
        foreach (var name in names_split)
        {
            var layout = get_layout_by_name (name);
            if (layout != null)
                layouts.append (layout);
        }

        return layouts;
    }

    private LightDM.Layout? get_layout_by_name (string name)
    {
        foreach (var layout in LightDM.get_layouts ())
        {
            if (layout.name == name)
                return layout;
        }
        return null;
    }

    private void user_added_cb (LightDM.User user)
    {
        debug ("Adding/updating user %s (%s)", user.name, user.real_name);

        var label = user.real_name;
        if (user.real_name == "")
            label = user.name;

        var layouts = new List <LightDM.Layout> ();
        foreach (var name in user.get_layouts ())
        {
            var layout = get_layout_by_name (name);
            if (layout != null)
                layouts.append (layout);
        }

        user_list.add_entry (user.name, label, user.background, layouts, user.logged_in);
    }

    private void user_removed_cb (LightDM.User user)
    {
        debug ("Removing user %s", user.name);
        user_list.remove_entry (user.name);
    }

    public void show ()
    {
        debug ("Showing main window");
        main_window.show ();
        main_window.get_window ().focus (Gdk.CURRENT_TIME);
    }

    private void update_session ()
    {
        if (have_session)
            return;

        if (test_mode)
        {
            if (test_username == null)
                return;

            switch (test_username)
            {
            case "alice":
                user_list.session = "ubuntu";
                break;
            case "bob":
                user_list.session = "gnome-shell";
                break;
            case "carol":
                user_list.session = "kde";
                break;
            default:
                return;
            }
            have_session = true;
            return;
        }
        else
        {
            if (greeter.authentication_user == null)
                return;

            var user = LightDM.UserList.get_instance ().get_user_by_name (greeter.authentication_user);
            if (user == null)
            {
                user_list.session = greeter.default_session_hint;
                return;
            }

            user_list.session = user.session;
            have_session = true;
        }
    }

    private void show_message_cb (string text, LightDM.MessageType type)
    {
        update_session ();
        user_list.show_message (text, type == LightDM.MessageType.ERROR);
    }

    private void show_prompt_cb (string text, LightDM.PromptType type)
    {
        update_session ();
        update_other_label ();

        prompted = true;
        if (text == "Password: ")
            text = _("Password:");
        if (text == "login:")
            text = _("Username:");
        user_list.show_prompt (text, type == LightDM.PromptType.SECRET);
    }

    private void background_loaded_cb (ParamSpec pspec)
    {
        if (user_list.background.alpha == 1.0)
        {
            user_list.background.notify["alpha"].disconnect (background_loaded_cb);
            start_session ();
        }
    }

    private void start_session ()
    {
        /* Set the background */
        var c = new Cairo.Context (background_surface);
        user_list.background.draw (c);
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
        update_session ();
        update_other_label ();

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
                if (!test_mode)
                {
                    if (user_list.background.alpha == 1.0)
                        start_session ();
                    else
                        user_list.background.notify["alpha"].connect (background_loaded_cb);
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
        state.set_value ("greeter", "last-user", username);
        var data = state.to_data ();
        try
        {
            state_file.replace_contents ((uint8[])data, null, false, FileCreateFlags.NONE, null);
        }
        catch (Error e)
        {
            debug ("Failed to write state: %s", e.message);
        }

        user_list.set_error (null);
        if (test_mode)
            user_list.session = "ubuntu";
        else
            user_list.session = greeter.default_session_hint;        
        start_authentication ();
    }

    private void update_other_label ()
    {
        if (!greeter.hide_users_hint)
            return;

        var text = _("Other...");
        if (test_mode)
        {
            if (user_list.selected == "*other" && test_username != null)
                text = test_username;
        }
        else
        {
            if (user_list.selected == "*other" && greeter.authentication_user != null)
                text = greeter.authentication_user;
        }

        user_list.add_entry ("*other", text, null, null);
    }

    private void start_authentication ()
    {
        prompted = false;
        have_session = false;

        if (test_mode)
        {
            test_username = null;
            test_is_authenticated = false;

            if (user_list.selected == "*other")
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
            else if (user_list.selected == "*guest")
            {
                test_is_authenticated = true;
                authentication_complete_cb ();
            }
            else if (user_list.selected == "bob")
            {
                test_is_authenticated = true;
                test_username = user_list.selected;
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
            if (user_list.selected == "*other")
            {
                greeter.authenticate (authenticate_user);
                authenticate_user = null;
            }
            else if (user_list.selected == "*guest")
                greeter.authenticate_as_guest ();
            else
                greeter.authenticate (user_list.selected);
        }

        update_session ();
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

    private static Gdk.FilterReturn focus_upon_map (X.Event xevent, Gdk.Event event)
    {
        if (xevent.type == X.EventType.MapNotify)
        {
            var display = Gdk.Display.get_default ();
            var win = Gdk.X11Window.foreign_new_for_display (display, xevent.xmap.window);
            win.focus(Gdk.CURRENT_TIME);
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
        root.add_filter ((Gdk.FilterFunc) focus_upon_map);
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
        Intl.setlocale (LocaleCategory.ALL, "");
        Intl.bindtextdomain (Config.GETTEXT_PACKAGE, Config.LOCALEDIR);
        Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (Config.GETTEXT_PACKAGE);

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

        return Posix.EXIT_SUCCESS;
    }
}

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

    private string state_file;
    private KeyFile state;

    private static Cairo.XlibSurface background_surface;

    private SettingsDaemon settings_daemon;

    private MainWindow main_window;
    public UserList user_list;

    private LightDM.Greeter greeter;
    private bool prompted = false;
    private bool clear_messages = false;

    /* User to authenticate against */
    private string ?authenticate_user = null;

    private const TestEntry[] test_entries =
    {
        { "has-password",       "Has Password",      "*",              "uk;us", false, false, null },
        { "different-prompt",   "Different Prompt",  "*",              "uk;us", false, false, null },
        { "no-password",        "No Password",       "*",              "uk;us", false, false, null },
        { "change-password",    "Change Password",   "*",              "uk;us", false, false, null },
        { "auth-error",         "Auth Error",        "*",              "uk;us", false, false, null },
        { "two-factor",         "Two Factor",        "*",              "uk;us", false, false, null },
        { "two-prompts",        "Two Prompts",       "*",              "gb;us", false, false, null },
        { "info-prompt",        "Info Prompt",       "*",              "uk;us", false, false, null },
        { "long-info-prompt",   "Long Info Prompt",  "*",              "uk;us", false, false, null },
        { "wide-info-prompt",   "Wide Info Prompt",  "*",              "uk;us", false, false, null },
        { "multi-info-prompt",  "Multi Info Prompt", "*",              "uk;us", false, false, null },
        { "very-very-long-name",    "Long name (far too long to fit)", "*", "uk;us", false, false, null },
        { "long-name-and-messages", "Long name and messages",          "*", "uk;us", false, true,  null },
        { "active",             "Active Account",    "*",              "uk;us", true,  false, null },
        { "has-messages",       "Has Messages",      "*",              "uk;us", false, true,  null },
        { "gnome",              "GNOME",             "*",              "uk;us", false, false, "gnome-shell" },
        { "locked",             "Locked Account",    "*",              "uk;us", false, false, null },
        { "color-background",   "Color Background",  "#dd4814",        "uk;us", false, false, null },
        { "white-background",   "White Background",  "#ffffff",        "uk;us", false, false, null },
        { "black-background",   "Black Background",  "#000000",        "uk;us", false, false, null },
        { "no-background",      "No Background",     null,             "uk;us", false, false, null },
        { "unicode",            "가나다라마",        "*",              "uk;us", false, false, null },
        { "system-layout",      "System Layout",     "*",              null,    false, false, null },
        { "four-layouts",       "Four Layouts",      "*",              "de\tdvorak;ca;gb;fr\toss", false, false, null },
        { "hy-layout",          "Layout Is 'hy'",    "*",              "am\teastern-alt", false, false, null }, // inherits parent layout's short_desc
        { "no-response",        "No Response",       "*",              null,    false, false, null },
        { "",                   "",                  null,             null,    false, false, null }
    };
    private List<string> test_backgrounds;
    private int n_test_entries = 0;
    private string? test_username = null;
    private bool test_prompted_sso = false;
    private bool test_request_new_password = false;
    private string? test_new_password = null;
    private bool test_is_authenticated = false;
    private Canberra.Context canberra_context;

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
        var last_user = "";
        try
        {
            last_user = state.get_value ("greeter", "last-user");
        }
        catch (Error e) {}

        main_window = new MainWindow ();
        user_list = main_window.user_list;

        if (test_mode)
        {
            test_backgrounds = new List<string> ();
            try
            {
                var dir = Dir.open ("/usr/share/backgrounds/");
                while (true)
                {
                    var bg = dir.read_name ();
                    if (bg == null)
                        break;
                    test_backgrounds.append ("/usr/share/backgrounds/" + bg);
                }
            }
            catch (FileError e)
            {
            }

            while (add_test_entry ());
            user_list.offer_guest = true;
            
            main_window.key_press_event.connect (key_press_cb);

            if (last_user != null)
                user_list.set_active_entry (last_user);
        }
        else
        {
            user_list.default_session = greeter.default_session_hint;
            user_list.always_show_manual = greeter.show_manual_login_hint;
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
                user_list.offer_guest = true;
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
        Gdk.threads_add_idle (ready_cb); 
    }
    
    private bool key_press_cb (Gdk.EventKey event)
    {
        if ((event.state & Gdk.CONTROL_MASK) == 0)
            return false;

        switch (event.keyval)
        {
        case Gdk.KEY_plus:
            add_test_entry ();
            break;
        case Gdk.KEY_minus:
            remove_test_entry ();
            break;
        case Gdk.KEY_0:
            while (remove_test_entry ());
            user_list.offer_guest = false;
            break;
        case Gdk.KEY_equal:
            while (add_test_entry ());
            user_list.offer_guest = true;
            break;
        case Gdk.KEY_g:
            user_list.offer_guest = false;
            break;
        case Gdk.KEY_G:
            user_list.offer_guest = true;
            break;
        case Gdk.KEY_m:
            user_list.always_show_manual = false;
            break;
        case Gdk.KEY_M:
            user_list.always_show_manual = true;
            break;
        }

        return false;
    }

    private bool add_test_entry ()
    {
        var e = test_entries[n_test_entries];
        if (e.username == "")
            return false;

        var background = e.background;
        if (background == "*")
        {
            var background_index = 0;
            for (var i = 0; i < n_test_entries; i++)
            {
                if (test_entries[i].background == "*")
                    background_index++;
            }
            if (test_backgrounds.length () > 0)
                background = test_backgrounds.nth_data (background_index % test_backgrounds.length ());
        }
        user_list.add_entry (e.username, e.real_name, background, make_layout_list (e.layouts), e.is_active, e.has_messages, e.session);
        n_test_entries++;

        return true;
    }

    private bool remove_test_entry ()
    {
        if (n_test_entries == 0)
            return false;

        user_list.remove_entry (test_entries[n_test_entries - 1].username);
        n_test_entries--;

        return true;
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

    public static LightDM.Layout? get_layout_by_name (string name)
    {
        foreach (var layout in LightDM.get_layouts ())
        {
            if (layout.name == name)
                return layout;
        }
        return null;
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

        user_list.add_entry (user.name, label, user.background, layouts, user.logged_in, user.has_messages, user.session);
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

    private void show_message_cb (string text, LightDM.MessageType type)
    {
        if (clear_messages)
        {
            user_list.clear_messages ();
            clear_messages = false;
        }
        user_list.show_message (text, type == LightDM.MessageType.ERROR);
    }

    private void show_prompt_cb (string text, LightDM.PromptType type)
    {
        if (clear_messages)
        {
            user_list.clear_messages ();
            clear_messages = false;
        }

        /* Notify the greeter on what user has been logged */
        if (user_list.selected == "*other" && user_list.manual_username == null)
        {
            if (test_mode)
                user_list.manual_username = test_username;
            else
                user_list.manual_username = greeter.authentication_user;
        }

        prompted = true;
        if (text == "Password: ")
            text = _("Password:");
        if (text == "login:")
            text = _("Username:");
        user_list.show_prompt (text, type == LightDM.PromptType.SECRET);

        /* Clear messages on the next prompt */
        clear_messages = true;
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
        user_list.background.draw_full (c, Background.DrawFlags.NONE);
        c = null;
        refresh_background (Gdk.Screen.get_default (), background_surface);

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
                if (!test_mode)
                {
                    if (user_list.background.alpha == 1.0)
                        start_session ();
                    else
                        user_list.background.notify["alpha"].connect (background_loaded_cb);
                }
                else
                {
                    /* Set the background */
                    var c = new Cairo.Context (background_surface);
                    user_list.background.draw_full (c, Background.DrawFlags.NONE);
                    c = null;
                    refresh_background (Gdk.Screen.get_default (), background_surface);

                    debug ("Successfully logged in!  Quitting...");
                    Gtk.main_quit ();
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
                /* Show an error if one wasn't provided */
                if (clear_messages)
                    user_list.clear_messages ();
                if (!user_list.have_messages ())
                    user_list.show_message (_("Invalid password, please try again"), true);

                /* Restart authentication */
                start_authentication ();
            }
            else
            {
                /* Show an error if one wasn't provided */
                if (!user_list.have_messages ())
                    user_list.show_message (_("Failed to authenticate"), true);

                /* Stop authentication */
                user_list.show_authenticated (false);
            }
        }
    }

    private void user_selected_cb (string? username)
    {
        state.set_value ("greeter", "last-user", username);
        var data = state.to_data ();
        try
        {
            FileUtils.set_contents (state_file, data);
        }
        catch (Error e)
        {
            debug ("Failed to write state: %s", e.message);
        }

        user_list.clear_messages ();
        start_authentication ();
    }

    private void start_authentication ()
    {
        prompted = false;

        /* Reset manual username */
        user_list.manual_username = null;

        clear_messages = false;

        if (test_mode)
        {
            test_username = null;
            test_is_authenticated = false;
            test_prompted_sso = false;
            test_request_new_password = false;
            test_new_password = null;

            switch (user_list.selected)
            {
            case "*other":
                if (authenticate_user != null)
                {
                    test_username = authenticate_user;
                    authenticate_user = null;
                    show_prompt_cb (_("Password:"), LightDM.PromptType.SECRET);
                }
                else
                    show_prompt_cb (_("Username:"), LightDM.PromptType.QUESTION);
                break;
            case "*guest":
                test_is_authenticated = true;
                authentication_complete_cb ();
                break;
            case "different-prompt":
                show_prompt_cb ("Secret word", LightDM.PromptType.SECRET);
                break;
            case "no-password":
                test_is_authenticated = true;
                authentication_complete_cb ();
                break;
            case "auth-error":
                show_message_cb ("Authentication Error", LightDM.MessageType.ERROR);
                test_is_authenticated = false;
                authentication_complete_cb ();
                break;
            case "info-prompt":
                show_message_cb ("Welcome to Unity Greeter", LightDM.MessageType.INFO);
                show_prompt_cb (_("Password:"), LightDM.PromptType.SECRET);
                break;
            case "long-info-prompt":
                show_message_cb ("Welcome to Unity Greeter\n\nWe like to annoy you with long messages.\nLike this one\n\nThis is the last line of a multiple line message.", LightDM.MessageType.INFO);
                show_prompt_cb (_("Password:"), LightDM.PromptType.SECRET);
                break;
            case "wide-info-prompt":
                show_message_cb ("Welcome to Unity Greeter, the greeteriest greeter that ever did appear in these fine lands", LightDM.MessageType.INFO);
                show_prompt_cb (_("Password:"), LightDM.PromptType.SECRET);
                break;
            case "multi-info-prompt":
                show_message_cb ("Welcome to Unity Greeter", LightDM.MessageType.INFO);
                show_message_cb ("This is an error", LightDM.MessageType.ERROR);
                show_message_cb ("You should have seen three messages", LightDM.MessageType.INFO);
                show_prompt_cb (_("Password:"), LightDM.PromptType.SECRET);
                break;
            case "two-prompts":
                show_prompt_cb (_("Favorite Color:"), LightDM.PromptType.QUESTION);
                show_prompt_cb (_("Password:"), LightDM.PromptType.SECRET);
                break;
            default:
                show_prompt_cb (_("Password:"), LightDM.PromptType.SECRET);
                break;
            }
        }
        else
        {
            if (user_list.selected == "*other")
                greeter.authenticate ();
            else if (user_list.selected == "*guest")
                greeter.authenticate_as_guest ();
            else
                greeter.authenticate (user_list.selected);
        }
    }

    private void respond_to_prompt_cb (string text)
    {
        if (test_mode)
        {
            debug ("response %s", text);
            switch (user_list.selected)
            {
            case "*other":
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
                break;
            case "two-factor":
                if (!test_prompted_sso)
                {
                    if (text == "password")
                    {
                        debug ("prompt otp");
                        test_prompted_sso = true;
                        show_prompt_cb ("OTP:", LightDM.PromptType.QUESTION);
                    }
                    else
                    {
                        test_is_authenticated = false;
                        authentication_complete_cb ();
                    }
                }
                else
                {
                    test_is_authenticated = text == "otp";
                    authentication_complete_cb ();
                }
                break;
            case "change-password":
                if (test_new_password != null)
                {
                    test_is_authenticated = text == test_new_password;
                    authentication_complete_cb ();
                }
                else if (test_request_new_password)
                {
                    test_new_password = text;
                    show_prompt_cb ("Retype new UNIX password: ", LightDM.PromptType.SECRET);
                }
                else
                {
                    if (text != "password")
                    {
                        test_is_authenticated = false;
                        authentication_complete_cb ();
                    }
                    else
                    {
                        test_request_new_password = true;
                        show_message_cb ("You are required to change your password immediately (root enforced)", LightDM.MessageType.ERROR);
                        show_prompt_cb ("Enter new UNIX password: ", LightDM.PromptType.SECRET);
                    }
                }
                break;
            case "no-response":
                break;
            case "locked":
                test_is_authenticated = false;
                show_message_cb ("Account is locked", LightDM.MessageType.ERROR);
                authentication_complete_cb ();
                break;
            default:
                test_is_authenticated = text == "password";
                authentication_complete_cb ();
                break;
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
        {
            user_list.clear_messages ();
            start_authentication ();
        }
    }

    private Gdk.FilterReturn focus_upon_map (X.Event xevent, Gdk.Event event)
    {
        if (xevent.type == X.EventType.MapNotify)
        {
            var display = Gdk.Display.get_default ();
            var win = Gdk.X11Window.foreign_new_for_display (display, xevent.xmap.window);

            if (win.get_accept_focus ())
                win.focus (Gdk.CURRENT_TIME);
            else
                user_list.focus_prompt ();
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

    private void refresh_background (Gdk.Screen screen, Cairo.XlibSurface surface)
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

private struct TestEntry
{
    string username;
    string real_name;
    string? background;
    string? layouts;
    bool is_active;
    bool has_messages;
    string? session;
}

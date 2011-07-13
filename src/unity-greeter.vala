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

    public UserList user_list;

    private Gtk.Window main_window;
    private LightDM.Greeter greeter;
    private bool prompted = false;
    
    private string? test_username = null;
    private bool test_is_authenticated = false;

    public UnityGreeter ()
    {
        if (!test_mode)
        {
            greeter = new LightDM.Greeter ();
            greeter.connected.connect (connected_cb);
            greeter.show_message.connect (show_message_cb);
            greeter.show_prompt.connect (show_prompt_cb);
            greeter.authentication_complete.connect (authentication_complete_cb);
            greeter.quit.connect (quit_cb);
            greeter.connect_to_server ();
        }

        user_list = new UserList ();
        user_list.user_selected.connect (user_selected_cb);
        user_list.respond_to_prompt.connect (respond_to_prompt_cb);
        user_list.start_session.connect (start_session_cb);
        user_list.show ();

        if (test_mode)
        {
            user_list.add_entry ("alice", "Alice User", "/usr/share/backgrounds/Berries_by_Orb9220.jpg", true);
            user_list.add_entry ("bob", "Bob User", "/usr/share/backgrounds/White_flowers_by_Garuna_bor-bor.jpg");
            user_list.add_entry ("carol", "Carol User", "/usr/share/backgrounds/Bird_by_Magnus.jpg");
            user_list.add_entry ("*guest", "Guest Account", null, true);
            user_list.add_entry (null, "Other...");

            user_list.add_session ("gnome", "Ubuntu");
            user_list.add_session ("gnome-shell", "GNOME");
            user_list.add_session ("kde", "KDE");
            user_list.session = "gnome";
        }

        main_window = new Gtk.Window ();
        if (test_mode)
            main_window.set_default_size (1024, 600);
        else
        {
            var screen = Gdk.Display.get_default ().get_default_screen ();
            main_window.set_default_size (screen.get_width (), screen.get_height ());
        }
        main_window.add (user_list);
    }

    public void show ()
    {
        main_window.show ();
    }

    private void connected_cb ()
    {
        foreach (var user in greeter.get_users ())
        {
            var label = user.real_name;
            if (user.real_name == null)
                label = user.name;
            user_list.add_entry (user.name, label, null);
        }
        if (greeter.has_guest_session)
            user_list.add_entry ("*guest", "Guest Account", null);
        user_list.add_entry (null, "Other...");

        foreach (var session in greeter.get_sessions ())
            user_list.add_session (session.key, session.name);
    }

    private void show_message_cb (string text, LightDM.MessageType type)
    {
    }

    private void show_prompt_cb (string text, LightDM.PromptType type)
    {
        debug ("prompt '%s'", text);
        prompted = true;
        user_list.show_prompt (text, type == LightDM.PromptType.SECRET);
    }

    private bool test_quit_cb ()
    {
        Posix.exit (Posix.EXIT_SUCCESS);
        return false;
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
                {
                    user_list.login_complete ();
                    Timeout.add (1000, test_quit_cb);
                }
                else
                    greeter.start_session (user_list.session);
            }
            else
            {
                prompted = true;
                user_list.show_authenticated ();
            }
        }
        else
        {
            user_list.set_error ("Invalid password, please try again");
            start_authentication ();
        }
    }

    private void user_selected_cb (string? username)
    {
        debug ("start authentication %s", username);
        // FIXME: Need to handle unprompted login where username comes later
        if (!test_mode)
        {
            user_list.session = greeter.default_session;
            if (username != null)
            {
                var user = greeter.get_user_by_name (username);
                if (user != null)
                    user_list.session = user.session;
            }
        }
        user_list.set_error (null);
        start_authentication ();
    }
    
    private void start_authentication ()
    {
        prompted = false;

        if (test_mode)
        {
            test_username = null;
            test_is_authenticated = false;

            if (user_list.selected == null)
                show_prompt_cb ("Username:", LightDM.PromptType.QUESTION);
            else if (user_list.selected == "*guest" || user_list.selected == "bob")
            {
                test_is_authenticated = true;
                authentication_complete_cb ();
            }
            else
            {
                test_username = user_list.selected;
                show_prompt_cb ("Password:", LightDM.PromptType.SECRET);
            }
        }
        else
        {
            if (user_list.selected == null)
                greeter.login_with_user_prompt ();
            else if (user_list.selected == "*guest")
                greeter.login_as_guest ();
            else
                greeter.login (user_list.selected);
        }
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
                show_prompt_cb ("Password:", LightDM.PromptType.SECRET);
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
        /* Finish authentication (again) */
        authentication_complete_cb ();
    }

    private void quit_cb ()
    {
        Posix.exit (Posix.EXIT_SUCCESS);
    }

    public static int main (string[] args)
    {
        Gtk.init (ref args);

        Gdk.get_default_root_window ().set_cursor (new Gdk.Cursor (Gdk.CursorType.LEFT_PTR));

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

        var greeter = new UnityGreeter ();
        greeter.show ();

        Gtk.main ();

        return Posix.EXIT_SUCCESS;
    }
}

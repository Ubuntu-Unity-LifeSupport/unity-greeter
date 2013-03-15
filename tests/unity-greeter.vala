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
    public static UnityGreeter singleton;

    public signal void show_message (string text, LightDM.MessageType type);
    public signal void show_prompt (string text, LightDM.PromptType type);
    public signal void authentication_complete ();

    public bool test_mode = false;
    public bool session_started = false;
    public string last_respond_response;
    public bool orca_needs_kick;

    public bool is_authenticated ()
    {
        return false;
    }

    public void authenticate (string? userid = null)
    {
    }

    public void authenticate_as_guest ()
    {
    }

    public void authenticate_remote (string? session, string? userid)
    {
    }

    public void cancel_authentication ()
    {
    }

    public void respond (string response)
    {
        last_respond_response = response;
    }

    public string authentication_user ()
    {
        return "";
    }

    public string default_session_hint ()
    {
        return "";
    }

    public string select_user_hint ()
    {
        return "";
    }

    public bool show_manual_login_hint ()
    {
        return false;
    }

    public bool show_remote_login_hint ()
    {
        return true;
    }

    public bool hide_users_hint ()
    {
        return false;
    }

    public bool has_guest_account_hint ()
    {
        return false;
    }

    public void start_session (string? session, Background bg)
    {
        session_started = true;
    }

    public void push_list (GreeterList widget)
    {
    }

    public void pop_list ()
    {
    }

    public string? get_state (string key)
    {
        return null;
    }

    public void set_state (string key, string value)
    {
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

    public static void add_style_class (Gtk.Widget widget)
    {
        /* Add style context class lightdm-user-list */
        var ctx = widget.get_style_context ();
        ctx.add_class ("lightdm");
    }
}

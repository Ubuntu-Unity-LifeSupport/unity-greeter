[CCode (cprefix = "", lower_case_cprefix = "", cheader_filename = "X11/Xlib.h")]
namespace X
{
    [CCode (cname = "XCreatePixmap")]
    public int CreatePixmap (X.Display display, X.Drawable d, uint width, uint height, uint depth);
    [CCode (cname = "XSetWindowBackgroundPixmap")]
    public int SetWindowBackgroundPixmap (X.Display display, X.Window w, int Pixmap);
    [CCode (cname = "XClearWindow")]
    public int ClearWindow (X.Display display, X.Window w);
    public const int RetainPermanent;
}

namespace Gdk
{
    public const int KEY_Home;
    public const int KEY_End;
    public const int KEY_Page_Up;
    public const int KEY_Page_Down;
    public const int KEY_Up;
    public const int KEY_Down;
    public const int KEY_KP_Home;
    public const int KEY_KP_End;
    public const int KEY_KP_Page_Up;
    public const int KEY_KP_Page_Down;
    public const int KEY_KP_Up;
    public const int KEY_KP_Down;
    public const int KEY_F10;
}

namespace Gtk
{
    public void socket_add_id (Gtk.Socket socket, int id);
}

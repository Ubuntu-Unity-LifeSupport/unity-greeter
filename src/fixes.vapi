namespace Posix
{
    [CCode (cheader_filename = "sys/mman.h")]
    public const int MCL_CURRENT;
    [CCode (cheader_filename = "sys/mman.h")]
    public const int MCL_FUTURE;
    [CCode (cheader_filename = "sys/mman.h")]
    public int mlockall (int flags);
    [CCode (cheader_filename = "sys/mman.h")]
    public int munlockall ();
}

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
    public const int KEY_Escape;
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
    public const int KEY_0;
    public const int KEY_g;
    public const int KEY_G;
    public const int KEY_h;
    public const int KEY_m;
    public const int KEY_M;
    public const int KEY_s;
    public const int KEY_plus;
    public const int KEY_minus;
    public const int KEY_equal;
    public const int CONTROL_MASK;
}

namespace Gtk
{
    public void socket_add_id (Gtk.Socket socket, int id);
}

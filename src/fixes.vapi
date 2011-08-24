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

[CCode (cprefix = "", lower_case_cprefix = "", cheader_filename = "ft2build.h")]
namespace FreeType
{
    [SimpleType]
    [CCode (cname = "FT_Library")]
    public struct Library { }

    [SimpleType]
    [CCode (cname = "FT_Face")]
    public struct Face { }

    [CCode (cname = "FT_Init_FreeType")]
    public void init (out Library library);

    [CCode (cname = "FT_New_Face")]
    public void new_face (Library library, string filepathname, int face_index, out Face face);
}

namespace Cairo
{
    [CCode (cprefix = "", lower_case_cprefix = "", cheader_filename = "cairo-ft.h")]
    public Cairo.FontFace ft_font_face_create_for_ft_face (FreeType.Face face, int load_flags);
}

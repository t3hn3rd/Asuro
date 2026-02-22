/*
 * imgbridge.c  -  C bridge between cimgui/Dear ImGui and the Pascal renderer
 *
 * Compiled with -DCIMGUI_DEFINE_ENUMS_AND_STRUCTS so ImGui structs are
 * available as plain C types.  This file iterates ImDrawData and calls
 * Pascal callbacks for every triangle and for the font texture.
 *
 * Targets cimgui master (ImGui 1.91+) which uses the new ImTextureData
 * / ImTextureStatus texture management API.
 *
 * Pascal side must export (cdecl, public):
 *   imgui_pascal_set_font_texture(unsigned char* pixels, int w, int h)
 *   imgui_pascal_render_triangle(
 *       float x0,y0,u0,v0, unsigned int c0,
 *       float x1,y1,u1,v1, unsigned int c1,
 *       float x2,y2,u2,v2, unsigned int c2,
 *       float clip_x0, clip_y0, clip_x1, clip_y1)
 */

/* CIMGUI_DEFINE_ENUMS_AND_STRUCTS is set via -D on the command line */
#include "cimgui.h"

#include <stdio.h>     /* FILE, stdout/stderr declarations for stubs */
#include <stdlib.h>    /* malloc, free */
#include <string.h>    /* memset */
#include <unistd.h>    /* fork, _exit */
#include <stddef.h>    /* size_t */
#include <stdint.h>    /* uintptr_t */

#ifdef __cplusplus
extern "C" {
#endif

/* --------------------------------------------------------------------------
 * File I/O stubs  (ImGui calls fopen/fclose/etc. for .ini save/load and
 *                  logging.  On bare metal there is no filesystem.)
 * -------------------------------------------------------------------------- */
static int _fake_file_storage;
FILE* stdout = (FILE*)&_fake_file_storage;
FILE* stderr = (FILE*)&_fake_file_storage;

FILE* fopen(const char* path, const char* mode)  { (void)path; (void)mode; return (FILE*)0; }
int   fclose(FILE* f)                            { (void)f; return 0; }
size_t fread(void* buf, size_t sz, size_t n, FILE* f)   { (void)buf;(void)sz;(void)n;(void)f; return 0; }
size_t fwrite(const void* buf, size_t sz, size_t n, FILE* f) { (void)buf;(void)sz;(void)f; return n; }
int   fseek(FILE* f, long off, int whence)       { (void)f;(void)off;(void)whence; return -1; }
long  ftell(FILE* f)                             { (void)f; return 0; }
int   fprintf(FILE* f, const char* fmt, ...)     { (void)f;(void)fmt; return 0; }
int   fflush(FILE* f)                            { (void)f; return 0; }
int   fputc(int c, FILE* f)                      { (void)c;(void)f; return c; }
int   fputs(const char* s, FILE* f)              { (void)s;(void)f; return 0; }
int   feof(FILE* f)                              { (void)f; return 1; }
int   ferror(FILE* f)                            { (void)f; return 0; }

/* --------------------------------------------------------------------------
 * Process stubs  (ImGui's Platform_OpenInShellFn_DefaultImpl on Linux
 *                 tries fork/execvp/waitpid — none available on bare metal.)
 * -------------------------------------------------------------------------- */
pid_t fork(void)  { return -1; }
pid_t waitpid(pid_t pid, int* status, int opts) { (void)pid;(void)status;(void)opts; return -1; }
int   execvp(const char* file, char* const argv[]) { (void)file;(void)argv; return -1; }
void  _exit(int code) { (void)code; for(;;); }

/* ---- Pascal callbacks ---- */
extern void imgui_pascal_set_font_texture(
    unsigned char* pixels, int width, int height);

extern void imgui_pascal_render_triangle(
    float x0, float y0, float u0, float v0, unsigned int c0,
    float x1, float y1, float u1, float v1, unsigned int c1,
    float x2, float y2, float u2, float v2, unsigned int c2,
    float clip_x0, float clip_y0, float clip_x1, float clip_y1);

/* Debug helper: write to serial via Pascal console */
/* FPC uses register calling convention: first param in EAX.
   regparm(3) tells GCC to pass first 3 params in EAX,EDX,ECX. */
extern void console_writestring(const char* s) __attribute__((regparm(3)));
static void dbg(const char* msg) {
    if (!msg) { console_writestring("(null)"); return; }
    console_writestring(msg);
}

/* Tiny helper to print a hex number over serial */
static void dbg_hex(unsigned int v) {
    static const char hex[] = "0123456789ABCDEF";
    char buf[11];
    buf[0] = '0'; buf[1] = 'x';
    for (int i = 7; i >= 0; i--)
        buf[2 + (7 - i)] = hex[(v >> (i * 4)) & 0xF];
    buf[10] = '\0';
    console_writestring(buf);
}

/* ---- Debug counters (read from Pascal after render) ---- */
int imgui_dbg_valid     = -1;  /* -1=no draw data, 0=invalid, 1=valid */
int imgui_dbg_cmdlists  = 0;
int imgui_dbg_triangles = 0;
int imgui_dbg_texcount  = 0;
int imgui_dbg_font_w    = 0;
int imgui_dbg_font_h    = 0;

/* ---- Texture management (ImGui 1.91+ ImTextureData API) ---- */

/*
 * Process pending texture operations from the draw data.
 * Called after igRender() which populates draw_data->Textures.
 */
static void imgui_handle_textures(ImDrawData* draw_data) {
    int i;

    if (!draw_data) return;
    if (!draw_data->Textures) return;

    int tex_count = draw_data->Textures->Size;
    ImTextureData** tex_data = draw_data->Textures->Data;

    for (i = 0; i < tex_count; i++) {
        ImTextureData* tex = tex_data[i];
        if (!tex) continue;

        imgui_dbg_texcount++;

        if (tex->Status == ImTextureStatus_WantCreate) {
            /* Log texture format for debugging */
            dbg("[TEX] Create: fmt="); dbg_hex(tex->Format);
            dbg(" bpp="); dbg_hex(tex->BytesPerPixel);
            dbg(" sz="); dbg_hex(tex->Width); dbg("x"); dbg_hex(tex->Height);
            dbg("\r\n");

            /* Font atlas (or other texture) is ready for uploading */
            if (tex->Pixels && tex->Width > 0 && tex->Height > 0) {
                imgui_pascal_set_font_texture(
                    (unsigned char*)tex->Pixels, tex->Width, tex->Height);
                imgui_dbg_font_w = tex->Width;
                imgui_dbg_font_h = tex->Height;
            }
            /* Assign a non-null dummy TexID so ImGui considers it valid */
            ImTextureData_SetTexID(tex, (ImTextureID)1);
            ImTextureData_SetStatus(tex, ImTextureStatus_OK);
        }
        else if (tex->Status == ImTextureStatus_WantUpdates) {
            /* Partial update – re-upload the entire texture (simple path) */
            if (tex->Pixels && tex->Width > 0 && tex->Height > 0) {
                imgui_pascal_set_font_texture(
                    (unsigned char*)tex->Pixels, tex->Width, tex->Height);
                imgui_dbg_font_w = tex->Width;
                imgui_dbg_font_h = tex->Height;
            }
            ImTextureData_SetStatus(tex, ImTextureStatus_OK);
        }
        else if (tex->Status == ImTextureStatus_WantDestroy) {
            ImTextureData_SetStatus(tex, ImTextureStatus_Destroyed);
        }
    }
}

/* ---- Main render entry point – called from Pascal imgui_render() ---- */
void imgui_render_frame(void) {
    ImDrawData* draw_data;
    int n;

    imgui_dbg_triangles = 0;
    imgui_dbg_texcount  = 0;

    igRender();
    draw_data = igGetDrawData();
    if (!draw_data) { imgui_dbg_valid = -1; dbg("[BRIDGE] no draw_data!\r\n"); return; }
    imgui_dbg_valid = draw_data->Valid ? 1 : 0;
    imgui_dbg_cmdlists = draw_data->CmdListsCount;
    if (!draw_data->Valid) return;

    /* Process any pending texture create/update/destroy operations */
    imgui_handle_textures(draw_data);

    if (draw_data->CmdListsCount == 0)
        return;
    for (n = 0; n < draw_data->CmdListsCount; n++) {
        ImDrawList*  cmd_list = draw_data->CmdLists.Data[n];
        ImDrawVert*  vtx_buf  = cmd_list->VtxBuffer.Data;
        ImDrawIdx*   idx_buf  = cmd_list->IdxBuffer.Data;
        int cmd_i;

        for (cmd_i = 0; cmd_i < cmd_list->CmdBuffer.Size; cmd_i++) {
            ImDrawCmd* pcmd = &cmd_list->CmdBuffer.Data[cmd_i];
            unsigned int elem_count, idx_off, vtx_off;
            float cx0, cy0, cx1, cy1;
            unsigned int i;

            /* User callbacks (e.g. ResetRenderState) */
            if (pcmd->UserCallback) {
                pcmd->UserCallback(cmd_list, pcmd);
                continue;
            }

            cx0 = pcmd->ClipRect.x - draw_data->DisplayPos.x;
            cy0 = pcmd->ClipRect.y - draw_data->DisplayPos.y;
            cx1 = pcmd->ClipRect.z - draw_data->DisplayPos.x;
            cy1 = pcmd->ClipRect.w - draw_data->DisplayPos.y;
            if (cx0 < 0.0f) cx0 = 0.0f;
            if (cy0 < 0.0f) cy0 = 0.0f;

            elem_count = pcmd->ElemCount;
            idx_off    = pcmd->IdxOffset;
            vtx_off    = pcmd->VtxOffset;

            for (i = 0; i + 2 < elem_count; i += 3) {
                ImDrawVert* v0 = &vtx_buf[vtx_off + idx_buf[idx_off + i + 0]];
                ImDrawVert* v1 = &vtx_buf[vtx_off + idx_buf[idx_off + i + 1]];
                ImDrawVert* v2 = &vtx_buf[vtx_off + idx_buf[idx_off + i + 2]];

                imgui_dbg_triangles++;

                imgui_pascal_render_triangle(
                    v0->pos.x, v0->pos.y, v0->uv.x, v0->uv.y, v0->col,
                    v1->pos.x, v1->pos.y, v1->uv.x, v1->uv.y, v1->col,
                    v2->pos.x, v2->pos.y, v2->uv.x, v2->uv.y, v2->col,
                    cx0, cy0, cx1, cy1);
            }
        }
    }
}

/* ---- ImGuiIO helpers (Pascal avoids needing struct layout knowledge) ---- */
void imgui_set_display_size(float w, float h) {
    ImGuiIO* io = igGetIO_Nil();
    io->DisplaySize.x = w;
    io->DisplaySize.y = h;
}

void imgui_set_delta_time(float dt) {
    ImGuiIO* io = igGetIO_Nil();
    io->DeltaTime = dt;
}

void imgui_set_config_flags(int flags) {
    ImGuiIO* io = igGetIO_Nil();
    io->ConfigFlags = flags;
}

void imgui_add_mouse_pos(float x, float y) {
    ImGuiIO* io = igGetIO_Nil();
    ImGuiIO_AddMousePosEvent(io, x, y);
}

void imgui_add_mouse_button(int button, int down) {
    ImGuiIO* io = igGetIO_Nil();
    ImGuiIO_AddMouseButtonEvent(io, button, (bool)down);
}

void imgui_add_mouse_wheel(float dx, float dy) {
    ImGuiIO* io = igGetIO_Nil();
    ImGuiIO_AddMouseWheelEvent(io, dx, dy);
}

void imgui_add_key_event(int key, int down) {
    ImGuiIO* io = igGetIO_Nil();
    ImGuiIO_AddKeyEvent(io, (ImGuiKey)key, (bool)down);
}

void imgui_add_input_char(unsigned int c) {
    ImGuiIO* io = igGetIO_Nil();
    ImGuiIO_AddInputCharacter(io, c);
}

/* ===========================================================================
 * PS/2 Scancode Set 1 → ImGuiKey mapping
 * Make codes 1-83.  Break code = make | 0x80.
 * =========================================================================== */
static const int sc_to_imgui[84] = {
    /* 0  */ 0,
    /* 1  */ ImGuiKey_Escape,
    /* 2  */ ImGuiKey_1,     /* 3  */ ImGuiKey_2,     /* 4  */ ImGuiKey_3,
    /* 5  */ ImGuiKey_4,     /* 6  */ ImGuiKey_5,     /* 7  */ ImGuiKey_6,
    /* 8  */ ImGuiKey_7,     /* 9  */ ImGuiKey_8,     /* 10 */ ImGuiKey_9,
    /* 11 */ ImGuiKey_0,
    /* 12 */ ImGuiKey_Minus, /* 13 */ ImGuiKey_Equal,
    /* 14 */ ImGuiKey_Backspace,
    /* 15 */ ImGuiKey_Tab,
    /* 16 */ ImGuiKey_Q,     /* 17 */ ImGuiKey_W,     /* 18 */ ImGuiKey_E,
    /* 19 */ ImGuiKey_R,     /* 20 */ ImGuiKey_T,     /* 21 */ ImGuiKey_Y,
    /* 22 */ ImGuiKey_U,     /* 23 */ ImGuiKey_I,     /* 24 */ ImGuiKey_O,
    /* 25 */ ImGuiKey_P,
    /* 26 */ ImGuiKey_LeftBracket, /* 27 */ ImGuiKey_RightBracket,
    /* 28 */ ImGuiKey_Enter,
    /* 29 */ ImGuiKey_LeftCtrl,
    /* 30 */ ImGuiKey_A,     /* 31 */ ImGuiKey_S,     /* 32 */ ImGuiKey_D,
    /* 33 */ ImGuiKey_F,     /* 34 */ ImGuiKey_G,     /* 35 */ ImGuiKey_H,
    /* 36 */ ImGuiKey_J,     /* 37 */ ImGuiKey_K,     /* 38 */ ImGuiKey_L,
    /* 39 */ ImGuiKey_Semicolon,   /* 40 */ ImGuiKey_Apostrophe,
    /* 41 */ ImGuiKey_GraveAccent,
    /* 42 */ ImGuiKey_LeftShift,
    /* 43 */ ImGuiKey_Backslash,
    /* 44 */ ImGuiKey_Z,     /* 45 */ ImGuiKey_X,     /* 46 */ ImGuiKey_C,
    /* 47 */ ImGuiKey_V,     /* 48 */ ImGuiKey_B,     /* 49 */ ImGuiKey_N,
    /* 50 */ ImGuiKey_M,
    /* 51 */ ImGuiKey_Comma, /* 52 */ ImGuiKey_Period, /* 53 */ ImGuiKey_Slash,
    /* 54 */ ImGuiKey_RightShift,
    /* 55 */ ImGuiKey_KeypadMultiply,
    /* 56 */ ImGuiKey_LeftAlt,
    /* 57 */ ImGuiKey_Space,
    /* 58 */ ImGuiKey_CapsLock,
    /* 59 */ ImGuiKey_F1,    /* 60 */ ImGuiKey_F2,    /* 61 */ ImGuiKey_F3,
    /* 62 */ ImGuiKey_F4,    /* 63 */ ImGuiKey_F5,    /* 64 */ ImGuiKey_F6,
    /* 65 */ ImGuiKey_F7,    /* 66 */ ImGuiKey_F8,    /* 67 */ ImGuiKey_F9,
    /* 68 */ ImGuiKey_F10,
    /* 69 */ ImGuiKey_NumLock,     /* 70 */ ImGuiKey_ScrollLock,
    /* 71 */ ImGuiKey_Home,        /* 72 */ ImGuiKey_UpArrow,
    /* 73 */ ImGuiKey_PageUp,      /* 74 */ ImGuiKey_KeypadSubtract,
    /* 75 */ ImGuiKey_LeftArrow,   /* 76 */ ImGuiKey_Keypad5,
    /* 77 */ ImGuiKey_RightArrow,  /* 78 */ ImGuiKey_KeypadAdd,
    /* 79 */ ImGuiKey_End,         /* 80 */ ImGuiKey_DownArrow,
    /* 81 */ ImGuiKey_PageDown,    /* 82 */ ImGuiKey_Insert,
    /* 83 */ ImGuiKey_Delete,
};

/* Unshifted ASCII for make codes (0 = non-printable) */
static const unsigned char sc_to_ascii[84] = {
    0, 0,
    '1','2','3','4','5','6','7','8','9','0','-','=', 0, 0,
    'q','w','e','r','t','y','u','i','o','p','[',']', 0, 0,
    'a','s','d','f','g','h','j','k','l',';','\'','`', 0, '\\',
    'z','x','c','v','b','n','m',',','.','/', 0, '*', 0, ' ',
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
};

/* Shifted ASCII */
static const unsigned char sc_to_ascii_shift[84] = {
    0, 0,
    '!','@','#','$','%','^','&','*','(',')','_','+', 0, 0,
    'Q','W','E','R','T','Y','U','I','O','P','{','}', 0, 0,
    'A','S','D','F','G','H','J','K','L',':','"','~', 0, '|',
    'Z','X','C','V','B','N','M','<','>','?', 0, '*', 0, ' ',
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
};

static int _ig_shift_down = 0;

/*
 * Called from the PS/2 keyboard ISR hook with a raw scancode byte.
 * Maps to ImGuiKey events and feeds printable ASCII characters.
 */
void imgui_handle_scancode(unsigned int scancode) {
    unsigned int is_break = scancode & 0x80;
    unsigned int make     = scancode & 0x7F;

    /* Map to ImGuiKey and send key down/up event */
    if (make < 84) {
        int key = sc_to_imgui[make];
        if (key != 0)
            imgui_add_key_event(key, is_break ? 0 : 1);
    }

    /* Track shift state for ASCII mapping */
    if (make == 42 || make == 54)
        _ig_shift_down = is_break ? 0 : 1;

    /* Feed printable ASCII on key-down only */
    if (!is_break && make < 84) {
        unsigned char c = _ig_shift_down
            ? sc_to_ascii_shift[make]
            : sc_to_ascii[make];
        if (c >= 32 && c < 127)
            imgui_add_input_char((unsigned int)c);
    }
}

/* ---- Show the full ImGui demo window (called from Pascal) ---- */
void imgui_test_window(void) {
    igShowDemoWindow((bool*)0);
}

/* Wrapper for igNewFrame with debug checkpoints.
   On the first call we also disable .ini persistence and run
   diagnostics to help identify hangs. */
static int _first_frame = 1;

static void dbg_float(float f) {
    /* Print a float as integer.fraction (2 decimal places) */
    int whole = (int)f;
    int frac = (int)((f - (float)whole) * 100.0f);
    if (frac < 0) frac = -frac;
    char buf[20]; int pos = 0;
    if (whole < 0) { buf[pos++] = '-'; whole = -whole; }
    /* integer part */
    char tmp[12]; int ti = 0;
    do { tmp[ti++] = '0' + (whole % 10); whole /= 10; } while (whole);
    while (ti > 0) buf[pos++] = tmp[--ti];
    buf[pos++] = '.';
    buf[pos++] = '0' + (frac / 10);
    buf[pos++] = '0' + (frac % 10);
    buf[pos] = '\0';
    console_writestring(buf);
}

void imgui_new_frame_impl(void) {
    if (_first_frame) {
        ImGuiIO* io = igGetIO_Nil();

        /* Disable .ini persistence (no filesystem) */
        io->IniFilename = (const char*)0;
        io->LogFilename = (const char*)0;

        /* Tell ImGui our renderer can handle dynamic texture updates.
           Without this flag, the font atlas gets locked and font baking
           is impossible, causing GetFontBaked() to return NULL. */
        io->BackendFlags |= ImGuiBackendFlags_RendererHasTextures;

        /* Force RGBA32 format so the Pascal rasterizer can sample
           as 4 bytes per pixel without format branching. */
        io->Fonts->TexDesiredFormat = ImTextureFormat_RGBA32;

        /* Let ImGui draw a software mouse cursor as part of the draw data */
        io->MouseDrawCursor = 1;

        /* Add bitmap font */
        dbg("[BRIDGE] adding bitmap font...\r\n");
        ImFont* font = ImFontAtlas_AddFontDefaultBitmap(io->Fonts, (const ImFontConfig*)0);
        if (!font) {
            dbg("[BRIDGE] FATAL: AddFontDefaultBitmap returned NULL!\r\n");
            return;
        }
        dbg("[BRIDGE] font added OK.\r\n");

        _first_frame = 0;
    }

    dbg("[BRIDGE] igNewFrame...\r\n");
    igNewFrame();
    dbg("[BRIDGE] igNewFrame done.\r\n");
}

#ifdef __cplusplus
} /* extern "C" */
#endif
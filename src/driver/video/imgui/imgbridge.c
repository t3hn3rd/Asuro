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

extern void imgui_pascal_fill_rect(
    float rx0, float ry0, float rx1, float ry1,
    unsigned int col, float tex_u, float tex_v,
    float cx0, float cy0, float cx1, float cy1);

extern void imgui_pascal_fill_rect_gradient(
    float rx0, float ry0, float rx1, float ry1,
    unsigned int col_tl, unsigned int col_tr,
    unsigned int col_br, unsigned int col_bl,
    float tex_u, float tex_v,
    float cx0, float cy0, float cx1, float cy1);

extern void imgui_pascal_fill_rect_textured(
    float rx0, float ry0, float rx1, float ry1,
    float u_left, float v_top, float u_right, float v_bottom,
    unsigned int col,
    float cx0, float cy0, float cx1, float cy1);

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
int imgui_dbg_quads_solid    = 0;
int imgui_dbg_quads_gradient = 0;
int imgui_dbg_quads_textured = 0;
int imgui_dbg_tris_fallback  = 0;

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
    imgui_dbg_quads_solid    = 0;
    imgui_dbg_quads_gradient = 0;
    imgui_dbg_quads_textured = 0;
    imgui_dbg_tris_fallback  = 0;

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
                /* ---- Quad detection: try to merge consecutive triangle pairs
                   into fast axis-aligned rect fills.  ImGui tessellates rects as
                   4 vertices with indices 0,1,2, 0,2,3 (shared diagonal 0-2).
                   Detecting these and using REP STOSD scanline fills gives a
                   massive speedup over per-pixel FP barycentric rasterization. ---- */
                if (i + 5 < elem_count) {
                    unsigned int i0 = idx_buf[idx_off + i + 0];
                    unsigned int i1 = idx_buf[idx_off + i + 1];
                    unsigned int i2 = idx_buf[idx_off + i + 2];
                    unsigned int i3 = idx_buf[idx_off + i + 3];
                    unsigned int i4 = idx_buf[idx_off + i + 4];
                    unsigned int i5 = idx_buf[idx_off + i + 5];

                    /* Standard ImGui quad winding: shared diagonal i0==i3, i2==i4 */
                    if (i0 == i3 && i2 == i4) {
                        ImDrawVert* va = &vtx_buf[vtx_off + i0];
                        ImDrawVert* vb = &vtx_buf[vtx_off + i1];
                        ImDrawVert* vc = &vtx_buf[vtx_off + i2];
                        ImDrawVert* vd = &vtx_buf[vtx_off + i5];

                        /* Check axis-aligned quad in EITHER vertex arrangement:
                           Arrangement 1: va-vb horizontal, va-vd vertical
                             xa==xd, xb==xc, ya==yb, yc==yd
                           Arrangement 2: va-vb vertical, va-vd horizontal (rotated)
                             xa==xb, xc==xd, ya==yd, yb==yc                        */
                        if ((va->pos.x == vd->pos.x && vb->pos.x == vc->pos.x &&
                             va->pos.y == vb->pos.y && vc->pos.y == vd->pos.y) ||
                            (va->pos.x == vb->pos.x && vc->pos.x == vd->pos.x &&
                             va->pos.y == vd->pos.y && vb->pos.y == vc->pos.y)) {

                            float qx0 = va->pos.x; float qy0 = va->pos.y;
                            float qx1 = va->pos.x; float qy1 = va->pos.y;
                            /* Compute AABB from all 4 vertices */
                            if (vb->pos.x < qx0) qx0 = vb->pos.x; if (vb->pos.x > qx1) qx1 = vb->pos.x;
                            if (vc->pos.x < qx0) qx0 = vc->pos.x; if (vc->pos.x > qx1) qx1 = vc->pos.x;
                            if (vd->pos.x < qx0) qx0 = vd->pos.x; if (vd->pos.x > qx1) qx1 = vd->pos.x;
                            if (vb->pos.y < qy0) qy0 = vb->pos.y; if (vb->pos.y > qy1) qy1 = vb->pos.y;
                            if (vc->pos.y < qy0) qy0 = vc->pos.y; if (vc->pos.y > qy1) qy1 = vc->pos.y;
                            if (vd->pos.y < qy0) qy0 = vd->pos.y; if (vd->pos.y > qy1) qy1 = vd->pos.y;

                            /* All UVs identical (no texture variation) → solid or gradient fill */
                            if (va->uv.x == vb->uv.x && va->uv.x == vc->uv.x && va->uv.x == vd->uv.x &&
                                va->uv.y == vb->uv.y && va->uv.y == vc->uv.y && va->uv.y == vd->uv.y) {

                                /* All same color → solid fill (REP STOSD per scanline) */
                                if (va->col == vb->col && vb->col == vc->col && vc->col == vd->col) {
                                    imgui_pascal_fill_rect(
                                        qx0, qy0, qx1, qy1,
                                        va->col, va->uv.x, va->uv.y,
                                        cx0, cy0, cx1, cy1);
                                    imgui_dbg_triangles += 2;
                                    imgui_dbg_quads_solid++;
                                    i += 3; /* skip second triangle; loop does i+=3 for first */
                                    continue;
                                }

                                /* Different colors → gradient fill (integer lerp) */
                                {
                                    /* Map vertex colors to corners by actual position */
                                    unsigned int c_tl = 0, c_tr = 0, c_br = 0, c_bl = 0;
                                    int vi;
                                    ImDrawVert* verts[4]; verts[0]=va; verts[1]=vb; verts[2]=vc; verts[3]=vd;
                                    for (vi = 0; vi < 4; vi++) {
                                        int is_left = (verts[vi]->pos.x == qx0);
                                        int is_top  = (verts[vi]->pos.y == qy0);
                                        if (is_left && is_top)  c_tl = verts[vi]->col;
                                        if (!is_left && is_top) c_tr = verts[vi]->col;
                                        if (!is_left && !is_top) c_br = verts[vi]->col;
                                        if (is_left && !is_top) c_bl = verts[vi]->col;
                                    }
                                    imgui_pascal_fill_rect_gradient(
                                        qx0, qy0, qx1, qy1,
                                        c_tl, c_tr, c_br, c_bl,
                                        va->uv.x, va->uv.y,
                                        cx0, cy0, cx1, cy1);
                                    imgui_dbg_triangles += 2;
                                    imgui_dbg_quads_gradient++;
                                    i += 3;
                                    continue;
                                }
                            }

                            /* Axis-aligned UV mapping with uniform color → textured rect
                               (text glyphs, icons, etc.) — integer fixed-point UV stepping.
                               UV must map left/right and top/bottom consistently. */
                            if (va->col == vb->col && vb->col == vc->col && vc->col == vd->col) {
                                /* Find UV at each corner by position */
                                float u_l = 0, u_r = 0, v_t = 0, v_b = 0;
                                int uv_ok = 1, vj;
                                ImDrawVert* vs[4]; vs[0]=va; vs[1]=vb; vs[2]=vc; vs[3]=vd;
                                for (vj = 0; vj < 4; vj++) {
                                    if (vs[vj]->pos.x == qx0 && vs[vj]->pos.y == qy0)
                                        { u_l = vs[vj]->uv.x; v_t = vs[vj]->uv.y; }
                                    if (vs[vj]->pos.x == qx1 && vs[vj]->pos.y == qy1)
                                        { u_r = vs[vj]->uv.x; v_b = vs[vj]->uv.y; }
                                }
                                /* Verify the other two corners are consistent */
                                for (vj = 0; vj < 4 && uv_ok; vj++) {
                                    if (vs[vj]->pos.x == qx1 && vs[vj]->pos.y == qy0) {
                                        if (vs[vj]->uv.x != u_r || vs[vj]->uv.y != v_t) uv_ok = 0;
                                    }
                                    if (vs[vj]->pos.x == qx0 && vs[vj]->pos.y == qy1) {
                                        if (vs[vj]->uv.x != u_l || vs[vj]->uv.y != v_b) uv_ok = 0;
                                    }
                                }
                                if (uv_ok && !(u_l == u_r && v_t == v_b)) {
                                    imgui_pascal_fill_rect_textured(
                                        qx0, qy0, qx1, qy1,
                                        u_l, v_t, u_r, v_b,
                                        va->col,
                                        cx0, cy0, cx1, cy1);
                                    imgui_dbg_triangles += 2;
                                    imgui_dbg_quads_textured++;
                                    i += 3;
                                    continue;
                                }
                            }
                        }
                    }
                }

                /* Fallback: general triangle rasterizer */
                {
                    ImDrawVert* v0 = &vtx_buf[vtx_off + idx_buf[idx_off + i + 0]];
                    ImDrawVert* v1 = &vtx_buf[vtx_off + idx_buf[idx_off + i + 1]];
                    ImDrawVert* v2 = &vtx_buf[vtx_off + idx_buf[idx_off + i + 2]];

                    imgui_dbg_triangles++;
                    imgui_dbg_tris_fallback++;

                    imgui_pascal_render_triangle(
                        v0->pos.x, v0->pos.y, v0->uv.x, v0->uv.y, v0->col,
                        v1->pos.x, v1->pos.y, v1->uv.x, v1->uv.y, v1->col,
                        v2->pos.x, v2->pos.y, v2->uv.x, v2->uv.y, v2->col,
                        cx0, cy0, cx1, cy1);
                }
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

float imgui_get_framerate(void) {
    ImGuiIO* io = igGetIO_Nil();
    return io->Framerate;
}

/* ---------------------------------------------------------------------------
 * imgui_apply_desktop_style  –  set style struct fields directly (no push/pop)
 * Called once from desktop_init.  Safe to call before any frame.
 * ------------------------------------------------------------------------- */
void imgui_apply_desktop_style(void) {
    ImGuiStyle* s = igGetStyle();

    /* Apply built-in dark palette first */
    igStyleColorsDark(s);

    /* Rounding — all zero to eliminate triangle fans (everything
       becomes axis-aligned quads that hit the fast rect-fill paths) */
    s->WindowRounding    = 0.0f;
    s->ChildRounding     = 0.0f;
    s->FrameRounding     = 0.0f;
    s->GrabRounding      = 0.0f;
    s->TabRounding       = 0.0f;
    s->PopupRounding     = 0.0f;
    s->ScrollbarRounding = 0.0f;
    s->WindowPadding     = (ImVec2){12, 10};
    s->FramePadding      = (ImVec2){10, 6};
    s->ItemSpacing       = (ImVec2){8, 6};
    s->ItemInnerSpacing  = (ImVec2){6, 4};
    s->ScrollbarSize     = 11.0f;
    s->GrabMinSize       = 8.0f;
    s->WindowBorderSize  = 0.0f;
    s->FrameBorderSize   = 0.0f;
    s->TabBorderSize     = 0.0f;
    s->WindowTitleAlign  = (ImVec2){0.04f, 0.50f};
    s->SeparatorTextBorderSize = 1.0f;

    /* Disable anti-aliasing — software rasterizer is too slow for AA fringes */
    s->AntiAliasedLines       = false;
    s->AntiAliasedLinesUseTex = false;
    s->AntiAliasedFill        = false;
    s->CircleTessellationMaxError = 1.2f;  /* coarser arcs = fewer tris */

    /* --- Deep blue-grey palette with vivid accents --- */
    s->Colors[ImGuiCol_WindowBg]             = (ImVec4){0.09f, 0.09f, 0.13f, 0.96f};
    s->Colors[ImGuiCol_PopupBg]              = (ImVec4){0.08f, 0.08f, 0.12f, 0.97f};
    s->Colors[ImGuiCol_ChildBg]              = (ImVec4){0.00f, 0.00f, 0.00f, 0.00f};

    /* Title bars — slate blue */
    s->Colors[ImGuiCol_TitleBg]              = (ImVec4){0.08f, 0.09f, 0.14f, 1.0f};
    s->Colors[ImGuiCol_TitleBgActive]        = (ImVec4){0.12f, 0.20f, 0.38f, 1.0f};
    s->Colors[ImGuiCol_TitleBgCollapsed]     = (ImVec4){0.06f, 0.06f, 0.10f, 0.70f};

    /* Borders — subtle */
    s->Colors[ImGuiCol_Border]               = (ImVec4){0.18f, 0.20f, 0.30f, 0.45f};
    s->Colors[ImGuiCol_Separator]            = (ImVec4){0.18f, 0.20f, 0.30f, 0.45f};

    /* Buttons — vivid blue */
    s->Colors[ImGuiCol_Button]               = (ImVec4){0.16f, 0.22f, 0.38f, 1.0f};
    s->Colors[ImGuiCol_ButtonHovered]        = (ImVec4){0.24f, 0.36f, 0.60f, 1.0f};
    s->Colors[ImGuiCol_ButtonActive]         = (ImVec4){0.14f, 0.22f, 0.42f, 1.0f};

    /* Headers (collapsing, selectable) */
    s->Colors[ImGuiCol_Header]               = (ImVec4){0.16f, 0.22f, 0.36f, 0.70f};
    s->Colors[ImGuiCol_HeaderHovered]        = (ImVec4){0.24f, 0.34f, 0.56f, 0.80f};
    s->Colors[ImGuiCol_HeaderActive]         = (ImVec4){0.18f, 0.28f, 0.48f, 1.0f};

    /* Tabs */
    s->Colors[ImGuiCol_Tab]                  = (ImVec4){0.10f, 0.12f, 0.20f, 1.0f};
    s->Colors[ImGuiCol_TabHovered]           = (ImVec4){0.24f, 0.36f, 0.60f, 1.0f};
    s->Colors[ImGuiCol_TabSelected]          = (ImVec4){0.16f, 0.26f, 0.46f, 1.0f};

    /* Scrollbar */
    s->Colors[ImGuiCol_ScrollbarBg]          = (ImVec4){0.06f, 0.06f, 0.10f, 0.50f};
    s->Colors[ImGuiCol_ScrollbarGrab]        = (ImVec4){0.24f, 0.26f, 0.36f, 1.0f};
    s->Colors[ImGuiCol_ScrollbarGrabHovered] = (ImVec4){0.34f, 0.38f, 0.50f, 1.0f};
    s->Colors[ImGuiCol_ScrollbarGrabActive]  = (ImVec4){0.44f, 0.48f, 0.60f, 1.0f};

    /* Input frames */
    s->Colors[ImGuiCol_FrameBg]              = (ImVec4){0.10f, 0.11f, 0.16f, 1.0f};
    s->Colors[ImGuiCol_FrameBgHovered]       = (ImVec4){0.16f, 0.20f, 0.30f, 1.0f};
    s->Colors[ImGuiCol_FrameBgActive]        = (ImVec4){0.14f, 0.18f, 0.28f, 1.0f};

    /* Menu / bar */
    s->Colors[ImGuiCol_MenuBarBg]            = (ImVec4){0.08f, 0.08f, 0.12f, 1.0f};

    /* Slider grab */
    s->Colors[ImGuiCol_SliderGrab]           = (ImVec4){0.26f, 0.40f, 0.66f, 1.0f};
    s->Colors[ImGuiCol_SliderGrabActive]     = (ImVec4){0.34f, 0.52f, 0.80f, 1.0f};

    /* Check / radio */
    s->Colors[ImGuiCol_CheckMark]            = (ImVec4){0.40f, 0.65f, 1.0f, 1.0f};

    /* Resize grip */
    s->Colors[ImGuiCol_ResizeGrip]           = (ImVec4){0.20f, 0.30f, 0.50f, 0.30f};
    s->Colors[ImGuiCol_ResizeGripHovered]    = (ImVec4){0.30f, 0.44f, 0.70f, 0.60f};
    s->Colors[ImGuiCol_ResizeGripActive]     = (ImVec4){0.36f, 0.54f, 0.82f, 0.90f};

    /* Text */
    s->Colors[ImGuiCol_Text]                 = (ImVec4){0.88f, 0.90f, 0.95f, 1.0f};
    s->Colors[ImGuiCol_TextDisabled]         = (ImVec4){0.42f, 0.44f, 0.50f, 1.0f};

    /* Table */
    s->Colors[ImGuiCol_TableHeaderBg]        = (ImVec4){0.12f, 0.14f, 0.22f, 1.0f};
    s->Colors[ImGuiCol_TableBorderStrong]    = (ImVec4){0.18f, 0.20f, 0.30f, 0.60f};
    s->Colors[ImGuiCol_TableBorderLight]     = (ImVec4){0.14f, 0.16f, 0.24f, 0.40f};
    s->Colors[ImGuiCol_TableRowBg]           = (ImVec4){0.00f, 0.00f, 0.00f, 0.00f};
    s->Colors[ImGuiCol_TableRowBgAlt]        = (ImVec4){0.10f, 0.12f, 0.18f, 0.40f};
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

/* ===========================================================================
 * ISR-safe input buffering
 *
 * The PS/2 keyboard and mouse ISRs fire asynchronously while the main
 * render loop may be mid-frame.  Calling ImGui IO functions from ISR
 * context causes data races and crashes.  Instead we buffer raw events
 * in lock-free ring buffers and drain them once per frame from the
 * main loop (before igNewFrame).
 * =========================================================================== */

/* --- Scancode ring buffer --- */
#define SC_BUF_SIZE 64
static volatile unsigned int _sc_buf[SC_BUF_SIZE];
static volatile int _sc_buf_head = 0;   /* ISR writes here */
static volatile int _sc_buf_tail = 0;   /* main loop reads here */

/* --- Mouse event ring buffer --- */
#define MS_BUF_SIZE 64
typedef struct { float x, y; int btn; int down; int kind; } _ms_evt;
/* kind: 0=pos, 1=button */
static volatile _ms_evt _ms_buf[MS_BUF_SIZE];
static volatile int _ms_buf_head = 0;
static volatile int _ms_buf_tail = 0;

/*
 * Called from the PS/2 keyboard ISR hook with a raw scancode byte.
 * Just pushes into the ring buffer — no ImGui calls.
 */
void imgui_handle_scancode(unsigned int scancode) {
    int next = (_sc_buf_head + 1) % SC_BUF_SIZE;
    if (next != _sc_buf_tail) {          /* drop if full */
        _sc_buf[_sc_buf_head] = scancode;
        _sc_buf_head = next;
    }
}

/*
 * Called from the mouse ISR hook.  Buffers position + button events.
 */
void imgui_handle_mouse_pos(float x, float y) {
    int next = (_ms_buf_head + 1) % MS_BUF_SIZE;
    if (next != _ms_buf_tail) {
        _ms_buf[_ms_buf_head].x    = x;
        _ms_buf[_ms_buf_head].y    = y;
        _ms_buf[_ms_buf_head].kind = 0;
        _ms_buf_head = next;
    }
}

void imgui_handle_mouse_button(int button, int down) {
    int next = (_ms_buf_head + 1) % MS_BUF_SIZE;
    if (next != _ms_buf_tail) {
        _ms_buf[_ms_buf_head].btn  = button;
        _ms_buf[_ms_buf_head].down = down;
        _ms_buf[_ms_buf_head].kind = 1;
        _ms_buf_head = next;
    }
}

/*
 * Drain all buffered input into ImGui.
 * Called once per frame from the main loop BEFORE igNewFrame.
 */
void imgui_drain_input(void) {
    /* --- keyboard --- */
    while (_sc_buf_tail != _sc_buf_head) {
        unsigned int scancode = _sc_buf[_sc_buf_tail];
        _sc_buf_tail = (_sc_buf_tail + 1) % SC_BUF_SIZE;

        unsigned int is_break = scancode & 0x80;
        unsigned int make     = scancode & 0x7F;

        if (make < 84) {
            int key = sc_to_imgui[make];
            if (key != 0)
                imgui_add_key_event(key, is_break ? 0 : 1);
        }

        if (make == 42 || make == 54)
            _ig_shift_down = is_break ? 0 : 1;

        if (!is_break && make < 84) {
            unsigned char c = _ig_shift_down
                ? sc_to_ascii_shift[make]
                : sc_to_ascii[make];
            if (c >= 32 && c < 127)
                imgui_add_input_char((unsigned int)c);
        }
    }

    /* --- mouse --- */
    while (_ms_buf_tail != _ms_buf_head) {
        int idx = _ms_buf_tail;
        float mx   = _ms_buf[idx].x;
        float my   = _ms_buf[idx].y;
        int   mbtn = _ms_buf[idx].btn;
        int   mdn  = _ms_buf[idx].down;
        int   mk   = _ms_buf[idx].kind;
        _ms_buf_tail = (_ms_buf_tail + 1) % MS_BUF_SIZE;

        if (mk == 0)
            imgui_add_mouse_pos(mx, my);
        else
            imgui_add_mouse_button(mbtn, mdn);
    }
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

    igNewFrame();
}

#ifdef __cplusplus
} /* extern "C" */
#endif
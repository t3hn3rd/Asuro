{
    prog->Splash - Boot boot.splash screen.

    Displays a centered logo (decoded from an embedded TGA), progress bar
    and status label during core.version initialization.  Because the gfxd
    render process is not yet running at this stage, update() manually
    drives the LVGL timer pipeline and flushes the framebuffer.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit boot.splash;

interface

uses
    driver.video.lvgl, driver.video, core.fmt.targa, core.gfx.texture, memory.heap;

{ Create the boot.splash screen and render the initial frame (0 %). }
procedure init;

{ Set progress to `percent` (0..100), update the status text, and
  manually redraw + flush the framebuffer. }
procedure update(percent: uint32; status: pchar);

{ Remove all boot.splash LVGL objects and load the default screen. }
procedure teardown;

implementation

const
    { LVGL image header magic number. }
    LV_IMAGE_HEADER_MAGIC = $19;

    { LV_COLOR_FORMAT_ARGB8888 }
    LV_CF_ARGB8888 = $10;

    BAR_WIDTH  = 300;
    BAR_HEIGHT = 16;

type
    { lv_image_header_t — 12 bytes, little-endian bitfield packing.
      Byte 0:   magic (8)
      Byte 1:   cf (8)
      Bytes 2-3: flags (16)
      Bytes 4-5: w (16)
      Bytes 6-7: h (16)
      Bytes 8-9: stride (16)
      Bytes 10-11: reserved (16) }
    TLVImageHeader = packed record
        magic_cf_flags : uint32;  { magic:8 | cf:8 | flags:16 }
        w_h            : uint32;  { w:16 | h:16 }
        stride_res     : uint32;  { stride:16 | reserved:16 }
    end;

    { lv_image_dsc_t — 24 bytes on 32-bit. }
    TLVImageDsc = packed record
        header    : TLVImageHeader;
        data_size : uint32;
        data      : pointer;
        reserved  : pointer;
    end;
    PLVImageDsc = ^TLVImageDsc;

var
    { Embedded TGA file — linked from the NASM incbin stub. }
    splash_tga_start : uint8; external name '_splash_tga_start';
    splash_tga_size  : uint32; external name '_splash_tga_size';

var
    { The dedicated LVGL screen that holds the boot.splash widgets. }
    splashScreen: Plv_obj;

    { The image widget, progress bar and status label. }
    logoImage:   Plv_obj;
    progressBar: Plv_obj;
    statusLabel: Plv_obj;

    { The original screen that was active before the splash. }
    previousScreen: Plv_obj;

    { Decoded texture and LVGL image descriptor (heap-allocated). }
    logoTexture: PTexture;
    logoDsc:     PLVImageDsc;

{ ---- private helpers -------------------------------------------------- }

{ Build an lv_image_dsc_t that points to the decoded ARGB8888 pixel data. }
function buildImageDsc(tex: PTexture): PLVImageDsc;
var
    dsc: PLVImageDsc;
begin
    dsc := PLVImageDsc(kalloc(sizeof(TLVImageDsc)));

    { Pack the bitfield header: magic | cf | flags=0 }
    dsc^.header.magic_cf_flags := uint32(LV_IMAGE_HEADER_MAGIC)
                               OR (uint32(LV_CF_ARGB8888) SHL 8);
    { w | h }
    dsc^.header.w_h := uint32(tex^.Width)
                     OR (uint32(tex^.Height) SHL 16);
    { stride = width * 4 bytes per pixel }
    dsc^.header.stride_res := uint32(tex^.Width * 4);

    dsc^.data_size := tex^.Width * tex^.Height * 4;
    dsc^.data      := tex^.Pixels;
    dsc^.reserved  := nil;

    buildImageDsc := dsc;
end;

{ Crude busy-wait delay.  Reads the PIT counter (channel 0) in a
  tight loop.  The PIT is clocked at 1.193182 MHz with divisor 149
  (8 kHz rate), so each rollover is ~125 µs.  ~4000 rollovers ≈ 500 ms.
  This works even before STI because we read the hardware directly.
  DEBUG ONLY — remove once boot.splash timing is no longer needed. }
procedure busywait_500ms;
var
    rollovers : uint32;
    prev, cur : uint16;
begin
    rollovers := 0;
    asm
        PUSH EAX
        MOV  AL, $00
        OUT  $43, AL
        IN   AL, $40
        MOV  AH, AL
        IN   AL, $40
        XCHG AH, AL
        MOV  prev, AX
        POP  EAX
    end;
    while rollovers < 4000 do begin
        asm
            PUSH EAX
            MOV  AL, $00
            OUT  $43, AL
            IN   AL, $40
            MOV  AH, AL
            IN   AL, $40
            XCHG AH, AL
            MOV  cur, AX
            POP  EAX
        end;
        if cur > prev then
            Inc(rollovers);
        prev := cur;
    end;
end;

{ Push a single rendered frame to the display.
  We feed a generous elapsed-time value to LVGL so that it always
  exceeds the display refresh period (~33 ms) and actually renders
  the pending invalidations, then flush the back-buffer to the front. }
procedure redraw;
begin
    lv_tick_inc(100);
    lv_timer_handler;
    driver.video.Flush;
end;

{ ---- public API ------------------------------------------------------- }

procedure init;
begin
    { Remember whatever screen was active so we can restore it later. }
    previousScreen := lv_screen_active;

    { Decode the embedded TGA into an ARGB pixel buffer. }
    logoTexture := core.fmt.targa.Parse(@splash_tga_start, splash_tga_size);
    logoDsc := nil;

    { Create a new screen for the boot.splash and make it current. }
    splashScreen := lv_obj_create(nil);
    lv_obj_remove_flag(splashScreen, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_color(splashScreen, lv_color_hex($1A1A2E), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(splashScreen, LV_OPA_COVER, LV_PART_MAIN);
    lv_screen_load(splashScreen);

    { Use flex-column layout centred on both axes so our children
      (logo, bar, label) are stacked vertically in the middle. }
    lv_obj_set_flex_flow(splashScreen, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(splashScreen,
                          LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);

    { -- Logo image -- }
    logoImage := lv_image_create(splashScreen);
    if logoTexture <> nil then begin
        logoDsc := buildImageDsc(logoTexture);
        lv_image_set_src(logoImage, logoDsc);
        lv_image_set_scale(logoImage, 128);  { 128/256 = 50% }
        lv_image_set_inner_align(logoImage, LV_IMAGE_ALIGN_CENTER);
    end;

    { -- Progress bar -- }
    progressBar := lv_bar_create(splashScreen);
    lv_obj_set_size(progressBar, BAR_WIDTH, BAR_HEIGHT);
    lv_bar_set_range(progressBar, 0, 100);
    lv_bar_set_value(progressBar, 0, LV_ANIM_OFF);

    { Bar background (track) }
    lv_obj_set_style_bg_color(progressBar, lv_color_hex($2A2A4A), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(progressBar, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_radius(progressBar, 4, LV_PART_MAIN);

    { Bar indicator (filled portion) }
    lv_obj_set_style_bg_color(progressBar, lv_color_hex($4FC3F7), LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(progressBar, LV_OPA_COVER, LV_PART_INDICATOR);
    lv_obj_set_style_radius(progressBar, 4, LV_PART_INDICATOR);

    { -- Status label -- }
    statusLabel := lv_label_create(splashScreen);
    lv_label_set_text_static(statusLabel, 'Loading...');
    lv_obj_set_style_text_font(statusLabel, @lv_font_montserrat_14, LV_PART_MAIN);
    lv_obj_set_style_text_color(statusLabel, lv_color_hex($888888), LV_PART_MAIN);

    { Push the first frame to the display. }
    redraw;
end;

procedure update(percent: uint32; status: pchar);
begin
    if splashScreen = nil then exit;

    { Clamp to 0..100 }
    if percent > 100 then percent := 100;

    lv_bar_set_value(progressBar, sint32(percent), LV_ANIM_OFF);
    lv_label_set_text(statusLabel, status);

    redraw;

    { DEBUG: pause so each step is visible on screen }
    busywait_500ms;
end;

procedure teardown;
begin
    if splashScreen = nil then exit;

    { Switch back to the screen that was active before the splash. }
    if previousScreen <> nil then
        lv_screen_load(previousScreen);

    { Delete the boot.splash screen and all of its children. }
    lv_obj_delete(splashScreen);
    splashScreen := nil;
    logoImage    := nil;
    progressBar  := nil;
    statusLabel  := nil;

    { Free the image descriptor and decoded texture. }
    if logoDsc <> nil then begin
        kfree(void(logoDsc));
        logoDsc := nil;
    end;
    if logoTexture <> nil then begin
        kfree(void(logoTexture^.Pixels));
        kfree(void(logoTexture));
        logoTexture := nil;
    end;
end;

end.

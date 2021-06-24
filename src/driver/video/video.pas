unit video;

interface

uses
    multiboot, lmemorymanager, tracer, color, rand, console;

procedure init();
procedure DrawPixel(X : uint32; Y : uint32; Pixel : TRGB32);
procedure Flush();

type
    VideoBuffer = uint64;
    TVESALinearBuffer = record
        Initialized     : Boolean;
        Location        : VideoBuffer;
        BitsPerPixel    : uint8;
        Width           : uint32;
        Height          : uint32;
    end;
    TBackBuffer = record
        Initialized     : Boolean;
        Location        : VideoBuffer;
        BitsPerPixel    : uint8;
        Width           : uint32;
        Height          : uint32;
    end;
    TVESA = record
        DefaultBuffer   : VideoBuffer;
        Framebuffer     : TVESALinearBuffer;
        BackBuffer      : TBackBuffer;
    end;
    PVESA = ^TVESA;

implementation

var
    VESA : TVESA;

function allocateBackBuffer(Width : uint32; Height : uint32; BitsPerPixel : uint8) : uint64;
begin
    Outputln('VIDEO','Start Kalloc Backbuffer');
    //This doesn't currently work... Needs a rework of lmemorymanager
    allocateBackBuffer:= uint64(klalloc((Width * Height) * BitsPerPixel));
    Outputln('VIDEO','End Kalloc Backbuffer');
end;

procedure initBackBuffer(VESAInfo : PVESA; Width : uint32; Height : uint32; BitsPerPixel : uint8);
begin
    VESAInfo^.BackBuffer.Width:= Width;
    VESAInfo^.BackBuffer.Height:= Height;
    VESAInfo^.BackBuffer.BitsPerPixel:= BitsPerPixel;
    VESAInfo^.BackBuffer.Location:= allocateBackBuffer(VESAInfo^.BackBuffer.Width, VESAInfo^.BackBuffer.Height, VESAInfo^.BackBuffer.BitsPerPixel);
    VESAInfo^.DefaultBuffer:= VESAInfo^.BackBuffer.Location;
    VESAInfo^.BackBuffer.Initialized:= True;
end;

procedure allocateVESAFrameBuffer(Address : uint32; Width : uint32; Height : uint32);
var
    LowerAddress, UpperAddress : uint32;
    Block : uint32;

begin
    tracer.push_trace('video.allocateFrameBuffer.enter');
    LowerAddress:= ((Address) SHR 22)-1;
    UpperAddress:= ((Address + (Width * Height)) SHR 22)+1;
    For Block:=LowerAddress to UpperAddress do begin
        kpalloc(Block SHL 22);
    end;
    tracer.push_trace('video.allocateFrameBuffer.enter');
end;

procedure initVESAFrameBuffer(VESAInfo : PVESA; Location : uint64; Width : uint32; Height : uint32; BitsPerPixel : uint8);
begin
    if not(VESAInfo^.Framebuffer.Initialized) then begin
        VESAInfo^.Framebuffer.Location:= Location;
        VESAInfo^.Framebuffer.BitsPerPixel:= BitsPerPixel;
        VESAInfo^.Framebuffer.Width:= Width;
        VESAInfo^.Framebuffer.Height:= Height;
        allocateVESAFrameBuffer(VESAInfo^.Framebuffer.Location, VESAInfo^.Framebuffer.Width, VESAInfo^.Framebuffer.Height);
        VESAInfo^.DefaultBuffer:= VESAInfo^.Framebuffer.Location;
        VESAInfo^.Framebuffer.Initialized:= True;
    end;
end;

procedure init();
var
    RGB : TRGB32;
    x,y : uint32;

begin
    tracer.push_trace('video.init.enter');
    console.Outputln('VIDEO', 'Init VESA Framebuffer');
    initVESAFrameBuffer(@VESA, multiboot.multibootinfo^.framebuffer_addr, multiboot.multibootinfo^.framebuffer_width, multiboot.multibootinfo^.framebuffer_height, multiboot.multibootinfo^.framebuffer_bpp);        
    console.Outputln('VIDEO', 'Init VESA Backbuffer');
    initBackBuffer(@VESA, multiboot.multibootinfo^.framebuffer_width, multiboot.multibootinfo^.framebuffer_height, multiboot.multibootinfo^.framebuffer_bpp);

    console.Outputln('VIDEO', 'Start Test Draw Loop');
    srand(98354754397);
    while true do begin
        Inc(RGB.R);
        for x:=0 to VESA.Framebuffer.Width-1 do begin
            Inc(RGB.G);
            for y:=0 to VESA.Framebuffer.Height-1 do begin
                DrawPixel(x,y,RGB);
                Inc(RGB.B);
            end;
        end;
        Flush();
    end;
    tracer.push_trace('video.init.exit');
end;

procedure DrawPixel(X : uint32; Y : uint32; Pixel : TRGB32);
var
    Location : PuInt32;
    LocationIndex : Uint32;

begin
    Location:= Puint32(VESA.DefaultBuffer);
    LocationIndex:= (Y * VESA.Framebuffer.Width) + X;
    Location[LocationIndex]:= uint32(Pixel);
end;

procedure Flush();
var
    x,y : uint32;
    Back,Front : PuInt32;

begin
    if not(VESA.BackBuffer.Initialized) then exit;
    Back:= PUint32(VESA.BackBuffer.Location);
    Front:= PuInt32(VESA.Framebuffer.Location);
    for x:=0 to VESA.Framebuffer.Width-1 do begin
        for y:=0 to VESA.Framebuffer.Height-1 do begin
            Front[(Y * VESA.Framebuffer.Width)+X]:= Back[(Y * VESA.Framebuffer.Width)+X];
        end;
    end;
end;

end.
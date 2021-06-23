unit video;

interface

uses
    multiboot, lmemorymanager, tracer, color, rand;

procedure init();
procedure DrawPixel(X : uint32; Y : uint32; Pixel : TRGB32);

type
    TVESALinearBuffer = record
        Location        : uint64;
        BitsPerPixel    : uint8;
        Width           : uint32;
        Height          : uint32;
    end;
    TVESA = record
        initialized : Boolean;
        Framebuffer : TVESALinearBuffer;
    end;

implementation

var
    VESA : TVESA;

procedure allocateFrameBuffer(Address : uint32; Width : uint32; Height : uint32);
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

procedure init();
var
    RGB : TRGB32;
    x,y : uint32;

begin
    tracer.push_trace('video.init.enter');
    If not(VESA.initialized) then begin
        VESA.Framebuffer.Location:= multiboot.multibootinfo^.framebuffer_addr;
        VESA.Framebuffer.BitsPerPixel:= multiboot.multibootinfo^.framebuffer_bpp;
        VESA.Framebuffer.Width:= multiboot.multibootinfo^.framebuffer_width;
        VESA.Framebuffer.Height:= multiboot.multibootinfo^.framebuffer_height;
        allocateFrameBuffer(VESA.Framebuffer.Location, VESA.Framebuffer.Width, VESA.Framebuffer.Height);
        VESA.initialized:= true;
    end;
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
    end;
    tracer.push_trace('video.init.exit');
end;

procedure DrawPixel(X : uint32; Y : uint32; Pixel : TRGB32);
var
    Location : PuInt32;
    Increment : Uint32;

begin
    Location:= Puint32(VESA.Framebuffer.Location);
    Increment:= (Y * VESA.Framebuffer.Width) + X;
    Location[Increment]:= uint32(Pixel);
end;

end.
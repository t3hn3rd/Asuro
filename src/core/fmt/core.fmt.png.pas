//  Copyright 2026 Aaron Hance
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

{ Decode a PNG image into a top-down BGRA texture. The caller owns both
  the texture and its Pixels allocation. Invalid input returns nil. }
unit core.fmt.png;

interface

uses core.gfx.texture;

function Parse(buffer : puint8; len : uint32) : PTexture;
procedure UnitTest;

implementation

uses memory.heap, core.util, core.gfx.color, core.comp.deflate, core.enc.crc, io.syslog;

const
    Signature : array[0..7] of uint8 = (137,80,78,71,13,10,26,10);
    IHDR = $49484452;
    PLTE = $504C5445;
    IDAT = $49444154;
    IEND = $49454E44;
    TRNS = $74524E53;
    { Entry zero describes a non-interlaced image. }
    startX : array[0..7] of uint8 = (0,0,4,0,2,0,1,0);
    startY : array[0..7] of uint8 = (0,0,0,4,0,2,0,1);
    stepX : array[0..7] of uint8 = (1,8,8,4,4,2,2,1);
    stepY : array[0..7] of uint8 = (1,8,8,8,4,4,2,2);
    { Bound peak kernel allocations from untrusted image dimensions. }
    DecodeBudget = 64 * 1024 * 1024;

type
    TImage = record
        width, height, channels, depth, kind, firstPass, lastPass : uint32;
        palette, alpha : puint8;
        colors, alphaBytes, firstIDAT, compressedBytes : uint32;
    end;

function big16(p : puint8) : uint32;
begin
    big16 := (uint32(p[0]) shl 8) or p[1];
end;

function big32(p : puint8) : uint32;
begin
    big32 := (big16(p) shl 16) or big16(p+2);
end;

function header(p : puint8; var img : TImage) : boolean;
begin
    header := false;
    img.width := big32(p);
    img.height := big32(p+4);
    if (img.width = 0) or (img.height = 0) or
       (uint64(img.width)*img.height > DecodeBudget div 4) then exit;
    img.depth := p[8];
    img.kind := p[9];
    if (p[10] <> 0) or (p[11] <> 0) or (p[12] > 1) then exit;
    case img.kind of
        0,3: img.channels := 1;
        2: img.channels := 3;
        4: img.channels := 2;
        6: img.channels := 4;
        else exit;
    end;
    if not (img.depth in [1,2,4,8,16]) then exit;
    if (img.depth < 8) and not (img.kind in [0,3]) then exit;
    if (img.depth = 16) and (img.kind = 3) then exit;
    img.firstPass := p[12];
    img.lastPass := img.firstPass * 7;
    header := true;
end;

function chunks(buffer : puint8; len : uint32; var img : TImage) : boolean;
var pos, count, tag, i : uint32;
    p : puint8;
    endedData : boolean;
begin
    chunks := false;
    if (buffer = nil) or (len < 8) then exit;
    for i := 0 to 7 do if buffer[i] <> Signature[i] then exit;
    pos := 8;
    endedData := false;
    while len-pos >= 12 do begin
        count := big32(buffer+pos);
        if count > len-pos-12 then exit;
        tag := big32(buffer+pos+4);
        p := buffer+pos+8;
        if CRC32(buffer+pos+4,count+4) <> big32(p+count) then exit;
        if (pos = 8) and (tag <> IHDR) then exit;
        if (img.firstIDAT <> 0) and (tag <> IDAT) then endedData := true;
        case tag of
            IHDR: begin
                if (pos <> 8) or (count <> 13) then exit;
                if not header(p,img) then exit;
            end;
            PLTE: begin
                if (img.firstIDAT <> 0) or (img.palette <> nil) or (img.alpha <> nil) or
                   (img.kind in [0,4]) or (count = 0) or (count > 768) or (count mod 3 <> 0) then exit;
                img.colors := count div 3;
                if (img.kind = 3) and (img.colors > uint32(1) shl img.depth) then exit;
                img.palette := p;
            end;
            TRNS: begin
                if (img.firstIDAT <> 0) or (img.alpha <> nil) then exit;
                case img.kind of
                    0: if count <> 2 then exit;
                    2: if count <> 6 then exit;
                    3: if (img.palette = nil) or (count > img.colors) then exit;
                    else exit;
                end;
                img.alpha := p;
                img.alphaBytes := count;
            end;
            IDAT: begin
                if endedData or ((img.kind = 3) and (img.palette = nil)) then exit;
                if img.firstIDAT = 0 then img.firstIDAT := pos;
                inc(img.compressedBytes,count);
            end;
            IEND: begin
                chunks := (count = 0) and (len-pos = 12) and (img.compressedBytes >= 6);
                exit;
            end;
            else if (tag and $20000000) = 0 then exit;
        end;
        inc(pos,count+12);
    end;
end;

function extent(size, start, step : uint32) : uint32;
begin
    extent := 0;
    if size > start then extent := 1+(size-start-1) div step;
end;

function paeth(a,b,c : sint32) : uint8;
var da, db, dc : sint32;
begin
    da := abs(b-c);
    db := abs(a-c);
    dc := abs(a+b-2*c);
    if (da <= db) and (da <= dc) then paeth := a
    else if db <= dc then paeth := b
    else paeth := c;
end;

function unfilter(row, prev : puint8; size, stride, kind : uint32) : boolean;
var i, a, b, c : uint32;
begin
    unfilter := kind <= 4;
    if (kind = 0) or (kind > 4) then exit;
    for i := 0 to size-1 do begin
        a := 0;
        b := 0;
        c := 0;
        if i >= stride then a := row[i-stride];
        if prev <> nil then begin
            b := prev[i];
            if i >= stride then c := prev[i-stride];
        end;
        case kind of
            1: row[i] := uint8(row[i]+a);
            2: row[i] := uint8(row[i]+b);
            3: row[i] := uint8(row[i]+((a+b) shr 1));
            4: row[i] := uint8(row[i]+paeth(a,b,c));
        end;
    end;
end;

function sample(row : puint8; index, depth : uint32) : uint32;
var bitOffset : uint32;
begin
    if depth = 8 then sample := row[index]
    else if depth = 16 then sample := big16(row+index*2)
    else begin
        bitOffset := index*depth;
        sample := (row[bitOffset shr 3] shr (8-depth-(bitOffset and 7))) and ((1 shl depth)-1);
    end;
end;

function toByte(value, depth : uint32) : uint8;
begin
    if depth = 8 then toByte := value
    else if depth = 16 then toByte := (value+128) div 257
    else toByte := (value*255) div ((1 shl depth)-1);
end;

function drawRow(var img : TImage; row : puint8; pixels : PRGB32; width, step : uint32) : boolean;
var x, i, r, g, b : uint32;
    color : TRGB32;
begin
    drawRow := false;
    i := 0;
    for x := 0 to width-1 do begin
        r := sample(row,i,img.depth);
        color.a := 255;
        if img.kind = 3 then begin
            if r >= img.colors then exit;
            color.r := img.palette[r*3];
            color.g := img.palette[r*3+1];
            color.b := img.palette[r*3+2];
            if r < img.alphaBytes then color.a := img.alpha[r];
        end else begin
            g := r;
            b := r;
            if img.kind in [2,6] then begin
                g := sample(row,i+1,img.depth);
                b := sample(row,i+2,img.depth);
            end;
            color.r := toByte(r,img.depth);
            color.g := toByte(g,img.depth);
            color.b := toByte(b,img.depth);
            if img.kind in [4,6] then
                color.a := toByte(sample(row,i+img.channels-1,img.depth),img.depth)
            else if img.alpha <> nil then begin
                if r = big16(img.alpha) then begin
                    if img.kind = 0 then color.a := 0
                    else if (g = big16(img.alpha+2)) and (b = big16(img.alpha+4)) then color.a := 0;
                end;
            end;
        end;
        pixels[x*step] := color;
        inc(i,img.channels);
    end;
    drawRow := true;
end;

function Parse(buffer : puint8; len : uint32) : PTexture;
var img : TImage;
    pass, w, h, rowBytes, rawSize, pos, count, i, n, y, stride, a, b : uint32;
    raw, stream, row, prev : puint8;
    tex : PTexture;
    total : uint64;
    ok : boolean;
begin
    Parse := nil;
    img.palette := nil;
    img.alpha := nil;
    img.alphaBytes := 0;
    img.firstIDAT := 0;
    img.compressedBytes := 0;
    if not chunks(buffer,len,img) then exit;
    total := 0;
    for pass := img.firstPass to img.lastPass do begin
        w := extent(img.width,startX[pass],stepX[pass]);
        h := extent(img.height,startY[pass],stepY[pass]);
        if w <> 0 then inc(total,(((uint64(w)*img.channels*img.depth+7) div 8)+1)*h);
    end;
    if total + img.compressedBytes + uint64(img.width)*img.height*4 > DecodeBudget then exit;
    rawSize := total;
    stream := puint8(kalloc(img.compressedBytes));
    if stream = nil then exit;
    pos := img.firstIDAT;
    n := 0;
    while n < img.compressedBytes do begin
        count := big32(buffer+pos);
        for i := 1 to count do stream[n+i-1] := buffer[pos+7+i];
        inc(n,count);
        inc(pos,count+12);
    end;
    ok := ((stream[0] and 15) = 8) and (stream[0] shr 4 <= 7) and
          ((stream[1] and 32) = 0) and (big16(stream) mod 31 = 0);
    raw := nil;
    if ok then raw := puint8(kalloc(rawSize));
    if raw <> nil then begin
        ok := core.comp.deflate.decompress(stream+2,n-6,raw,rawSize,count) and (count = rawSize);
        if ok then begin
            a := 1;
            b := 0;
            for i := 0 to rawSize-1 do begin
                inc(a,raw[i]);
                if a >= 65521 then dec(a,65521);
                inc(b,a);
                if b >= 65521 then dec(b,65521);
            end;
            ok := ((b shl 16) or a) = big32(stream+n-4);
        end;
    end else ok := false;
    kfree(void(stream));
    if ok then begin
        tex := newTexture(img.width,img.height);
        if tex = nil then begin
            kfree(void(raw));
            exit;
        end;
        pos := 0;
        stride := (img.channels*img.depth+7) div 8;
        for pass := img.firstPass to img.lastPass do begin
            w := extent(img.width,startX[pass],stepX[pass]);
            h := extent(img.height,startY[pass],stepY[pass]);
            if (w = 0) or (h = 0) then continue;
            rowBytes := (w*img.channels*img.depth+7) div 8;
            prev := nil;
            for y := 0 to h-1 do begin
                row := raw+pos+1;
                ok := unfilter(row,prev,rowBytes,stride,raw[pos]);
                if ok then ok := drawRow(img,row,@tex^.Pixels[(startY[pass]+y*stepY[pass])*img.width+
                                             startX[pass]],w,stepX[pass]);
                if not ok then break;
                inc(pos,rowBytes+1);
                prev := row;
            end;
            if not ok then break;
        end;
        if ok then Parse := tex
        else begin
            kfree(void(tex^.Pixels));
            kfree(void(tex));
        end;
    end;
    if raw <> nil then kfree(void(raw));
end;

procedure UnitTest;
const
    rgba : array[0..108] of uint8 = (
        $89,$50,$4E,$47,$0D,$0A,$1A,$0A,$00,$00,$00,$0D,$49,$48,$44,$52,
        $00,$00,$00,$02,$00,$00,$00,$05,$08,$06,$00,$00,$00,$6F,$B3,$3D,
        $9C,$00,$00,$00,$03,$49,$44,$41,$54,$78,$9C,$63,$AA,$67,$82,$BE,
        $00,$00,$00,$25,$49,$44,$41,$54,$60,$60,$64,$62,$66,$61,$65,$63,
        $67,$64,$E7,$E0,$E4,$62,$01,$02,$26,$76,$28,$60,$E6,$E3,$E7,$17,
        $60,$03,$02,$16,$10,$0F,$24,$05,$00,$15,$E8,$01,$11,$CF,$76,$94,
        $FD,$00,$00,$00,$00,$49,$45,$4E,$44,$AE,$42,$60,$82);
    indexed : array[0..115] of uint8 = (
        $89,$50,$4E,$47,$0D,$0A,$1A,$0A,$00,$00,$00,$0D,$49,$48,$44,$52,
        $00,$00,$00,$03,$00,$00,$00,$03,$01,$03,$00,$00,$01,$1B,$E1,$17,
        $6A,$00,$00,$00,$06,$50,$4C,$54,$45,$0A,$14,$1E,$32,$3C,$46,$EA,
        $F9,$27,$E3,$00,$00,$00,$02,$74,$52,$4E,$53,$00,$80,$9B,$2B,$4E,
        $18,$00,$00,$00,$03,$49,$44,$41,$54,$78,$9C,$63,$AA,$67,$82,$BE,
        $00,$00,$00,$0C,$49,$44,$41,$54,$60,$00,$83,$06,$20,$5C,$00,$00,
        $04,$AC,$01,$A1,$E6,$0F,$31,$76,$00,$00,$00,$00,$49,$45,$4E,$44,
        $AE,$42,$60,$82);
    badAdler : array[0..78] of uint8 = (
        $89,$50,$4E,$47,$0D,$0A,$1A,$0A,$00,$00,$00,$0D,$49,$48,$44,$52,
        $00,$00,$00,$01,$00,$00,$00,$01,$08,$00,$00,$00,$00,$3A,$7E,$9B,
        $55,$00,$00,$00,$03,$49,$44,$41,$54,$78,$9C,$63,$AA,$67,$82,$BE,
        $00,$00,$00,$07,$49,$44,$41,$54,$E0,$01,$00,$00,$0E,$00,$0C,$82,
        $82,$CF,$B7,$00,$00,$00,$00,$49,$45,$4E,$44,$AE,$42,$60,$82);
    gray : array[0..95] of uint8 = (
        $89,$50,$4E,$47,$0D,$0A,$1A,$0A,$00,$00,$00,$0D,$49,$48,$44,$52,
        $00,$00,$00,$02,$00,$00,$00,$01,$10,$00,$00,$00,$00,$81,$D9,$FC,
        $15,$00,$00,$00,$02,$74,$52,$4E,$53,$12,$34,$2F,$D3,$49,$5E,$00,
        $00,$00,$03,$49,$44,$41,$54,$78,$9C,$63,$AA,$67,$82,$BE,$00,$00,
        $00,$0A,$49,$44,$41,$54,$10,$32,$11,$32,$05,$00,$01,$42,$00,$8E,
        $19,$2A,$32,$5F,$00,$00,$00,$00,$49,$45,$4E,$44,$AE,$42,$60,$82);

var tex : PTexture;
    i, v, failures : uint32;

    procedure check(ok : boolean; name : pchar);
    begin
        if not ok then begin
            inc(failures);
            io.syslog.logln('PNG FAIL',name);
        end;
    end;

    procedure release;
    begin
        if tex = nil then exit;
        kfree(void(tex^.Pixels));
        kfree(void(tex));
        tex := nil;
    end;

begin
    failures := 0;
    tex := Parse(@rgba,sizeof(rgba));
    check(tex <> nil,'filtered RGBA');
    if tex <> nil then begin
        check((tex^.Width = 2) and (tex^.Height = 5),'dimensions');
        for i := 0 to 9 do begin
            v := (i div 2)*7+(i mod 2)*4;
            check((tex^.Pixels[i].r = v) and (tex^.Pixels[i].g = v+1) and
                  (tex^.Pixels[i].b = v+2) and (tex^.Pixels[i].a = v+3),'filter reconstruction');
        end;
    end;
    release;
    tex := Parse(@indexed,sizeof(indexed));
    check(tex <> nil,'interlaced indexed');
    if tex <> nil then for i := 0 to 8 do begin
        v := i mod 2;
        check((tex^.Pixels[i].r = 10+40*v) and (tex^.Pixels[i].a = 128*v),'Adam7 palette and alpha');
    end;
    release;
    tex := Parse(@gray,sizeof(gray));
    check(tex <> nil,'16-bit grayscale');
    if tex <> nil then check((tex^.Pixels[0].a = 0) and (tex^.Pixels[1].a = 255),
                             'transparency uses original precision');
    release;
    tex := Parse(@rgba,sizeof(rgba)-1);
    check(tex = nil,'truncated chunk');
    release;
    tex := Parse(@badAdler,sizeof(badAdler));
    check(tex = nil,'zlib checksum');
    release;
    io.syslog.log('PNG','Failures: ');
    io.syslog.writeintln(failures);
end;

end.

{
    Core->Gfx->FileIcons — File-type icon constants and mapping functions

    Provides ICO_* PUA codepoint constants (U+E000–E078) matching the
    asuro_icons_* bitmap font glyphs, plus getFileTypeIcon() and
    getFileTypeColor() helpers that map a filename to its icon and color
    based on file extension.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit core.gfx.fileicons;

interface

uses
    core.strings,
    core.search;

const
    { File-type icon PUA constants (U+E000..E078) — rendered by asuro_icons_* }
    { Generic }
    ICO_FILE       = #$EE#$80#$80;  { U+E000 generic file }
    ICO_FOLDER     = #$EE#$80#$81;  { U+E001 folder closed }
    ICO_FOLDER_O   = #$EE#$80#$82;  { U+E002 folder open }
    ICO_DRIVE      = #$EE#$80#$83;  { U+E003 drive }
    ICO_MOUNT      = #$EE#$80#$84;  { U+E004 mount point }
    ICO_SYMLINK    = #$EE#$80#$85;  { U+E005 symlink }
    { Code }
    ICO_CODE       = #$EE#$80#$90;  { U+E010 generic code }
    ICO_PAS        = #$EE#$80#$91;  { U+E011 .pas }
    ICO_PY         = #$EE#$80#$92;  { U+E012 .py }
    ICO_JS         = #$EE#$80#$93;  { U+E013 .js }
    ICO_TS         = #$EE#$80#$94;  { U+E014 .ts }
    ICO_C          = #$EE#$80#$95;  { U+E015 .c }
    ICO_H          = #$EE#$80#$96;  { U+E016 .h }
    ICO_CPP        = #$EE#$80#$97;  { U+E017 .cpp }
    ICO_RS         = #$EE#$80#$98;  { U+E018 .rs }
    ICO_GO         = #$EE#$80#$99;  { U+E019 .go }
    ICO_RB         = #$EE#$80#$9A;  { U+E01A .rb }
    ICO_SH         = #$EE#$80#$9B;  { U+E01B .sh }
    ICO_ASM        = #$EE#$80#$9C;  { U+E01C .asm }
    ICO_LUA        = #$EE#$80#$9D;  { U+E01D .lua }
    ICO_SQL        = #$EE#$80#$9E;  { U+E01E .sql }
    ICO_CSS        = #$EE#$80#$9F;  { U+E01F .css }
    ICO_HTM        = #$EE#$80#$A0;  { U+E020 .html }
    ICO_PHP        = #$EE#$80#$A1;  { U+E021 .php }
    ICO_JAV        = #$EE#$80#$A2;  { U+E022 .java }
    ICO_CS         = #$EE#$80#$A3;  { U+E023 .cs }
    { Documents }
    ICO_TXT        = #$EE#$80#$A8;  { U+E028 .txt }
    ICO_MD         = #$EE#$80#$A9;  { U+E029 .md }
    ICO_PDF        = #$EE#$80#$AA;  { U+E02A .pdf }
    ICO_DOC        = #$EE#$80#$AB;  { U+E02B .doc }
    ICO_RTF        = #$EE#$80#$AC;  { U+E02C .rtf }
    ICO_LOG        = #$EE#$80#$AD;  { U+E02D .log }
    ICO_CSV        = #$EE#$80#$AE;  { U+E02E .csv }
    ICO_TEX        = #$EE#$80#$AF;  { U+E02F .tex }
    { Data/Config }
    ICO_JSON       = #$EE#$80#$B0;  { U+E030 .json }
    ICO_XML        = #$EE#$80#$B1;  { U+E031 .xml }
    ICO_YML        = #$EE#$80#$B2;  { U+E032 .yml }
    ICO_INI        = #$EE#$80#$B3;  { U+E033 .ini }
    ICO_CFG        = #$EE#$80#$B4;  { U+E034 .cfg }
    ICO_ENV        = #$EE#$80#$B5;  { U+E035 .env }
    ICO_TOML       = #$EE#$80#$B6;  { U+E036 .toml }
    { Images }
    ICO_IMG        = #$EE#$80#$B8;  { U+E038 generic image }
    ICO_PNG        = #$EE#$80#$B9;  { U+E039 .png }
    ICO_JPG        = #$EE#$80#$BA;  { U+E03A .jpg }
    ICO_BMP        = #$EE#$80#$BB;  { U+E03B .bmp }
    ICO_TGA        = #$EE#$80#$BC;  { U+E03C .tga }
    ICO_GIF        = #$EE#$80#$BD;  { U+E03D .gif }
    ICO_SVG        = #$EE#$80#$BE;  { U+E03E .svg }
    ICO_ICO        = #$EE#$80#$BF;  { U+E03F .ico }
    ICO_PSD        = #$EE#$81#$80;  { U+E040 .psd }
    ICO_WEBP       = #$EE#$81#$81;  { U+E041 .webp }
    { Audio }
    ICO_AUD        = #$EE#$81#$84;  { U+E044 generic audio }
    ICO_MP3        = #$EE#$81#$85;  { U+E045 .mp3 }
    ICO_WAV        = #$EE#$81#$86;  { U+E046 .wav }
    ICO_OGG        = #$EE#$81#$87;  { U+E047 .ogg }
    ICO_FLAC       = #$EE#$81#$88;  { U+E048 .flac }
    ICO_MID        = #$EE#$81#$89;  { U+E049 .midi }
    { Video }
    ICO_VID        = #$EE#$81#$8C;  { U+E04C generic video }
    ICO_MP4        = #$EE#$81#$8D;  { U+E04D .mp4 }
    ICO_AVI        = #$EE#$81#$8E;  { U+E04E .avi }
    ICO_MKV        = #$EE#$81#$8F;  { U+E04F .mkv }
    ICO_WEBM       = #$EE#$81#$90;  { U+E050 .webm }
    ICO_MOV        = #$EE#$81#$91;  { U+E051 .mov }
    { Archives }
    ICO_ARC        = #$EE#$81#$94;  { U+E054 generic archive }
    ICO_ZIP        = #$EE#$81#$95;  { U+E055 .zip }
    ICO_TAR        = #$EE#$81#$96;  { U+E056 .tar }
    ICO_GZ         = #$EE#$81#$97;  { U+E057 .gz }
    ICO_7Z         = #$EE#$81#$98;  { U+E058 .7z }
    ICO_RAR        = #$EE#$81#$99;  { U+E059 .rar }
    ICO_XZ         = #$EE#$81#$9A;  { U+E05A .xz }
    ICO_BZ2        = #$EE#$81#$9B;  { U+E05B .bz2 }
    ICO_ISO        = #$EE#$81#$9C;  { U+E05C .iso }
    { System/Binary }
    ICO_SYS        = #$EE#$81#$A0;  { U+E060 generic system }
    ICO_BIN        = #$EE#$81#$A1;  { U+E061 .bin }
    ICO_EXE        = #$EE#$81#$A2;  { U+E062 .exe }
    ICO_DLL        = #$EE#$81#$A3;  { U+E063 .dll }
    ICO_SO         = #$EE#$81#$A4;  { U+E064 .so }
    ICO_PPU        = #$EE#$81#$A5;  { U+E065 .ppu }
    ICO_OBJ        = #$EE#$81#$A6;  { U+E066 .o/.obj }
    ICO_WASM       = #$EE#$81#$A7;  { U+E067 .wasm }
    ICO_ELF        = #$EE#$81#$A8;  { U+E068 elf }
    ICO_KRN        = #$EE#$81#$A9;  { U+E069 kernel/driver }
    { Font }
    ICO_FNT        = #$EE#$81#$AC;  { U+E06C generic font }
    ICO_TTF        = #$EE#$81#$AD;  { U+E06D .ttf }
    ICO_OTF        = #$EE#$81#$AE;  { U+E06E .otf }
    ICO_WOFF       = #$EE#$81#$AF;  { U+E06F .woff }
    { Misc }
    ICO_LNK        = #$EE#$81#$B0;  { U+E070 shortcut }
    ICO_BAK        = #$EE#$81#$B1;  { U+E071 .bak }
    ICO_TMP        = #$EE#$81#$B2;  { U+E072 .tmp }
    ICO_LCK        = #$EE#$81#$B3;  { U+E073 lock }
    ICO_KEY        = #$EE#$81#$B4;  { U+E074 key/cert }
    ICO_DB         = #$EE#$81#$B5;  { U+E075 database }
    ICO_GIT        = #$EE#$81#$B6;  { U+E076 .git }
    ICO_MK         = #$EE#$81#$B7;  { U+E077 Makefile }
    ICO_DOCKER     = #$EE#$81#$B8;  { U+E078 Dockerfile }

function getFileTypeIcon(name: pchar): pchar;
function getFileTypeColor(name: pchar): uint32;

implementation

{ ============================================================
  getFileTypeIcon — map a filename to its PUA icon constant
  Returns ICO_* pchar for the file extension, or ICO_FILE if
  no specific match.  No allocation; returns a const string.
  ============================================================ }
function getFileTypeIcon(name: pchar): pchar;
var
    ext: pchar;
begin
    ext := getFileExtension(name);
    if ext = nil then begin getFileTypeIcon := ICO_FILE; exit; end;

    { Code }
    if stringEqualsCI(ext, '.pas') then begin getFileTypeIcon := ICO_PAS; exit; end;
    if stringEqualsCI(ext, '.pp')  then begin getFileTypeIcon := ICO_PAS; exit; end;
    if stringEqualsCI(ext, '.py')  then begin getFileTypeIcon := ICO_PY;  exit; end;
    if stringEqualsCI(ext, '.js')  then begin getFileTypeIcon := ICO_JS;  exit; end;
    if stringEqualsCI(ext, '.ts')  then begin getFileTypeIcon := ICO_TS;  exit; end;
    if stringEqualsCI(ext, '.c')   then begin getFileTypeIcon := ICO_C;   exit; end;
    if stringEqualsCI(ext, '.h')   then begin getFileTypeIcon := ICO_H;   exit; end;
    if stringEqualsCI(ext, '.cpp') then begin getFileTypeIcon := ICO_CPP; exit; end;
    if stringEqualsCI(ext, '.hpp') then begin getFileTypeIcon := ICO_CPP; exit; end;
    if stringEqualsCI(ext, '.cc')  then begin getFileTypeIcon := ICO_CPP; exit; end;
    if stringEqualsCI(ext, '.rs')  then begin getFileTypeIcon := ICO_RS;  exit; end;
    if stringEqualsCI(ext, '.go')  then begin getFileTypeIcon := ICO_GO;  exit; end;
    if stringEqualsCI(ext, '.rb')  then begin getFileTypeIcon := ICO_RB;  exit; end;
    if stringEqualsCI(ext, '.sh')  then begin getFileTypeIcon := ICO_SH;  exit; end;
    if stringEqualsCI(ext, '.bat') then begin getFileTypeIcon := ICO_SH;  exit; end;
    if stringEqualsCI(ext, '.asm') then begin getFileTypeIcon := ICO_ASM; exit; end;
    if stringEqualsCI(ext, '.s')   then begin getFileTypeIcon := ICO_ASM; exit; end;
    if stringEqualsCI(ext, '.inc') then begin getFileTypeIcon := ICO_ASM; exit; end;
    if stringEqualsCI(ext, '.lua') then begin getFileTypeIcon := ICO_LUA; exit; end;
    if stringEqualsCI(ext, '.sql') then begin getFileTypeIcon := ICO_SQL; exit; end;
    if stringEqualsCI(ext, '.css') then begin getFileTypeIcon := ICO_CSS; exit; end;
    if stringEqualsCI(ext, '.htm') then begin getFileTypeIcon := ICO_HTM; exit; end;
    if stringEqualsCI(ext, '.html')then begin getFileTypeIcon := ICO_HTM; exit; end;
    if stringEqualsCI(ext, '.php') then begin getFileTypeIcon := ICO_PHP; exit; end;
    if stringEqualsCI(ext, '.java')then begin getFileTypeIcon := ICO_JAV; exit; end;
    if stringEqualsCI(ext, '.cs')  then begin getFileTypeIcon := ICO_CS;  exit; end;

    { Documents }
    if stringEqualsCI(ext, '.txt') then begin getFileTypeIcon := ICO_TXT; exit; end;
    if stringEqualsCI(ext, '.md')  then begin getFileTypeIcon := ICO_MD;  exit; end;
    if stringEqualsCI(ext, '.pdf') then begin getFileTypeIcon := ICO_PDF; exit; end;
    if stringEqualsCI(ext, '.doc') then begin getFileTypeIcon := ICO_DOC; exit; end;
    if stringEqualsCI(ext, '.docx')then begin getFileTypeIcon := ICO_DOC; exit; end;
    if stringEqualsCI(ext, '.rtf') then begin getFileTypeIcon := ICO_RTF; exit; end;
    if stringEqualsCI(ext, '.log') then begin getFileTypeIcon := ICO_LOG; exit; end;
    if stringEqualsCI(ext, '.csv') then begin getFileTypeIcon := ICO_CSV; exit; end;
    if stringEqualsCI(ext, '.tex') then begin getFileTypeIcon := ICO_TEX; exit; end;

    { Data/Config }
    if stringEqualsCI(ext, '.json')then begin getFileTypeIcon := ICO_JSON; exit; end;
    if stringEqualsCI(ext, '.xml') then begin getFileTypeIcon := ICO_XML;  exit; end;
    if stringEqualsCI(ext, '.yml') then begin getFileTypeIcon := ICO_YML;  exit; end;
    if stringEqualsCI(ext, '.yaml')then begin getFileTypeIcon := ICO_YML;  exit; end;
    if stringEqualsCI(ext, '.ini') then begin getFileTypeIcon := ICO_INI;  exit; end;
    if stringEqualsCI(ext, '.cfg') then begin getFileTypeIcon := ICO_CFG;  exit; end;
    if stringEqualsCI(ext, '.conf')then begin getFileTypeIcon := ICO_CFG;  exit; end;
    if stringEqualsCI(ext, '.env') then begin getFileTypeIcon := ICO_ENV;  exit; end;
    if stringEqualsCI(ext, '.toml')then begin getFileTypeIcon := ICO_TOML; exit; end;

    { Images }
    if stringEqualsCI(ext, '.png') then begin getFileTypeIcon := ICO_PNG;  exit; end;
    if stringEqualsCI(ext, '.jpg') then begin getFileTypeIcon := ICO_JPG;  exit; end;
    if stringEqualsCI(ext, '.jpeg')then begin getFileTypeIcon := ICO_JPG;  exit; end;
    if stringEqualsCI(ext, '.bmp') then begin getFileTypeIcon := ICO_BMP;  exit; end;
    if stringEqualsCI(ext, '.tga') then begin getFileTypeIcon := ICO_TGA;  exit; end;
    if stringEqualsCI(ext, '.gif') then begin getFileTypeIcon := ICO_GIF;  exit; end;
    if stringEqualsCI(ext, '.svg') then begin getFileTypeIcon := ICO_SVG;  exit; end;
    if stringEqualsCI(ext, '.ico') then begin getFileTypeIcon := ICO_ICO;  exit; end;
    if stringEqualsCI(ext, '.psd') then begin getFileTypeIcon := ICO_PSD;  exit; end;
    if stringEqualsCI(ext, '.webp')then begin getFileTypeIcon := ICO_WEBP; exit; end;

    { Audio }
    if stringEqualsCI(ext, '.mp3') then begin getFileTypeIcon := ICO_MP3;  exit; end;
    if stringEqualsCI(ext, '.wav') then begin getFileTypeIcon := ICO_WAV;  exit; end;
    if stringEqualsCI(ext, '.ogg') then begin getFileTypeIcon := ICO_OGG;  exit; end;
    if stringEqualsCI(ext, '.flac')then begin getFileTypeIcon := ICO_FLAC; exit; end;
    if stringEqualsCI(ext, '.mid') then begin getFileTypeIcon := ICO_MID;  exit; end;
    if stringEqualsCI(ext, '.midi')then begin getFileTypeIcon := ICO_MID;  exit; end;

    { Video }
    if stringEqualsCI(ext, '.mp4') then begin getFileTypeIcon := ICO_MP4;  exit; end;
    if stringEqualsCI(ext, '.avi') then begin getFileTypeIcon := ICO_AVI;  exit; end;
    if stringEqualsCI(ext, '.mkv') then begin getFileTypeIcon := ICO_MKV;  exit; end;
    if stringEqualsCI(ext, '.webm')then begin getFileTypeIcon := ICO_WEBM; exit; end;
    if stringEqualsCI(ext, '.mov') then begin getFileTypeIcon := ICO_MOV;  exit; end;

    { Archives }
    if stringEqualsCI(ext, '.zip') then begin getFileTypeIcon := ICO_ZIP; exit; end;
    if stringEqualsCI(ext, '.tar') then begin getFileTypeIcon := ICO_TAR; exit; end;
    if stringEqualsCI(ext, '.gz')  then begin getFileTypeIcon := ICO_GZ;  exit; end;
    if stringEqualsCI(ext, '.tgz') then begin getFileTypeIcon := ICO_GZ;  exit; end;
    if stringEqualsCI(ext, '.7z')  then begin getFileTypeIcon := ICO_7Z;  exit; end;
    if stringEqualsCI(ext, '.rar') then begin getFileTypeIcon := ICO_RAR; exit; end;
    if stringEqualsCI(ext, '.xz')  then begin getFileTypeIcon := ICO_XZ;  exit; end;
    if stringEqualsCI(ext, '.bz2') then begin getFileTypeIcon := ICO_BZ2; exit; end;
    if stringEqualsCI(ext, '.iso') then begin getFileTypeIcon := ICO_ISO; exit; end;

    { System/Binary }
    if stringEqualsCI(ext, '.bin') then begin getFileTypeIcon := ICO_BIN;  exit; end;
    if stringEqualsCI(ext, '.exe') then begin getFileTypeIcon := ICO_EXE;  exit; end;
    if stringEqualsCI(ext, '.dll') then begin getFileTypeIcon := ICO_DLL;  exit; end;
    if stringEqualsCI(ext, '.so')  then begin getFileTypeIcon := ICO_SO;   exit; end;
    if stringEqualsCI(ext, '.ppu') then begin getFileTypeIcon := ICO_PPU;  exit; end;
    if stringEqualsCI(ext, '.o')   then begin getFileTypeIcon := ICO_OBJ;  exit; end;
    if stringEqualsCI(ext, '.obj') then begin getFileTypeIcon := ICO_OBJ;  exit; end;
    if stringEqualsCI(ext, '.wasm')then begin getFileTypeIcon := ICO_WASM; exit; end;
    if stringEqualsCI(ext, '.elf') then begin getFileTypeIcon := ICO_ELF;  exit; end;
    if stringEqualsCI(ext, '.sys') then begin getFileTypeIcon := ICO_KRN;  exit; end;
    if stringEqualsCI(ext, '.drv') then begin getFileTypeIcon := ICO_KRN;  exit; end;
    if stringEqualsCI(ext, '.asr') then begin getFileTypeIcon := ICO_KRN;  exit; end;

    { Fonts }
    if stringEqualsCI(ext, '.ttf') then begin getFileTypeIcon := ICO_TTF;  exit; end;
    if stringEqualsCI(ext, '.otf') then begin getFileTypeIcon := ICO_OTF;  exit; end;
    if stringEqualsCI(ext, '.woff')then begin getFileTypeIcon := ICO_WOFF; exit; end;

    { Misc }
    if stringEqualsCI(ext, '.bak') then begin getFileTypeIcon := ICO_BAK; exit; end;
    if stringEqualsCI(ext, '.tmp') then begin getFileTypeIcon := ICO_TMP; exit; end;
    if stringEqualsCI(ext, '.lock')then begin getFileTypeIcon := ICO_LCK; exit; end;
    if stringEqualsCI(ext, '.key') then begin getFileTypeIcon := ICO_KEY; exit; end;
    if stringEqualsCI(ext, '.pem') then begin getFileTypeIcon := ICO_KEY; exit; end;
    if stringEqualsCI(ext, '.crt') then begin getFileTypeIcon := ICO_KEY; exit; end;
    if stringEqualsCI(ext, '.db')  then begin getFileTypeIcon := ICO_DB;  exit; end;
    if stringEqualsCI(ext, '.sqlite')then begin getFileTypeIcon := ICO_DB; exit; end;

    { Default }
    getFileTypeIcon := ICO_FILE;
end;

{ ============================================================
  getFileTypeColor — return a color value packed as $00RRGGBB
  for the icon label based on file type category.
  ============================================================ }
function getFileTypeColor(name: pchar): uint32;
var
    ext: pchar;
begin
    ext := getFileExtension(name);
    if ext = nil then begin getFileTypeColor := $A0A8BE; exit; end;

    { Code — blue-green }
    if stringEqualsCI(ext, '.pas') or stringEqualsCI(ext, '.pp') or
       stringEqualsCI(ext, '.py')  or stringEqualsCI(ext, '.js') or
       stringEqualsCI(ext, '.ts')  or stringEqualsCI(ext, '.c')  or
       stringEqualsCI(ext, '.h')   or stringEqualsCI(ext, '.cpp') or
       stringEqualsCI(ext, '.hpp') or stringEqualsCI(ext, '.cc') or
       stringEqualsCI(ext, '.rs')  or stringEqualsCI(ext, '.go') or
       stringEqualsCI(ext, '.rb')  or stringEqualsCI(ext, '.sh') or
       stringEqualsCI(ext, '.bat') or stringEqualsCI(ext, '.asm') or
       stringEqualsCI(ext, '.s')   or stringEqualsCI(ext, '.inc') or
       stringEqualsCI(ext, '.lua') or stringEqualsCI(ext, '.sql') or
       stringEqualsCI(ext, '.css') or stringEqualsCI(ext, '.htm') or
       stringEqualsCI(ext, '.html')or stringEqualsCI(ext, '.php') or
       stringEqualsCI(ext, '.java')or stringEqualsCI(ext, '.cs') then
    begin getFileTypeColor := $5CB8D6; exit; end;

    { Documents — warm white }
    if stringEqualsCI(ext, '.txt') or stringEqualsCI(ext, '.md') or
       stringEqualsCI(ext, '.pdf') or stringEqualsCI(ext, '.doc') or
       stringEqualsCI(ext, '.docx')or stringEqualsCI(ext, '.rtf') or
       stringEqualsCI(ext, '.log') or stringEqualsCI(ext, '.csv') or
       stringEqualsCI(ext, '.tex') then
    begin getFileTypeColor := $D6D0C4; exit; end;

    { Data/Config — orange }
    if stringEqualsCI(ext, '.json')or stringEqualsCI(ext, '.xml') or
       stringEqualsCI(ext, '.yml') or stringEqualsCI(ext, '.yaml') or
       stringEqualsCI(ext, '.ini') or stringEqualsCI(ext, '.cfg') or
       stringEqualsCI(ext, '.conf')or stringEqualsCI(ext, '.env') or
       stringEqualsCI(ext, '.toml')then
    begin getFileTypeColor := $E0A050; exit; end;

    { Images — pink/magenta }
    if stringEqualsCI(ext, '.png') or stringEqualsCI(ext, '.jpg') or
       stringEqualsCI(ext, '.jpeg')or stringEqualsCI(ext, '.bmp') or
       stringEqualsCI(ext, '.tga') or stringEqualsCI(ext, '.gif') or
       stringEqualsCI(ext, '.svg') or stringEqualsCI(ext, '.ico') or
       stringEqualsCI(ext, '.psd') or stringEqualsCI(ext, '.webp')then
    begin getFileTypeColor := $E06090; exit; end;

    { Audio — green }
    if stringEqualsCI(ext, '.mp3') or stringEqualsCI(ext, '.wav') or
       stringEqualsCI(ext, '.ogg') or stringEqualsCI(ext, '.flac') or
       stringEqualsCI(ext, '.mid') or stringEqualsCI(ext, '.midi')then
    begin getFileTypeColor := $60C080; exit; end;

    { Video — purple }
    if stringEqualsCI(ext, '.mp4') or stringEqualsCI(ext, '.avi') or
       stringEqualsCI(ext, '.mkv') or stringEqualsCI(ext, '.webm') or
       stringEqualsCI(ext, '.mov') then
    begin getFileTypeColor := $B070E0; exit; end;

    { Archives — brown/amber }
    if stringEqualsCI(ext, '.zip') or stringEqualsCI(ext, '.tar') or
       stringEqualsCI(ext, '.gz')  or stringEqualsCI(ext, '.tgz') or
       stringEqualsCI(ext, '.7z')  or stringEqualsCI(ext, '.rar') or
       stringEqualsCI(ext, '.xz')  or stringEqualsCI(ext, '.bz2') or
       stringEqualsCI(ext, '.iso') then
    begin getFileTypeColor := $C89050; exit; end;

    { System/Binary — red }
    if stringEqualsCI(ext, '.bin') or stringEqualsCI(ext, '.exe') or
       stringEqualsCI(ext, '.dll') or stringEqualsCI(ext, '.so') or
       stringEqualsCI(ext, '.ppu') or stringEqualsCI(ext, '.o') or
       stringEqualsCI(ext, '.obj') or stringEqualsCI(ext, '.wasm') or
       stringEqualsCI(ext, '.elf') or stringEqualsCI(ext, '.sys') or
       stringEqualsCI(ext, '.drv') or stringEqualsCI(ext, '.asr') then
    begin getFileTypeColor := $D06060; exit; end;

    { Fonts — teal }
    if stringEqualsCI(ext, '.ttf') or stringEqualsCI(ext, '.otf') or
       stringEqualsCI(ext, '.woff')then
    begin getFileTypeColor := $50B0B0; exit; end;

    { Default — neutral grey-blue }
    getFileTypeColor := $A0A8BE;
end;

end.

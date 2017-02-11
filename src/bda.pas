unit bda;

interface

type
     TBDA = bitpacked record
          COM1            : WORD;
          COM2            : WORD;
          COM3            : WORD;
          COM4            : WORD;
          LPT1            : WORD;
          LPT2            : WORD;
          LPT3            : WORD;
          EBDA            : WORD;
          Hardware_Flags  : WORD;
          Keyboard_Flags  : WORD;
          Keyboard_Buffer : ARRAY[0..31] OF BYTE;
          Display_Mode    : BYTE;
          BaseIO          : WORD;
          Ticks           : WORD;
          HDD_Count       : BYTE;
          Keyboard_Start  : WORD;
          Keyboard_End    : WORD;
          Keyboard_State  : Byte;
     end;
     PBDA = ^TBDA;

implementation

end.

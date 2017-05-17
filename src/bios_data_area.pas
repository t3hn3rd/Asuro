{ ************************************************
  * Asuro
  * Unit: bios_data_area
  * Description: Data Structures controlled by
  *              the BIOS.
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit bios_data_area;

interface

type
     TBDA = bitpacked record
          COM1            : uint16;
          COM2            : uint16;
          COM3            : uint16;
          COM4            : uint16;
          LPT1            : uint16;
          LPT2            : uint16;
          LPT3            : uint16;
          EBDA            : uint16;
          Hardware_Flags  : uint16;
          Keyboard_Flags  : uint16;
          Keyboard_Buffer : ARRAY[0..31] OF uint8;
          Display_Mode    : uint8;
          BaseIO          : uint16;
          Ticks           : uint16;
          HDD_Count       : uint8;
          Keyboard_Start  : uint16;
          Keyboard_End    : uint16;
          Keyboard_State  : uint8;
     end;
     PBDA = ^TBDA;

const
     BDA : PBDA = PBDA($0400);

implementation

end.

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

     TMCFG = bitpacked record
        Signature        : Array[0..3] of Char;
        Table_Length     : uint32;
        Revision         : Byte;
        Checksum         : Byte;
        OEM_ID           : Array[0..5] of Byte;
        OEM_Table_ID     : uint64;
        OEM_Revision     : uint32;
        Creator_ID       : uint32;
        Creator_Revision : uint32;
        Reserved         : uint64;
     end;
     PMCFG = ^TMCFG;

const
     BDA : PBDA = PBDA($C0000400);

var
     EBDA : void;
     MCFG : PMCFG;

procedure tick_update(data : void);
procedure init();

implementation

uses
    console, vmemorymanager;

procedure tick_update(data : void);
begin
    BDA^.Ticks:= BDA^.Ticks + 1;
end;

procedure init();
begin
    console.outputln('BDA','Loaded.');
    //TO-DO search for important structures like the MCFG or the EBDA.
end;

end.

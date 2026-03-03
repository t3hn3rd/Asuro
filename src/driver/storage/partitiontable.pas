{ ************************************************
  * Asuro
  * Unit: Drivers/storage/partitiontable
  * Description: partionTable
  * 
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }

unit partitiontable;

interface

uses
    console,
    lists,
    lmemorymanager,
    rtc,
    storagemanagement,
    strings,
    terminal,
    tracer,
    util;

type 

    TpartitionTable = record 

    end;
    PpartitionTable = ^TpartitionTable;

var 
    location = $1BE;

procedure create_new(device : PStorage_Device);
function get_table() : PpartitionTable;
procedure add_volume(volume : TStorage_Volume);

implementation 

procedure create_new(device : PStorage_Device);
var

begin
    
end;

function get_table() : PpartitionTable;
procedure add_volume(volume : TStorage_Volume);

end.
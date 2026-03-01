{ ************************************************
  * Asuro
  * Unit: Drivers/storage/partitontable
  * Description: partionTable
  * 
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }

unit partitontable;

interface

uses
    storagemanagement,
    util,
    lmemorymanager,
    strings,
    lists,
    tracer,
    rtc;

type 

    TPartitonTable = record 

    end;
    PPartitonTable = ^TPartitonTable;

var 
    location = $1BE;

procedure create_new(device : PStorage_Device);
function get_table() : PPartitonTable;
procedure add_volume(volume : TStorage_Volume);

implementation 

procedure create_new(device : PStorage_Device);
var

begin
    
end;

function get_table() : PPartitonTable;
procedure add_volume(volume : TStorage_Volume);

end.
//  Copyright 2021 Aaron Hance
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
{
    Driver->Storage->PartitionTable - MBR partition table parsing and management.

    @author(Aaron Hance <ah@aaronhance.me>)
}

unit partitiontable;

interface

uses
    syslog,
    lists,
    lmemorymanager,
    rtc,
    storagemanagement,
    strings,
    stdio,
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
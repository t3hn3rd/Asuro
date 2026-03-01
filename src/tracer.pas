//  Copyright 2021 Kieron Morris
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
	Tracer - Trace stack for debugging method calls.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit tracer;

interface

procedure init;
procedure push_trace(t_name : pchar);
procedure pop_trace;
function  get_last_trace : pchar;
procedure freeze;
function  get_trace_count : uint32;
function  get_trace_N(idx : uint32) : pchar;

implementation

uses
    lmemorymanager, util, strings, serial, stdio;

type
    PTracerEntry = ^TTracerEntry;
    TTracerEntry = record
        Next        : PTracerEntry;
        Data        : pchar;
        Previous    : PTracerEntry;
    end;

const
    MAX_TRACE = 40;

var
    t_ready     : Boolean;
    Locked      : Boolean;
    Traces      : Array[0..MAX_TRACE-1] of PChar;
    c_lock      : Boolean = false;

var
    head : PTracerEntry;
    tail : PTracerEntry;

procedure terminal_command_tracer(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    p1, p2 : PChar;
    count : uint32;
    i : uint32; 
    t : PChar;

begin
    if ParamCount(Params) > 0 then begin
        p1:= getParam(0, Params);
        if StringEquals(p1, 'list') then begin
            count:= 5;
            if ParamCount(Params) > 1 then begin
                count:= stringToInt(getParam(1, Params));
                if count > MAX_TRACE-1 then count:= MAX_TRACE-1;
            end;
            for i:=0 to count do begin
                stdio.bufWriteStr(stdout_buf, '[-');
                stdio.bufWriteInt(stdout_buf, i);
                stdio.bufWriteStr(stdout_buf, '] ');
                t:= get_trace_N(i);
                if t <> nil then stdio.bufWriteStr(stdout_buf, t);
                stdio.bufWriteStrLn(stdout_buf, ' ');
            end;
        end;
        if StringEquals(p1, 'disable') then begin
            if TRACER_ENABLE then begin
                t_ready:= false;
                stdio.bufWriteStrLn(stdout_buf, 'Tracer disabled.');
            end else begin
                stdio.bufWriteStrLn(stderr_buf, 'Tracer is disabled by the system and it''s status cannot be changed.');
            end;
        end;
        if StringEquals(p1, 'enable') then begin
            if TRACER_ENABLE then begin
                t_ready:= true;
                stdio.bufWriteStrLn(stdout_buf, 'Tracer enabled.');
            end else begin
                stdio.bufWriteStrLn(stderr_buf, 'Tracer is disabled by the system and it''s status cannot be changed.');
            end;
        end;
    end else begin
        stdio.bufWriteStrLn(stdout_buf, 'System Trace Utility');
        stdio.bufWriteStrLn(stdout_buf, ' ');
        stdio.bufWriteStrLn(stdout_buf, 'Usage: ');
        stdio.bufWriteStrLn(stdout_buf, '       tracer list <Count> - Print the last <count> traces.');
        stdio.bufWriteStrLn(stdout_buf, '       tracer disable      - Disable Tracer.');
        stdio.bufWriteStrLn(stdout_buf, '       tracer enable       - Enable Tracer.');
        stdio.bufWriteStrLn(stdout_buf, ' ');
    end;
end;

procedure freeze;
begin
    if TRACER_ENABLE then t_ready:= false;
end;

procedure push_trace(t_name : pchar);
var
    i   : uint32;

begin
    if TRACER_ENABLE then begin
        if t_ready then begin
            if not Locked then begin
                if not c_lock then begin
                    Locked:= true;
                    if Traces[MAX_TRACE-1] <> nil then kfree(void(Traces[MAX_TRACE-1]));
                    for i:=MAX_TRACE-1 downto 1 do begin
                        Traces[i]:= Traces[i-1];
                    end;
                    Traces[0]:= StringCopy(t_name);
                    Locked:= false;
                end;
            end;
        end;
    end;
end;

procedure pop_trace;
begin

end;

function get_last_trace : pchar;
begin
    get_last_trace:= Traces[0];
end;

procedure init;
var
    i   : uint32;

begin
    if TRACER_ENABLE then begin
        for i:=0 to MAX_TRACE-1 do begin
            traces[i]:= nil;
        end;
        t_ready:= true;
        push_trace('kmain');
    end;
    stdio.registerCommand('TRACER', @terminal_command_tracer, 'System.Tracer Interface.');
end;

function get_trace_count : uint32;
begin
    if TRACER_ENABLE then begin
        get_trace_count:= MAX_TRACE;
    end;
end;

function get_trace_N(idx : uint32) : pchar;
begin
    if idx > MAX_TRACE-1 then exit;
    if TRACER_ENABLE then begin
        get_trace_N:= traces[idx];
    end;
end;

end.
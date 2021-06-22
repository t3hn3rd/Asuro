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
    console, lmemorymanager, util, strings, serial, terminal;

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

procedure terminal_command_tracer(Params : PParamList);
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
                writeStringWND('[-', getTerminalHWND);
                writeintWND(i, getTerminalHWND);
                writeStringWND('] ', getTerminalHWND);
                t:= get_trace_N(i);
                if t <> nil then writeStringWND(t, getTerminalHWND);
                writeStringLnWND(' ', getTerminalHWND);
            end;
        end;
        if StringEquals(p1, 'disable') then begin
            if TRACER_ENABLE then begin
                t_ready:= false;
                writeStringLnWND('Tracer disabled.', getTerminalHWND);
            end else begin
                writeStringLnWND('Tracer is disabled by the system and it''s status cannot be changed.', getTerminalHWND);
            end;
        end;
        if StringEquals(p1, 'enable') then begin
            if TRACER_ENABLE then begin
                t_ready:= true;
                writeStringLnWND('Tracer enabled.', getTerminalHWND);
            end else begin
                writeStringLnWND('Tracer is disabled by the system and it''s status cannot be changed.', getTerminalHWND);
            end;
        end;
    end else begin
        writeStringLnWND('System Trace Utility', getTerminalHWND);
        writeStringLnWND(' ', getTerminalHWND);
        writeStringLnWND('Usage: ', getTerminalHWND);
        writeStringLnWND('       tracer list <Count> - Print the last <count> traces.', getTerminalHWND);
        writeStringLnWND('       tracer disable      - Disable Tracer.', getTerminalHWND);
        writeStringLnWND('       tracer enable       - Enable Tracer.', getTerminalHWND);
        writeStringLnWND(' ', getTerminalHWND);
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
    terminal.registerCommand('TRACER', @terminal_command_tracer, 'System.Tracer Interface.');
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
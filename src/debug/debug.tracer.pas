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
	Tracer - Ring buffer trace log for debugging method calls.
	
	IMPORTANT: push_trace MUST only be called with pointers to
	static/persistent data (e.g. string literals). The pointer is
	stored directly - no copy is made.

	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit debug.tracer;

interface

procedure init;
procedure push_trace(t_name : pchar);
procedure pop_trace;
function  get_last_trace : pchar;
procedure freeze;
function  get_trace_count : uint32;
function  get_trace_N(idx : uint32) : pchar;
procedure print_traces;

implementation

uses
    boot.mgr,
    core.util, arch.x86.util, core.strings, io.stdio, io.syslog;

const
    MAX_TRACE = 40;

var
    t_ready     : Boolean;
    Locked      : Boolean;
    head        : uint32;
    Traces      : Array[0..MAX_TRACE-1] of PChar;

procedure terminal_command_tracer(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    p1 : PChar;
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
                io.stdio.bufWriteStr(stdout_buf, '[-');
                io.stdio.bufWriteInt(stdout_buf, i);
                io.stdio.bufWriteStr(stdout_buf, '] ');
                t:= get_trace_N(i);
                if t <> nil then io.stdio.bufWriteStr(stdout_buf, t);
                io.stdio.bufWriteStrLn(stdout_buf, ' ');
            end;
        end;
        if StringEquals(p1, 'disable') then begin
            if TRACER_ENABLE then begin
                t_ready:= false;
                io.stdio.bufWriteStrLn(stdout_buf, 'Tracer disabled.');
            end else begin
                io.stdio.bufWriteStrLn(stderr_buf, 'Tracer is disabled by the system and it''s status cannot be changed.');
            end;
        end;
        if StringEquals(p1, 'enable') then begin
            if TRACER_ENABLE then begin
                t_ready:= true;
                io.stdio.bufWriteStrLn(stdout_buf, 'Tracer enabled.');
            end else begin
                io.stdio.bufWriteStrLn(stderr_buf, 'Tracer is disabled by the system and it''s status cannot be changed.');
            end;
        end;
    end else begin
        io.stdio.bufWriteStrLn(stdout_buf, 'System Trace Utility');
        io.stdio.bufWriteStrLn(stdout_buf, ' ');
        io.stdio.bufWriteStrLn(stdout_buf, 'Usage: ');
        io.stdio.bufWriteStrLn(stdout_buf, '       debug.tracer list <Count> - Print the last <count> traces.');
        io.stdio.bufWriteStrLn(stdout_buf, '       debug.tracer disable      - Disable Tracer.');
        io.stdio.bufWriteStrLn(stdout_buf, '       debug.tracer enable       - Enable Tracer.');
        io.stdio.bufWriteStrLn(stdout_buf, ' ');
    end;
end;

procedure freeze;
begin
    if TRACER_ENABLE then t_ready:= false;
end;

procedure push_trace(t_name : pchar);
begin
    if TRACER_ENABLE then begin
        if t_ready then begin
            if not Locked then begin
                Locked:= true;
                head:= head + 1;
                if head >= MAX_TRACE then head:= 0;
                Traces[head]:= t_name;
                Locked:= false;
            end;
        end;
    end;
end;

procedure pop_trace;
begin

end;

function get_last_trace : pchar;
begin
    get_last_trace:= Traces[head];
end;

procedure init;
var
    i   : uint32;

begin
    if TRACER_ENABLE then begin
        for i:=0 to MAX_TRACE-1 do begin
            Traces[i]:= nil;
        end;
        Locked:= false;
        head:= MAX_TRACE - 1;
        t_ready:= true;
        push_trace('kmain');
    end;
    io.stdio.registerCommand('TRACER', @terminal_command_tracer, 'System.Tracer Interface.');
end;

function get_trace_count : uint32;
begin
    if TRACER_ENABLE then begin
        get_trace_count:= MAX_TRACE;
    end;
end;

procedure print_traces;
var
    i : uint32;

begin
    for i:=0 to MAX_TRACE-1 do begin
        io.syslog.log('TRACER', '[');
        io.syslog.writeint(i);
        io.syslog.writestring('] ');
        if Traces[i] <> nil then begin
            io.syslog.writestringln(Traces[i]);
        end else begin
            io.syslog.writestringln('?????????');
        end;
    end;
end;

function get_trace_N(idx : uint32) : pchar;
var
    slot : uint32;
begin
    if idx > MAX_TRACE-1 then exit;
    if TRACER_ENABLE then begin
        if head >= idx then
            slot:= head - idx
        else
            slot:= MAX_TRACE - (idx - head);
        get_trace_N:= Traces[slot];
    end;
end;

initialization
    //procedure registerBoot(Name: PChar; InitProc: TBootProc; Status: PChar; DependsOn: PChar);
    boot.mgr.registerBoot('debug.tracer.freeze', @freeze, 'Debug Tracer Freeze', 'io.syslog' );
    boot.mgr.registerBoot('debug.tracer', @init, 'Debug Tracer Initialization', 'io.stdio' );

end.
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
    console, util, lists, strings, serial;

const
    MAX_TRACE = 40;
    SERIALID = '[TRACER]  ';

var
    t_ready     : Boolean;
    Locked      : Boolean;
    TraceStack  : PLinkedListBase;
    Traces      : Array[0..MAX_TRACE-1] of PChar;

procedure freeze;
begin
    if TRACER_ENABLE then t_ready:= false;
end;

procedure push_trace(t_name : pchar);
var
    i   : uint32;

begin
    CLI;
    if TRACER_ENABLE then begin
        if t_ready then begin
            if not Locked then begin
                Locked:= true;
                for i:=MAX_TRACE-1 downto 1 do begin
                    Traces[i]:= Traces[i-1];
                end;
                Traces[0]:= StringCopy(t_name);
                for i:=0 to StringSize(SERIALID)-1 do begin
                    serial.send(COM1, uint8(SERIALID[i]), 1000);
                end;
                for i:=0 to StringSize(t_name)-1 do begin
                    serial.send(COM1, uint8(t_name[i]), 1000);
                end;
                serial.send(COM1, 13, 10);
                //serial.send(COM1, 10, 10);
                Locked:= false;
            end;
        end;
    end;
    STI;
end;

procedure pop_trace;
begin

end;

function get_last_trace : pchar;
begin
    get_last_trace:= Traces[0];
end;

procedure init;
begin
    if TRACER_ENABLE then begin
        t_ready:= true;
        push_trace('kmain');
    end;
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
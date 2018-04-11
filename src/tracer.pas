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
    console, util, lists, strings;

var
    t_ready     : Boolean;
    Locked      : Boolean;
    TraceStack  : PLinkedListBase;

procedure freeze;
begin
    if TRACER_ENABLE then t_ready:= false;
end;

procedure push_trace(t_name : pchar);
var
    mem : void;

begin
    if TRACER_ENABLE then begin
        if t_ready then begin
            if not Locked then begin
                Locked:= true;
                mem:= LL_Insert(TraceStack, 0);
                memset(uint32(mem), 0, StringSize(t_name) + 5);
                memcpy(uint32(t_name), uint32(mem), StringSize(t_name) + 1);
                Locked:= false;
            end;
        end;
    end;
end;

procedure pop_trace;
begin
    if TRACER_ENABLE then begin
        if t_ready then begin
            if not Locked then begin
                Locked:= true;
                LL_Delete(TraceStack, 0);
                Locked:= false;
            end;
        end;
    end;
end;

function get_last_trace : pchar;
begin
    get_last_trace:= nil;
    if TRACER_ENABLE then begin
        if t_ready then begin
            get_last_trace:= pchar(LL_Get(TraceStack, 0));
        end;
    end;
end;

procedure init;
begin
    if TRACER_ENABLE then begin
        TraceStack:= LL_New(255);
        t_ready:= true;
        push_trace('kmain');
    end;
end;

function get_trace_count : uint32;
begin
    if TRACER_ENABLE then begin
        get_trace_count:= LL_Size(TraceStack);
    end;
end;

function get_trace_N(idx : uint32) : pchar;
begin
    if TRACER_ENABLE then begin
        get_trace_N:= pchar(LL_Get(TraceStack, idx));
    end;
end;

end.
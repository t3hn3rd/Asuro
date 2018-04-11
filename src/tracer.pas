unit tracer;

interface

procedure init;
procedure push_trace(t_name : pchar);
procedure pop_trace;
function  get_last_trace : pchar;

implementation

uses
    console, util, lists, strings;

var
    t_ready     : Boolean = false;
    Locked      : Boolean = false;
    TraceStack  : PLinkedListBase;

procedure lock;
begin
    t_ready:= false;
end;

procedure push_trace(t_name : pchar);
var
    mem : void;

begin
    if not Initialized then exit;
    console.writestringln('WTF?!?!?');
    if not Locked then begin
        Locked:= true;
        mem:= LL_Insert(TraceStack, 0);
        memset(uint32(mem), 0, StringSize(t_name) + 5);
        memcpy(uint32(t_name), uint32(mem), StringSize(t_name) + 1);
        Locked:= false;
    end;
end;

procedure pop_trace;
begin
    if not Initialized then exit;
    if not Locked then begin
        Locked:= true;
        LL_Delete(TraceStack, 0);
        Locked:= false;
    end;
end;

function get_last_trace : pchar;
begin
    if not Initialized then exit;
    get_last_trace:= pchar(LL_Get(TraceStack, 0));
end;

procedure init;
begin
    TraceStack:= LL_New(255);
    push_trace('kmain');
    Initialized:= true;
end;

end.
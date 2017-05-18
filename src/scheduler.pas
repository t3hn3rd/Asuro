unit scheduler;

interface

uses
    console,
    isr32,
    memorymanager;

const
    Quantum = 64;

type
    TScheduler_Entry = packed record
        ThreadID : uint32;
        Priority : uint8;
        Delta    : uint32;
        Next     : void;
    end;
    PScheduler_Entry = ^TScheduler_Entry;

procedure init;
procedure add_task(priority : uint8);

implementation

var
   Tick         : uint32;
   Root_Task    : PScheduler_Entry = nil;
   Current_Task : PScheduler_Entry = nil;

procedure context_switch();
begin
    // This will switch contexts eventually,
    // For now just print upon context switch.
    Current_Task:= PScheduler_Entry(Current_Task^.Next);
    console.writestring('Task: ');
    console.writeintln(Current_Task^.ThreadID);
end;

procedure add_task(priority : uint8);
var
    new_task : PScheduler_Entry;
    task     : PScheduler_Entry;
    i        : uint32;

begin
    new_task:= PScheduler_Entry(kalloc(sizeof(TScheduler_Entry)));
    new_task^.Priority:= priority;
    new_task^.Delta:= Tick;
    new_task^.Next:= void(Root_Task);
    task:= Root_Task;
    i:= 1;
    while PScheduler_Entry(task^.next) <> Root_Task do begin
        i:= i+1;
        task:= PScheduler_Entry(task^.next);
    end;
    task^.next:= void(new_task);
    new_task^.ThreadID:= i;
end;

procedure delta(data : void);
begin
    Tick:= Tick + 1;
    If (Current_Task^.Delta + (Current_Task^.Priority * Quantum)) <= Tick then context_switch();
end;

procedure init;
begin
    Root_Task:= PScheduler_Entry(kalloc(sizeof(TScheduler_Entry)));
    Root_Task^.ThreadID:= 0;
    Root_Task^.Priority:= 1;
    Root_Task^.Delta:= 0;
    Root_Task^.Next:= void(Root_Task);
    Current_Task:= Root_Task;
    Tick:= 0;
    isr32.hook(uint32(@delta));
end;

end.
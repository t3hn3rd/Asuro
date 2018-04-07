{ ************************************************
  * Asuro
  * Unit: Scheduler
  * Description: Schedules Context Switches
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit scheduler;

interface

uses
    console,
    isr32,
    lmemorymanager,
    terminal;

const
    Quantum = 64;

type
    TTaskState = packed record
        //EAX, EDX, 
    end;
    TScheduler_Entry = packed record
        ThreadID : uint32;
        Priority : uint8;
        Delta    : uint32;
        Next     : void;
    end;
    PScheduler_Entry = ^TScheduler_Entry;

var
    Active : Boolean;

procedure init;
procedure add_task(priority : uint8);

implementation

var
   Tick         : uint32;
   Root_Task    : PScheduler_Entry = nil;
   Current_Task : PScheduler_Entry = nil;

procedure context_switch();
begin
    Current_Task:= PScheduler_Entry(Current_Task^.Next);
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
    If Active then begin
        Tick:= Tick + 1;
        If Tick = 0 then context_switch();
        If (Current_Task^.Delta + (Current_Task^.Priority * Quantum)) <= Tick then context_switch();
    end;
end;

procedure terminal_command_tasks(params : PParamList);
var
    list : PScheduler_Entry;

begin
    console.writestringln('ThreadID - Priority - Delta');
    list:= Root_Task;
    console.writeint(list^.ThreadID);
    console.writestring('        - ');
    console.writeint(list^.Priority);
    console.writestring('        - ');
    console.writeintln(list^.Delta);
    list:= PScheduler_Entry(list^.Next);
    while list <> Root_Task do begin
        console.writeint(list^.ThreadID);
        console.writestring('        - ');
        console.writeint(list^.Priority);
        console.writestring('        - ');
        console.writeintln(list^.Delta);
        list:= PScheduler_Entry(list^.Next);
    end;
end;

procedure init;
begin
    console.outputln('SCHEDULER','INIT BEGIN.');
    Root_Task:= PScheduler_Entry(kalloc(sizeof(TScheduler_Entry)));
    Root_Task^.ThreadID:= 0;
    Root_Task^.Priority:= 1;
    Root_Task^.Delta:= 0;
    Root_Task^.Next:= void(Root_Task);
    Current_Task:= Root_Task;
    Tick:= 0;
    Active:= False;
    isr32.hook(uint32(@delta));
    terminal.registerCommand('TASKS', @terminal_command_tasks, 'List Active Processes.');
    console.outputln('SCHEDULER','INIT END.');
end;

end.
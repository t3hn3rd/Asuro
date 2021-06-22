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
	Prog->VMState - Live MINJ Virtual Machine State Information.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit vmstate;

interface

uses
    console, terminal, keyboard, util, strings, tracer, 
    vm_scheduler, vm_instance;

procedure init();

implementation

var
    Handle  : HWND = 0;

procedure OnClose();
begin
    Handle:= 0;
end;

procedure OnDraw();
begin
    if Handle <> 0 then begin
        clearWND(Handle);
        if vm_instance.Task.Valid then begin
            console.writeStringlnWND(' ', Handle);
            
            console.writeStringWND('  Task:        ', Handle);
            console.writeIntWND   (vm_instance.Task.State^.TASK_ID, Handle);
            console.writeStringWND('  |  SCHED:       ', Handle);
            console.writeintlnWND (vm_scheduler.getActiveTask, Handle);

            console.writeStringlnWND(' ', Handle);

            console.writeStringWND('  OBJ1:        ', Handle);
            console.writeintWND   (vm_instance.Task.State^.Registers[OBJ1], Handle);
            console.writeStringWND('  |  OBJ2:        ', Handle);
            console.writeintlnWND (vm_instance.Task.State^.Registers[OBJ2], Handle);

            console.writeStringWND('  C1:          ', Handle);
            console.writeintWND   (vm_instance.Task.State^.Registers[C1], Handle);
            console.writeStringWND('  |  C2:          ', Handle);
            console.writeintlnWND (vm_instance.Task.State^.Registers[C2], Handle);

            console.writeStringWND('  RET:         ', Handle);
            console.writeintlnWND (vm_instance.Task.State^.Registers[RET], Handle);

            console.writeStringWND('  INSTANCEID:  ', Handle);
            console.writeintlnWND (vm_instance.Task.State^.Registers[INSTANCEID], Handle);

            console.writeStringWND('  PC:          ', Handle);
            console.writeintlnWND (vm_instance.Task.State^.Registers[PC], Handle);

            console.writeStringWND('  STORE1:      ', Handle);
            console.writeintWND   (vm_instance.Task.State^.Registers[STORE1], Handle);
            console.writeStringWND('  |  STORE2:      ', Handle);
            console.writeintlnWND (vm_instance.Task.State^.Registers[STORE2], Handle);

            console.writeStringWND('  STORE3:      ', Handle);
            console.writeintWND   (vm_instance.Task.State^.Registers[STORE3], Handle);
            console.writeStringWND('  |  STORE4:      ', Handle);
            console.writeintlnWND (vm_instance.Task.State^.Registers[STORE4], Handle);

            console.writeStringWND('  STORE5:      ', Handle);
            console.writeintlnWND (vm_instance.Task.State^.Registers[STORE1], Handle);
            {WriteLn('Task: ', Task.State^.TASK_ID);
            WriteLn('OBJ1: ', Task.State^.Registers[OBJ1]);
            WriteLn('OBJ2: ', Task.State^.Registers[OBJ2]);
            WriteLn('C1: ', Task.State^.Registers[C1]);
            WriteLn('C2: ', Task.State^.Registers[C2]);
            WriteLn('RET: ', Task.State^.Registers[RET]);
            WriteLn('INSTANCEID: ', Task.State^.Registers[INSTANCEID]);
            WriteLn('PC: ', Task.State^.Registers[PC]);
            WriteLn('STORE1: ', Task.State^.Registers[STORE1]);
            WriteLn('STORE2: ', Task.State^.Registers[STORE2]);
            WriteLn('STORE3: ', Task.State^.Registers[STORE3]);
            WriteLn('STORE4: ', Task.State^.Registers[STORE4]);
            WriteLn('STORE5: ', Task.State^.Registers[STORE5]);
            Writeln(' ');}
        end else begin
            console.writeStringlnWND(' ', Handle);
            console.writeStringWND  ('  Task:        IDLE  |', Handle);
            console.writeStringWND  ('  SCHED:       ', Handle);
            console.writeintlnWND   (vm_scheduler.getActiveTask, Handle);
            console.writeStringlnWND(' ', Handle);
            console.writeStringWND  ('  OBJ1:        IDLE  |', Handle);
            console.writeStringlnWND('  OBJ2:        IDLE', Handle);
            console.writeStringWND  ('  C1:          IDLE  |', Handle);
            console.writeStringlnWND('  C2:          IDLE', Handle);
            console.writeStringlnWND('  RET:         IDLE', Handle);
            console.writeStringlnWND('  INSTANCEID:  IDLE', Handle);
            console.writeStringlnWND('  PC:          IDLE', Handle);
            console.writeStringWND  ('  STORE1:      IDLE  |', Handle);
            console.writeStringlnWND('  STORE2:      IDLE', Handle);
            console.writeStringWND  ('  STORE3:      IDLE  |', Handle);
            console.writeStringlnWND('  STORE4:      IDLE', Handle);
            console.writeStringlnWND('  STORE5:      IDLE', Handle);
            //console.writeHexWND(vm_instance.Task.State^.TASK_ID);    
        end;
    end;
end;

procedure run(Params : PParamList);
begin
    if Handle = 0 then begin
        Handle:= newWindow(20, 40, 63, 14, 'VMSTATE');
        clearWND(Handle);
        registerEventHandler(Handle, EVENT_CLOSE, void(@OnClose));
        registerEventHandler(Handle, EVENT_DRAW, void(@OnDraw));
    end;
end;

procedure init();
begin
    tracer.push_trace('vmstate.init');
    terminal.registerCommand('VMSTATE', @Run, 'View virtual-machine state.');
end;

end.

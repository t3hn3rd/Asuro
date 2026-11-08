// Copyright 2026 Aaron Hance
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

{ Shared I/O data contracts without console, driver or runtime dependencies.
  Types extracted from io.stdio by Kieron Morris. }
unit io.types;

interface
type
    { Output buffer — kalloc'd, growable }
    POutBuf = ^TOutBuf;
    TOutBuf = record
        buf : pchar;
        len : uint32;
        cap : uint32;
    end;

    { Parameter linked list }
    PParamList = ^TParamList;
    TParamList = record
        Param : pchar;
        Next  : PParamList;
    end;

    { Command buffer type }
    TCommandBuffer = array[0..1023] of byte;

    { Command method — receives params plus stdin (read), stdout (write), stderr (write) }
    TCommandMethod = procedure(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);

    { Command record }
    PCommand = ^TCommand;
    TCommand = record
        registered  : boolean;
        hidden      : boolean;
        command     : pchar;
        method      : TCommandMethod;
        description : pchar;
    end;

    { Halt callback }
    THaltCallback = procedure();

implementation
end.

{
    Prog->WASM->WASMCleanup - Tears down all WASURO VM allocations.

    Called via processmanager.bindResource when a WASM process exits
    or is killed.  Walks the PWASMProcessContext and kfrees every
    allocation made by the parser, VM setup, and host-function registry.

    Because wasuro/ is read-only, we perform the teardown Asuro-side
    by mirroring the known allocation patterns from the parser and VM.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit wasmcleanup;

interface

{ Signature matches TResourceCleanup = procedure(handle : void) }
procedure wasm_resource_cleanup(handle : void);

implementation

uses
    lmemorymanager,
    wasm.types.builtin,
    wasm.types.context,
    wasm.types.sections,
    wasm.types.heap,
    wasm.types.values,
    wasmshim;

{ ---- Heap teardown ---- }

procedure freeHeap(heap : PWasmHeap);
var
    i : uint32;
begin
    if heap = nil then exit;
    if heap^.Memory <> nil then begin
        for i := 0 to heap^.PageCount - 1 do begin
            if heap^.Memory[i] <> nil then
                kfree(void(heap^.Memory[i]));
        end;
        kfree(void(heap^.Memory));
    end;
    kfree(void(heap));
end;

{ ---- Stack teardown ---- }

procedure freeStack(stack : PWASMStack);
begin
    if stack = nil then exit;
    if stack^.Entries <> nil then
        kfree(void(stack^.Entries));
    kfree(void(stack));
end;

{ ---- Globals teardown ---- }

procedure freeGlobals(globals : PWASMGlobals);
begin
    if globals = nil then exit;
    if globals^.Globals <> nil then
        kfree(void(globals^.Globals));
    kfree(void(globals));
end;

{ ---- Tables teardown ---- }

procedure freeTables(tables : PWASMTables);
var
    i : uint32;
begin
    if tables = nil then exit;
    if tables^.Tables <> nil then begin
        for i := 0 to tables^.TableCount - 1 do begin
            if tables^.Tables[i].Elements <> nil then
                kfree(void(tables^.Tables[i].Elements));
        end;
        kfree(void(tables^.Tables));
    end;
    kfree(void(tables));
end;

{ ---- Data segments teardown ---- }

procedure freeDataSegments(ds : PWASMDataSegments);
var
    i : uint32;
begin
    if ds = nil then exit;
    if ds^.Segments <> nil then begin
        for i := 0 to ds^.SegmentCount - 1 do begin
            if ds^.Segments[i].Data <> nil then
                kfree(void(ds^.Segments[i].Data));
        end;
        kfree(void(ds^.Segments));
    end;
    kfree(void(ds));
end;

{ ---- Element segments teardown ---- }

procedure freeElementSegments(es : PWASMElementSegments);
var
    i : uint32;
begin
    if es = nil then exit;
    if es^.Segments <> nil then begin
        for i := 0 to es^.SegmentCount - 1 do begin
            if es^.Segments[i].FuncIndices <> nil then
                kfree(void(es^.Segments[i].FuncIndices));
        end;
        kfree(void(es^.Segments));
    end;
    kfree(void(es));
end;

{ ---- Type section teardown ---- }

procedure freeTypeSection(ts : PWASMTypeSection);
var
    i : uint32;
begin
    if ts = nil then exit;
    if ts^.Types <> nil then begin
        for i := 0 to ts^.TypeCount - 1 do begin
            if ts^.Types[i].ParamTypes <> nil then
                kfree(void(ts^.Types[i].ParamTypes));
            if ts^.Types[i].ReturnTypes <> nil then
                kfree(void(ts^.Types[i].ReturnTypes));
        end;
        kfree(void(ts^.Types));
    end;
    kfree(void(ts));
end;

{ ---- Import section teardown ---- }

procedure freeImportSection(is_ : PWASMImportSection);
var
    i : uint32;
begin
    if is_ = nil then exit;
    if is_^.Entries <> nil then begin
        for i := 0 to is_^.ImportCount - 1 do begin
            if is_^.Entries[i].ModuleName <> nil then
                kfree(void(is_^.Entries[i].ModuleName));
            if is_^.Entries[i].FieldName <> nil then
                kfree(void(is_^.Entries[i].FieldName));
        end;
        kfree(void(is_^.Entries));
    end;
    kfree(void(is_));
end;

{ ---- Function section teardown ---- }

procedure freeFunctionSection(fs : PWASMFunctionSection);
begin
    if fs = nil then exit;
    if fs^.Functions <> nil then
        kfree(void(fs^.Functions));
    kfree(void(fs));
end;

{ ---- Export section teardown ---- }

procedure freeExportSection(es : PWASMExportSection);
var
    i : uint32;
begin
    if es = nil then exit;
    if es^.Entries <> nil then begin
        for i := 0 to es^.ExportCount - 1 do begin
            if es^.Entries[i].Name <> nil then
                kfree(void(es^.Entries[i].Name));
        end;
        kfree(void(es^.Entries));
    end;
    kfree(void(es));
end;

{ ---- Code section teardown ---- }

procedure freeCodeSection(cs : PWASMCodeSection);
var
    i : uint32;
begin
    if cs = nil then exit;
    if cs^.Entries <> nil then begin
        for i := 0 to cs^.CodeCount - 1 do begin
            if cs^.Entries[i].Code <> nil then
                kfree(void(cs^.Entries[i].Code));
            if cs^.Entries[i].Locals.Locals <> nil then
                kfree(void(cs^.Entries[i].Locals.Locals));
        end;
        kfree(void(cs^.Entries));
    end;
    kfree(void(cs));
end;

{ ---- Memory section teardown ---- }

procedure freeMemorySection(ms : PWASMMemorySection);
begin
    if ms = nil then exit;
    if ms^.Memories <> nil then
        kfree(void(ms^.Memories));
    kfree(void(ms));
end;

{ ---- Resolved imports teardown ---- }
{ Note: ModuleName/FieldName pointers alias ImportSection strings,
  so we must NOT free them here — freeImportSection handles those. }

procedure freeResolvedImports(var ri : TWASMResolvedImports);
begin
    if ri.Imports <> nil then begin
        kfree(void(ri.Imports));
        ri.Imports := nil;
    end;
end;

{ ---- Host function registry teardown ---- }
{ Note: ModuleName/FieldName in registry entries are string constants
  from the WASI preview1 registration — they are NOT heap allocated. }

procedure freeHostFuncRegistry(var reg : TWASMHostFuncRegistry);
begin
    if reg.Entries <> nil then begin
        kfree(void(reg.Entries));
        reg.Entries := nil;
    end;
end;

{ ==== Top-level cleanup ==== }

procedure wasm_resource_cleanup(handle : void);
var
    shim : PProcessWASMShim;
    wctx : PWASMProcessContext;
begin
    if handle = nil then exit;
    shim := PProcessWASMShim(handle);
    wctx := shim^.WASMCtx;

    if wctx <> nil then begin
        { --- Execution state --- }
        freeHeap(wctx^.ExecutionState.Memory);
        freeStack(wctx^.ExecutionState.Operand_Stack);
        freeStack(wctx^.ExecutionState.Control_Stack);
        freeGlobals(wctx^.ExecutionState.Globals);
        freeTables(wctx^.ExecutionState.Tables);
        freeDataSegments(wctx^.ExecutionState.DataSegments);
        freeElementSegments(wctx^.ExecutionState.ElementSegments);

        { Flat code buffer (concatenation of all code entries) }
        if wctx^.ExecutionState.Code <> nil then
            kfree(void(wctx^.ExecutionState.Code));

        { ExecutionState.Locals points into CodeSection entries — no separate free }

        { --- Sections --- }
        freeTypeSection(wctx^.Sections.TypeSection);
        freeImportSection(wctx^.Sections.ImportSection);
        freeFunctionSection(wctx^.Sections.FunctionSection);
        freeExportSection(wctx^.Sections.ExportSection);
        freeCodeSection(wctx^.Sections.CodeSection);
        freeMemorySection(wctx^.Sections.MemorySection);

        { --- Import resolution & host function registry --- }
        freeResolvedImports(wctx^.ResolvedImports);
        freeHostFuncRegistry(wctx^.HostFuncRegistry);

        { --- The context record itself --- }
        kfree(void(wctx));
    end;

    { --- Shim-owned allocations --- }
    if shim^.FileBuffer <> nil then
        kfree(void(shim^.FileBuffer));

    if shim^.ArgBuf <> nil then
        kfree(void(shim^.ArgBuf));

    kfree(void(shim));
end;

end.

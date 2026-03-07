//  Copyright 2021 Aaron Hance
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
    Driver->Storage->GPT - GUID Partition Table support.

    Provides types and helpers for reading/validating GPT headers and
    partition entries.  The volume manager calls gpt_read_header to check
    for a protective MBR + GPT; on success it iterates the partition
    array to create volumes.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit gpt;

interface

uses
    crc,
    lmemorymanager,
    storagetypes,
    syslog,
    tracer,
    util;

const
    GPT_SIGNATURE : array[0..7] of char = ('E','F','I',' ','P','A','R','T');
    GPT_HEADER_LBA = 1;
    GPT_STANDARD_ENTRY_SIZE  = 128;
    GPT_STANDARD_ENTRY_COUNT = 128;

    { Protective MBR partition type }
    MBR_TYPE_GPT_PROTECTIVE = $EE;

type
    PGPTHeader = ^TGPTHeader;
    TGPTHeader = packed record
        Signature     : array[0..7] of char;  { 'EFI PART' }
        Revision      : uint32;
        HeaderSize    : uint32;
        HeaderCRC32   : uint32;
        Reserved      : uint32;
        MyLBA         : uint32;               { Low 32 bits of MyLBA (i386 only) }
        MyLBA_Hi      : uint32;
        AlternateLBA  : uint32;
        AlternateLBA_Hi : uint32;
        FirstUsableLBA: uint32;
        FirstUsable_Hi: uint32;
        LastUsableLBA : uint32;
        LastUsable_Hi : uint32;
        DiskGUID      : TGuid;
        PartEntryLBA  : uint32;
        PartEntry_Hi  : uint32;
        NumPartEntries: uint32;
        PartEntrySize : uint32;
        PartArrayCRC32: uint32;
        { Remainder of sector is zeroed }
    end;

    PGPTPartitionEntry = ^TGPTPartitionEntry;
    TGPTPartitionEntry = packed record
        TypeGUID      : TGuid;
        UniqueGUID    : TGuid;
        StartLBA      : uint32;
        StartLBA_Hi   : uint32;
        EndLBA        : uint32;
        EndLBA_Hi     : uint32;
        Attributes    : uint32;
        Attributes_Hi : uint32;
        Name          : array[0..35] of uint16;  { UTF-16LE partition name }
    end;

{ Check whether a GUID is all-zero (empty partition entry). }
function gpt_guid_is_zero(const g : TGuid) : boolean;

{ Validate a GPT header: check signature and CRC32.
  headerBuf must point to at least HeaderSize bytes.
  Returns true if the header is valid. }
function gpt_validate_header(header : PGPTHeader) : boolean;

{ Validate the partition entry array CRC.
  entryBuf must point to NumPartEntries * PartEntrySize bytes.
  Returns true if the CRC matches. }
function gpt_validate_entries(header : PGPTHeader; entryBuf : puint8) : boolean;

{ Read and validate the GPT header from a device.
  Tries primary (LBA 1) first, then backup (last LBA) if primary fails.
  On success, allocates and returns a header (caller must kfree).
  On failure, returns nil. }
function gpt_read_header(device : PStorage_Device) : PGPTHeader;

{ Read the partition entry array from disk.
  Allocates a buffer large enough for all entries (caller must kfree).
  Returns nil on failure. }
function gpt_read_entries(device : PStorage_Device; header : PGPTHeader) : PGPTPartitionEntry;

implementation

uses
    storagemanager;

function gpt_guid_is_zero(const g : TGuid) : boolean;
var
    i : uint32;
begin
    gpt_guid_is_zero := false;
    if g.Data1 <> 0 then exit;
    if g.Data2 <> 0 then exit;
    if g.Data3 <> 0 then exit;
    for i := 0 to 7 do
        if g.Data4[i] <> 0 then exit;
    gpt_guid_is_zero := true;
end;

function gpt_validate_header(header : PGPTHeader) : boolean;
var
    savedCRC : uint32;
    calcCRC  : uint32;
    i        : uint32;
begin
    push_trace('gpt.validate_header');
    gpt_validate_header := false;
    if header = nil then exit;

    { Check signature }
    for i := 0 to 7 do begin
        if header^.Signature[i] <> GPT_SIGNATURE[i] then begin
            syslog.logln('GPT', 'Signature mismatch.');
            exit;
        end;
    end;

    { Validate header CRC: zero the CRC field, compute, then restore }
    savedCRC := header^.HeaderCRC32;
    header^.HeaderCRC32 := 0;
    calcCRC := crc.CRC32(puint8(header), header^.HeaderSize);
    header^.HeaderCRC32 := savedCRC;

    if calcCRC <> savedCRC then begin
        syslog.logln('GPT', 'Header CRC32 mismatch.');
        exit;
    end;

    gpt_validate_header := true;
end;

function gpt_validate_entries(header : PGPTHeader; entryBuf : puint8) : boolean;
var
    totalSize : uint32;
    calcCRC   : uint32;
begin
    push_trace('gpt.validate_entries');
    gpt_validate_entries := false;
    if (header = nil) or (entryBuf = nil) then exit;

    totalSize := header^.NumPartEntries * header^.PartEntrySize;
    if totalSize = 0 then exit;

    calcCRC := crc.CRC32(entryBuf, totalSize);
    if calcCRC <> header^.PartArrayCRC32 then begin
        syslog.logln('GPT', 'Partition array CRC32 mismatch.');
        exit;
    end;

    gpt_validate_entries := true;
end;

{ Read a single sector into a newly allocated buffer. Returns nil on error. }
function read_sector(device : PStorage_Device; lba : uint32) : puint32;
var
    buf : puint32;
    err : TError;
begin
    read_sector := nil;
    buf := puint32(kalloc(device^.sectorSize));
    if buf = nil then exit;
    memset(uint32(buf), 0, device^.sectorSize);
    err := storagemanager.storage_read(device, lba, 1, buf);
    if err <> eNone then begin
        kfree(buf);
        exit;
    end;
    read_sector := buf;
end;

function gpt_read_header(device : PStorage_Device) : PGPTHeader;
var
    sectorBuf  : puint32;
    header     : PGPTHeader;
    backupLBA  : uint32;
begin
    push_trace('gpt.read_header');
    gpt_read_header := nil;
    if device = nil then exit;

    { Try primary header at LBA 1 }
    sectorBuf := read_sector(device, GPT_HEADER_LBA);
    if sectorBuf <> nil then begin
        header := PGPTHeader(sectorBuf);
        if gpt_validate_header(header) then begin
            { Copy to a tightly-sized allocation }
            gpt_read_header := PGPTHeader(kalloc(sizeof(TGPTHeader)));
            if gpt_read_header <> nil then
                memcpy(uint32(header), uint32(gpt_read_header), sizeof(TGPTHeader));
            kfree(sectorBuf);
            exit;
        end;
        { Primary invalid — remember backup LBA before freeing }
        backupLBA := PGPTHeader(sectorBuf)^.AlternateLBA;
        kfree(sectorBuf);
    end else begin
        { Can't even read LBA 1 — try last sector as backup }
        if device^.maxSectorCount > 0 then
            backupLBA := device^.maxSectorCount - 1
        else
            exit;
    end;

    { Try backup header }
    if backupLBA = 0 then exit;
    syslog.logln('GPT', 'Primary header invalid, trying backup.');
    sectorBuf := read_sector(device, backupLBA);
    if sectorBuf = nil then exit;
    header := PGPTHeader(sectorBuf);
    if gpt_validate_header(header) then begin
        gpt_read_header := PGPTHeader(kalloc(sizeof(TGPTHeader)));
        if gpt_read_header <> nil then
            memcpy(uint32(header), uint32(gpt_read_header), sizeof(TGPTHeader));
    end;
    kfree(sectorBuf);
end;

function gpt_read_entries(device : PStorage_Device; header : PGPTHeader) : PGPTPartitionEntry;
var
    totalSize    : uint32;
    sectorsNeeded: uint32;
    buf          : puint32;
    err          : TError;
begin
    push_trace('gpt.read_entries');
    gpt_read_entries := nil;
    if (device = nil) or (header = nil) then exit;
    if header^.NumPartEntries = 0 then exit;
    if header^.PartEntrySize = 0 then exit;

    totalSize := header^.NumPartEntries * header^.PartEntrySize;
    sectorsNeeded := (totalSize + device^.sectorSize - 1) div device^.sectorSize;

    buf := puint32(kalloc(sectorsNeeded * device^.sectorSize));
    if buf = nil then exit;
    memset(uint32(buf), 0, sectorsNeeded * device^.sectorSize);

    err := storagemanager.storage_read(device, header^.PartEntryLBA, sectorsNeeded, buf);
    if err <> eNone then begin
        kfree(buf);
        exit;
    end;

    { Validate CRC }
    if not gpt_validate_entries(header, puint8(buf)) then begin
        syslog.logln('GPT', 'Partition entry array CRC mismatch.');
        kfree(buf);
        exit;
    end;

    gpt_read_entries := PGPTPartitionEntry(buf);
end;

end.

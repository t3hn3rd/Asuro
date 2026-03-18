unit driver.storage.fs.fat32;

interface

uses
    boot.mgr,
    driver.storage.fs.mgr,
    driver.storage.types;

procedure init;
procedure FAT32ReleaseVolumeState(volume : PStorage_Volume);

implementation

uses
    io.syslog,
    core.util,
    driver.storage.fs.fat32.vol,
    driver.storage.fs.fat32.core,
    driver.storage.fs.fat32.transfer;

var
    filesystem : TFilesystem;

procedure FAT32ReleaseVolumeState(volume : PStorage_Volume);
begin
    FAT32ReleaseVolumeCtx(volume);
end;

procedure init;
begin
    io.syslog.logln('FAT32', 'init: registering FAT32 filesystem');
    memset(uint32(@filesystem), 0, sizeof(TFilesystem));
    filesystem.sName := 'FAT32';
    filesystem.system_id := $0B;
    filesystem.readDirCallback := @FAT32ReadDirectory;
    filesystem.createDirCallback := @FAT32CreateDirectory;
    filesystem.createCallback := @create_volume;
    filesystem.createAsyncCallback := @create_volume_async;
    filesystem.detectCallback := @detect_volumes;
    filesystem.readOffsetCallback := @FAT32ReadFileAtOffset;
    filesystem.writeOffsetCallback := @FAT32WriteFileAtOffset;
    filesystem.readOffsetAsyncCallback := @FAT32ReadFileAtOffsetAsync;
    filesystem.writeOffsetAsyncCallback := @FAT32WriteFileAtOffsetAsync;
    filesystem.fileSizeCallback := @FAT32GetFileSize;
    filesystem.identifyCallback := @identify_volume;
    filesystem.deleteFileCallback := @FAT32DeleteFile;
    filesystem.deleteDirCallback := @FAT32DeleteDir;
    filesystem.renameFileCallback := @FAT32RenameFile;
    filesystem.openFileCallback := @FAT32OpenFile;
    filesystem.closeFileCallback := @FAT32CloseFile;
    filesystem.createDirAsyncCallback := nil;
    filesystem.readDirAsyncCallback := nil;
    filesystem.formatParamFlags := FS_FORMAT_PARAM_CLUSTER_SIZE;

    FAT32VolInit(@filesystem);
    driver.storage.fs.mgr.register_filesystem(@filesystem);
end;

initialization
    boot.mgr.registerBoot('driver.storage.fs.fat32', @init, 'FAT32 Filesystem', 'driver.storage.fs.mgr');

end.

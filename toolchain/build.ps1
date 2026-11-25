<#
.SYNOPSIS
    Builds Asuro through Ninja inside the Docker builder.

.DESCRIPTION
    Selects a build target, architecture, and profile, then generates the Ninja dependency graph.
    Ninja calls this script with --stage to run individual steps using the selected profile's configuration.
    An ISO build publishes Asuro.iso at the repository root.

.EXAMPLE
    docker compose run --rm builder iso --arch x86 --profile test:complex

.EXAMPLE
    docker compose run --rm builder docs

.NOTES
    Defaults to all, x86, and release. ASURO_ARCH, UNIT_TESTS, and COMPLEX_TESTS can override the defaults.
#>
#Requires -Version 7.4

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

Set-Location -LiteralPath (Join-Path $PSScriptRoot '..')
$root = (Get-Location).Path
[Environment]::CurrentDirectory = $root
$launcher = 'toolchain/build.ps1'
$lvgl = 'build/vendor/v9.2.2/lvgl'
$wasuro = 'build/vendor/wasuro'
$lvglIntegration = 'src/driver/video/lvgl'
$iconSizes = 32, 64, 128
$nativeFlags = @(
    '-m32', '-march=i686', '-ffreestanding', '-fno-builtin',
    '-fno-stack-protector', '-fno-pic', '-fno-pie', '-O2', '-DLV_CONF_INCLUDE_SIMPLE'
)
$profiles = @{
    'release'      = @('-O3')
    'debug'        = @('-O-', '-gw', '-g', '-gl')
    'test:minimal' = @('-O3', '-gw', '-g', '-gl', '-dUNIT_TESTS')
    'test:complex' = @('-O3', '-gw', '-g', '-gl', '-dUNIT_TESTS', '-dUNIT_TESTS_COMPLEX')
}

# Run a native tool and turn a nonzero exit code into a build error.
function Invoke-Tool {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Program exited with code $LASTEXITCODE."
    }
}

# Create a build directory and any missing parents.
function New-BuildDirectory([string]$Path) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($Path))
}

# Replace a generated file only when its contents change so Ninja can reuse its dependents.
function Write-BuildFile([string]$Path, [string]$Content) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    if ([IO.File]::Exists($fullPath) -and [IO.File]::ReadAllText($fullPath) -ceq $Content) {
        return
    }
    New-BuildDirectory (Split-Path -Parent $fullPath)
    $temporary = "$fullPath.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, $Content)
        [IO.File]::Move($temporary, $fullPath, $true)
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

# List repository-relative file paths for Ninja and the source inventories.
function Get-RelativePaths([string[]]$Directories, [string[]]$Extensions) {
    Get-ChildItem -LiteralPath $Directories -File -Recurse |
        Where-Object { !$Extensions -or $_.Extension -in $Extensions } |
        ForEach-Object { [IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/') } |
        Sort-Object -CaseSensitive -Unique
}

# Refresh the profile’s source mirror while preserving generated Pascal files.
function Sync-Sources {
    New-BuildDirectory "$buildPath/source/src/arch/$arch"
    New-BuildDirectory "$buildPath/source/wasuro"
    Invoke-Tool rsync @(
        '-a', '--checksum', '--delete', '--exclude=/core/core.version.pas',
        '--exclude=/boot/dangling_units.inc', '--exclude=/arch/',
        'src/', "$buildPath/source/src/"
    )
    Invoke-Tool rsync @('-a', '--checksum', '--delete', "src/arch/$arch/", "$buildPath/source/src/arch/$arch/")
    Invoke-Tool rsync @('-a', '--checksum', '--delete', "$wasuro/", "$buildPath/source/wasuro/")
}

# Fetch Wasuro and LVGL when their caches are absent.
function Initialize-Dependencies {
    if (!(Test-Path -LiteralPath $wasuro)) {
        New-BuildDirectory 'build/vendor'
        $scratch = Join-Path 'build/vendor' ("wasuro." + [Guid]::NewGuid().ToString('N'))
        try {
            Invoke-Tool git @(
                'clone', '--depth', '1', '--branch', 'develop', '--filter=blob:none',
                '--sparse', 'https://gitea.spexeah.com/Spexeah/Wasuro.git', $scratch
            )
            Invoke-Tool git @('-C', $scratch, 'sparse-checkout', 'set', 'src/wasm')
            Move-Item -LiteralPath "$scratch/src/wasm" -Destination $wasuro
        } finally {
            if (Test-Path -LiteralPath $scratch) {
                Remove-Item -LiteralPath $scratch -Recurse -Force
            }
        }
    }
    if (!(Test-Path -LiteralPath "$lvgl/src")) {
        New-BuildDirectory (Split-Path -Parent $lvgl)
        Invoke-Tool git @('clone', '--depth', '1', '--branch', 'v9.2.2', 'https://github.com/lvgl/lvgl.git', $lvgl)
    }
}

# Record Pascal input contents so Ninja can see changes even when timestamps collide.
function Write-PascalInputs([string[]]$Sources) {
    $hashes = [ordered]@{}
    foreach ($file in (Get-FileHash -LiteralPath $Sources -Algorithm SHA256)) {
        $path = [IO.Path]::GetRelativePath($root, $file.Path).Replace('\', '/')
        $hashes[$path] = $file.Hash
    }
    Write-BuildFile "$buildPath/pascal-inputs.json" (ConvertTo-Json -InputObject $hashes)
}

# Remove both compiler artifacts so FPC has to read the unit's source again.
function Remove-PascalUnit([string]$Name) {
    $unit = $Name.ToLowerInvariant()
    [IO.File]::Delete("$buildPath/units/$unit.ppu")
    [IO.File]::Delete("$buildPath/units/$unit.o")
}

# Prune cached units for deleted sources and invalidate incomplete compiler outputs.
function Update-UnitInventory([string[]]$Sources) {
    $manifest = "$buildPath/units.manifest"
    $units = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($source in $Sources) { [void]$units.Add($source) }

    if (Test-Path -LiteralPath $manifest) {
        foreach ($source in [IO.File]::ReadLines($manifest)) {
            if ($source.EndsWith('.pas') -and !$units.Contains($source)) {
                Remove-PascalUnit ([IO.Path]::GetFileNameWithoutExtension($source))
            }
        }
    }
    Write-BuildFile $manifest (($Sources -join "`n") + "`n")

    if (Test-Path -LiteralPath "$buildPath/pascal-objects.rsp") {
        foreach ($object in [IO.File]::ReadLines("$buildPath/pascal-objects.rsp")) {
            $ppu = [IO.Path]::ChangeExtension($object, '.ppu')
            if (![IO.File]::Exists($object) -or ![IO.File]::Exists($ppu)) {
                [IO.File]::Delete($object)
                [IO.File]::Delete($ppu)
                [IO.File]::Delete("$buildPath/pascal.stamp")
            }
        }
    }
}

# Generate the Pascal unit containing build and source metadata.
function Write-Version {
    $version = Invoke-Tool git @('describe', '--tags', '--always')
    $revision = Invoke-Tool git @('rev-parse', '--short=8', 'HEAD')
    $major = $minor = $patch = 0
    $release = ''
    if ($version -match '^v?([0-9]+)\.([0-9]+)\.([0-9]+)(.*)$') {
        $major, $minor, $patch = $Matches[1], $Matches[2], $Matches[3]
        $release = $Matches[4].TrimStart('-')
    }
    $sources = @([IO.File]::ReadLines("$buildPath/units.manifest") | Where-Object { $_ -match '^src/.*\.pas$' })
    $lines = 0
    foreach ($source in $sources) {
        foreach ($line in [IO.File]::ReadLines($source)) { $lines++ }
    }
    $drivers = @($sources -like 'src/driver/*').Count
    $hashes = (Invoke-Tool md5sum $sources) -join "`n"
    $checksum = [Convert]::ToHexString([Security.Cryptography.MD5]::HashData(
        [Text.Encoding]::UTF8.GetBytes($hashes + "`n")
    )).ToLowerInvariant()
    $now = Get-Date
    $fpcVersion = Invoke-Tool fpc @('-iV')
    $nasmVersion = (Invoke-Tool nasm @('-v') -split ' ')[2]
    $makeVersion = ((Invoke-Tool make @('--version'))[0] -split ' ')[2]
    Write-BuildFile "$buildPath/source/src/core/core.version.pas" @"
unit core.version;

interface

const
    VERSION = '$version';
    VERSION_MAJOR = '$major';
    VERSION_MINOR = '$minor';
    VERSION_SUB = '$patch';
    REVISION = '$revision';
    RELEASE = '$release';
    LINE_COUNT = $lines;
    FILE_COUNT = $($sources.Count);
    DRIVER_COUNT = $drivers;
    FPC_VERSION = '$fpcVersion';
    NASM_VERSION = '$nasmVersion';
    MAKE_VERSION = '$makeVersion';
    COMPILE_DATE = '$($now.ToString('dd/MM/yy'))';
    COMPILE_TIME = '$($now.ToString('HH:mm:ss'))';
    CHECKSUM = '$checksum';

implementation

end.
"@
}

# Run Moderne in a temporary repository and keep its detailed output in the profile log.
function Write-BootUnits {
    Sync-Sources
    $work = [IO.Directory]::CreateTempSubdirectory('asuro-boot-')
    $previousOptions = $env:PASCAL_JAVA_OPTIONS
    $log = "$buildPath/boot-units.log"
    try {
        $env:PASCAL_JAVA_OPTIONS = '-Dpascal.sourceRoots=src -Dpascal.failOnParseError=true'
        Invoke-Tool rsync @('-a', '--exclude=/boot/dangling_units.inc', "$buildPath/source/src/", "$($work.FullName)/src/")
        Invoke-Tool git @('-C', $work.FullName, 'init', '-q')
        Invoke-Tool git @('-C', $work.FullName, 'remote', 'add', 'origin', 'https://gitea.spexeah.com/Spexeah/Asuro.git')
        Invoke-Tool pascal-lst @($work.FullName) *> $log
        Invoke-Tool mod @(
            'run', $work.FullName, '--recipe', 'org.openrewrite.pascal.boot.FindDanglingUnits',
            '--recipe-option', "architecture=$arch"
        ) *>> $log
        $staged = Join-Path $work.FullName 'dangling_units.inc'
        Invoke-Tool dangling-include @($work.FullName, $staged) *>> $log
        $content = [IO.File]::ReadAllText($staged)
        $destination = "$buildPath/source/src/boot/dangling_units.inc"
        Write-BuildFile $destination $content
        $count = [regex]::Matches($content, '(?m)^\s*,\s*\S').Count
        Write-Host "$count Dangling units written to $destination"
    } catch {
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 40 | Write-Host }
        throw "Dangling unit generation failed. See $log. $_"
    } finally {
        $env:PASCAL_JAVA_OPTIONS = $previousOptions
        Remove-Item -LiteralPath $work.FullName -Recurse -Force
    }
}

# Walk FPC’s compiled-unit dependencies from asuro to get the objects for the kernel link.
function Get-PascalObjects {
    $ppus = @(Get-ChildItem -LiteralPath "$buildPath/units" -Filter '*.ppu' -File)
    $units = @{}
    $current = $null
    foreach ($line in (Invoke-Tool ppudump (@('-VIM') + $ppus.FullName))) {
        switch -Regex ($line) {
            '^Analyzing (.+\.ppu) \(' {
                $current = @{
                    Dependencies = [Collections.Generic.List[string]]::new()
                    Objects = [Collections.Generic.List[string]]::new()
                }
                $units[[IO.Path]::GetFileNameWithoutExtension($Matches[1])] = $current
            }
            '^\s*Uses unit:\s+(\S+)' { $current.Dependencies.Add($Matches[1]) }
            '^\s*Link unit object file:\s+(\S+)' { $current.Objects.Add($Matches[1]) }
        }
    }
    $pending = [Collections.Generic.Queue[string]]::new()
    $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $objects = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $pending.Enqueue('asuro')
    while ($pending.Count) {
        $name = $pending.Dequeue()
        if (!$visited.Add($name)) { continue }
        if (!$units.ContainsKey($name)) { throw "Missing compiled Pascal unit: $name" }
        foreach ($dependency in $units[$name].Dependencies) { $pending.Enqueue($dependency) }
        foreach ($object in $units[$name].Objects) {
            $path = [IO.Path]::GetFullPath("$buildPath/units/$object")
            if (![IO.File]::Exists($path)) { throw "Missing Pascal link input: $path" }
            [void]$objects.Add($path)
        }
    }
    if (!$objects.Count) { throw 'No Pascal objects reachable from asuro.' }
    $objects | Sort-Object -CaseSensitive
}

# Keep the effective FPC options in one place for compilation and cache validation.
function Get-PascalOptions {
    @(
        '-Cn', '-Aelf', '-n', '-v0e', '-OpPENTIUM3', '-Si', '-Sc', '-Sg', '-Xd', '-CX', '-XXs',
        '-CfSSE', '-CfSSE2', '-Rintel', '-Pi386', '-Tlinux'
    ) + $profiles[$buildProfile]
}

# Compile the kernel units and refresh the linker list and rebuild stamp.
function Build-Pascal {
    Sync-Sources
    $includePaths = @()
    foreach ($directory in @("$buildPath/source/src", "$buildPath/source/wasuro")) {
        $includePaths += "-Fu$([IO.Path]::GetFullPath($directory))"
        $includePaths += @(Get-ChildItem -LiteralPath $directory -Directory -Recurse |
            Sort-Object FullName | ForEach-Object { "-Fu$($_.FullName)" })
    }

    $absolute = [IO.Path]::GetFullPath($buildPath)
    $options = @($config.PascalOptions) + @("-FE$absolute/", "-FU$absolute/units/") + $includePaths
    $inputs = Get-Content -LiteralPath "$buildPath/pascal-inputs.json" -Raw | ConvertFrom-Json -AsHashtable
    $versionSource = "$buildPath/source/src/core/core.version.pas"
    $bootInclude = "$buildPath/source/src/boot/dangling_units.inc"
    foreach ($generated in @($versionSource, $bootInclude)) {
        $inputs[$generated] = (Get-FileHash -LiteralPath $generated -Algorithm SHA256).Hash
    }

    $statePath = "$buildPath/pascal-cache.json"
    $signature = ConvertTo-Json -Compress -InputObject @($config.Compiler, $options)
    $rebuildAll = $true
    if ([IO.File]::Exists($statePath)) {
        $previous = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $rebuildAll = $previous.Signature -cne $signature
        if (!$rebuildAll) {
            $changed = @($inputs.Keys | Where-Object { $inputs[$_] -cne $previous.Inputs[$_] })
            $removedIncludes = @($previous.Inputs.Keys |
                Where-Object { $_.EndsWith('.inc') -and !$inputs.Contains($_) })
            $rebuildAll = $removedIncludes.Count -gt 0
            foreach ($path in $changed) {
                if ($path -ceq $bootInclude) {
                    Remove-PascalUnit 'boot.mgr'
                } elseif ($path.EndsWith('.pas', [StringComparison]::OrdinalIgnoreCase)) {
                    Remove-PascalUnit ([IO.Path]::GetFileNameWithoutExtension($path))
                } elseif ($path.EndsWith('.inc', [StringComparison]::OrdinalIgnoreCase)) {
                    # Pascal includes can be used by more than one unit.
                    $rebuildAll = $true
                }
            }
        }
    }
    if ($rebuildAll) {
        Write-Host 'Rebuilding Pascal units because the compiler configuration or includes changed.'
        # Unreachable units can become reachable later, so discard their old outputs as well.
        Get-ChildItem -LiteralPath "$buildPath/units" -File |
            Where-Object { $_.Extension -in '.ppu', '.o' } |
            ForEach-Object { [IO.File]::Delete($_.FullName) }
        $options = @('-B') + $options
    }

    # Only a complete compiler run can validate the cache for the next build.
    [IO.File]::Delete($statePath)
    [IO.File]::Delete("$buildPath/pascal.stamp")
    Invoke-Tool fpc ($options + "$buildPath/source/src/asuro.pas")
    $objects = @(Get-PascalObjects)
    Write-BuildFile "$buildPath/pascal-objects.rsp" (($objects -join "`n") + "`n")
    Write-BuildFile $statePath (ConvertTo-Json -Depth 4 -InputObject @{
        Signature = $signature
        Inputs = $inputs
    })
    [IO.File]::WriteAllText("$buildPath/pascal.stamp", '')
}

# Build the INITFINAL table from the same Pascal objects used by the linker.
function Build-InitCalls {
    $objects = [IO.File]::ReadAllLines("$buildPath/pascal-objects.rsp")
    $symbols = @(Invoke-Tool nm (@('--defined-only') + $objects) | ForEach-Object {
        if ($_ -match '^\s*[0-9a-fA-F]+\s+T\s+(INIT\$_\$\S+)') { $Matches[1] }
    })
    $lines = @(
        'typedef void (*initproc_t)(void);'
        'typedef struct __attribute__((packed)) { initproc_t init; initproc_t fini; } TInitFinalRec;'
    )
    for ($i = 0; $i -lt $symbols.Count; $i++) {
        $lines += 'extern void initcall_{0}(void) asm("{1}");' -f $i, $symbols[$i]
    }
    if ($symbols.Count) {
        $lines += 'struct __attribute__((packed)) {{ int count; TInitFinalRec procs[{0}]; }} INITFINAL = {{ {0}, {{' -f $symbols.Count
        for ($i = 0; $i -lt $symbols.Count; $i++) {
            $lines += '    {{ initcall_{0}, (initproc_t)0 }},' -f $i
        }
        $lines += '} };'
    } else {
        $lines += 'struct __attribute__((packed)) { int count; } INITFINAL = { 0 };'
    }
    Write-BuildFile "$buildPath/initcalls.c" (($lines -join "`n") + "`n")
    Invoke-Tool gcc @('-m32', '-c', '-fno-pic', '-ffreestanding', '-o', "$buildPath/initcalls.o", "$buildPath/initcalls.c")
    Write-Host "Found $($symbols.Count) unit initialization sections."
}

# Map a native source to its object path under the selected profile.
function Get-NativeObject([string]$Path) {
    "$buildPath/native/$([IO.Path]::ChangeExtension($Path, '.o'))"
}

# Return the generated icon objects needed by the kernel link.
function Get-IconObjects {
    foreach ($size in $iconSizes) { "$buildPath/icons/asuro_icons_$size.o" }
}

# Generate and compile the three icon font sizes.
function Build-Icons {
    New-BuildDirectory "$buildPath/icons"
    Invoke-Tool python3 @('toolchain/gen_file_icons.py', "$buildPath/icons", '--font-dir', 'assets/embedded')
    foreach ($size in $iconSizes) {
        Invoke-Tool gcc ($nativeFlags + @(
            '-I', (Split-Path -Parent $lvgl), '-I', $lvgl, '-I', $lvglIntegration,
            '-c', "$buildPath/icons/asuro_icons_$size.c", '-o', "$buildPath/icons/asuro_icons_$size.o"
        ))
    }
}

# Link the Pascal, assembly, and native objects into the kernel image.
function Link-Kernel {
    $objects = [IO.File]::ReadAllLines("$buildPath/pascal-objects.rsp")
    $libgcc = Invoke-Tool gcc @('-m32', '-print-libgcc-file-name')
    $strip = @()
    if ($buildProfile -eq 'release') { $strip = @('-s') }
    Invoke-Tool ld (@('-m', 'elf_i386') + $strip + @(
        '--gc-sections', '--no-warn-execstack', '-T', 'toolchain/linker.script',
        '-o', "$buildPath/kernel.bin", "$buildPath/stub.o"
    ) + $objects + @("$buildPath/splash_tga.o", "$buildPath/initcalls.o") + @(Get-IconObjects) +
        @('--start-group', "$buildPath/liblvgl.a", $libgcc, '--end-group'))
}

# Stage the ISO source tree and add the linked kernel before packaging.
function Package-Iso {
    $stage = [IO.Directory]::CreateTempSubdirectory('asuro-iso-')
    try {
        Invoke-Tool rsync @('-a', 'assets/iso/', "$($stage.FullName)/")
        Copy-Item -LiteralPath "$buildPath/kernel.bin" -Destination "$($stage.FullName)/boot/asuro.bin"
        Invoke-Tool grub-mkrescue @('-o', "$buildPath/Asuro.iso", $stage.FullName)
    } finally {
        Remove-Item -LiteralPath $stage.FullName -Recurse -Force
    }
}

# Dispatch a single Ninja stage using the configuration of its build directory.
function Invoke-Stage {
    param(
        [ValidateSet('docs', 'version', 'boot-units', 'compile-pascal', 'stub', 'splash', 'lvgl', 'icons', 'initcalls', 'link', 'iso')]
        [string]$Step,

        [ValidatePattern('^build/(?:docs|x86/(?:debug|release|test-minimal|test-complex))$')]
        [string]$Path
    )

    if ($Step -eq 'docs') {
        Invoke-Tool python3 @('-m', 'mkdocs', 'build', '--strict')
        return
    }
    if ($Path -eq 'build/docs') {
        throw "Stage '$Step' requires an architecture and build profile."
    }
    $buildPath = $Path
    $config = Get-Content -LiteralPath "$buildPath/toolchain.json" -Raw | ConvertFrom-Json
    $arch, $buildProfile = $config.Arch, $config.Profile
    if ($arch -cne 'x86' -or !$buildProfile -or !$profiles.ContainsKey($buildProfile) -or
        $buildPath -cne "build/$arch/$($buildProfile.Replace(':', '-'))") {
        throw "Toolchain configuration does not match $buildPath."
    }

    switch ($Step) {
        'version'        { Write-Version }
        'boot-units'     { Write-BootUnits }
        'compile-pascal' { Build-Pascal }
        'stub'           { Invoke-Tool nasm @('-f', 'elf', "src/arch/$arch/boot/stub.asm", '-o', "$buildPath/stub.o") }
        'splash'         { Invoke-Tool nasm @('-f', 'elf', 'src/boot/splash_tga.asm', '-o', "$buildPath/splash_tga.o") }
        'lvgl' {
            $objects = @([IO.File]::ReadLines("$buildPath/native.manifest") | ForEach-Object { Get-NativeObject $_ })
            [IO.File]::Delete("$buildPath/liblvgl.a")
            Invoke-Tool ar (@('rcs', "$buildPath/liblvgl.a") + $objects)
        }
        'icons'          { Build-Icons }
        'initcalls'      { Build-InitCalls }
        'link'           { Link-Kernel }
        'iso'            { Package-Iso }
        default          { throw "Unknown build stage: $Step" }
    }
}

# Escape paths for use as Ninja input or output tokens.
function ConvertTo-NinjaPaths([string[]]$Paths) {
    ($Paths | ForEach-Object { $_.Replace('$', '$$').Replace(' ', '$ ').Replace(':', '$:') }) -join ' '
}

# Describe the selected build’s outputs and dependencies in Ninja syntax.
function Write-Graph([string[]]$Pascal, [string[]]$Native, [bool]$DocsOnly) {
    $graph = [Collections.Generic.List[string]]::new()
    $graph.AddRange([string[]]@(
        'ninja_required_version = 1.10'
        "builddir = $buildPath"
        'rule stage'
        '  command = pwsh -NoProfile -File ' + $launcher + ' --stage $step ' + $buildPath
        '  description = $step'
        '  restat = 1'
    ))
    # Attach the launcher as an input because it implements each stage.
    function Add-Edge([string[]]$Outputs, [string[]]$Inputs, [string]$Step) {
        $graph.Add("build $(ConvertTo-NinjaPaths $Outputs): stage $(ConvertTo-NinjaPaths ($Inputs + $launcher))")
        $graph.Add("  step = $Step")
    }

    $docsRoot = 'build/docs'
    $docs = @(Get-RelativePaths @('doc'))
    Write-BuildFile "$docsRoot/files.manifest" (($docs -join "`n") + "`n")
    Add-Edge @("$docsRoot/site/index.html") (@('mkdocs.yml', "$docsRoot/files.manifest") + $docs) 'docs'
    $graph.Add("build docs: phony $docsRoot/site/index.html")

    if (!$DocsOnly) {
        $config = "$buildPath/toolchain.json"
        $units = "$buildPath/units.manifest"
        $pascalInputs = "$buildPath/pascal-inputs.json"
        $version = "$buildPath/source/src/core/core.version.pas"
        $dangling = "$buildPath/source/src/boot/dangling_units.inc"
        $stamp = "$buildPath/pascal.stamp"
        $objects = "$buildPath/pascal-objects.rsp"
        $kernel = "$buildPath/kernel.bin"
        $iso = "$buildPath/Asuro.iso"

        $graph.AddRange([string[]]@(
            'rule cc'
            "  command = gcc $($nativeFlags -join ' ') -I $lvgl -I $(Split-Path -Parent $lvgl) -I $lvglIntegration " +
                '-MMD -MF $out.d -c $in -o $out'
            '  description = CC $in'
            '  depfile = $out.d'
            '  deps = gcc'
        ))
        Add-Edge @($version) @($config, $units, "$buildPath/revision") 'version'
        Add-Edge @($dangling) (@($units, $version, $pascalInputs) + $Pascal) 'boot-units'
        Add-Edge @($stamp, $objects) (@($units, $config, $dangling, $version, $pascalInputs) + $Pascal) 'compile-pascal'
        Add-Edge @("$buildPath/stub.o") @("src/arch/$arch/boot/stub.asm", $config) 'stub'
        Add-Edge @("$buildPath/splash_tga.o") @(
            'src/boot/splash_tga.asm', 'assets/embedded/asuro.tga', 'assets/embedded/teapot.tga', $config
        ) 'splash'

        $nativeObjects = @(foreach ($source in $Native) {
            $object = Get-NativeObject $source
            $graph.Add("build $(ConvertTo-NinjaPaths @($object)): cc $(ConvertTo-NinjaPaths @($source)) | $config")
            $object
        })
        Add-Edge @("$buildPath/liblvgl.a") (@("$buildPath/native.manifest", $config) + $nativeObjects) 'lvgl'
        $headers = @(Get-RelativePaths @($lvgl, $lvglIntegration) @('.h'))
        $icons = @(Get-IconObjects)
        Add-Edge $icons (@($config, 'toolchain/gen_file_icons.py', 'assets/embedded/fa-solid-900.ttf') + $headers) 'icons'
        Add-Edge @("$buildPath/initcalls.o") @($stamp, $objects) 'initcalls'
        Add-Edge @($kernel) (@(
            $stamp, $objects, "$buildPath/initcalls.o", "$buildPath/stub.o",
            "$buildPath/splash_tga.o", "$buildPath/liblvgl.a", 'toolchain/linker.script', $config
        ) + $icons) 'link'
        $isoFiles = @(Get-RelativePaths @('assets/iso'))
        Write-BuildFile "$buildPath/iso.manifest" (($isoFiles -join "`n") + "`n")
        Add-Edge @($iso) (@($kernel, "$buildPath/iso.manifest") + $isoFiles) 'iso'
        $graph.Add("build compile: phony $kernel")
        $graph.Add("build iso: phony $iso")
        $graph.Add('build all: phony iso docs')
        $graph.Add('default all')
    } else {
        $graph.Add('default docs')
    }
    Write-BuildFile "$buildPath/build.ninja" (($graph -join "`n") + "`n")
}

# Parse the public Compose command syntax and environment defaults.
function Get-BuildOptions {
    param([string[]]$Arguments)

    $options = @{
        Task = 'all'
        Arch = if ($env:ASURO_ARCH) { $env:ASURO_ARCH } else { 'x86' }
        BuildProfile = if ($env:COMPLEX_TESTS -eq '1') { 'test:complex' }
            elseif ($env:UNIT_TESTS -eq '1') { 'test:minimal' } else { 'release' }
    }

    $index = 0
    if ($Arguments.Count -and $Arguments[0] -notlike '-*') {
        $options.Task = $Arguments[0]
        $index++
    }
    while ($index -lt $Arguments.Count) {
        $flag = $Arguments[$index++]
        switch ($flag) {
            { $_ -in '--arch', '--profile' } {
                if ($index -ge $Arguments.Count -or
                    !$Arguments[$index] -or $Arguments[$index] -like '-*') {
                    throw "$flag requires a value."
                }

                $value = $Arguments[$index++]
                if ($flag -eq '--arch') { $options.Arch = $value }
                else { $options.BuildProfile = $value }
            }
            default { throw "Unknown build argument: $flag" }
        }
    }
    return $options
}

# Prepare one build configuration, run Ninja, and publish the root ISO when requested.
function Invoke-Build {
    param(
        [ValidateSet('compile', 'iso', 'docs', 'all')]
        [string]$Task,

        [ValidateSet('x86', IgnoreCase = $false)]
        [string]$Arch,

        [ValidateSet('debug', 'test:minimal', 'test:complex', 'release')]
        [string]$BuildProfile
    )

    $Task = $Task.ToLowerInvariant()
    if (!(Get-Command ninja -ErrorAction SilentlyContinue)) {
        throw 'Ninja is missing. Rebuild the Docker builder image.'
    }
    if ($task -eq 'docs') {
        $buildPath = 'build/docs'
        Write-Graph @() @() $true
        Invoke-Tool ninja @('-f', "$buildPath/build.ninja", 'docs')
        return
    }
    $buildProfile = $buildProfile.ToLowerInvariant()
    $buildPath = "build/$arch/$($buildProfile.Replace(':', '-'))"
    New-BuildDirectory "$buildPath/units"
    Initialize-Dependencies
    $pascal = @(Get-RelativePaths @('src', $wasuro) @('.pas', '.inc') | Where-Object {
        ($_ -notlike 'src/arch/*' -or $_ -like "src/arch/$arch/*") -and
        $_ -notin @('src/core/core.version.pas', 'src/boot/dangling_units.inc')
    })
    Update-UnitInventory $pascal
    Write-PascalInputs $pascal
    $native = @(Get-RelativePaths @("$lvgl/src", $lvglIntegration) @('.c') |
        Where-Object { $_ -notmatch '/test/' })
    Write-BuildFile "$buildPath/native.manifest" (($native -join "`n") + "`n")
    Write-BuildFile "$buildPath/revision" ((Invoke-Tool git @('rev-parse', 'HEAD')) + "`n")
    $config = [ordered]@{
        Arch = $arch
        Profile = $buildProfile
        Compiler = Invoke-Tool fpc @('-iV')
        PascalOptions = @(Get-PascalOptions)
        GCC = Invoke-Tool gcc @('-dumpfullversion')
        NASM = Invoke-Tool nasm @('-v')
    }
    Write-BuildFile "$buildPath/toolchain.json" ($config | ConvertTo-Json)
    Write-Graph $pascal $native $false
    Invoke-Tool ninja @('-f', "$buildPath/build.ninja", $task)
    if ($task -in @('iso', 'all')) {
        $iso = "$buildPath/Asuro.iso"
        & cmp -s $iso Asuro.iso
        if ($LASTEXITCODE -ne 0) { Copy-Item -LiteralPath $iso -Destination Asuro.iso -Force }
    }
}

try {
    if ($args.Count -and $args[0] -eq '--stage') {
        if ($args.Count -ne 3) { throw '--stage requires a stage name and a build directory.' }
        Invoke-Stage -Step $args[1] -Path $args[2]
    } elseif ($args -contains '--help' -or $args -contains '-h') {
        Write-Host 'Usage: build [compile|iso|docs|all] [--arch x86] [--profile debug|test:minimal|test:complex|release]'
    } else {
        $options = Get-BuildOptions -Arguments $args
        Invoke-Build @options
    }
} catch {
    [Console]::Error.WriteLine("Build error: $_")
    exit 1
}

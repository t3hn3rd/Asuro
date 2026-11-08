# Copyright 2026 Aaron Hance
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Run from the workspace root after building the selected ASURO_BOOT_TEST.
# Restore temporary optical medium and optional RAM changes after the test.
param(
    [string[]]$TerminalCommands = @(),
    [string[]]$OpenPrograms = @(),
    [switch]$NetworkInput,
    [switch]$DesktopInput,
    [ValidateSet('none', 'ud', 'pf', 'df')][string]$Test = 'none',
    [ValidateRange(0, 8192)][int]$MemoryMB = 0,
    [string]$Controller = 'AHCI',
    [int]$Port = 1,
    [int]$Device = 0,
    [ValidateRange(5, 45)][int]$TimeoutSeconds = 35
)
$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath .\localenv.json -Raw | ConvertFrom-Json
$vm = $config.virtualbox.MachineName
$serialPath = $config.virtualbox.LogLocation
if (-not $serialPath) { throw 'VirtualBox serial LogLocation is required.' }
$isoPath = (Resolve-Path -LiteralPath .\Asuro-x86_64.iso).Path
$state = & VBoxManage.exe showvminfo $vm --machinereadable
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect VirtualBox VM.' }
if ($state -notcontains 'VMState="poweroff"') {
    throw 'The configured VM must already be powered off before boot validation.'
}
$mediumKey = '"{0}-{1}-{2}"=' -f $Controller, $Port, $Device
$mediumLine = @($state | Where-Object { $_.StartsWith($mediumKey) })
if ($mediumLine.Count -ne 1) { throw 'Cannot identify original optical medium.' }
$originalMedium = $mediumLine[0].Substring($mediumKey.Length).Trim('"').Replace('\\', '\')
if ($originalMedium -notin @('none', 'emptydrive') -and $originalMedium -notmatch '(?i)\.iso$') {
    throw 'Selected port is not an ISO/empty optical drive; refusing to replace it.'
}
if ($originalMedium -eq 'none') { $originalMedium = 'emptydrive' }
$evidence = Join-Path (Get-Location) 'bin\x86_64'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$originalMemory = [int](($state | Where-Object { $_ -match '^memory=' }) -replace '^memory=', '')
$originalNetwork = (($state | Where-Object { $_ -match '^nic1=' }) -replace '^nic1=', '').Trim('"')
if ($originalMemory -le 0) { throw 'Cannot identify original VM RAM size.' }
function Open-DesktopProgram($mouse, [string]$name) {
            $mouse.PutMouseEvent(-2000, -2000, 0, 0, 0)
            Start-Sleep -Milliseconds 200
            $mouse.PutMouseEvent(240, 0, 0, 0, 0)
            for ($step = 0; $step -lt 12; $step++) {
                $mouse.PutMouseEvent(0, 100, 0, 0, 0)
                Start-Sleep -Milliseconds 100
            }
            $mouse.PutMouseEvent(0, -32, 0, 0, 0)
            Start-Sleep -Milliseconds 200
            $mouse.PutMouseEvent(0, 0, 0, 0, 1)
            Start-Sleep -Milliseconds 200
            $mouse.PutMouseEvent(0, 0, 0, 0, 0)
            & VBoxManage.exe controlvm $vm keyboardputstring $name
            Start-Sleep -Seconds 1
            & VBoxManage.exe controlvm $vm keyboardputscancode 1c 9c
            Start-Sleep -Seconds 1
}
$started = $false
try {
    if ($NetworkInput) {
        & VBoxManage.exe modifyvm $vm --nic1 nat
        if ($LASTEXITCODE -ne 0) { throw 'Cannot set test NAT network.' }
        Start-Sleep -Milliseconds 600
    }
    if ($MemoryMB -ne 0) {
        & VBoxManage.exe modifyvm $vm --memory $MemoryMB
        if ($LASTEXITCODE -ne 0) { throw 'Cannot set test RAM size.' }
        Start-Sleep -Milliseconds 600
    }
    & VBoxManage.exe storageattach $vm --storagectl $Controller --port $Port --device $Device --type dvddrive --medium $isoPath
    if ($LASTEXITCODE -ne 0) { throw 'Cannot attach bootstrap ISO.' }
    # VBoxSVC releases configuration sessions asynchronously.
    Start-Sleep -Milliseconds 500
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        $launchOutput = & .\virtualbox-wrapper.ps1 -command up -Headless -NoMonitor 2>&1
        if ($LASTEXITCODE -eq 0) {
            $started = $true
            break
        }
        if (($launchOutput -join "`n") -notmatch 'already locked') {
            throw "Cannot start test VM: $launchOutput"
        }
        Start-Sleep -Seconds 1
    }
    if (-not $started) { throw "VirtualBox session remained locked: $launchOutput" }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $output = ''
    $marker = if ($Test -eq 'none') { 'desktop ready' } else { 'HALTED: exception diagnostics complete' }
    do {
        if (Test-Path -LiteralPath $serialPath) {
            $output = Get-Content -LiteralPath $serialPath -Raw
        }
        if ($output -and ($output.Contains($marker) -or $output.Contains('FAIL:'))) { break }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    $output | Set-Content -LiteralPath (Join-Path $evidence "boot-$Test-$MemoryMB.log")
    & VBoxManage.exe debugvm $vm getregisters rip rsp cs cr0 cr2 cr3 cr4 efer tr |
        Set-Content -LiteralPath (Join-Path $evidence "registers-$Test-$MemoryMB.log")
    if ($LASTEXITCODE -ne 0) { throw 'Cannot capture CPU registers.' }
    if (($DesktopInput -or $NetworkInput -or $TerminalCommands.Count -gt 0 -or $OpenPrograms.Count -gt 0) -and $Test -eq 'none' -and $output.Contains($marker)) {
        $vbox = New-Object -ComObject VirtualBox.VirtualBox
        $session = New-Object -ComObject VirtualBox.Session
        $machine = $vbox.FindMachine($vm)
        $machine.LockMachine($session, 1)
        try {
            Start-Sleep -Seconds 1
            $mouse = $session.Console.Mouse
            Open-DesktopProgram $mouse 'Terminal'
            $mouse.PutMouseEvent(100, -400, 0, 0, 0)
            Start-Sleep -Milliseconds 200
            $mouse.PutMouseEvent(0, 0, 0, 0, 1)
            Start-Sleep -Milliseconds 200
            $mouse.PutMouseEvent(0, 0, 0, 0, 0)
            Start-Sleep -Seconds 1
            foreach ($character in 'echo native64'.ToCharArray()) {
                & VBoxManage.exe controlvm $vm keyboardputstring ([string]$character)
                Start-Sleep -Milliseconds 150
            }
            Start-Sleep -Seconds 2
            & VBoxManage.exe controlvm $vm keyboardputscancode 1c 9c
            Start-Sleep -Seconds 3
            & VBoxManage.exe controlvm $vm keyboardputstring 'echo burst64'
            & VBoxManage.exe controlvm $vm keyboardputscancode 1c 9c
            Start-Sleep -Seconds 3
            foreach ($command in $TerminalCommands) {
                & VBoxManage.exe controlvm $vm keyboardputstring $command
                & VBoxManage.exe controlvm $vm keyboardputscancode 1c 9c
                Start-Sleep -Seconds 3
            }
            if ($NetworkInput) {
                & VBoxManage.exe controlvm $vm keyboardputstring 'dhclient'
                & VBoxManage.exe controlvm $vm keyboardputscancode 1c 9c
                Start-Sleep -Seconds 5
                & VBoxManage.exe controlvm $vm keyboardputstring 'ifconfig'
                & VBoxManage.exe controlvm $vm keyboardputscancode 1c 9c
                Start-Sleep -Seconds 2
                & VBoxManage.exe controlvm $vm keyboardputstring 'ping 10.0.2.2'
                & VBoxManage.exe controlvm $vm keyboardputscancode 1c 9c
                Start-Sleep -Seconds 12
            }
            foreach ($program in $OpenPrograms) {
                Open-DesktopProgram $mouse $program
                Start-Sleep -Seconds 3
                $safeName = $program -replace '[^A-Za-z0-9]', '-'
                & VBoxManage.exe controlvm $vm screenshotpng (Join-Path $evidence "app-$safeName-$MemoryMB.png")
                if ($LASTEXITCODE -ne 0) { throw "Cannot capture $program." }
            }
        } finally {
            $session.UnlockMachine()
        }
    }
    & VBoxManage.exe controlvm $vm screenshotpng (Join-Path $evidence "screen-$Test-$MemoryMB.png")
    $output = Get-Content -LiteralPath $serialPath -Raw
    $output | Set-Content -LiteralPath (Join-Path $evidence "boot-$Test-$MemoryMB.log")
    Write-Output $output
    if (-not $output -or -not $output.Contains($marker) -or $output.Contains('FAIL:')) {
        throw 'Boot did not reach its expected completion marker.'
    }
    if ($Test -eq 'none' -and $output.Contains('HALTED:')) {
        throw 'The kernel halted after starting the desktop.'
    }
    foreach ($required in @('PASS: native unit initialization runs once', 'EXCEPTION_TESTS_PASSED=0000000000000002', 'EXCEPTION_TESTS_FAILED=0000000000000000',
        'PASS: VFS reads ELF64 kernel through AHCI', 'VFS_TESTS_FAILED=0000000000000000',
        'STORMETA_TESTS_FAILED=0000000000000000', 'AHCI_TESTS_FAILED=0000000000000000', 'USBTYPES_TESTS_FAILED=0000000000000000', 'USBCORE_TESTS_FAILED=0000000000000000',
        'USBMSC_TESTS_FAILED=0000000000000000', 'USBKEYBOARD_TESTS_FAILED=0000000000000000', 'USBMOUSE_TESTS_FAILED=0000000000000000', 'USBHUB_TESTS_FAILED=0000000000000000', 'OHCI_TESTS_FAILED=0000000000000000',
        'Device enumerated at address 1', 'IOREQ_TESTS_FAILED=0000000000000000', 'CFIFO_TESTS_FAILED=0000000000000000', 'FSMGR_TESTS_FAILED=0000000000000000', 'PATH_TESTS_FAILED=0000000000000000', 'FNV1A_TESTS_FAILED=0000000000000000', 'HASHMAP_TESTS_FAILED=0000000000000000', 'LISTS_TESTS_FAILED=0000000000000000', 'PMM_TESTS_FAILED=0000000000000000', 'VMM_TESTS_FAILED=0000000000000000',
        'HEAP_TESTS_FAILED=0000000000000000', 'IRQ_TESTS_FAILED=0000000000000000', 'CONTEXT_TESTS_FAILED=0000000000000000', 'PROCESS_TESTS_FAILED=0000000000000000', 'FD_TESTS_FAILED=0000000000000000', 'STRINGS_TESTS_FAILED=0000000000000000', 'STDIO_TESTS_FAILED=0000000000000000')) {
        if (-not $output.Contains($required)) { throw "Missing check: $required" }
    }
    if ($MemoryMB -gt 4096 -and -not $output.Contains('PASS: AHCI DMA above 4 GiB matches every disk sector')) {
        throw 'High physical memory test was skipped.'
    }
    if ($NetworkInput -and -not $output.Contains('Process ACK.')) {
        throw 'Network test did not receive a DHCP acknowledgement.'
    }
    if ($Test -ne 'none') {
        $vector = @{ud = '6'; pf = 'E'; df = '8'}[$Test]
        $errorCode = if ($Test -eq 'pf') { '2' } else { '0' }
        foreach ($required in @("VECTOR=000000000000000$vector", "ERROR=000000000000000$errorCode", 'CS=0000000000000018')) {
            if (-not $output.Contains($required)) { throw "Missing diagnostic: $required" }
        }
        if ($Test -eq 'pf' -and -not $output.Contains('CR2=0000000100000000')) {
            throw 'Page fault did not preserve the expected CR2.'
        }
        if ($Test -eq 'df' -and (-not $output.Contains('STACK=double-fault IST1') -or
                               -not $output.Contains('RSP=0000000100001000'))) {
            throw 'Double fault did not switch from the broken stack to IST1.'
        }
    }
    Write-Output "PASS: VirtualBox x86_64 boot test '$Test'"
} finally {
    try {
        if ($started) {
            & .\virtualbox-wrapper.ps1 -command down
            if ($LASTEXITCODE -ne 0) { throw 'Cannot stop test VM.' }
        }
    } finally {
        & VBoxManage.exe storageattach $vm --storagectl $Controller --port $Port --device $Device --type dvddrive --medium $originalMedium
        if ($LASTEXITCODE -ne 0) { throw 'Cannot restore original optical medium.' }
        if ($MemoryMB -ne 0) {
            Start-Sleep -Milliseconds 500
            & VBoxManage.exe modifyvm $vm --memory $originalMemory
            if ($LASTEXITCODE -ne 0) { throw 'Cannot restore original VM RAM size.' }
        }
        if ($NetworkInput) {
            Start-Sleep -Milliseconds 600
            & VBoxManage.exe modifyvm $vm --nic1 $originalNetwork
            if ($LASTEXITCODE -ne 0) { throw 'Cannot restore original network mode.' }
        }
    }
}

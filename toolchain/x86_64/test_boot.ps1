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
    [ValidateSet('none', 'regression', 'storage', 'ud', 'pf', 'df')][string]$Test = 'none',
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
    $marker = if (($Test -in @('none','regression','storage'))) { 'desktop ready' } else { 'HALTED: exception diagnostics complete' }
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
    if (($DesktopInput -or $NetworkInput -or $TerminalCommands.Count -gt 0 -or $OpenPrograms.Count -gt 0) -and ($Test -in @('none','regression','storage')) -and $output.Contains($marker)) {
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
    if ($Test -eq 'storage' -and $output.Contains('PASS: USB bulk read from sector zero matches reference reads')) {
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while (-not ($output -match '128 KiB QD1, elapsed us=[1-9][0-9]*') -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 200
            $output = Get-Content -LiteralPath $serialPath -Raw
        }
        if ($output -notmatch '128 KiB QD1, elapsed us=[1-9][0-9]*') { throw 'Timed USB read did not finish.' }
    }
    $output | Set-Content -LiteralPath (Join-Path $evidence "boot-$Test-$MemoryMB.log")
    Write-Output $output
    if (-not $output -or -not $output.Contains($marker) -or $output.Contains('FAIL:')) {
        throw 'Boot did not reach its expected completion marker.'
    }
    if (($Test -in @('none','regression','storage')) -and $output.Contains('HALTED:')) {
        throw 'The kernel halted after starting the desktop.'
    }
    if ($Test -ne 'none') {
        if ($output -notmatch '\[test\] [1-9][0-9]* tests run, [1-9][0-9]* passed, 0 failed\.') {
            throw 'Missing passing shared test harness summary.'
        }
        foreach ($unit in @('driver.storage.vfs', 'driver.storage.ctl.ahci', 'driver.bus.usb.types', 'driver.bus.usb.core', 'driver.storage.ctl.usb', 'driver.hid.usb.keyboard', 'driver.hid.usb.mouse', 'driver.bus.usb.hub', 'driver.bus.usb.ohci', 'driver.bus.usb.xhci', 'core.ds.cfifo', 'core.ds.cfifols', 'core.ds.fifo', 'core.ds.lifo', 'core.ds.circ', 'core.ds.minh', 'core.ds.maxh', 'core.ds.prio', 'core.enc.sha1', 'core.enc.djb2', 'core.enc.fnv1a', 'core.strings')) {
            if ($output -notmatch ('\[test:' + [regex]::Escape($unit) + '\] [1-9][0-9]* passed, 0 failed\.')) {
                throw "Missing passing test summary for $unit"
            }
        }
        foreach ($required in @('PASS: native FPC compiler runtime', 'PASS: native unit initialization runs once', 'EXCEPTION_TESTS_PASSED=0000000000000003', 'EXCEPTION_TESTS_FAILED=0000000000000000',
            'PASS: VFS reads ELF64 kernel through AHCI',
            'IOREQ_TESTS_FAILED=0000000000000000', 'FSMGR_TESTS_FAILED=0000000000000000', 'PATH_TESTS_FAILED=0000000000000000', 'HASHMAP_TESTS_FAILED=0000000000000000', 'LISTS_TESTS_FAILED=0000000000000000', 'PMM_TESTS_FAILED=0000000000000000', 'VMM_TESTS_FAILED=0000000000000000',
            'HEAP_TESTS_FAILED=0000000000000000', 'IRQ_TESTS_FAILED=0000000000000000', 'CONTEXT_TESTS_FAILED=0000000000000000', 'PROCESS_TESTS_FAILED=0000000000000000', 'FD_TESTS_FAILED=0000000000000000', 'STDIO_TESTS_FAILED=0000000000000000')) {
            if (-not $output.Contains($required)) { throw "Missing check: $required" }
        }
    } elseif ($output.Contains('PROCESS_TESTS_PASSED=')) {
        throw 'Regression suite ran during normal boot.'
    }
    if ($Test -eq 'storage' -and $output -notmatch '\[test:driver\.storage\.bench\] [1-9][0-9]* passed, 0 failed\.') {
        throw 'Missing passing native storage benchmark test summary.'
    }
    if ($Test -eq 'storage' -and $output -notmatch '\[test:driver\.storage\.perftest\] [1-9][0-9]* passed, 0 failed\.') {
        throw 'Missing passing native storage regression tests.'
    }
    $ohci = $state -contains 'usb="on"'
    $xhci = $state -contains 'xhci="on"'
    if ($ohci -or $xhci) {
        foreach ($usbController in @('ohci', 'xhci')) {
            if ((($usbController -eq 'ohci' -and $ohci) -or ($usbController -eq 'xhci' -and $xhci)) -and
                -not $output.Contains("Registered HC: driver.bus.usb.$usbController")) {
                throw "Configured $usbController controller was not registered."
            }
        }
        $usbInput = $state -contains 'hidkeyboard="usbkbd"' -or
                    $state -contains 'hidpointing="usbmouse"' -or
                    $state -contains 'hidpointing="usbtablet"'
        $usbDisk = $false
        if ($xhci -or $state -contains 'ehci="off"') {
            foreach ($line in $state) {
                if ($line -match '^storagecontrollertype(\d+)="USB"$') {
                    $nameKey = 'storagecontrollername' + $Matches[1] + '="'
                    $nameLine = $state | Where-Object { $_.StartsWith($nameKey) }
                    $name = $nameLine.Substring($nameKey.Length).TrimEnd('"')
                    $mediumPattern = '^"' + [regex]::Escape($name) + '-\d+-\d+"="(?!none"|emptydrive")[^"]+"$'
                    if ($state -match $mediumPattern) { $usbDisk = $true }
                }
            }
        }
        if (($Test -eq 'storage') -and $usbInput -and -not $usbDisk -and -not $output.Contains('Device enumerated at address ')) {
            throw 'Configured USB device did not enumerate.'
        }
        if ($Test -eq 'storage' -and $usbDisk -and -not $output.Contains('PASS: USB bulk read from sector zero matches reference reads')) {
            throw 'Configured USB disk did not complete the sector-zero read.'
        }
    }
    if ($Test -eq 'storage' -and $MemoryMB -gt 4096 -and -not $output.Contains('PASS: AHCI DMA above 4 GiB matches every disk sector')) {
        throw 'High physical memory test was skipped.'
    }
    if ($NetworkInput -and -not $output.Contains('Process ACK.')) {
        throw 'Network test did not receive a DHCP acknowledgement.'
    }
    if ($Test -notin @('none','regression','storage')) {
        $vector = @{ud = '6'; pf = 'E'; df = '8'}[$Test]
        $errorCode = if ($Test -eq 'pf') { '2' } else { '0' }
        foreach ($required in @("VECTOR=000000000000000$vector", "ERROR=000000000000000$errorCode", 'CS=0000000000000018')) {
            if (-not $output.Contains($required)) { throw "Missing diagnostic: $required" }
        }
        if ($Test -eq 'pf' -and -not $output.Contains('CR2=0000000100000000')) {
            throw 'Page fault did not preserve the expected CR2.'
        }
        if ($Test -eq 'df' -and (-not $output.Contains('STACK=double-fault IST1') -or
                               -not $output.Contains('FAULT=bootstrap stack guard'))) {
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

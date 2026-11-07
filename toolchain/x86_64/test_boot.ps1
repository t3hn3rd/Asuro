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
if ($originalMemory -le 0) { throw 'Cannot identify original VM RAM size.' }
$started = $false
try {
    if ($MemoryMB -ne 0) {
        & VBoxManage.exe modifyvm $vm --memory $MemoryMB
        if ($LASTEXITCODE -ne 0) { throw 'Cannot set test RAM size.' }
    }
    & VBoxManage.exe storageattach $vm --storagectl $Controller --port $Port --device $Device --type dvddrive --medium $isoPath
    if ($LASTEXITCODE -ne 0) { throw 'Cannot attach bootstrap ISO.' }
    & .\virtualbox-wrapper.ps1 -command up -Headless -NoMonitor
    if ($LASTEXITCODE -ne 0) { throw 'Cannot start test VM.' }
    $started = $true
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $output = ''
    $marker = if ($Test -eq 'none') { 'bootstrap complete; interrupts disabled' } else { 'HALTED: exception diagnostics complete' }
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
    Write-Output $output
    if (-not $output -or -not $output.Contains($marker) -or $output.Contains('FAIL:')) {
        throw 'Boot did not reach its expected completion marker.'
    }
    foreach ($required in @('EXCEPTION_TESTS_PASSED=0000000000000002', 'EXCEPTION_TESTS_FAILED=0000000000000000',
        'PMM_TESTS_FAILED=0000000000000000', 'VMM_TESTS_FAILED=0000000000000000',
        'HEAP_TESTS_FAILED=0000000000000000', 'IRQ_TESTS_FAILED=0000000000000000', 'CONTEXT_TESTS_FAILED=0000000000000000', 'PROCESS_TESTS_FAILED=0000000000000000', 'FD_TESTS_FAILED=0000000000000000', 'STRINGS_TESTS_FAILED=0000000000000000', 'STDIO_TESTS_FAILED=0000000000000000')) {
        if (-not $output.Contains($required)) { throw "Missing check: $required" }
    }
    if ($MemoryMB -gt 4096 -and $output.Contains('SKIP: no available physical RAM above 4 GiB')) {
        throw 'High physical memory test was skipped.'
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
            & VBoxManage.exe modifyvm $vm --memory $originalMemory
            if ($LASTEXITCODE -ne 0) { throw 'Cannot restore original VM RAM size.' }
        }
    }
}

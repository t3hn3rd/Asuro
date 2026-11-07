<# 
You need a local git-ignored localenv.json file with the following content:
{
  "virtualbox": {
    "MachineName": "your-machine-name or guid"
  }
}
#>

param (
  [Parameter(Mandatory=$true)]
  [ValidateSet('up', 'down')]
  [String]$Command,
  # Optional modes for bounded, script-driven boot validation (Aaron Hance).
  [switch]$Headless,
  [switch]$NoMonitor
)

$Config = Get-Content .\localenv.json | ConvertFrom-Json
$MachineName = $Config.virtualbox.MachineName
$LogLocation = $Config.virtualbox.LogLocation
$LogOutputEnabled = $LogLocation -ne $null

if ($Command -eq 'up') {

  if($LogOutputEnabled) {
    Clear-Content $LogLocation
  }

  if ($NoMonitor) {
    if ($Headless) {
      VBoxManage.exe startvm $MachineName --type headless
    } else {
      VBoxManage.exe startvm $MachineName
    }
    exit $LASTEXITCODE
  }

  $MonitorJob = Start-Job -ArgumentList $MachineName, $Headless.IsPresent -ScriptBlock {
    param($MachineName, $Headless)
    Write-Output "Starting $MachineName"
    if ($Headless) {
      VBoxManage.exe startvm $MachineName --type headless
    } else {
      VBoxManage.exe startvm $MachineName
    }
    $running=$true
    while($running) {
      $status=(VBoxManage.exe list runningvms)
      if($status) {
        $running=$status.contains($MachineName)
      } else {
        $running=$false
      }
    }
  }
  
  if($LogOutputEnabled) {
    $LogJob = Start-Job -ArgumentList $LogLocation -ScriptBlock {
      param($LogLocation)
      Get-Content -Path $LogLocation -Wait
    }
  }

  while($MonitorJob.State -eq 'Running') {
    if($LogOutputEnabled) {
      Receive-Job $LogJob
    }
    Receive-Job $MonitorJob
  }
  Get-Job | Stop-Job | Remove-Job -Force
} elseif ($Command -eq 'down') {
  Write-Output "Stopping $MachineName"
  VBoxManage.exe controlvm $MachineName poweroff
}

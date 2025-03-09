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
  [String]$Command
)

$Config = Get-Content .\localenv.json | ConvertFrom-Json
$MachineName = $Config.virtualbox.MachineName
$LogLocation = $Config.virtualbox.LogLocation
$LogOutputEnabled = $LogLocation -ne $null

if ($Command -eq 'up') {

  if($LogOutputEnabled) {
    Clear-Content $LogLocation
  }

  $MonitorJob = Start-Job -ArgumentList $MachineName -ScriptBlock {
    param($MachineName)
    Write-Output "Starting $MachineName"
    VBoxManage.exe startvm $MachineName
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
} elseif ($Command -eq 'down') {
  Write-Output "Stopping $MachineName"
  VBoxManage.exe controlvm $MachineName poweroff
}
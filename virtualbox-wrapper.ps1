param (
  $MachineName
)

VBoxManage.exe startvm $MachineName

$running=$true
while($running) {
  Start-Sleep -Seconds 1
  $status=(VBoxManage.exe list runningvms)
  if($status) {
    $running=$status.contains($MachineName)
  } else {
    $running=$false
  }
}
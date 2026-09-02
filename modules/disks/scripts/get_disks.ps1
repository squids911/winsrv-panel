# get_disks.ps1 - lists disks, partitions and volumes.
# NOTE: keep ASCII-only.

Write-Host "== Disks =="
Get-Disk -ErrorAction SilentlyContinue | Format-Table -AutoSize

Write-Host "== Partitions =="
Get-Partition -ErrorAction SilentlyContinue | Format-Table -AutoSize

Write-Host "== Volumes (with filesystem) =="
Get-Volume -ErrorAction SilentlyContinue | Select-Object DriveLetter, FileSystemLabel, FileSystem, @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB,1)}} | Format-Table -AutoSize

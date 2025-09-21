param (
    [Parameter(Mandatory)]
    [string]$ImportPath,

    [long]$MinimumFreeBytes = 8GB,

    [string]$LogFilePath = "logs$([IO.Path]::DirectorySeparatorChar)"
)

function Get-HumanReadableSize {
    param (
        [Parameter(Mandatory)]
        [long]$SizeInBytes
    )

    if ($SizeInBytes -ge 1GB) {
        return "$([Math]::Round($SizeInBytes / 1GB, 2)) GB"
    }
    elseif ($SizeInBytes -ge 1MB) {
        return "$([Math]::Round($SizeInBytes / 1MB, 2)) MB"
    }
    elseif ($SizeInBytes -ge 1KB) {
        return "$([Math]::Round($SizeInBytes / 1KB, 2)) KB"
    }
    else {
        return "$SizeInBytes B"
    }
}

function Get-ScriptLastWriteTime {
    return (Get-Item $PSCommandPath).LastWriteTime
}

function Remove-DirectoryIfEmpty {
    param (
        [Parameter(Mandatory, ValueFromPipeline = $true)]
        [System.IO.DirectoryInfo]$Directory
    )
    
    process {
        $normalizedDirectoryPath = $Directory.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar)
        if ($normalizedDirectoryPath.Length -gt $normalizedImportPath.Length -and
            $normalizedDirectoryPath.StartsWith($normalizedImportPath, [StringComparison]::OrdinalIgnoreCase) -and
            -not (Get-ChildItem -Force -LiteralPath $Directory.FullName)
        ) {
            Write-Log "Deleting empty directory $Directory..."
            Remove-Item -Force -LiteralPath $Directory.FullName
        }
    }
}

function Remove-File {
    param (
        [Parameter(Mandatory, ValueFromPipeline = $true)]
        [System.IO.FileInfo]$File
    )

    process {
        Write-Log "Deleting file $File ($(Get-HumanReadableSize -SizeInBytes $File.Length))..."
        Remove-Item -Force -LiteralPath $File.FullName
    }
}

function Write-DriveFreeSpace {
    param (
        [Parameter(Mandatory)]
        [System.Management.Automation.PSDriveInfo]$Drive
    )

    Write-Log "Free space on drive ${Drive}: $(Get-HumanReadableSize -SizeInBytes $Drive.Free)"
}

function Write-Log {
    param (
        [string]$Message
    )

    Write-Host "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff") $Message"
}

Start-Transcript -Append -LiteralPath "$LogFilePath$(Get-Date -Format "yyyy-MM-dd-HH-mm").log"

try {
    $normalizedImportPath = (Get-Item $ImportPath).FullName.TrimEnd([IO.Path]::DirectorySeparatorChar)
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.IncludeSubdirectories = $true
    $watcher.Path = $ImportPath

    Register-ObjectEvent -InputObject $watcher -EventName Created -Action {
        # Write-Log "Directory or file creation detected: $($Event.SourceEventArgs.FullPath)"
        if ((Split-Path -Extension -Path $Event.SourceEventArgs.Name) -iin '.LRV', '.THM') {
            Remove-File -ErrorAction SilentlyContinue -File $Event.SourceEventArgs.FullPath
        }
    } | Out-Null

    Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action {
        # Write-Log "Directory or file deletion detected: $($Event.SourceEventArgs.FullPath)"
        Split-Path -Path $Event.SourceEventArgs.FullPath | Remove-DirectoryIfEmpty
    } | Out-Null

    $watcher.EnableRaisingEvents = $true

    Get-ChildItem -File -Filter *.LRV -Force -LiteralPath $ImportPath -Recurse | Remove-File
    Get-ChildItem -File -Filter *.THM -Force -LiteralPath $ImportPath -Recurse | Remove-File

    Get-ChildItem -Directory -Force -LiteralPath $ImportPath -Recurse | Remove-DirectoryIfEmpty

    $drive = (Get-Item $ImportPath).PSDrive
    $scriptLastWriteTime = Get-ScriptLastWriteTime

    while ($true) {
        if ($drive.Free -lt $MinimumFreeBytes) {
            Write-DriveFreeSpace -Drive $drive
            $files = Get-ChildItem -File -Force -LiteralPath $ImportPath -Recurse | Sort-Object LastWriteTime
            foreach ($file in $files) {
                Remove-File -File $file
                if ($drive.Free -ge $MinimumFreeBytes) {
                    break
                }
            }
            Write-DriveFreeSpace -Drive $drive
        }

        # Sleep until the end of the current minute to allow checking for script modifications and exit just before the next scheduled run, ensuring the script reloads with any updates.
        $currentTime = Get-Date
        $endOfCurrentMinute = Get-Date -Date $currentTime.Date -Hour $currentTime.Hour -Minute $currentTime.Minute -Second 59
        if ($currentTime -ge $endOfCurrentMinute) {
            $sleepUntil = $endOfCurrentMinute.AddMinutes(1)
        }
        else {
            $sleepUntil = $endOfCurrentMinute
        }
        Start-Sleep -Duration ($sleepUntil - $currentTime)

        if ((Get-ScriptLastWriteTime) -gt $scriptLastWriteTime) {
            Write-Log "Script has been modified — exiting."
            break
        }
    }
}
finally {
    Stop-Transcript
}

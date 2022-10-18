# Restart-ServerForSystem.ps1
# Meant to be run as SYSTEM, or in a remote powershell session.
# perfect for use within Task scheduler
# attempts to log off all users, and then Restarts server
[CmdletBinding()]
param()

################################################################
### Functions
################################################################
function Get-quserOutput {
    # Gets Text output from quser command
    $quserTXT = quser 2>&1

    # Checks for an empty userlist
    $outputType = $quserTXT.GetType().FullName
    $isErrorRecord = $outputType -eq 'System.Management.Automation.ErrorRecord'
    if ($isErrorRecord) {
        [string]$errTXT = $quserTXT.CategoryInfo.TargetName
        $goodError = $errTXT -eq 'No User exists for *'
        if ($goodError) {
            [PSCustomObject[]]$result = @(
                [PSCustomObject]@{
                    ID = 'nobody'
                }
            )
            return $result
        }
        else {
            Throw "Unspecified quser error"
        }
    }
    else {
        # parses the ID column in quser output
        # will work for logon ID numbers less than 1000
        $idColumn = @(
            foreach ($line in $quserTXT) {
                $line.Substring(41, 3).Trim()
            }
        )
        [PSCustomObject[]]$result = @(
            $idColumn | ConvertFrom-Csv
        )
        return $result
    }
}

Function Disconnect-Users {
    # starts Logoff off all users
    param(
        [PSCustomObject[]]$ids
    )

    foreach ($logon in $ids) {
        logoff.exe $logon.ID
    }
}

function Start-ServerReboot {
    # uses shutdown.exe for backwards compatibility
    # Restart-Computer may trigger 'unknown shutdown' 
    # warnings on older servers after reboot
    $exe = "$env:windir\System32\shutdown.exe"
    $comment = "`"Scheduled Restart`""
    $argList = @(
        '/r'
        '/t 1'
        '/d p:1:1'
        "/c $comment"
    )
    $splat = @{
        FilePath     = $exe
        ArgumentList = $argList
    }
    Start-Process @splat
}


################################################################
### Main
################################################################

[PSCustomObject[]]$userLogons = Get-quserOutput

[bool]$loginsActive = -not ($userLogons[0].ID -eq 'nobody')
If ($loginsActive) {
    Disconnect-Users -ids $userLogons
}

# Waits for a few minutes for all users to be logged off
# will Halt script if logoffs are freezing or hanging
$minutes = 8
[datetime]$now = Get-Date
$timeout = $now.AddMinutes($minutes)
if ($loginsActive) {
    do {
        Start-Sleep -Seconds 15
        $userLogons = Get-quserOutput
        $nologins = $userLogons[0].ID -eq 'nobody'
        If ($nologins) {
            $loginsActive = $false
            break
        }
        $now = Get-Date
    }
    while ( $now -lt $timeout )
}

If ($loginsActive) {
    Throw "User logons are still active after " + $minutes.ToString() + " minutes"
}
else {
    Start-ServerReboot
}

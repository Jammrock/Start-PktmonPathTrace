#requires -RunAsAdministrator

[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $vmName,

    [Parameter()]
    [string]
    $SavePath = "$env:TEMP"
)

begin {
    # given a VM name, find the pktmon components in the data path
    function Get-PktmonVmDataPath {
        [CmdletBinding()]
        param (
            [Parameter()]
            [string]
            $vmName
        )

        # get vmSwitches
        $vmSw = Get-VMSwitch

        # get the pktmon components
        $rawComps = pktmon comp list --json | ConvertFrom-Json
        $swComps = $rawComps | Where-Object Group -in $vmSw.Name | ForEach-Object Components
        $allComps = foreach ($comp in $rawComps) {
            $comp.Components
        }
        
        # add ifIndex to allComps
        $allComps | Add-Member -MemberType NoteProperty -Name ifIndex -Value -1

        foreach ($comp in $allComps) {
            $idx = $comp.Properties | Where-Object {$_.Name -eq "ifIndex"}

            if ($idx) {
                $comp.ifIndex = $idx.Value
            }
        }

        # now find the starting component, the vmNIC
        $currComp = $swComps | Where-Object {$_.Name -eq $vmName -and $_.Type -eq "VM Nic"}

        # list of the components in the data path
        $comps = [System.Collections.Generic.List[object]]::new()

        # add the root component
        $comps.Add($currComp)

        # get the physical NIC
        [array]$swNICS = Get-VMSwitchTeam -Name ($currComp.Properties | Where-Object Name -eq "Switch name" | ForEach-Object Value) | ForEach-Object NetAdapterInterfaceDescription
        $nicComps = $allComps | Where-Object Name -in $swNICS
        if ($nicComps) {
            $comps.AddRange($nicComps)
        }

        # controls when the data path is complete
        $endPath = $false

        do {
            # get the next component in the path
            $nextComp = $currComp.Properties | Where-Object {$_.Name -eq "Ext ifIndex"}

            # end if there is no next component
            if (-NOT $nextComp) {
                $endPath = $true
            } else {
                # update currComp
                [array]$currComp = $allComps | Where-Object ifIndex -eq $nextComp.Value

                if ($currComp) {
                    $comps.AddRange($currComp)
                }
            }
        } until ($endPath)

        # return the data path
        return $comps
    }

    function Add-MacAddressDelimiter {
        param(
            [Parameter(Mandatory=$true)]
            [string]$MacAddress,

            [Parameter(Mandatory=$false)]
            [string]$Delimiter =":" 
        )

        # Remove any existing delimiters or non-hex characters
        $CleanMac = $MacAddress -replace "[^a-fA-F0-9]", ""

        # Ensure it's 12 hex characters
        if ($CleanMac.Length -ne 12) {
            throw "Invalid MAC address: must contain 12 hexadecimal characters."
        }

        # Insert delimiter every 2 characters
        $FormattedMac = ($CleanMac -split "(..)" | Where-Object { $_ }) -join $Delimiter

        return $FormattedMac
    }

    # setup the save directory
    $ts = Get-Date -Format FileDateTime
    $dirName = "pktmon--$env:COMPUTERNAME`--$vmName`--$ts"
    $dataPath = "$SavePath\$dirName"
    $null = mkdir "$dataPath" -Force

    # get the VM NIC(s)
    try {
        $vm = Get-VM $vmName -EA Stop
        [array]$vmNICs = $vm | Get-VMNetworkAdapter
        Write-Verbose "The VM was found:`n$($vm | Format-List | Out-String)"
    } catch {
        throw "Failed to find a VM named or its vmNIC(s): $vmName"
    }
}

process {
    # get the VM data path
    [string]$pktComps = (Get-PktmonVmDataPath $vmName | ForEach-Object Id | Sort-Object -Unique) -join ' '

    # prepare pktmon
    pktmon stop
    pktmon filter remove

    # add one MAC address filter per vmNIC
    $c = 1
    foreach ($nic in $vmNICs) {
        # format the MAC address
        $mac = Add-MacAddressDelimiter $nic.MacAddress

        $cmd = "pktmon filter add MacFilt$c --mac $mac"
        Write-Verbose "Adding a MAC filter: $cmd"
        $sb = [scriptblock]::Create($cmd)
        Invoke-Command -ScriptBlock $sb
        $c++
    }

    # start pktmon
    $cmd = "pktmon start --capture --comp $pktComps --log-mode memory --file-size 1024"
    $sb = [scriptblock]::Create($cmd)
    Invoke-Command -ScriptBlock $sb

    Write-Host -ForegroundColor Yellow "Reproduce the issue and then press 'q' to continue..."

    while ($true) {
        $key = [System.Console]::ReadKey($true)
        if ($key.KeyChar -eq 'q') {
            break
        }
    }

    Write-Host "Stopping data collection..."
}

end {
    Push-Location "$dataPath"
    pktmon stop
    pktmon comp list --json | Out-File .\pktmon.json -Encoding utf8 -Force
    Pop-Location

    Write-Host -ForegroundColor Green "The data was saved to: $dataPath`n`nRequired files: pktmon.etl and pktmon.json."

}

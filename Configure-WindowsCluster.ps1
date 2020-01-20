#Global Variables
$parameters = Get-Content ./cluster_config.json | ConvertFrom-Json
$g_fwRules = Get-Content ./firewall_rules.json | ConvertFrom-Json

#Functions
function Test-RemoteConnection {
    [CmdletBinding()]
    param (
        [Parameter()]
        [String[]]
        $Node
    )
    foreach ($n in $node) {
        try {
            Test-WSMan -ComputerName $n -ErrorAction Stop | Out-Null
            Write-Log -Message "Conectividad satisfactoria a $n" -Level Info
            continue
        }
        catch {
            Write-Log -Message "No se pudo conectar a $n" -Level Error      
            return $false
        }
    }
    return $true   
}

 

function Get-OS {

    [CmdletBinding()]

    param (

        [Parameter()]

        [String[]]

        $node

    )

    Write-Log -Message "Obteniendo Version de Sistema Operativo en $node" -Level Info

    $OS = Invoke-Command -ComputerName $node -ScriptBlock { Get-ComputerInfo -Property "OsName" }

    Write-Log -Message "Version de Sistema operativo obtenido en $node" -Level Info

    return $OS

}

 

function Compare-OS {
    [CmdletBinding()]
    param (
        [Parameter()]
        [System.Array]
        $OS
    )
    Write-Log -Message "Comparando version de sistema operativo" -Level Info
    for ($i = 0; $i -lt $OS.length; $i++) {
        for ($k = $i + 1; $k -lt $OS.length; $k++) {
            if ($OS[$i].OsName -NE $OS[$k].OsName) {
                Write-Log -Message "Version de Sistema operativo no es igual"
                return $false
            }
        }
    }
    Write-Log -Message "Version de Sistema operativo igual en todos los nodos" -Level Info
    return $true
}
function Test-DNSRegister {   
    [CmdletBinding()]
    param (
        [Parameter()]
        [String]
        $computerName
    )
    if (Resolve-DnsName -Name $computerName -Type A -ErrorAction SilentlyContinue) {
        Write-Log -Message "DNS resuelto satisfactoriamente para $computerName"
        return $true
    }
    else {
        return $false
    }
}
function set-ADPermission {

}
function Get-FWRulesByClusterType {
    [CmdletBinding()]
    param(
        [Parameter()]
        [String[]]
        $clusterType       
    )
    $firewallRules = $g_fwRules.$clusterType
    return $firewallRules
}
function Get-FirewallRule {
    [CmdletBinding()]
    param (
        [Parameter()]
        [String[]]
        $node,       
        [String[]]
        $firewallRules
    ) 
    $fwRules = Get-NetFirewallRule -CimSession $node -DisplayName $firewallRules
    return $fwRules
}
function Enable-FirewallRule {
    [CmdletBinding()]
    param (
        [Parameter()]
        [String[]]
        $node,
        [System.Object[]]
        $firewallRules
    )         
    Enable-NetFirewallRule -CimSession $node -DisplayName $firewallRules.DisplayName
}
function Get-AvailableClusterStorage {
    [CmdletBinding()]
    param (
        [Parameter()]
        [String[]]
        $Node,       
        [System.Object[]]
        $Disk
    )
    $disks = @()
    foreach ($d in $disk) {
        switch ($d.tipo) {
            'quorum' {
                try {
                    $disks += Get-Disk -CimSession $node -UniqueId $d.uid -ErrorAction Stop                   
                }
                catch {
                    Write-Log -Message "No existen discos para Quorum con este UID: $($d.uid)" -Level Error
                }              
            }           
            'base' {
                try {
                    $disks += Get-Disk -CimSession $node -UniqueId $d.uid -ErrorAction Stop                   
                }
                catch {
                    Write-Log -Message "No existen discos para Base con este UID: $($d.uid)" -Level Error
                }
            }
            'datos' {
                try {
                    $disks += Get-Disk -CimSession $node -UniqueId $d.uid -ErrorAction Stop                   
                }
                catch {
                    Write-Log -Message "No existen discos para Datos con este UID: $($d.uid)" -Level Error
                }
            }
            Default {
                Write-Log -Message "No se han especificado discos en cluster_config.json, verifique la informacion."
            }
        }       
    }
    return $disks    
}

function Initialize-AvailableClusterStorage {
    [CmdletBinding()]
    param (
        [Parameter()]
        [String[]]
        $Node,
        [System.Object[]]
        $Disk
    )
    foreach ($d in $Disk) {
        Initialize-Disk -CimSession $node -UniqueId $d.UniqueId -PartitionStyle GPT
    }
}

function New-VolumeAvailableClusterDisk {
    [CmdletBinding()]
    param (
        [Parameter()]
        [String[]]
        $Node,
        [System.Object[]]
        $Disk
    )
    foreach ($n in $Node) {
        foreach ($d in $Disk) {
            switch ($d.tipo) {
                'quorum' {
                    try {                   
                        New-Volume -CimSession $n -DiskUniqueId $d.uid -FriendlyName "Quorum" -FileSystem NTFS -DriveLetter "Q" -ErrorAction Stop -ErrorVariable $ev                   
                    }
                    catch {
                        Write-Log -Message "No fue posible crear volumen para disco Quorum con este UID: $($d.uid) en $n" -Level Error
                    }              
                }           
                'base' {
                    try {
                        New-Volume -CimSession $n -DiskUniqueId $d.uid -FriendlyName "Disco_Base" -FileSystem NTFS -DriveLetter "E"                    
                    }
                    catch {
                        Write-Log -Message "No fue posible crear volumen para disco Quorum con este UID: $($d.uid) en $n" -Level Error
                    }
                }
                'datos' {
                    try {
                        $disks += Get-Disk -CimSession $node -UniqueId $d.uid -ErrorAction Stop                   
                    }
                    catch {
                        Write-Log -Message "No existen discos para Datos con este UID: $($d.uid)" -Level Error
                    }
                }
                Default {
                    Write-Log -Message "No se han especificado discos en cluster_config.json, verifique la informacion."
                }
            }
        }
    }
    $ev
}

function Install-FCFeature {
    [CmdletBinding()]
    param (
        [Parameter()]
        [String[]]
        $Node
    )
    foreach ($n in $Node) {
        Install-WindowsFeature -Name 'Failover-Clustering' -ComputerName $n -IncludeManagementTools
    }   
}

function Move-Cluster2OU() { 

}

function Set-NICName {
    [CmdletBinding()]
    param (
        [Parameter()]
        [String[]]
        $Node,

    )
    foreach ($n in $Node) {
        $NIC = Get-NetIPInterface -CimSession $n
        foreach ($na in $NIC) {
            switch ($na) {
                '90.44' {  }
                '' {}
                '' {}
                Default {}
            }                        
        }        
    }
}

function Set-NICPriority {
    [CmdletBinding()]
    param (
        [Parameter()]
        [String[]]
        $Node
    )
    foreach ($n in $Node) {
        $NIC = Get-NetIPInterface -CimSession $n
        foreach ($na in $NIC) {
            switch ($na.InterfaceAlias) {
                'Lan Davivienda' { Set-NetIPInterface -InterfaceAlias 'Lan Davivienda' -CimSession $n -InterfaceMetric 1 }                
                'Heartbeat' { Set-NetIPInterface -InterfaceAlias 'Heartbeat' -CimSession $n -InterfaceMetric 2 }
                'Backup' { Set-NetIPInterface -InterfaceAlias 'Backup' -CimSession $n -InterfaceMetric 3 }
                Default { "No existe Interface con descripcion $($na.InterfaceAlias)" }
            }
        }      
    }    
}

 

function Write-Log {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [Alias('LogPath')]
        [string]$Path = ".\Logs\Configure-WindowsCluster-$((Get-Date).ToString('yyyy-MM-dd')).log",
        [Parameter(Mandatory = $false)]
        [ValidateSet("Error", "Warn", "Info")]
        [string]$Level = "Info",
        [Parameter(Mandatory = $false)]
        [switch]$NoClobber
    )

    Begin {         
        $VerbosePreference = 'Continue'
    }

    Process {
        if ((Test-Path $Path) -AND $NoClobber) {
            Write-Error "Log file $Path already exists, and you specified NoClobber. Either delete the file or specify a different name."
            Return
        } 
        elseif (!(Test-Path $Path)) {
            Write-Verbose "Creating $Path."
            $NewLogFile = New-Item $Path -Force -ItemType File
        }
        else {
        }
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        switch ($Level) {
            'Error' {
                Write-Error $Message
                $LevelText = 'ERROR:'
            }
            'Warn' {
                Write-Warning $Message
                $LevelText = 'WARNING:'
            }
            'Info' {
                Write-Verbose $Message
                $LevelText = 'INFO:'
            }
        }
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
    }
    End {
    }
}

 

$connection = Test-RemoteConnection -node $parameters.nodos

if ($connection) {

    Write-Log -Message "Conexion a los $(($parameters.nodos).Count) nodos mediante WSMan" -Level Info

    $OS = Get-OS -node $parameters.nodos

    Compare-OS -OS $OS

}
else {

    Write-Log -Message "Finalizando debido a falta de conectividad a uno o ambos nodos" -Level Error

} 
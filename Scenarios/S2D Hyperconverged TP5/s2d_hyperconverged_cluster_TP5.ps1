﻿##S2D Cluster##
<#
This scenario simulates hyperconverged cluster consisting of 3,4,8,or 16 nodes. 

issues: 16 node TP5 with latest patches pool creation fails when fault domains configured
#>
##### VMS Config in variables.ps1 #####
$LabConfig=@{AdminPassword='LS1setup!'; DomainAdminName='Ned'; Prefix = 's2d_HyperConverged-'; SecureBoot='Off'; CreateClientParent='No';DCEdition='ServerDataCenter'}

$NetworkConfig=@{SwitchName = 'LabSwitch' ; StorageNet1='172.16.1.'; StorageNet2='172.16.2.'}

$LAbVMs = @()
1..4| % {"S2D$_"}  | % { $LAbVMs += @{ VMName = $_ ; Configuration = 'S2D'      ; ParentVHD = 'Win2016NanoHV_G2.vhdx'   ; SSDNumber = 4; SSDSize=800GB ; HDDNumber = 12 ; HDDSize= 4TB ; MemoryStartupBytes= 512MB } } 

#### Or with Nested Virtualization #####

$LabConfig=@{AdminPassword='LS1setup!'; DomainAdminName='Ned'; Prefix = 'S2DLabNested-'; SecureBoot='On'; CreateClientParent='No';DCEdition='ServerDataCenter';ClientEdition='Enterprise'}
$NetworkConfig=@{SwitchName = 'LabSwitch' ; StorageNet1='172.16.1.'; StorageNet2='172.16.2.'}
$LAbVMs = @()
1..4 | % {"S2D$_"}  | % { $LAbVMs += @{ VMName = $_ ; Configuration = 'S2D'      ; ParentVHD = 'Win2016NanoHV_G2.vhdx'   ; SSDNumber = 4; SSDSize=800GB ; HDDNumber = 12 ; HDDSize= 4TB ; MemoryStartupBytes= 4GB ; NestedVirt='Yes'} }

###############
# Run from DC #
###############

Start-Transcript -Path '.\S2DHydration.log'

$StartDateTime = get-date
Write-host "Script started at $StartDateTime"
##### LAB Config #####

# 3,4,8, or 16 nodes
$numberofnodes=4
#servernames
1..$numberofnodes | ForEach-Object {$servers=$servers+@("S2D$_")}
#Cluster Name
$ClusterName="S2D-Cluster"

#?Networking
$Networking='Yes'


#Number of MultiResiliencyDisks Created
$MRTNumber=$numberofnodes

###############


#install features for management
Install-WindowsFeature -Name RSAT-Clustering,RSAT-Clustering-Mgmt,RSAT-Clustering-PowerShell,RSAT-Storage-Replica,RSAT-Hyper-V-Tools

<#install Hyper-V for core servers
Invoke-Command -ComputerName $servers -ScriptBlock {Enable-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V -Online -NoRestart}
foreach ($server in $servers) {Install-WindowsFeature -Name Failover-Clustering,Failover-Clustering-S2D,Hyper-V-PowerShell -ComputerName $server} 
#restart and wait for computers
Invoke-Command -ComputerName $servers -ScriptBlock {Restart-Computer -Force}
Start-Sleep 60
#>

if ($Networking -eq "Yes"){
    ###Configure networking###
    Invoke-Command -ComputerName $servers -ScriptBlock {New-VMSwitch -Name SETSwitch -EnableEmbeddedTeaming $TRUE -MinimumBandwidthMode Weight -NetAdapterName (Get-NetIPAddress -IPAddress 10.* ).InterfaceAlias}
    $Servers | ForEach-Object {
        Rename-VMNetworkAdapter -ManagementOS -Name SETSwitch -NewName Management1 -ComputerName $_
        Add-VMNetworkAdapter    -ManagementOS -Name Management2 -SwitchName SETSwitch -ComputerName $_
    }
    Start-Sleep 5
    Clear-DnsClientCache
}

###Test and create new cluster ###
Test-Cluster –Node $servers –Include “Storage Spaces Direct”,Inventory,Network,”System Configuration”
New-Cluster –Name $ClusterName –Node $servers –NoStorage 
Start-Sleep 5
Clear-DnsClientCache

#region Create Fault Domains https://technet.microsoft.com/en-us/library/mt703153.aspx (just example, not best practice. It has caveats this way. Will change in RTM)
if ($numberofnodes -eq 4){
$xml =  @"
<Topology>
    <Site Name="SEA" Location="Contoso HQ, 123 Example St, Room 4010, Seattle">
        <Rack Name="Rack01" Location="Contoso HQ, Room 4010, Aisle A, Rack 01">
                <Node Name="S2D1"/>
                <Node Name="S2D2"/>
                <Node Name="S2D3"/>
                <Node Name="S2D4"/>
        </Rack>
    </Site>
</Topology>
"@

Set-ClusterFaultDomainXML -XML $xml -CimSession $ClusterName

}

if ($numberofnodes -eq 8){

$xml =  @"
<Topology>
    <Site Name="SEA" Location="Contoso HQ, 123 Example St, Room 4010, Seattle">
        <Rack Name="Rack01" Location="Contoso HQ, Room 4010, Aisle A, Rack 01">
            <Node Name="S2D1"/>
            <Node Name="S2D2"/>
            <Node Name="S2D3"/>
            <Node Name="S2D4"/>
        </Rack>
        <Rack Name="Rack02" Location="Contoso HQ, Room 4010, Aisle A, Rack 02">
            <Node Name="S2D5"/>
            <Node Name="S2D6"/>
            <Node Name="S2D7"/>
            <Node Name="S2D8"/>
        </Rack>
    </Site>
</Topology>
"@

Set-ClusterFaultDomainXML -XML $xml -CimSession $ClusterName
    
}

<# TP5 issues
if ($numberofnodes -eq 16){
$xml =  @"
<Topology>
    <Site Name="SEA" Location="Contoso HQ, 123 Example St, Room 4010, Seattle">
        <Rack Name="Rack01" Location="Contoso HQ, Room 4010, Aisle A, Rack 01">
            <Chassis Name="Chassis01" Location="Rack Unit 1 (Upper)" >
                <Node Name="S2D1"/>
                <Node Name="S2D2"/>
                <Node Name="S2D3"/>
                <Node Name="S2D4"/>
            </Chassis>
            <Chassis Name="Chassis02" Location="Rack Unit 1 (Lower)" >
                <Node Name="S2D5"/>
                <Node Name="S2D6"/>
                <Node Name="S2D7"/>
                <Node Name="S2D8"/>
            </Chassis>
        </Rack>
        <Rack Name="Rack02" Location="Contoso HQ, Room 4010, Aisle A, Rack 02">
            <Chassis Name="Chassis03" Location="Rack Unit 2 (Upper)" >
                <Node Name="S2D9"/>
                <Node Name="S2D10"/>
                <Node Name="S2D11"/>
                <Node Name="S2D12"/>
            </Chassis>
            <Chassis Name="Chassis04" Location="Rack Unit 2 (Lower)" >
                <Node Name="S2D13"/>
                <Node Name="S2D14"/>
                <Node Name="S2D15"/>
                <Node Name="S2D16"/>
            </Chassis>
        </Rack>
    </Site>
</Topology>
"@

Set-ClusterFaultDomainXML -XML $xml -CimSession $ClusterName

}

#>
#endregion Create Fault Domains

#show fault domain configuration
Get-ClusterFaultDomainxml -CimSession $ClusterName

#TP5
Enable-ClusterS2D -CimSession $ClusterName -AutoConfig:0 -Confirm:$false -SkipEligibilityChecks

#TP5 fix
Invoke-Command -ComputerName $servers -ScriptBlock {Get-ScheduledTask "SpaceManagerTask" | Disable-ScheduledTask}

#register storage provider 
Get-StorageProvider | Register-StorageSubsystem -ComputerName $ClusterName
   
#create pool (sometime I cannot get all disks, therefore there is a loop)
do {
    $phydisk = Get-StorageSubSystem -FriendlyName *$ClusterName | Get-PhysicalDisk -CanPool $true
    Write-Host "Number of physical disks found:" $phydisk.count -ForegroundColor Cyan
}
until ($phydisk.count -eq $numberofnodes*16)
$pool=New-StoragePool -FriendlyName  DirectPool -PhysicalDisks $phydisk -StorageSubSystemFriendlyName *$ClusterName 
$pool | get-physicaldisk | where Size -le 900GB | Set-PhysicalDisk -MediaType SSD
$pool | get-physicaldisk | where Size -ge 900GB | Set-PhysicalDisk -MediaType HDD
#Create Tiers
$Perf = New-StorageTier -FriendlyName Performance  -MediaType SSD -ResiliencySettingName Mirror -StoragePoolFriendlyName $pool.friendlyname  -PhysicalDiskRedundancy 2
if  ($numberofnodes -ne 3){
    $Cap  = New-StorageTier -FriendlyName Capacity     -MediaType HDD -ResiliencySettingName Parity -StoragePoolFriendlyName $pool.friendlyname  -PhysicalDiskRedundancy 2
}
if  ($numberofnodes -eq 3){
    $Cap  = New-StorageTier -FriendlyName Capacity     -MediaType HDD -ResiliencySettingName Mirror -StoragePoolFriendlyName $pool.friendlyname  -PhysicalDiskRedundancy 2
}

1..$MRTNumber | ForEach-Object {
New-Volume -StoragePoolFriendlyName $pool.friendlyname -FriendlyName MultiResiliencyDisk$_ -FileSystem CSVFS_ReFS -StorageTiers $perf,$cap -StorageTierSizes 1TB,10TB
}

<# More manual way
if  ($numberofnodes -eq 3){    
    1..$MRTNumber | ForEach-Object {
        $vdiskname="MultiResiliencyDisk$_"
        $virtualDisk = new-virtualdisk -StoragePoolUniqueId $pool.uniqueid -FriendlyName $vdiskname -StorageTiers $perf,$Cap -StorageTierSizes 10TB
        $virtualDisk | get-disk | New-Partition -UseMaximumSize
        Get-ClusterResource -Cluster $ClusterName -Name *$vdiskname* | Suspend-ClusterResource
        $virtualdisk | Get-Disk | Get-Partition | get-volume | Initialize-Volume -FileSystem REFS -AllocationUnitSize 4KB -NewFileSystemLabel $vdiskname -confirm:$False
        Get-ClusterResource -Cluster $ClusterName -Name *$vdiskname* | Resume-ClusterResource
        Get-ClusterResource -Cluster $ClusterName -Name *$vdiskname* | Add-ClusterSharedVolume
    }
}

if ($numberofnodes -ge 4){
    1..$MRTNumber | ForEach-Object {
        $vdiskname="MultiResiliencyDisk$_"
        $virtualDisk = new-virtualdisk -StoragePoolUniqueId $pool.uniqueid -FriendlyName $vdiskname -StorageTiers $perf,$cap -StorageTierSizes 1TB,10TB
        $virtualDisk | get-disk | New-Partition -UseMaximumSize
        Get-ClusterResource -Cluster $ClusterName -Name *$vdiskname* | Suspend-ClusterResource
        $virtualdisk | Get-Disk | Get-Partition | get-volume | Initialize-Volume -FileSystem REFS -AllocationUnitSize 4KB -NewFileSystemLabel $vdiskname -confirm:$False
        Get-ClusterResource -Cluster $ClusterName -Name *$vdiskname* | Resume-ClusterResource
        Get-ClusterResource -Cluster $ClusterName -Name *$vdiskname* | Add-ClusterSharedVolume
    }
}
#>

start-sleep 10

#rename CSV(s)
Get-ClusterSharedVolume -Cluster $ClusterName | % {
    $volumepath=$_.sharedvolumeinfo.friendlyvolumename
    $newname=$_.name.Substring(22,$_.name.Length-23)
    Invoke-Command -ComputerName (Get-ClusterSharedVolume -Cluster $ClusterName -Name $_.Name).ownernode -ScriptBlock {param($volumepath,$newname); Rename-Item -Path $volumepath -NewName $newname} -ArgumentList $volumepath,$newname -ErrorAction SilentlyContinue
} 


###Configure quorum###

#Create new directory
Invoke-Command -ComputerName DC -ScriptBlock {new-item -Path c:\Shares -Name S2DWitness -ItemType Directory}
$nodes=@()
1..$numberofnodes | % {$nodes+="corp\S2D$_$"}
$nodes+="corp\$ClusterName$"
$nodes+="corp\Administrator"
New-SmbShare -Name S2DWitness -Path c:\Shares\S2DWitness -FullAccess $nodes -CimSession DC
# Set NTFS permissions 
Invoke-Command -ComputerName DC -ScriptBlock {(Get-SmbShare S2DWitness).PresetPathAcl | Set-Acl}
#Set Quorum
Set-ClusterQuorum -Cluster $ClusterName -FileShareWitness \\DC\S2DWitness

#set CSV Cache
(Get-Cluster $ClusterName).BlockCacheSize = 1024 

#show errors... 
Get-StorageSubSystem *$ClusterName | Debug-StorageSubSystem

#get healthreport
Get-StorageSubSystem *$ClusterName  | Get-StorageHealthReport -Count 5

#get cluster diagnostic
Get-ClusterDiagnostics -ClusterName $ClusterName

#storagedisagnostic
Get-StorageSubSystem -FriendlyName *$ClusterName | Get-StorageDiagnosticInfo -DestinationPath c:\temp

#unregister StorageSubsystem
#$ss=Get-StorageSubSystem -FriendlyName *$ClusterName
#Unregister-StorageSubsystem -ProviderName "Windows Storage Management Provider" -StorageSubSystemUniqueId $ss.UniqueId

#finishing
Write-Host "Script finished at $(Get-date) and took $(((get-date) - $StartDateTime).TotalMinutes) Minutes"
Stop-Transcript

<#
    .SYNOPSIS
        Installs ScreenConnect client on All Windows Azure VMs

    .DESCRIPTION
        Uses CustomScriptExtension to install the client specific instance of ScreenConnect on all Windows Virtual Machines in a Azure Subscription

    .PARAMETER Uri 
        The Windows (.MSI) type ScreenConnect installer URL taken from https://screenconnect.com > Access > Build

    .PARAMETER ResourceGroupName
        The Name of the Resource Group the temporary Storage Account should be created in

    .EXAMPLE
        C:\PS>Install-AzScreenConnect -ResourceGroupName "RG-AZ-Core" -Uri "https://screenconnect.com/Bin/ConnectWiseControl.ClientSetup.msi"

#>

param (
    [Parameter(Mandatory)]
    [string]$Uri, # Uri should be the Windows (.MSI) type ScreenConnect installer URL taken from https://screenconnect.com > Access > Build
    [Parameter(Mandatory)]
    [string]$ResourceGroupName # The Name of the Resource Group the temporary Storage Account should be created in
)

$ErrorActionPreference = "Stop"

# Credit for Write-ProgressHelper function https://adamtheautomator.com/building-progress-bar-powershell-scripts/
function Write-ProgressHelper {
	param(
        [string]$Message
	)
    
    Write-Progress -Activity 'Deploy ScreenConnect' -Status $Message
}

## The Az location of the Resource Group
$Location = Get-AzResourceGroup -Name $ResourceGroupName | Select-Object Location

## Create the Powershell Script
Write-ProgressHelper -Message 'Creating installation PS1 script...'
### Make a temporary file
$TemporaryScript = New-TemporaryFile
### Multi-line string to out to the temp file
$Script = @'
    param ($uri)
    $tmpOutfile = New-TemporaryFile
    $downloadUri = $uri
    Invoke-WebRequest -Uri $downloadUri -OutFile $tmpOutfile.FullName
    $outFile = $tmpOutfile | Rename-Item -NewName { $_ -replace 'tmp$', 'msi' } -PassThru
    $paramsList = '/i', "$outFile", '/qb'
    $install = Start-Process msiexec.exe -Wait -ArgumentList $paramsList
    $install.ExitCode
    Remove-Item $outFile
'@
### Write the string to the file
Set-Content -Path $TemporaryScript -Value $Script

## Create temporary storage account to upload script
Write-ProgressHelper -Message "Creating Storage Account... "
### Random name, lower case and numbers only
$StorageAccountName = -join ((48..57) + (97..122) | Get-Random -Count 24 | % {[char]$_})
### Create the storage account
New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $Location.Location -SkuName "Standard_LRS" -Kind Storage
### Get the keys to the castle
$StorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName) | Where-Object {$_.KeyName -eq "key1"}
## Create a container in the Storage Account
Write-ProgressHelper -Message "Creating Container Account... "
### The context where the container should exist
$StorageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey.Value
### Random name, lower case and numbers only
$StorageContainerName = -join ((48..57) + (97..122) | Get-Random -Count 24 | % {[char]$_})
### Create the Container
$ContainerName = New-AzStorageContainer -Name $StorageContainerName -Context $StorageContext
### Variable for upload
$Container = Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName | Get-AzStorageContainer -Container $ContainerName.Name
### Rename that temporary file to something more appropriate
$ScriptName = "Install-ScreenConnect.ps1"
### Upload parameters
$Upload = @{
    'File' = $TemporaryScript
    'BlobType' = 'Block'
    'Blob' = $ScriptName
}
### Upload the script to the Container
Write-ProgressHelper -Message "Uploading PS1 to Azure Container... "
$Container | Set-AzStorageBlobContent @Upload

## Add the extension on all VMs
### Get a list of all VMs running Windows
$OsType = (get-azvm).StorageProfile.OsDisk.OsType
$VirtualMachines = Get-azvm | where-object {$OsType -eq 'Windows'}
### Perform these steps on each VM listed
foreach ($VM in $VirtualMachines){
### Only one CustomScript extension can exist, check and remove if one already exists
    $vmExtensions = Get-AzVMExtension -VMName $VM.Name -ResourceGroupName $VM.ResourceGroupName
    if ($vmExtensions.ExtensionType -match "CustomScriptExtension"){
        Write-ProgressHelper -Message "Removing existing ExtensionScript from $($VM.Name)... "
        $ExistingCustomScript = $vmExtensions | Where-Object {$_.ExtensionType -eq "CustomScriptExtension"}
        Remove-AzVMCustomScriptExtension `
        -VMName $VM.Name `
        -ResourceGroupName $VM.ResourceGroupName `
        -Name $ExistingCustomScript.Name
    }
### Set the CustomScript as the PowerShell script and passthrough the Uri 
    Write-ProgressHelper -Message "Installing ScreenConnect on $($VM.Name)... "
    $SetExtension = Set-AzVMCustomScriptExtension `
        -ResourceGroupName $ResourceGroupName `
        -VMName $VM.Name `
        -Name "InstallScreenConnect" `
        -Location $VM.Location `
        -StorageAccountName $StorageAccountName `
        -StorageAccountKey $StorageAccountKey.Value `
        -FileName $ScriptName `
        -ContainerName $ContainerName.Name `
        -Run ".\$ScriptName -uri $uri"
        $Results.Add = @{
            "$($VM.Name)"="$($SetExtension.Status)"
        }
}

## Clean up
### Remove the Storage Account
Write-ProgressHelper -Message "Removing Storage Account... "
Remove-AzStorageAccount -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName -Force
### Remove the temporary file
Write-ProgressHelper -Message "Removing temporary files... "
Remove-Item $TemporaryScript -Force

## Dispaly Results
Write-Host $Results

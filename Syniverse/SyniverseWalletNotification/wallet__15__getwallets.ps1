################################################
#
# INPUT
#
################################################

Param(
    [hashtable] $params
)

#-----------------------------------------------
# DEBUG SWITCH
#-----------------------------------------------

$debug = $true


#-----------------------------------------------
# INPUT PARAMETERS, IF DEBUG IS TRUE
#-----------------------------------------------

if ( $debug ) {
    $params = [hashtable]@{
	    Password= "def"
	    scriptPath= "D:\Scripts\Syniverse\WalletNotification"
	    Username= "abc"
    }
}


################################################
#
# NOTES
#
################################################

<#

TODO [ ] more logging
TODO [ ] replace mssql with already existent functions of EpiServer

#>

################################################
#
# SCRIPT ROOT
#
################################################

if ( $debug ) {
  # Load scriptpath
  if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
      $scriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
  } else {
      $scriptPath = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0])
  }
} else {
  $scriptPath = "$( $params.scriptPath )" 
}
Set-Location -Path $scriptPath


################################################
#
# SETTINGS
#
################################################

# General settings
$functionsSubfolder = "functions"
$settingsFilename = "settings.json"
$moduleName = "GETWALLETTEMPLATE"
$processId = [guid]::NewGuid()
$timestamp = [datetime]::Now.ToString("yyyyMMddHHmmss")

# Load settings
$settings = Get-Content -Path "$( $scriptPath )\$( $settingsFilename )" -Encoding UTF8 -Raw | ConvertFrom-Json

# Allow only newer security protocols
# hints: https://www.frankysweb.de/powershell-es-konnte-kein-geschuetzter-ssltls-kanal-erstellt-werden/
if ( $settings.changeTLS ) {
  $AllProtocols = @(    
      [System.Net.SecurityProtocolType]::Tls12
      #[System.Net.SecurityProtocolType]::Tls13,
      ,[System.Net.SecurityProtocolType]::Ssl3
  )
  [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
}

# more settings
$logfile = $settings.logfile
$mssqlConnectionString = $settings.responseDB


# append a suffix, if in debug mode
if ( $debug ) {
  $logfile = "$( $logfile ).debug"
}


################################################
#
# FUNCTIONS & ASSEMBLIES
#
################################################

Add-Type -AssemblyName System.Data  #, System.Text.Encoding

# Load all PowerShell Code
"Loading..."
Get-ChildItem -Path ".\$( $functionsSubfolder )" -Recurse -Include @("*.ps1") | ForEach {
    . $_.FullName
    "... $( $_.FullName )"
}

<#
# Load all exe files in subfolder
$libExecutables = Get-ChildItem -Path ".\$( $libSubfolder )" -Recurse -Include @("*.exe") 
$libExecutables | ForEach {
    "... $( $_.FullName )"
    
}

# Load dll files in subfolder
$libExecutables = Get-ChildItem -Path ".\$( $libSubfolder )" -Recurse -Include @("*.dll") 
$libExecutables | ForEach {
    "Loading $( $_.FullName )"
    [Reflection.Assembly]::LoadFile($_.FullName) 
}
#>


################################################
#
# LOG INPUT PARAMETERS
#
################################################

# Start the log
Write-Log -message "----------------------------------------------------"
Write-Log -message "$( $modulename )"
Write-Log -message "Got a file with these arguments:"
[Environment]::GetCommandLineArgs() | ForEach {
    Write-Log -message "    $( $_ -replace "`r|`n",'' )"
}
# Check if params object exists
if (Get-Variable "params" -Scope Global -ErrorAction SilentlyContinue) {
    $paramsExisting = $true
} else {
    $paramsExisting = $false
}

# Log the params, if existing
if ( $paramsExisting ) {
    Write-Log -message "Got these params object:"
    $params.Keys | ForEach-Object {
        $param = $_
        Write-Log -message "    ""$( $param )"" = ""$( $params[$param] )"""
    }
}


################################################
#
# GET WALLETS
#
################################################

#-----------------------------------------------
# AUTHENTICATION + HEADERS
#-----------------------------------------------

$baseUrl = $settings.base
$contentType = $settings.contentType
$headers = @{
    "Authorization"="Basic $( Get-SecureToPlaintext -String $settings.login.accesstoken )"
    "X-API-Version"="2"
    "int-companyid"=$settings.companyId
}


#-----------------------------------------------
# LOAD WALLET DETAILS
#-----------------------------------------------

Write-Log "Loading available wallets"

$walletDetails = @()

<#
$walletIds | ForEach {
    $walletId = $_
    $walletUrl = "$( $baseUrl )/companies/$( $companyId )/campaigns/wallet/$( $walletId )"
    $walletDetails += Invoke-RestMethod -ContentType $contentType -Method Get -Uri $walletUrl -Headers $headers
}
#>
$param = @{
    "Uri" = "$( $baseUrl )/companies/$( $settings.companyId )/campaigns/wallet"
    "ContentType" = $contentType
    "Method" = "Get"
    "Headers" = $headers
    "Verbose" = $true
}
$walletDetails = Invoke-RestMethod @param

$wallets = $walletDetails | Select @{name="id";expression={ $_.wallet_id }}, @{name="name";expression={ "$( $_.wallet_id )$( $settings.nameConcatChar )$( $_.Name )" }}

Write-Log "Loaded $( $wallets.count ) wallets through the API"

$wallets


################################################
#
# RETURN VALUES TO PEOPLESTAGE
#
################################################

$wallets
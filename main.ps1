Set-ExecutionPolicy Bypass
$ErrorActionPreference = 'SilentlyContinue'


function Regex-Name ( [string]$program_full_name ) {
    <#
     # Split program name into strings $program_name and $program_version.
     # Used regex to split $program_full_name after first " " or "_" or "." or "," into:
     #  * $program_name - supposed to contain program name.
     #  * $program_version - supposed to contain program version.
     # Operate on substrings to make sure $program_name:
     #  * first letter is upper case and rest letters lower case
     #
     # :param: str: $program_name: String with program name and / or version.
     # :return: Collection of strings $program_name, $program_version.
     # :rtype: collection[str, str]
     #>
    [string]$program_name, [string]$program_version = $program_full_name `
        -split{ $_ -eq " " -or `
                $_ -eq "," -or `
                $_ -eq "." -or `
                $_ -eq "_" `
        }, 2
    [string]$program_name = `
        $program_name.substring(0,1).toupper()+ `
        $program_name.substring(1).tolower()
    return $program_name, $program_version
}

function Is-Installer ( [string]$program_name ) {
    <#
     # Check if program with given version is found in Windows installer. Used SQL Query for fast execution.
     # * Find only if program with given version is found.
     #
     # :param: str: $program_name: String with program name and / or version.
     # :return: True if $program_name is found by Windows Installer else False.
     # :rtype: bool
     #>
    return (Get-WMIObject -Query "SELECT * FROM Win32_Product Where Name Like '%$program_name%'").Length -gt 0
}

function List-Program-Installations ( [string]$program_full_name ) {
    <#
     # List $program_full_name in any version except the one with given version is found in Windows installer.
     # Used regex to split $program_full_name after first " " or "_" or "." or "," into:
     #  * $program_name - supposed to contain program name.
     #  * $program_version - supposed to contain program version.
     #
     # :param: str: $program_full_name: String with program name and / or version.
     # :return: List of found programs in Windows Installer similar to $program_name.
     # :rtype collection of WmiObject.name
     #>
    $program_name, $program_version = Regex-Name $program_full_name
    return Get-WmiObject -Class Win32_Product `
        | Where-Object { `
            $_.Name -Match $program_name -or `
            $_.Name -match $program_name.ToUpper() -or `
            $_.Name -match $program_name.ToLower() -and `
            $_.Name -notMatch $program_version`
    }
}

function List-Registry-Entries ( [string]$program_full_name ) {
    <#
     # List $program_full_name in any version except the one with given version is found in Windows registry.
     # Used regex to split $program_full_name after first " " or "_" or "." or "," into:
     #  * $program_name - supposed to contain program name.
     #  * $program_version - supposed to contain program version.
     #
     # :param: str $program_full_name: String with program name and / or version.
     # :return: List of found registry positions in Windows registry similar to $program_name.
     # :rtype collection of strings
     #>
    $program_name, $program_version = Regex-Name $program_full_name
    $x86registry = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* `
        | Where-Object { `
            $_.DisplayName -Match $program_name -or `
            $_.DisplayName -match $program_name.ToUpper() -or `
            $_.DisplayName -match $program_name.ToLower() -and `
            $_.DisplayName -notMatch $program_version `
        }
    $x64registry = Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* `
        | Where-Object { `
            $_.DisplayName -Match $program_name -or `
            $_.DisplayName -match $program_name.ToUpper() -or `
            $_.DisplayName -match $program_name.ToLower() -and `
            $_.DisplayName -notMatch $program_version `
        }
    return $x86registry + $x64registry
}

function List-Directory-Entries ( [string]$program_full_name ) {
    <#
     # List $program_name in every directory on C: drive indiscriminately.
     # Used regex to split $program_full_name after first " " or "_" or "." or "," into:
     #  * $program_name - supposed to contain program name.
     #  * $program_version - supposed to contain program version.
     #
     # :param: str $program_full_name: String with program name and / or version.
     # :return: List of directories in Windows C: drive similiar to $program_name.
     # :rtype: collection of strings
     #>
    $program_name, $program_version = regex_name $program_full_name
    return Get-ChildItem -Path "C:" -recurse -Directory `
        | Where-Object {`
            $_.Name -match $program_name.ToUpper() -or `
            $_.Name -match $program_name.ToLower() -or `
            $_.Name -match $program_name `
        } -ErrorAction SilentlyContinue
}

function List-Path-Entries ( [string]$program_full_name ) {
    <#
     # List $program_name in Path environment variables in the machine.
     # Used regex to split $program_full_name after first " " or "_" or "." or "," into:
     #  * $program_name - supposed to contain program name.
     #  * $program_version - supposed to contain program version.
     # Program split outputs by ";" as path file is continuous line of text.
     #
     # :param: str $program_full_name: String with program name and / or version.
     # :return: List of environment variables in Path file on Windows machine.
     # :rtype: collection of strings
     #>
    $program_name, $program_version = Regex-Name $program_full_name
    return $env:path -split ";" `
         | Where-Object { `
            $_ -match $program_name -or `
            $_ -match $program_name.ToUpper() -or `
            $_ -match $program_name.ToLower() `
        }
}

function Remove-Program-Installation ( [string]$program_full_name ) {
    <#
     # Remove content of List-Program-Installations collection found in Windows installer.
     #
     # :param: str $program_full_name: String with program name and / or version.
     # :return: Remove path entries related to the given $program_full_name.
     # :rtype: none
     #>
    foreach ($program_installation_to_remove in List-Program-Installations $program_full_name) {
        try {
            $program_installation_to_remove.Uninstall()     # This easy
        } catch {
            Write-Warning $Error[0]
        }
    }
}

function Remove-Registry-Entry ( [string]$program_full_name ) {
    <#
     # Remove content of List-Registry-Entries collection found in Windows registry.
     #
     # :param: str $program_full_name: String with program name and / or version.
     # :return: Remove registry entries related to the given $program_full_name.
     # :rtype: none
     #>
    try {
        foreach ($registry_entry_to_remove in List-Registry-Entries $program_full_name) {
            Remove-Item $registry_entry_to_remove -ErrorAction SilentlyContinue     # This easy
        }
    } catch {
        Write-Warning $Error[0]
    }
}

function Remove-Directory-Entry ( [string]$program_full_name ) {
    <#
     # Remove content of List-Directory-Entries collection recursive from directories in Windows C: drive.
     #
     #
     # :param: str $program_full_name: String with program name and / or version.
     # :return: Remove registry entries related to the given $program_full_name.
     # :rtype: none
     #>
    try {
        foreach ($directory_entry_to_remove in List-Directory-Entries $program_full_name) {
            Remove-Item -path [$directory_entry_to_remove] -Recurse -Force -ErrorAction SilentlyContinue      # This easy
        }
    } catch {
        Write-Warning $Error[0]
    }
}

function Remove-Path-Entry ( [string]$program_full_name ) {
    <#
     # Remove content of List-Path-Entries collection from Windows path.
     #
     # :param: str $program_full_name: String with program name and / or version.
     # :return: Remove path entries related to the given $program_full_name.
     # :rtype: none
     #>
    foreach ($path_entry_to_remove in List-Path-Entries $program_full_name) {
        try {
            $env:Path = ($env:Path.Split(';') `
                | Where-Object -FilterScript { `
                    $_ -ne $path_entry_to_remove `
                } ) -join ';'
        } catch {
            Write-Warning $Error[0]
        }
    }
}

function One-To-Rule-Them-All ( [string]$program_full_name ) {
    <#
     # This function wraps all previous functions into one.
     # Remove-Program-Installation: uninstall every program that has in the name $program_full_name.
     # Remove-Registry-Entry: purge registry entries of program mentions that has in the name $program_full_name.
     # Remove-Directory-Entry: purge every directory recursively that has in the name $program_full_name.
     # Remove-Path-Entry: purge path entries of program mentions that has in the name $program_full_name.
     #
     # :param: str $program_full_name: String with program name and / or version.
     # :return: Supposedly purge program from the machine.
     # :rtype: none
     #>
    Remove-Program-Installation $program_full_name
    Remove-Registry-Entry $program_full_name
    Remove-Directory-Entry $program_full_name
    Remove-Path-Entry $program_full_name
}

One-To-Rule-Them-All("Python 1.2.3")

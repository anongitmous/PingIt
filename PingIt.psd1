#
# Module manifest for module 'PingIt'
#
# Generated by: mattf
#
# Generated on: 5/16/2023
#

@{

# Script module or binary module file associated with this manifest.
RootModule = 'PingIt.psm1'

# Version number of this module.
ModuleVersion = '0.0.9'

# Supported PSEditions
# CompatiblePSEditions = @('Core')

# ID used to uniquely identify this module
GUID = '967835a7-b970-4bd6-87e5-fbcffd362e7f'

# Author of this module
Author = 'mattf'

# Company or vendor of this module
CompanyName = 'n/a'

# Copyright statement for this module
Copyright = '(c) mattf. All rights reserved.'

# Description of the functionality provided by this module
Description = 'Ping-like functionality that also has the capability to track outages and latency issues.'

# Minimum version of the PowerShell engine required by this module
PowerShellVersion = '7.2.0'

# Name of the PowerShell host required by this module
# PowerShellHostName = ''

# Minimum version of the PowerShell host required by this module
# PowerShellHostVersion = ''

# Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# DotNetFrameworkVersion = ''

# Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# ClrVersion = ''

# Processor architecture (None, X86, Amd64) required by this module
# ProcessorArchitecture = ''

# Modules that must be imported into the global environment prior to importing this module
# RequiredModules = @()

# Assemblies that must be loaded prior to importing this module
# RequiredAssemblies = @()

# Script files (.ps1) that are run in the caller's environment prior to importing this module.
# ScriptsToProcess = @()

# Type files (.ps1xml) to be loaded when importing this module
# TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
# FormatsToProcess = @()

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
# NestedModules = @()

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = @('Invoke-PingIt')

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = '*'

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = @('PingIt')

# DSC resources to export from this module
# DscResourcesToExport = @()

# List of all modules packaged with this module
# ModuleList = @()

# List of all files packaged with this module
FileList = @('PingIt.psd1', "PingIt.psm1")

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = @('Ping', 'Icmp', 'Network', 'Diagnostics', 'Troubleshooting', 'Linux', 'Windows')

        # A URL to the license for this module.
        LicenseUri = 'https://github.com/anongitmous/PingIt/blob/master/LICENSE'

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/anongitmous/PingIt'

        # A URL to an icon representing this module.
        # IconUri = ''

        # ReleaseNotes of this module
        ReleaseNotes = @'
## 0.0.9
* Updated the minimum version. Added some minor comments.

## 0.0.8
* The actual status is now displayed to the user for ping result error statuses for which we do not specifically account

## 0.0.7
* Added a default handler for ping results
* Fixed regression defect within FinalizeOutage introduced when support for configuring a ping count threshold for outages
* If there is only a single latency or outage issue, then neither summary info nor total info will be shown

## 0.0.6
* When tracking latency issues using the -LatencyMovingAvg switch, prior to the summary output display, it can be difficult
to figure out from the per-ping output when a latency issue has come to an end. A change has been made which inverts the foreground
and background colors of a ping output to indicate the end of a latency issue.
* If the -Timestamps switch is specified, per-ping output timestamps are now displayed using the 24-hour clock.
* Added new parameter, -OutageMinPackets, which controls how many non-successful pings must occur for an outage record to be created.
Using the default of 2 (or higher) avoids situations where e.g. a single timeout creates an outage record.

## 0.0.5
* Updated manifest's tags

## 0.0.4
* In some instances, summary output was not being output when Ctrl-C was pressed. The problem seems to have been that
TreatControlCAsInput was a script-level variable. Moving its handling into Invoke-PingIt seems to have rectified the issue

## 0.0.3
* intermittently, final summary and stats data were not showing up, so that logic was moved inside of the try block
* added ErrorAction = SilentlyContinue to the calls to Test-Connection

## 0.0.2
* tightened up the resolve destination functionality to be more uniform in the event of errors
* other minor tweaks

## 0.0.1
Initial Release
* Works on both Windows and Linux
  ** On Linux, sudo is required due to Test-Connection being broken on Linux
     see https://github.com/MicrosoftDocs/PowerShell-Docs/issues/8684
'@

        # Prerelease string of this module
        # Prerelease = ''

        # Flag to indicate whether the module requires explicit user acceptance for install/update/save
        # RequireLicenseAcceptance = $false

        # External dependent modules of this module
        # ExternalModuleDependencies = @()

    } # End of PSData hashtable

} # End of PrivateData hashtable

# HelpInfo URI of this module
# HelpInfoURI = ''

# Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
# DefaultCommandPrefix = ''

}


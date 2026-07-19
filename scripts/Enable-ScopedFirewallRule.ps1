<#
.SYNOPSIS
Previews or creates one or more narrowly scoped inbound Windows Firewall rules.

.DESCRIPTION
No change is made unless -Apply is supplied. Even with -Apply, PowerShell asks
for confirmation. Rules are limited to the configured service, one protocol,
one port, the configured server LAN address, and the Private network profile.
This script never configures a router, enables UPnP, changes DNS recursion or
exposes an administration panel.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('WebHttp', 'WebHttps', 'MailSmtp', 'MailSubmission', 'MailImaps', 'MailSmtps', 'AuthoritativeDnsUdp', 'AuthoritativeDnsTcp')]
    [string[]]$Rule,

    [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\server.config.psd1'),

    [switch]$Apply,

    # Required in addition to the config flag before DNS 53 can be considered.
    [switch]$PublishAuthoritativeDns
)

. (Join-Path $PSScriptRoot 'lib\HomeServer.Common.ps1')
$config = Get-HomeServerConfig -ConfigPath $ConfigPath
$definitions = Get-HomeServerRuleDefinitions

$selectedDefinitions = foreach ($ruleId in ($Rule | Select-Object -Unique)) {
    $definition = @($definitions | Where-Object { $_.Id -eq $ruleId })
    if ($definition.Count -ne 1) {
        throw "Unknown rule: $ruleId"
    }
    $definition[0]
}

$pending = [System.Collections.Generic.List[object]]::new()
foreach ($definition in $selectedDefinitions) {
    if (-not (Test-HomeServerRuleConfigured -Rule $definition -Config $config)) {
        throw "Rule '$($definition.Id)' is disabled by config. Enable only the needed feature first."
    }
    if ($definition.Id -like 'AuthoritativeDns*' -and -not $PublishAuthoritativeDns) {
        throw 'DNS 53 needs both Features.PublishAuthoritativeDns = $true and -PublishAuthoritativeDns.'
    }

    $serviceName = [string]$config.ServiceNames[$definition.ServiceKey]
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($null -eq $service -or $service.Status -ne 'Running') {
        throw "Service '$serviceName' is not running; no firewall rule will be created."
    }

    $displayName = "HomeServer-$($definition.Id)"
    $existing = @(Get-NetFirewallRule -DisplayName $displayName -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        Write-Warning "Rule '$displayName' already exists. It will not be modified by this script."
        continue
    }

    [void]$pending.Add([pscustomobject]@{
            DisplayName = $displayName
            Protocol = $definition.Protocol
            Port = $definition.Port
            ServiceName = $serviceName
            Description = $definition.Description
        })
}

if ($pending.Count -eq 0) {
    Write-Host 'No new firewall rule is required.' -ForegroundColor Yellow
    return
}

Write-Host 'Proposed local firewall rules:' -ForegroundColor Cyan
$pending | Format-Table DisplayName, Protocol, Port, ServiceName, Description -AutoSize
Write-Host 'Router port forwarding is intentionally NOT changed.' -ForegroundColor Yellow

if (-not $Apply) {
    Write-Host 'Preview only. Re-run with -Apply after reviewing the list; use -WhatIf first if desired.' -ForegroundColor Yellow
    return
}

if (-not $WhatIfPreference) {
    $privateProfiles = @(Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Private' })
    if ($privateProfiles.Count -eq 0) {
        throw 'No Private Windows network profile was found. This helper will not create a rule on a Public profile; verify your trusted LAN classification manually first.'
    }
}

if (-not $WhatIfPreference -and -not (Test-HomeServerAdministrator)) {
    throw 'Open an elevated PowerShell window to create Windows Firewall rules.'
}

foreach ($item in $pending) {
    $target = "$($item.Protocol)/$($item.Port) on $($config.ServerLanIp), service $($item.ServiceName)"
    if ($PSCmdlet.ShouldProcess($target, "Create $($item.DisplayName)")) {
        New-NetFirewallRule `
            -DisplayName $item.DisplayName `
            -Description ("HomeServer tool: {0}. Limited to the configured service, local address and Private profile." -f $item.Description) `
            -Direction Inbound `
            -Action Allow `
            -Protocol $item.Protocol `
            -LocalPort $item.Port `
            -LocalAddress ([string]$config.ServerLanIp) `
            -Service $item.ServiceName `
            -Profile Private `
            -Enabled True | Out-Null
    }
}

if ($WhatIfPreference) {
    Write-Host 'WhatIf completed. No firewall rule was created.' -ForegroundColor Yellow
}
else {
    Write-Host 'Firewall operation completed. Test externally from a separate network.' -ForegroundColor Green
}

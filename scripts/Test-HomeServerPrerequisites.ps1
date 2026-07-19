<#
.SYNOPSIS
Read-only audit for a small Windows home server.

.DESCRIPTION
Checks configured service names, local listeners, network profiles and (unless
skipped) the public resolver's view of the configured domain. It never opens a
port, changes application settings, contacts a router or creates credentials.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\server.config.psd1'),
    [switch]$SkipExternalDnsCheck
)

. (Join-Path $PSScriptRoot 'lib\HomeServer.Common.ps1')
$config = Get-HomeServerConfig -ConfigPath $ConfigPath

Write-Host 'Home server read-only audit' -ForegroundColor Cyan
Write-Host 'Bu komut router, DNS, web veya mail ayarlarını değiştirmez.' -ForegroundColor DarkGray

Write-Host "`nConfigured services" -ForegroundColor Cyan
Get-HomeServerServiceStatus -Config $config | Format-Table -AutoSize

Write-Host "`nExpected local listeners" -ForegroundColor Cyan
Get-HomeServerListenerStatus -Config $config | Format-Table -AutoSize

Write-Host "`nWindows network profiles" -ForegroundColor Cyan
$networkProfiles = @(Get-NetConnectionProfile)
$networkProfiles |
    Select-Object InterfaceAlias, NetworkCategory, IPv4Connectivity, IPv6Connectivity |
    Format-Table -AutoSize
if (@($networkProfiles | Where-Object { $_.NetworkCategory -eq 'Public' }).Count -gt 0) {
    Write-Warning 'A Public network profile was detected. The firewall helper only creates Private-profile rules and will not change this setting automatically.'
}

Write-Host "`nExisting HomeServer firewall rules" -ForegroundColor Cyan
$firewallRules = @(Get-NetFirewallRule -DisplayName 'HomeServer-*' -ErrorAction SilentlyContinue)
if ($firewallRules.Count -eq 0) {
    Write-Host 'No HomeServer-prefixed firewall rule exists.' -ForegroundColor Yellow
}
else {
    $firewallRules |
        Select-Object DisplayName, Enabled, Direction, Action, Profile |
        Format-Table -AutoSize
}

if (-not $SkipExternalDnsCheck) {
    Write-Host "`nPublic DNS delegation view (Cloudflare resolver)" -ForegroundColor Cyan
    try {
        $records = Resolve-DnsName -Name ([string]$config.Domain) -Type NS -Server '1.1.1.1' -DnsOnly -NoHostsFile -ErrorAction Stop |
            Where-Object { $_.Type -eq 'NS' } |
            Select-Object Name, NameHost, Section
        if ($null -eq $records -or @($records).Count -eq 0) {
            Write-Warning 'No NS answer returned. Check registrar delegation and glue records.'
        }
        else {
            $records | Format-Table -AutoSize
        }
    }
    catch {
        Write-Warning "Public DNS check failed: $($_.Exception.Message)"
    }
}

Write-Host "`nManual checks still required:" -ForegroundColor Yellow
Write-Host '- Test port reachability from a different internet connection.'
Write-Host '- Verify Technitium recursion is disabled or restricted to the LAN.'
Write-Host '- Verify DNS administration, RDP, databases and phpMyAdmin are not exposed.'
Write-Host '- Confirm TLS certificate names match the web and mail host names.'

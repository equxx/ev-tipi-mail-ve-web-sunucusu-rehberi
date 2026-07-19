<#
.SYNOPSIS
Generates a local, non-secret setup plan from a private configuration file.

.DESCRIPTION
The output is deliberately written under reports/, which is ignored by Git.
It does not call router APIs, registrar APIs, Technitium APIs or certificate
issuers, and it does not change any application or firewall setting.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\server.config.psd1'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'reports')
)

. (Join-Path $PSScriptRoot 'lib\HomeServer.Common.ps1')
$config = Get-HomeServerConfig -ConfigPath $ConfigPath

$null = New-Item -ItemType Directory -Force -Path $OutputDirectory
$planPath = Join-Path $OutputDirectory ("home-server-plan-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$plan = [System.Collections.Generic.List[string]]::new()

[void]$plan.Add('HOME SERVER PLAN')
[void]$plan.Add(('Generated: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')))
[void]$plan.Add('')
[void]$plan.Add(('Domain: {0}' -f $config.Domain))
[void]$plan.Add(('Mail host: mail.{0}' -f $config.Domain))
[void]$plan.Add(('Server LAN IP: {0}' -f $config.ServerLanIp))
[void]$plan.Add(('Public IP: {0}' -f $(if ([string]::IsNullOrWhiteSpace([string]$config.PublicIp)) { '[NOT SET]' } else { $config.PublicIp })))
[void]$plan.Add('')

[void]$plan.Add('ROUTER TASKS (manual; this script never uses UPnP or a router API)')
foreach ($rule in Get-HomeServerConfiguredRules -Config $config) {
    [void]$plan.Add(('  - Forward {0}/{1} to {2} for {3}' -f $rule.Protocol, $rule.Port, $config.ServerLanIp, $rule.Description))
}
[void]$plan.Add('  - Do not forward RDP, MySQL, phpMyAdmin or administration panels.')
[void]$plan.Add('')

[void]$plan.Add('REGISTRAR / DNS TASKS (manual)')
if ([bool]$config.Features.PublishAuthoritativeDns) {
    if ([string]::IsNullOrWhiteSpace([string]$config.PublicIp)) {
        [void]$plan.Add('  - PublicIp is empty. Fill it before creating A, NS or glue records.')
    }
    else {
        [void]$plan.Add(('  - A @ -> {0}' -f $config.PublicIp))
        [void]$plan.Add(('  - A mail -> {0}' -f $config.PublicIp))
        [void]$plan.Add(('  - A ns1 -> {0}' -f $config.PublicIp))
        [void]$plan.Add(('  - A ns2 -> {0}' -f $config.PublicIp))
        [void]$plan.Add(('  - Ask the registrar to publish ns1/ns2 glue and delegate {0} to them.' -f $config.Domain))
    }
    [void]$plan.Add('  - Before publishing DNS, restrict recursion to the LAN and do not expose the DNS admin panel.')
}
else {
    [void]$plan.Add('  - Authoritative DNS publishing is disabled in config; no DNS 53 port is planned.')
}
[void]$plan.Add('')

[void]$plan.Add('TLS / MAIL TASKS (manual)')
[void]$plan.Add(('  - Obtain a certificate covering {0} and mail.{0}.' -f $config.Domain))
[void]$plan.Add('  - Require SMTP authentication; verify open relay is disabled.')
[void]$plan.Add('  - Configure SPF, DKIM, DMARC and provider-side PTR/rDNS.')
[void]$plan.Add('')

[void]$plan.Add('SAFETY')
[void]$plan.Add('  - This report can contain your domain and IP. Do not commit or publish it.')
[void]$plan.Add('  - Never put passwords, API tokens, DKIM private keys or certificate private keys in config.')
[void]$plan.Add('  - Test from a separate internet connection after every router/firewall change.')

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllLines($planPath, [string[]]$plan, $utf8NoBom)
Write-Host "Plan written locally: $planPath" -ForegroundColor Green

Set-StrictMode -Version Latest

function Test-HomeServerPrivateIPv4 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Address
    )

    try {
        $ip = [System.Net.IPAddress]::Parse($Address)
    }
    catch {
        return $false
    }

    if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return $false
    }

    $octets = $ip.GetAddressBytes()
    if ($octets[0] -eq 10) {
        return $true
    }
    if ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) {
        return $true
    }
    if ($octets[0] -eq 192 -and $octets[1] -eq 168) {
        return $true
    }

    return $false
}

function Assert-HomeServerConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    foreach ($key in @('Domain', 'ServerLanIp', 'PublicIp', 'Features', 'ServiceNames')) {
        if (-not $Config.ContainsKey($key)) {
            throw "Yapılandırmada zorunlu '$key' alanı eksik."
        }
    }

    $domain = [string]$Config.Domain
    $domainPattern = '^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$'
    if ($domain -notmatch $domainPattern) {
        throw 'Domain geçerli bir alan adı olmalı; örnek: example.com.'
    }

    if (-not (Test-HomeServerPrivateIPv4 -Address ([string]$Config.ServerLanIp))) {
        throw 'ServerLanIp RFC1918 özel IPv4 adresi olmalı; örnek: 192.168.1.10.'
    }

    $publicIp = [string]$Config.PublicIp
    if (-not [string]::IsNullOrWhiteSpace($publicIp)) {
        try {
            $parsedPublicIp = [System.Net.IPAddress]::Parse($publicIp)
        }
        catch {
            throw 'PublicIp boş olmalı veya geçerli IPv4 adresi olmalı.'
        }

        if ($parsedPublicIp.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or
            (Test-HomeServerPrivateIPv4 -Address $publicIp)) {
            throw 'PublicIp herkese açık IPv4 adresi olmalı; özel ağ adresi kullanmayın.'
        }
    }

    if ($Config.Features -isnot [hashtable]) {
        throw 'Features bir PowerShell hashtable olmalı.'
    }
    foreach ($feature in @('Web', 'Mail', 'Smtps465', 'PublishAuthoritativeDns')) {
        if (-not $Config.Features.ContainsKey($feature) -or $Config.Features[$feature] -isnot [bool]) {
            throw "Features.$feature boolean ($true veya $false) olmalı."
        }
    }

    if ($Config.ServiceNames -isnot [hashtable]) {
        throw 'ServiceNames bir PowerShell hashtable olmalı.'
    }
    foreach ($serviceKey in @('Web', 'Mail', 'Dns')) {
        if (-not $Config.ServiceNames.ContainsKey($serviceKey) -or
            [string]::IsNullOrWhiteSpace([string]$Config.ServiceNames[$serviceKey])) {
            throw "ServiceNames.$serviceKey zorunlu."
        }
    }
}

function Get-HomeServerConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    $resolvedConfigPath = Resolve-Path -LiteralPath $ConfigPath -ErrorAction Stop
    $config = Import-PowerShellDataFile -LiteralPath $resolvedConfigPath
    if ($config -isnot [hashtable]) {
        throw 'Yapılandırma dosyası bir PowerShell data file (hashtable) olmalı.'
    }

    Assert-HomeServerConfig -Config $config
    return $config
}

function Get-HomeServerRuleDefinitions {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{ Id = 'WebHttp'; Feature = 'Web'; OptionalFeature = $null; ServiceKey = 'Web'; Protocol = 'TCP'; Port = 80; Description = 'HTTP, sertifika doğrulaması ve HTTPS yönlendirmesi' }
        [pscustomobject]@{ Id = 'WebHttps'; Feature = 'Web'; OptionalFeature = $null; ServiceKey = 'Web'; Protocol = 'TCP'; Port = 443; Description = 'HTTPS web ve webmail' }
        [pscustomobject]@{ Id = 'MailSmtp'; Feature = 'Mail'; OptionalFeature = $null; ServiceKey = 'Mail'; Protocol = 'TCP'; Port = 25; Description = 'Sunucular arası SMTP teslimi' }
        [pscustomobject]@{ Id = 'MailSubmission'; Feature = 'Mail'; OptionalFeature = $null; ServiceKey = 'Mail'; Protocol = 'TCP'; Port = 587; Description = 'Kimlik doğrulamalı SMTP submission' }
        [pscustomobject]@{ Id = 'MailImaps'; Feature = 'Mail'; OptionalFeature = $null; ServiceKey = 'Mail'; Protocol = 'TCP'; Port = 993; Description = 'Şifreli IMAP' }
        [pscustomobject]@{ Id = 'MailSmtps'; Feature = 'Mail'; OptionalFeature = 'Smtps465'; ServiceKey = 'Mail'; Protocol = 'TCP'; Port = 465; Description = 'İsteğe bağlı SSL/TLS SMTP uyumluluğu' }
        [pscustomobject]@{ Id = 'AuthoritativeDnsUdp'; Feature = 'PublishAuthoritativeDns'; OptionalFeature = $null; ServiceKey = 'Dns'; Protocol = 'UDP'; Port = 53; Description = 'Yetkili DNS sorguları (UDP)' }
        [pscustomobject]@{ Id = 'AuthoritativeDnsTcp'; Feature = 'PublishAuthoritativeDns'; OptionalFeature = $null; ServiceKey = 'Dns'; Protocol = 'TCP'; Port = 53; Description = 'Yetkili DNS sorguları (TCP)' }
    )
}

function Test-HomeServerRuleConfigured {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Rule,
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    if (-not [bool]$Config.Features[$Rule.Feature]) {
        return $false
    }
    if ($null -ne $Rule.OptionalFeature -and -not [bool]$Config.Features[$Rule.OptionalFeature]) {
        return $false
    }
    return $true
}

function Get-HomeServerConfiguredRules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $enabledRules = foreach ($rule in Get-HomeServerRuleDefinitions) {
        if (Test-HomeServerRuleConfigured -Rule $rule -Config $Config) {
            $rule
        }
    }
    return @($enabledRules)
}

function Get-HomeServerServiceStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    foreach ($serviceKey in @('Web', 'Mail', 'Dns')) {
        $serviceName = [string]$Config.ServiceNames[$serviceKey]
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Role = $serviceKey
            ServiceName = $serviceName
            Status = if ($null -eq $service) { 'Missing' } else { [string]$service.Status }
            StartType = if ($null -eq $service) { 'Unknown' } else { [string]$service.StartType }
        }
    }
}

function Get-HomeServerListenerStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    foreach ($rule in Get-HomeServerConfiguredRules -Config $Config) {
        if ($rule.Protocol -eq 'TCP') {
            $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $rule.Port -ErrorAction SilentlyContinue)
        }
        else {
            $listeners = @(Get-NetUDPEndpoint -LocalPort $rule.Port -ErrorAction SilentlyContinue)
        }

        $expectedAddresses = @('0.0.0.0', '::', [string]$Config.ServerLanIp)
        $matchingListeners = @($listeners | Where-Object { $_.LocalAddress -in $expectedAddresses })
        [pscustomobject]@{
            Rule = $rule.Id
            Protocol = $rule.Protocol
            Port = $rule.Port
            Listening = $matchingListeners.Count -gt 0
            Bindings = ($matchingListeners.LocalAddress -join ', ')
        }
    }
}

function Test-HomeServerAdministrator {
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

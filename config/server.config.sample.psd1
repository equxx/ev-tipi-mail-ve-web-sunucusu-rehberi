@{
    # Bu dosyayı server.config.psd1 adıyla kopyalayın. Gerçek dosya .gitignore
    # tarafından dışlanır; alan adınızı, IP'nizi veya sırlarınızı depoya koymayın.
    Domain = 'example.com'
    ServerLanIp = '192.168.1.10'

    # Boş bırakmak planı çalıştırır ancak DNS kaydı önerileri üretmez.
    PublicIp = ''

    Features = @{
        Web = $true
        Mail = $true
        Smtps465 = $false

        # DNS 53 varsayılan olarak kapalıdır. Ancak registrar delegation/glue
        # tamamlandıktan ve recursion güvenliği doğrulandıktan sonra $true yapın.
        PublishAuthoritativeDns = $false
    }

    # Bu adlar Windows hizmet adıdır; sisteminizde farklıysa önce Audit ile doğrulayın.
    ServiceNames = @{
        Web = 'wampapache64'
        Mail = 'hMailServer'
        Dns = 'DnsService'
    }
}

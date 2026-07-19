# Güvenli otomasyon yardımcıları

Bu depodaki PowerShell araçları, bir Windows ev sunucusunun tekrar eden denetim ve planlama işlerini kolaylaştırır. Bilerek **tam otomatik internet yayını** yapmazlar.

Yapmadıkları şeyler:

- Router'a giriş yapmak, UPnP açmak veya port yönlendirmesi oluşturmak
- Registrar/delegation/glue ayarlarını değiştirmek
- Technitium yönetim API'sine bağlanmak veya DNS recursion ayarını değiştirmek
- Posta kutusu, parola, DKIM özel anahtarı ya da TLS özel anahtarı oluşturmak/depolamak
- RDP, veritabanı, phpMyAdmin veya yönetim panelini internete açmak

Bu sınırlar, yanlış bir çalıştırmanın bilgisayarı açık DNS resolver veya açık relay haline getirmesini önlemek içindir.

## Başlangıç

Örnek dosyayı kopyalayın; kopya dosya Git tarafından yok sayılır:

```powershell
Copy-Item .\config\server.config.sample.psd1 .\config\server.config.psd1
```

`server.config.psd1` içine kendi alan adınızı ve sunucunun **yerel** IP adresini yazın. Parola, API anahtarı veya özel anahtar koymayın.

Windows bir yerel betiği çalıştırmayı engellerse, kalıcı ilke değiştirmek yerine yalnızca açtığınız PowerShell penceresi için `RemoteSigned` kullanın:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

Bu ayarı genel sistem veya kullanıcı kapsamına yükseltmeyin; betiğin içeriğini önce inceleyin.

Önce yalnızca denetim yapın:

```powershell
.\scripts\Test-HomeServerPrerequisites.ps1
```

Ardından router, registrar, DNS ve TLS için yerel bir plan üretin:

```powershell
.\scripts\New-HomeServerPlan.ps1
```

Plan dosyası `reports/` altında oluşur. Bu klasör depoya gönderilmez; yine de gerçek alan adı/IP içerebileceğinden herkese açık paylaşmayın.

## Güvenlik duvarı: önce önizleme

Örneğin yalnızca HTTPS kuralını önce değişiklik yapmadan görün:

```powershell
.\scripts\Enable-ScopedFirewallRule.ps1 -Rule WebHttps
```

Sonra yükseltilmiş PowerShell penceresinde önce simülasyonla kontrol edin:

```powershell
.\scripts\Enable-ScopedFirewallRule.ps1 -Rule WebHttps -Apply -WhatIf
```

Liste doğruysa aynı komutu `-WhatIf` olmadan çalıştırın. Komut her kural için Windows onayı ister. Oluşturulan kurallar:

- `HomeServer-` önekiyle adlandırılır,
- sadece seçilen servis, tek port ve tek protokole bağlanır,
- yalnızca yapılandırılan yerel IP ve **Private** ağ profili için geçerlidir,
- mevcut bir `HomeServer-...` kuralını değiştirmez veya silmez.

Audit ekranı ağ profilini `Public` gösterirse, kural aracı gerçek değişiklik yapmayı reddeder. Bu güvenlidir: rastgele veya ortak Wi-Fi ağlarını "Private" yapmayın. Sadece kendi güvenilir ev LAN'ınızın Windows tarafından doğru sınıflandırıldığını manuel olarak doğruladıktan sonra devam edin.

Mail için her portu ayrıca seçin. Örnek:

```powershell
.\scripts\Enable-ScopedFirewallRule.ps1 -Rule MailSubmission,MailImaps
```

Port 465, config içindeki `Smtps465 = $true` olmadan seçilemez. DNS 53 daha sıkı korunur: hem config içinde `PublishAuthoritativeDns = $true`, hem de komutta `-PublishAuthoritativeDns` gerekir.

```powershell
.\scripts\Enable-ScopedFirewallRule.ps1 -Rule AuthoritativeDnsUdp,AuthoritativeDnsTcp -PublishAuthoritativeDns
```

DNS'i yayınlamadan önce Technitium recursion'unu yalnızca yerel ağla sınırlayın, zone transferini kontrol edin ve yönetim panelini internetten kapalı tutun.

## Son testler

Router yönlendirmesini ve registrar ayarlarını manuel tamamladıktan sonra, farklı bir mobil/veri bağlantısından aşağıdakileri doğrulayın:

- Açık olan sadece ihtiyaç duyulan portlar mı?
- DNS sadece kendi zone'unuz için yetkili cevap veriyor, rastgele alanları recursive çözmüyor mu?
- TLS sertifikası web ve mail sunucu adıyla uyuşuyor mu?
- SMTP kimlik doğrulaması zorunlu ve açık relay kapalı mı?
- SPF, DKIM, DMARC ve PTR/rDNS yapılandırıldı mı?

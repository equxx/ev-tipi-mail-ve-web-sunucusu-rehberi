# Ev Tipi DNS, Web, Mail ve Webmail Sunucusu Rehberi

Bu depo, tek bir Windows bilgisayarı üzerinde küçük ölçekli bir web sitesi ve özel alan adlı e-posta hizmeti kurmak için güvenlik odaklı bir başlangıç rehberidir.

> Bu bir üretim barındırma platformu değildir. Kişisel, eğitim veya düşük trafikli kullanım için tasarlanmıştır. Düzenli yedek, güncelleme ve izleme olmadan kritik iş verisini burada tutmayın.

## Hedef mimari

```text
Internet
   |
Modem/router (yalnızca gerekli portlar)
   |
Windows sunucu
   |-- Yetkili DNS: Technitium DNS Server
   |-- Web: Apache / WAMP
   |-- E-posta: hMailServer
   `-- Webmail: Roundcube
```

Örnek adlandırma:

| Amaç | Örnek ad |
| --- | --- |
| Ana web sitesi | `alan-adiniz.tld` |
| E-posta ve webmail | `mail.alan-adiniz.tld` |
| Yetkili ad sunucuları | `ns1.alan-adiniz.tld`, `ns2.alan-adiniz.tld` |

Bu depoda gerçek alan adı, IP adresi, e-posta hesabı, parola, sertifika dosyası veya yerel bilgisayar yolu bulunmaz.

## Linux + Docker alternatifi

Windows yerine Ubuntu/Debian üzerinde Docker Compose kullanmak isteyenler için Türkçe, host'a paket kurmayan ve varsayılan olarak yalnızca localhost'a bağlanan ayrı kurulum [linux/README.md](linux/README.md) dosyasındadır. Bu yol, Windows'taki servisleri değiştirmez; tüm web, webmail, posta ve veritabanı bileşenlerini container olarak çalıştırır.

## Güvenli otomasyon

Tekrarlanan denetim, planlama ve dar kapsamlı Windows Güvenlik Duvarı kuralları için PowerShell yardımcıları eklendi. Router, registrar, DNS yönetim paneli ve parolalara dokunmazlar; her internet erişimi değişikliği açık onay ister. Kullanım için [AUTOMATION.md](AUTOMATION.md) dosyasına bakın.

## Başlamadan önce

- Sabit yerel ağ IP'si belirleyin: ör. `<SUNUCU_LAN_IP>`.
- İnternetten erişilebilen sabit bir genel IP veya dinamik DNS planı sağlayın.
- Alan adınızın kayıt kuruluşunda (registrar) DNS/glue/delegation yönetimini kontrol edin.
- Bilgisayarda kesintisiz güç, güncel Windows, güçlü yönetici parolası ve düzenli yedekleme sağlayın.
- İnternet sağlayıcınızın 25 numaralı SMTP portunu engelleyebileceğini unutmayın. Bu, mail sunucularında yaygındır.

## 1. DNS tasarımı

Technitium'ı yalnızca kendi alan adınız için **yetkili** DNS olarak kullanın. Açık recursive DNS sunucusu çalıştırmayın.

Gerekli temel kayıtlar:

| Tür | Ad | Değer |
| --- | --- | --- |
| A | `@` | `<GENEL_IP>` |
| A | `mail` | `<GENEL_IP>` |
| A | `ns1` | `<GENEL_IP>` |
| A | `ns2` | `<GENEL_IP>` |
| MX | `@` | `mail.alan-adiniz.tld` |
| TXT | `@` | SPF politikası |
| TXT | `selector._domainkey` | DKIM genel anahtarı |
| TXT | `_dmarc` | DMARC politikası |

### DNS güvenliği

- Recursion'u yalnızca yerel ağ için açın veya tamamen kapatın.
- DNS yönetim panelini internete açmayın; gerekirse sadece yerel ağ veya VPN üzerinden yönetin.
- TCP ve UDP 53'ü yalnızca gerçekten kendi yetkili DNS'inizi yayınlayacaksanız yönlendirin.
- Zone transferi/notify kullanmıyorsanız kapalı tutun. "Notify failed" uyarısı çoğunlukla tanımlı ama erişilemeyen secondary DNS hedefinden kaynaklanır.

### Delegation ve glue neden önemlidir?

Kendi alan adınızın altında `ns1` ve `ns2` kullanıyorsanız, registrar'ın üst seviye alan adı sistemine bu adların IP eşleşmesini (glue) yayımlaması gerekir. Sadece kendi Technitium sunucunuzda kayıt olması yeterli değildir.

Kontrol akışı:

```text
Kayıt kuruluşu / TLD üst DNS
        -> ns1/ns2 için doğru glue ve delegation
        -> sizin Technitium sunucunuz
        -> alan adınızın A, MX, TXT kayıtları
```

Let's Encrypt veya bazı dış DNS çözümleyiciler zaman aşımı veriyorsa, önce registrar/TLD tarafındaki delegation'ı doğrulayın. Çocuğunuzdaki (Technitium) doğru kayıtlar, üst tarafta delegation bozuksa tek başına işe yaramaz.

## 2. Router ve güvenlik duvarı

Sunucuya yalnızca gerekli portları yönlendirin:

| Hizmet | Port | Protokol | Gerekli mi? |
| --- | ---: | --- | --- |
| DNS | 53 | TCP + UDP | Yalnızca dışarıya yetkili DNS sunacaksanız |
| HTTP | 80 | TCP | Sertifika doğrulama ve HTTP yönlendirmesi için |
| HTTPS | 443 | TCP | Web ve webmail için |
| SMTP | 25 | TCP | Sunucular arası e-posta teslimi için |
| SMTPS | 465 | TCP | Eski/uyumluluk istemcileri için isteğe bağlı |
| Submission | 587 | TCP | Kullanıcıların güvenli SMTP gönderimi için |
| IMAPS | 993 | TCP | Kullanıcıların güvenli IMAP erişimi için |

Şunları internete yönlendirmeyin: RDP, MySQL, phpMyAdmin, Technitium yönetim paneli, hMailServer yönetim aracı veya WAMP yönetim sayfaları.

Her router yönlendirmesi için Windows Güvenlik Duvarı'nda aynı porta gelen bağlantıyı sadece ilgili uygulamaya izin verecek şekilde kontrol edin.

## 3. TLS sertifikası

Web ve mail için güvenilir bir sertifika kullanın. win-acme (WACS) ile Let's Encrypt HTTP-01 doğrulaması pratik bir seçenektir.

- Sertifika isteğinde `alan-adiniz.tld` ve `mail.alan-adiniz.tld` adlarını birlikte (SAN) isteyin.
- HTTP-01 için dış dünyadan port 80 ile doğrulama dosyasına erişilebilmelidir.
- Başarısız olmaya devam eden istekleri art arda denemeyin; önce dış DNS çözümleme ve delegation sorununu çözün.
- Sertifikayı Apache'ye ve hMailServer'a aynı uygun zincir/anahtar biçiminde bağlayın.
- Yenilemeyi zamanlanmış görevle otomatikleştirin ve yenileme sonrası servis yeniden yükleme adımını test edin.

`mail.alan-adiniz.tld` için geçerli bir SAN yoksa, istemcileri geçici olarak yalnızca sertifikada bulunan sunucu adıyla yapılandırın. Sertifika adı uyarısını asla görmezden gelmeyin.

## 4. Web ve Roundcube

Roundcube'u güncel resmi paketinden kurun. Uygulamanın veritabanı, yapılandırması ve geçici dosyaları web kökünün dışında olmalıdır.

Yaygın ve güvenli geçici adres:

```text
https://alan-adiniz.tld/webmail/
```

Mail alt alanının sertifikası hazır olduğunda tercihen:

```text
https://mail.alan-adiniz.tld/
```

Uygulama ilk kurulumu tamamlandıktan sonra:

- Kurulum aracını kaldırın veya webden erişilemez hale getirin.
- Dizin listelemeyi kapatın.
- HTTPS zorlaması kullanın.
- Oturum çerezlerinde `Secure`, `HttpOnly` ve uygun `SameSite` ayarlarını doğrulayın.
- Roundcube'un uygulama gizli anahtarını güçlü ve rastgele üretin; bunu depoya veya ekran görüntülerine koymayın.

## 5. hMailServer ve istemci ayarları

İstemciler için önerilen ayarlar:

| İşlev | Sunucu | Port | Şifreleme |
| --- | --- | ---: | --- |
| Gelen posta (IMAP) | `mail.alan-adiniz.tld` | 993 | SSL/TLS |
| Giden posta (SMTP submission) | `mail.alan-adiniz.tld` | 587 | STARTTLS |
| Giden posta uyumluluğu | `mail.alan-adiniz.tld` | 465 | SSL/TLS |

SMTP kimlik doğrulaması zorunlu olmalı; açık relay kesinlikle kapalı kalmalıdır. Kullanıcıların gelen/giden sunucusu olarak aynı sertifikalı adı kullanması, Thunderbird ve Android istemcilerindeki bağlantı hatalarını önler.

hMailServer'ın aktif geliştirilmediğini göz önünde bulundurun. İnternete açık, iş açısından kritik e-posta için bakım gören bir mail altyapısı veya güvenilir bir e-posta hizmeti daha uygundur.

## 6. Teslim edilebilirlik

Mail gönderebilmek tek başına yeterli değildir. Büyük sağlayıcılarda spam'e düşmemek için şunlar gerekir:

- SPF: hangi sunucuların alan adınız adına gönderebileceğini tanımlar.
- DKIM: giden iletileri imzalar.
- DMARC: SPF/DKIM başarısızlığında alıcıya ne yapacağını söyler ve rapor sağlar.
- PTR/rDNS: genel IP'nizin ters kaydının mail sunucunuzun adıyla uyumlu olması gerekir; bunu genellikle internet sağlayıcısı ayarlar.
- TLS: sertifika adının istemcinin kullandığı adla tam uyuşması gerekir.

Başlangıçta DMARC için `p=none` ile rapor izlemek, sonradan `quarantine` veya `reject` politikasına geçmek daha güvenlidir.

## 7. Test listesi

Kurulumdan sonra ayrı bir mobil internet bağlantısından test edin:

- Alan adı ve `mail` kaydı doğru genel IP'ye çözülüyor mu?
- DNS'iniz yalnızca kendi zone'unuz için cevap veriyor, rastgele alanları recursive çözmüyor mu?
- `https://alan-adiniz.tld/` çalışıyor mu?
- `https://alan-adiniz.tld/webmail/` HTTPS ile açılıyor mu?
- Sertifika adları hem kök alanı hem mail alt alanını kapsıyor mu?
- IMAP 993 ve SMTP 587 ile giriş/gönderim çalışıyor mu?
- Gerekiyorsa SMTP 465 ile SSL/TLS test edildi mi?
- Dış bir alıcıya gönderim ve dışarıdan alma başarılı mı?
- SPF/DKIM/DMARC ve PTR kontrolü yapıldı mı?

## 8. Yedek ve bakım

- DNS zone dışa aktarımlarını yedekleyin.
- Mail veri dizinini, Roundcube veritabanını ve web dosyalarını şifreli harici ortama yedekleyin.
- Sertifika yenilemesini ayda en az bir kez gözle kontrol edin.
- Windows, Apache/PHP, Roundcube ve DNS yazılımını düzenli güncelleyin.
- Günlükleri izleyin; beklenmeyen SMTP denemeleri, açık relay işaretleri veya DNS sorgu patlamaları varsa erişimi kısıtlayın.

## Lisans ve katkı

Bu dokümantasyon [MIT lisansı](LICENSE) ile paylaşılır. Hata veya güvenlik önerileri için lütfen [SECURITY.md](SECURITY.md) dosyasındaki yöntemi izleyin.

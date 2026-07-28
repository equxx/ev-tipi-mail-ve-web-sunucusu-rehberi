# Linux ev tipi web + mail sunucusu

Bu paket, önceki Windows tasarımının Ubuntu/Debian karşılığıdır. Hedef sistem Ubuntu Server 24.04 LTS veya güncel Debian tabanlı bir sunucudur.

## Windows’tan Linux’a karşılıklar

| Önceki bileşen | Linux karşılığı |
| --- | --- |
| Apache / WAMP | Nginx + PHP-FPM |
| hMailServer | Postfix + Dovecot |
| Spam filtreleme | Rspamd + Redis |
| Roundcube | Roundcube (Nginx üzerinde) |
| Technitium DNS | DNS’i registrar/sağlayıcıda tutmak; gerekiyorsa Technitium Linux veya BIND9 |

Mail sunucusu için alan adı, sunucunun sabit LAN adresi, dışarıdan erişilebilen genel IP, PTR/rDNS ve ISP’nin 25 numaralı SMTP portuna izin vermesi gerekir. Bunlardan biri yoksa web sitesi çalışabilir ama mail teslimatı güvenilir olmayabilir.

Bu klasördeki betikler gerçek alan adı, parola, DKIM özel anahtarı veya sertifika özel anahtarı içermez. Betikler Linux makinesinde çalıştırılmak üzere hazırlanmıştır; bu Windows çalışma alanında çalıştırılmamıştır.

## Hızlı başlangıç

```bash
cp config/server.env.example config/server.env
nano config/server.env
chmod 700 scripts/*.sh

sudo ./scripts/install-linux.sh config/server.env
sudo ./scripts/configure-mail-baseline.sh config/server.env
sudo ./scripts/configure-web-site.sh config/server.env
sudo ./scripts/audit-linux.sh config/server.env
```

`server.env` içindeki örnek değerleri gerçek değerlerle değiştirmeden betikleri çalıştırmayın. `install-linux.sh` paketleri kurar; diğer iki yapılandırma betiği yalnızca yerel servis ayarlarını uygular.

## Ağ ve DNS

Router’da yalnızca gerçekten kullanılan portları sunucunun LAN adresine yönlendirin:

| Hizmet | Port | Not |
| --- | ---: | --- |
| HTTP | TCP 80 | Sertifika doğrulama ve HTTPS yönlendirmesi |
| HTTPS | TCP 443 | Web sitesi ve webmail |
| SMTP | TCP 25 | Sunucular arası posta; ISP engelleyebilir |
| Submission | TCP 587 | Kullanıcıların TLS’li posta gönderimi |
| IMAPS | TCP 993 | TLS’li IMAP |
| SMTPS | TCP 465 | İsteğe bağlı uyumluluk portu |

RDP/SSH yönetim portu, MariaDB, phpMyAdmin, Rspamd paneli ve DNS yönetim panelini internete açmayın. DNS’i kendi sunucunuzdan yetkili olarak yayınlayacaksanız TCP/UDP 53’ü ayrıca planlayın; açık recursive resolver çalıştırmayın.

Temel dış DNS kayıtları:

```text
@       A       <GENEL_IP>
mail    A       <GENEL_IP>
@       MX 10   mail.<ALAN_ADI>
@       TXT     v=spf1 mx -all
_dmarc  TXT     v=DMARC1; p=none; rua=mailto:dmarc@<ALAN_ADI>
```

DKIM anahtarını Rspamd oluşturduktan sonra onun verdiği TXT kaydını ekleyin. PTR/rDNS kaydı `mail.<ALAN_ADI>` ile uyumlu olmalıdır; bunu genellikle ISP değiştirir.

## TLS ve web sitesi

DNS kayıtları yayıldıktan ve TCP 80 dışarıdan erişilebilir olduktan sonra:

```bash
sudo certbot --nginx -d <ALAN_ADI> -d mail.<ALAN_ADI>
```

Web sitesi kökü varsayılan olarak `/var/www/<ALAN_ADI>/public` olur. Sertifika yenilemesini kurduktan sonra şu testi yapın:

```bash
sudo nginx -t
sudo systemctl reload nginx
sudo certbot renew --dry-run
```

## Roundcube

Roundcube’un güncel resmi “complete” paketini indirin. Güncel sürümlerde Nginx document root’u Roundcube dizininin `public_html` altı olmalıdır. Kurulumdan sonra `installer` dizinini tamamen silin; `/config`, `/temp` ve `/logs` yollarını webden erişilemez bırakın. Roundcube veritabanını ve uygulama gizli anahtarını yalnızca yerel sunucuda tutun.

Roundcube’un kendi kurulum belgesindeki sürüm notlarını izleyin: <https://github.com/roundcube/roundcubemail/wiki/Installation>

## Mail yapılandırmasının sınırları

`configure-mail-baseline.sh` tek alan adlı, sistem kullanıcılarının Maildir kutularını kullanan güvenli bir başlangıç yapılandırması verir. Çok alan adlı sanal posta kutuları, web üzerinden kullanıcı yönetimi veya yüksek hacimli üretim için ayrı bir sanal kullanıcı veritabanı ve daha kapsamlı bir dağıtım (ör. Mailcow) tercih edilmelidir.

Rspamd paneli varsayılan olarak dışarı açılmaz. Yönetici parolası hash’i şu komutla üretilebilir:

```bash
sudo rspamadm pw
```

Hash’i `/etc/rspamd/local.d/worker-controller.inc` içine manuel ve güvenli şekilde ekleyip yapılandırmayı doğrulayın:

```bash
sudo rspamadm configtest
sudo systemctl restart rspamd
```

## Doğrulama

```bash
sudo postfix check
sudo doveconf -n
sudo rspamadm configtest
sudo nginx -t
sudo ss -lntup
sudo ./scripts/audit-linux.sh config/server.env
```

Farklı bir mobil internet bağlantısından web, IMAPS ve SMTP submission testleri yapın. Ayrıca dışarıya mail gönderme/alma, SPF/DKIM/DMARC, TLS sertifika adı ve açık relay kontrolü yapın.

## Kaynaklar

- Ubuntu Server: [Postfix kurulumu](https://ubuntu.com/server/docs/install-and-configure-postfix/) ve [mail servisleri](https://documentation.ubuntu.com/server/how-to/mail-services/)
- Rspamd: [kurulum](https://docs.rspamd.com/downloads/) ve [Postfix entegrasyonu](https://docs.rspamd.com/getting-started/)
- Roundcube: [resmî kurulum rehberi](https://github.com/roundcube/roundcubemail/wiki/Installation)

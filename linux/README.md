# Docker ile Linux ev tipi web + e-posta sunucusu

Bu klasör, önceki Windows kurulumunun Linux karşılığıdır. Web sitesi, webmail, e-posta, spam filtreleme ve veritabanı ayrı Docker container'ları olarak çalışır. Hedef işletim sistemi Ubuntu/Debian tabanlı bir Linux ve Docker Compose V2'dir.

## Güvenlik sınırı

- Betikler Linux'a paket kurmaz; `sudo`, `apt`, `systemctl` veya Windows ayarı çalıştırmaz.
- Varsayılan port bağları yalnızca `127.0.0.1` üzerindedir. Router'a veya internete açmak için `.env` içinde bunu bilinçli olarak değiştirmeniz gerekir.
- `docker compose down` verileri silmez. **`down -v` komutunu yedek almadan kullanmayın.**
- Gerçek alan adı, IP, parola, API anahtarı, DKIM/SSL özel anahtarı depoda yoktur. Üretilecek gizli dosyalar `.gitignore` ile korunur.
- Docker Engine/Docker Desktop'ı işletim sistemine kurmak ayrı bir adımdır; kurulumunu yalnızca Docker'ın resmi belgelerinden ve kendi onayınızla yapın.

Bu düzen, host işletim sistemindeki posta/web servislerini değiştirmez. Yine de Docker'ın kendisi sistem kaynağı kullandığı için önce boş disk, RAM ve Docker daemon durumunu kontrol edin.

## İçerik

| Bileşen | Container/image | Görevi |
| --- | --- | --- |
| Mail sunucusu | Docker Mailserver `15.1.0` | Postfix, Dovecot, Rspamd ve hesap yönetimi |
| Webmail | Roundcube `1.7.2-apache` | IMAP/SMTP web arayüzü |
| Veritabanı | MariaDB `11.4` | Roundcube ayar/verileri |
| Web sunucusu | Nginx `1.27-alpine` | Statik site ve `/webmail/` ters proxy |

Image etiketleri kasıtlı olarak sabittir; `latest` kullanmak yerine sürümü kontrollü şekilde güncelleyin.

## Ön koşullar

1. Ubuntu/Debian tabanlı bir Linux makine.
2. Docker Engine ve Docker Compose V2. `docker compose version` çıktısı alınabilmeli.
3. Gerçek e-posta kullanımı için alan adı, sabit/genel IP, PTR (rDNS) ve ISP'nin gerekli portlara izin vermesi.

Docker'ı kurmadan önce [Docker'ın resmi kurulum belgelerini](https://docs.docker.com/engine/install/) izleyin. Bu depodaki betikler Docker kurmaz.

## Güvenli yerel başlangıç

`linux` klasörünün içindeyken:

```bash
cp .env.example .env
nano .env
chmod 700 scripts/*.sh

# Örnek alan adını kendi alan adınızla değiştirdikten sonra:
./scripts/prepare-docker-data.sh --apply

# Bu komut yalnızca yapılandırmayı doğrular, container başlatmaz:
./scripts/docker-up.sh

# Image indirip container'ları başlatmak için açık onay gerekir:
./scripts/docker-up.sh --apply
```

`.env` içinde en az `MAIL_DOMAIN` ve `MAIL_HOSTNAME` değerlerini değiştirin. `example.test` örneğiyle gerçek posta gönderimi yapılmaz. `prepare-docker-data.sh` ilk çalışmada rastgele MariaDB parolaları üretir; mevcut gizli dosyaların üzerine yazmaz.

Container'lar başladıktan sonra:

- Web sitesi: `http://127.0.0.1:8088/`
- Roundcube: `http://127.0.0.1:8088/webmail/`

İlk posta hesabını etkileşimli ve parolayı ekrana göstermeden oluşturun:

```bash
./scripts/mail-account.sh
```

E-posta hesabı oluşturma işleminden sonra DMS container'ının durumunu kontrol edin:

```bash
./scripts/docker-check.sh
```

Durdurmak için:

```bash
./scripts/docker-down.sh       # sadece ne yapılacağını gösterir
./scripts/docker-down.sh --apply
```

Bu işlem container'ları durdurur; `docker-data/` içindeki posta ve veritabanı verilerini silmez.

## Dışarı açmadan önce

İlk testleri localhost'ta yapın. Gerçek istemciler veya internet için `.env` içindeki `MAIL_BIND_IP` değerini yalnızca router/firewall kurallarını kontrol ettikten sonra `0.0.0.0` yapın. Web arayüzünü dışarı açacaksanız `WEB_BIND_IP` değerini de ayrıca değiştirin ve TLS'li bir reverse proxy kullanın.

Gereken yönlendirmeler genellikle şöyledir:

| Hizmet | TCP portu | Not |
| --- | ---: | --- |
| SMTP | 25 | Sunucular arası posta; ISP sıkça engeller |
| Submission | 587 | Kullanıcıların TLS'li gönderimi |
| IMAPS | 993 | TLS'li posta okuma |
| HTTP/HTTPS | 80/443 | Web sitesi ve webmail; bu örnek HTTP'yi localhost'ta tutar |

MariaDB, Roundcube ve yönetim arayüzleri internete port olarak yayınlanmaz. Router'da yalnızca gerçekten kullandığınız portları yönlendirin. SSH/RDP'yi ve Docker daemon soketini internete açmayın.

## DNS ve teslim edilebilirlik

Gerçek alan adınız için DNS sağlayıcısında en az şu kayıtları planlayın:

```text
@       A       <GENEL_IP>
mail    A       <GENEL_IP>
@       MX 10   mail.<ALAN_ADI>
@       TXT     v=spf1 mx -all
_dmarc  TXT     v=DMARC1; p=none; rua=mailto:dmarc@<ALAN_ADI>
```

DKIM anahtarını DMS/Rspamd container'ında üretip yalnızca gereken TXT kaydını DNS'e ekleyin. Özel anahtarı repoya koymayın. PTR kaydı `mail.<ALAN_ADI>` ile uyumlu olmalı; bunu genellikle internet sağlayıcısı değiştirir. CGNAT veya kapalı TCP/25 varsa ev bağlantısından güvenilir gelen posta servisi çalışmayabilir; bu durumda bir SMTP relay gerekir.

## TLS

Örnek yapılandırma `MAIL_SSL_TYPE=self-signed` ile yerel test içindir. Bu sertifika tarayıcı ve posta istemcisinde uyarı üretir. İnternete açmadan önce DMS'in [TLS belgelerini](https://docker-mailserver.github.io/docker-mailserver/latest/config/security/ssl/) izleyip gerçek sertifika kullanın. Sertifika/özel anahtar dosyalarını git'e eklemeyin.

## Yedekleme ve güncelleme

Posta kutuları ve Roundcube verileri `docker-data/` altındadır. Container'ları durdurup bu klasörü güvenli bir diske yedekleyin; `.env` ve `*.env` dosyaları parola içerir, yedek erişimini kısıtlayın. Güncellemeden önce yedek alın, image etiketlerini tek tek değiştirin ve ardından:

```bash
./scripts/docker-up.sh
./scripts/docker-up.sh --apply
```

Resmi image ve sürüm belgeleri:

- [Docker Mailserver kullanım ve Compose rehberi](https://docker-mailserver.github.io/docker-mailserver/latest/usage/)
- [Roundcube resmi Docker image değişkenleri](https://hub.docker.com/r/roundcube/roundcubemail)
- [Docker Compose ortam değişkenleri](https://docs.docker.com/compose/how-tos/environment-variables/set-environment-variables/)
- [Compose healthcheck ve başlangıç sırası](https://docs.docker.com/compose/how-tos/startup-order/)

Bu çalışma alanında Docker daemon bulunmadığı için image'lar çekilerek çalıştırılmadı; dosyalar statik olarak doğrulanmıştır. Gerçek makinede önce doğrulama komutunu (`docker-up.sh` argümansız) çalıştırın.

<div align="center">

<img src="docs/icon.png" alt="Pilsiz simgesi" width="128">

# Pilsiz

**Vestel tabanlı akıllı TV'ni Mac'in menü çubuğundan yönet.**

Kumanda, kanal listesi, uygulamalar, ses ve izleme istatistikleri; hepsi menü çubuğundaki simgeden açılan tek bir panelde.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-AppKit-0A84FF)
![Bağımlılık yok](https://img.shields.io/badge/ba%C4%9F%C4%B1ml%C4%B1l%C4%B1k-yok-2ea44f)

<img src="docs/screenshots/hero.png" alt="Pilsiz panelleri: Ekranda, Kumanda, Kanallar, Aktivite" width="100%">

</div>

---

## Neden?

Fiziksel kumanda kırılınca TV'yi telefondaki *TV Smart Centre* uygulamasıyla yönetmek zorunda kalmıştım. Bu proje, aynı kontrolü Mac'e taşıyor. Hiçbir buluta bağlanmıyor; Mac ile TV, yerel ağ üzerinden doğrudan konuşuyor. Adı da buradan: pili hiç bitmeyen bir kumanda.

Test edilen cihaz: **Daewoo 43DE54F** (anakart: Vestel **17MB181TC**). Vestel'in SmartCenter altyapısını kullanan diğer TV'lerde de (Vestel, Toshiba, Hitachi, Telefunken, JVC, Finlux…) çalışması beklenir.

## 🎙 Pilsiz'e söyle

Türkçe konuş ya da yaz; Pilsiz anlayıp TV'de yapar. **⌃⌥⌘ Space**'i basılı tutup konuş (kısa basarsan susunca biter), paneldeki 🎙 düğmesine bas ya da ⌘K'ya cümle yaz.

| Söylediğin | Pilsiz |
|---|---|
| "TRT biri aç", "kanal 15", "Show TV'yi aç" | Kanala geçer |
| "Sesi biraz kıs", "sesi 20 yap", "sessize al" | Sesi ayarlar |
| "Kızılcık Şerbeti ne zaman", "maç hangi kanalda" | Yayın akışından bulur, listeler |
| "Haberleri aç", "maçı aç", "Survivor'ı aç" | Yayındaysa o kanala geçer; değilse sıradaki yayına hatırlatıcı kurar |
| "Bu akşam ne var", "ne izlesem" | Akşamın programlarını, en çok izlediğin kanallara göre gösterir |
| "Televizyonu kapat" | TV'yi kapatır |

**Tamamen cihaz içinde:** konuşma, macOS'un Türkçe cihaz içi konuşma tanımasıyla yazıya dökülür; anlam, Apple'ın cihaz içi dil modeliyle (Foundation Models, macOS 26 + Apple Intelligence) çıkarılır. İnternet, hesap ya da API anahtarı gerekmez; ses Mac'ten çıkmaz. Sık komutlar (numara, ses, aç/kapat, "bu akşam") modele gitmeden kurallarla anında çözülür. Kanal ve program bilgisi her zaman uygulamanın kendi verisinden gelir; model yalnızca niyeti anlar, kanal ya da program uydurmaz. Apple Intelligence yoksa basit komutlar yine çalışır.

## Özellikler

| | |
|---|---|
| 🖥 **Ekranda** | TV'de o an ne açık: kanal logosu, **yayındaki program**, ilerlemesi ve sıradaki program; ya da Netflix/Prime Video/YouTube. Ses, favori kanallar, uygulamalar, girişler |
| 🎮 **Kumanda** | TV'nin kendi kumandasına benzeyen, kaydırmasız gövde: yön tuşları + OK, ana ekran, geri, menü, çıkış, medya tuşları, kanal ±, rakamlar, renkli tuşlar. Basılı tutunca tekrarlar |
| 📺 **TV'de göster** | Mac ekranını TV'ye yansıt, fotoğrafları slayt olarak göster, video oynat (AirPlay olmadan, HbbTV ile) |
| 📋 **Kanallar** | Logolu kanal listesi; her kanalın altında o an yayındaki program. Tıkla, TV o kanala geçsin. Arama, favoriler (★), düzenleme ve kanal tarama sihirbazı |
| 🔲 **Uygulamalar** | Netflix, Prime Video ve YouTube'u tek tıkla aç. Hangisinin açık olduğu izlenir |
| 📊 **Aktivite** | TV'nin açık kaldığı süre, en çok izlenen kanallar, uygulama süreleri (bugün / 7 gün / 30 gün) |
| ⚙️ **Ayarlar** | TV menü kısayolları, IP/MAC, giriş sırası, oturum açılışında başlatma, ham tuş kodu deneme |

Ayrıca:

- 🔔 **Program hatırlatıcı:** Kanallar listesindeki takvim düğmesinden ya da "Sırada" satırındaki zilden bir programa hatırlatıcı kur. Başlamadan 5 dk önce gelen bildirimdeki **Kanala geç** düğmesi, TV kapalıysa önce açar, sonra o kanala geçer.
- ▶️ **YouTube linkini TV'de aç:** Linki Uygulamalar sekmesindeki karta yapıştır, panele sürükle-bırak ya da ⌘K'ya yapıştır; video (varsa zaman damgası ve oynatma listesiyle) TV'deki YouTube'da başlar. Panodaki link kendiliğinden önerilir.
- 📡 **Kanal listesi TV'den:** Kanallar sekmesindeki ⟳ düğmesiyle (ve günde bir kendiliğinden) TV'deki tüm kanallar (radyolar hariç) listeye eklenir; düzenlediğin adlar ve favoriler korunur.
- 🔎 **Hızlı arama (⌘K):** Kanal adı, numarası ya da **yayındaki program adıyla** ara ("kuruluş" yazınca dizinin olduğu kanal çıkar); ↑↓ ile seç, ↩ ile geç.
- 🧷 **Menü çubuğunda kanal:** Simgenin yanında kanal adı ya da "kanal · program" yazar (Ayarlar'dan seçilir).
- ⌨️ **Her yerde çalışan kısayollar** (panel kapalıyken de; Ayarlar'dan kapatılabilir):

  | Kısayol | İşlev |
  |---|---|
  | `⌃⌥⌘ ↑` / `⌃⌥⌘ ↓` | Ses |
  | `⌃⌥⌘ →` / `⌃⌥⌘ ←` | Kanal + / − |
  | `⌃⌥⌘ M` | Sessiz |
  | `⌃⌥⌘ K` | Paneli kanal aramasıyla aç |
  | `⌃⌥⌘ Space` | Pilsiz'e söyle (basılı tut ve konuş) |

  ⌃⌥⌘ seçildi çünkü ⌥⌘←/→ tarayıcılarda sekme değiştirir.

- 🔍 **Otomatik keşif:** TV'yi yerel ağda kendisi bulur, MAC adresini öğrenir.
- 🔊 **Sürüklenebilir ses çubuğu:** TV ses seviyesini ağdan bildirmediği için seviye uygulamada takip edilir. Çubuk, aradaki fark kadar +/− basışı gönderir.
- ⚡ **Wake-on-LAN:** TV kapalıyken güç tuşu ağdan uyandırma paketi gönderir.
- ⌨️ **Panel kısayolları** (Ekranda ve Kumanda sekmelerinde):

  | Tuş | İşlev | Tuş | İşlev |
  |---|---|---|---|
  | ← ↑ → ↓ | Yön | `Return` | OK |
  | `Delete` | Geri | `Space` | Oynat |
  | `+` / `-` | Ses | `m` | Sessiz |
  | `]` / `[` | Kanal ± | `0`–`9` | Rakam |
  | `h` | Ana ekran | `s` | Kaynak |
  | `i` | Bilgi | `e` | Çıkış |

## Ekran görüntüleri

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/ekranda.png" width="260"><br><sub>Ekranda</sub></td>
    <td align="center"><img src="docs/screenshots/kumanda.png" width="260"><br><sub>Kumanda</sub></td>
    <td align="center"><img src="docs/screenshots/kanallar.png" width="260"><br><sub>Kanallar</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/uygulamalar.png" width="260"><br><sub>Uygulamalar</sub></td>
    <td align="center"><img src="docs/screenshots/aktivite.png" width="260"><br><sub>Aktivite</sub></td>
    <td></td>
  </tr>
</table>

## Kurulum

**Gereksinimler:** Çalıştırmak için macOS 14 veya üstü ("Pilsiz'e söyle"nin dil modeli için macOS 26 ve Apple Intelligence). Derlemek için Xcode 26 (macOS 26 SDK, Swift 6). Harici bağımlılık yok.

```bash
git clone https://github.com/thealibrs/pilsiz.git
cd pilsiz
./build.sh
```

`build.sh` şunları yapar:

1. `swift build -c release` ile derler.
2. `.app` paketini geçici bir klasörde oluşturur, logoları ekler ve uygulama simgesini `actool` ile derler.
3. Anahtar zincirindeki ilk **Apple Development** sertifikasıyla imzalar (yoksa ad-hoc imzalar).
4. `/Applications/Pilsiz.app` olarak kurar ve başlatır.

> **Neden sabit sertifika?** macOS, *Yerel Ağ* iznini uygulamanın imzasına bağlar. Ad-hoc imza her derlemede değiştiği için izin her seferinde sıfırlanır. Farklı bir sertifika kullanmak için: `SIGN_IDENTITY="..." ./build.sh`

### İlk açılış

1. macOS **"yerel ağdaki aygıtları bulma"** izni ister → **İzin Ver**. (Sonradan: *Sistem Ayarları › Gizlilik ve Güvenlik › Yerel Ağ*)
2. Uygulama TV'yi ağda arar ve bulur. Bulamazsa *Ayarlar › Bağlantı*'dan IP adresini elle gir.
3. TV kapalıyken de açabilmek için TV'de **Ayarlar › Ağ › Ağda Uyandırma** seçeneğini aç.

## Nasıl çalışır?

Vestel TV'ler, SmartCenter mobil uygulaması için **56789** portunda bir DIAL sunucusu çalıştırır. Uygulama bu sunucuyla düz HTTP üzerinden konuşur.

```
┌──────────────────┐        HTTP (yerel ağ)        ┌────────────────────────┐
│  Pilsiz          │  POST /apps/SmartCenter  ───▶ │  Vestel TV  :56789     │
│  (menü çubuğu)   │  POST /apps/Netflix      ───▶ │  DIAL + sanal kumanda  │
│                  │  GET  /apps/<uygulama>   ───▶ │                        │
│                  │  UDP :9  Wake-on-LAN     ───▶ │  (bekleme modunda)     │
└──────────────────┘                               └────────────────────────┘
```

### Tuş gönderme

```http
POST /apps/SmartCenter HTTP/1.1
Content-Type: application/xml
Connection: close

<remote><key code=1016 /></remote>
```

> ⚠️ `code` değeri **tırnaksız** gönderilmeli. Ayrıca TV'nin gömülü sunucusu bağlantı tekrar kullanımında takılabildiği için her istek kendi TCP bağlantısını açar ve komutlar sırayla gönderilir.

<details>
<summary><b>Tuş kodları</b></summary>

| Tuş | Kod | Tuş | Kod | Tuş | Kod |
|---|---|---|---|---|---|
| 0–9 | 1000–1009 | Güç | 1012 | Sessiz | 1013 |
| Geri | 1010 | Ses + | 1016 | Ses − | 1017 |
| Bilgi | 1018 | Aşağı | 1019 | Yukarı | 1020 |
| Sol | 1021 | Sağ | 1022 | OK | 1053 |
| Durdur | 1024 | Oynat | 1025 | Duraklat | 1049 |
| Geri sar | 1027 | İleri sar | 1028 | Altyazı | 1031 |
| Kanal + | 1032 | Kanal − | 1033 | Önceki kanal | 1034 |
| Çıkış | 1037 | Kanal listesi | 1045 | Ana ekran | 1046 |
| Rehber (EPG) | 1047 | Menü | 1048 | Kaynak | 1056 |
| Kırmızı | 1055 | Yeşil | 1054 | Sarı | 1050 |
| Mavi | 1052 | Medya | 1057 | İnternet | 1065 |
| Ayarlar | 1067 | Hızlı menü | 1043 | Görüntü oranı | 1011 |

</details>

### TV'de göster (HbbTV)

TV'nin Vewd DIAL sunucusu (port **12345**) bir `HbbTV` uygulaması yayımlıyor (HbbTV 2.0 "companion screen"). Buraya bir uygulama tanımı (XML AIT) gönderilince TV, verilen adresteki web sayfasını tam ekran bir HbbTV uygulaması olarak açar:

```http
POST http://<tv>:12345/apps/HbbTV
Content-Type: text/plain; charset=utf-8

<mhp:ServiceDiscovery …><mhp:URLBase>http://<mac>:8765/</mhp:URLBase>…<mhp:applicationLocation>index.html</mhp:applicationLocation>…
```

- TV her açılışta bir **Evet/Hayır** onayı sorar ("Evet" seçili gelir) ve sayfayı ancak onaydan sonra indirir. Pilsiz 1,5 sn sonra OK gönderir, sayfa inmediyse 4,5 ve 8 sn'de yeniden dener. Sayfa açık kaldıkça yeni gönderimlerde tekrar sorulmaz.
- Pilsiz Mac'te küçük bir sunucu (port **8765**) çalıştırır; TV'deki sayfa ~150–400 ms'de bir `/state` sorar, kareleri `/frame.jpg`'den, videoyu `/video.mp4`'ten (Range destekli) alır.
- Tarayıcı Chrome 108 tabanlı Opera (Vewd OMI); sayfayı **katı XHTML** olarak okur: betikler `CDATA` içinde olmalı, yoksa sessizce çalışmaz.
- Videoyu JavaScript ile eklemek ya da `play()` ile başlatmak TV'nin uygulamayı kapatmasına yol açar; video, `<video autoplay>` etiketinin doğrudan yazıldığı ayrı bir sayfada oynatılır.
- TV'nin video çözücüsü 1920×1080 ile sınırlı: iPhone'un dikey videoları (720p ayarıyla 1280 px yükseklik) oynamaz; Pilsiz dikey videoları 540×960, yatayları 1280×720 H.264 MP4'e dönüştürür.
- Ekran yansıtma ScreenCaptureKit ile saniyede ~6 kareye kadar JPEG gönderir (Pilsiz'in kendi paneli hariç tutulur).

### Pano

Pano, aynı HbbTV ekranında açılan bir ana ekran: uygulamalar, YouTube kısayolları, haberler, Ankara havası ve piyasa. *TV'de göster* sekmesindeki **Panoyu TV'de aç** düğmesiyle açılır.

- Veriyi Mac toplar (Gazete Oksijen RSS'i, Open-Meteo, Yahoo Finance, YouTube küçük resimleri) ve `/pano.json` ile `/pano/img/…` üzerinden verir; TV'nin tarayıcısı dışarıya istek atmaz.
- Ağdan gönderilen kumanda tuşları HbbTV sayfasına ulaşmadığı için gezinme Mac'ten yapılır: pano açıkken Pilsiz'in ok, OK ve geri tuşları TV'ye değil sayfaya gider. Sayfa `/pano/poll` isteğini açık tutar (uzun yoklama), tuş gelince istek hemen yanıtlanır.
- Pano kartındaki dokunmatik alan trackpad'i kumandaya çevirir: iki parmakla kaydırmak odağı o yöne taşır, iki parmakla dokunmak ya da tıklamak seçer.
- Seçilen kart `/pano/act` ile Mac'e bildirilir. Mac önce panoyu kapatır, ardından uygulamayı açar ya da videoyu YouTube'a gönderir.
- Kısayol olarak kanal linki verilirse (`youtube.com/@kanal`) o kanalın o anki canlı yayını açılır.
- Üç dakika tuşa basılmazsa pano saat ve dönen haber başlığından oluşan bekleme ekranına geçer.
- Geliştirirken `PILSIZ_PANO=1 PILSIZ_PORT=8791 swift run` panoyu TV'ye dokunmadan sunar; `http://localhost:8791/` tarayıcıda açılır, klavyenin ok tuşlarıyla gezilir.

### Komutlar, klavye ve imleç

Aşağıdakiler, telefondaki *TV Smart Centre* uygulamasının trafiği mitmproxy ile kaydedilip [REA](https://github.com/morluto/rea) ile çözümlenerek bulundu. Hepsi aynı uç noktaya gider; komutlarda telefon uygulaması gibi `application_name: tv smart centre` başlığı gönderilir.

| Amaç | İstek gövdesi |
|---|---|
| Kanal listesi | `<?xml version='1.0'?><command>activechannellist</command>` |
| TV özellikleri | `<?xml version='1.0'?><command>specialportalapps</command>` |
| Metin (harf başına) | `<?xml version='1.0' ?><keyboard><key value='116'/></keyboard>` (ASCII/Unicode kodu) |
| İmleç (~60 Hz) | `<?xml version='1.0'?><mouseevent><event_data dx='8.0' dy='-29.3' button='0'/></mouseevent>` |

Komutların HTTP yanıtı boştur; **sonuç, TV'nin 7681 portundaki WebSocket'ine yayınlanır**. Kanal listesi şöyle gelir (TV adlarda `&` karakterini kaçırmadığı için esnek ayrıştırılır):

```xml
<active_list network='None' count='614' total_size='67979'>
  <service rsn='1' name='TRT 1 HD' handle='715' onid='0' tsid='7' sid='10601' type='25' is_encrypted='0'/>
  …
```

`rsn` TV'deki kanal numarası, `type` 25/22/1 yayın, 2 radyo, 131 internet kanalıdır. TV listeyi yalnızca o an bağlı istemcilere gönderdiği için WebSocket, komuttan **önce** açılmalıdır.

### YouTube'a video gönderme

DIAL'a `v=<id>` göndermek YouTube'u açar ama videoyu oynatmaz. Bunun yerine telefonlardaki "TV'de izle" düğmesinin kullandığı **YouTube Lounge** kanalı kullanılır:

1. **Eşleştirme (bir kez):** `POST /apps/YouTube` gövdesi `pairingCode=<uuid>&theme=cl` → TV'deki YouTube bu kodla kaydolur; `POST https://www.youtube.com/api/lounge/pairing/get_screen` (`pairing_code=<uuid>`) kalıcı `screenId` döndürür. TV'de kod girmek gerekmez.
2. **Anahtar:** `POST …/pairing/get_lounge_token_batch` (`screen_ids=<screenId>`) → `loungeToken`.
3. **Oturum:** `POST …/bc/bind?…&loungeIdToken=…` gövdesi `count=0` → yanıttan `SID`, `gsessionid`, `AID`.
4. **Oynat:** aynı uca `req0__sc=setPlaylist&req0_videoId=<id>&req0_currentTime=<sn>…`.

Lounge API'si belgelenmemiştir; açık kaynak istemcilerle (ör. pyytlounge) aynı biçimde kullanılır.

### Uygulamalar (DIAL)

| Uygulama | Uç nokta | Not |
|---|---|---|
| Netflix | `POST /apps/Netflix` | Ek başlık gerekmez |
| Prime Video | `POST /apps/AmazonInstantVideo` | Ek başlık gerekmez |
| YouTube | `POST /apps/YouTube` | `Origin: https://www.youtube.com` olmadan **403** döner |

Açık olan uygulama, `GET /apps/<ad>` yanıtındaki `<state>running</state>` ile izlenir.

### Yayın akışı

Programlar iki açık XMLTV kaynağından birleştirilir: **[epgshare01](https://epgshare01.online/epgshare01/)** (178 kanal, 3 gün; gzip, macOS'un yerleşik DEFLATE çözücüsüyle açılır) ve onda olmayan kanallar için **[iptv-epg-turkey](https://github.com/trology85/iptv-epg-turkey)** (yalnızca o gün). İkisi aynı yayın verisini veriyor; üçüncü bir kaynağın (iptv-epg.org) saatleri tutmadığı için kullanılmadı. Akış 6 saatte bir ve gün değişince yenilenir, `~/Library/Application Support/Pilsiz/` altında önbelleğe alınır. Kanallar adlarıyla eşleştirilir (`"STAR TV HD"` ↔ `"Star"`, `"HABERTÜRK HD"` ↔ `"HABERTÜRK TV"`).

### Kanal geçişi

TV kanal adlarını ağ üzerinden vermez. Bu yüzden kanal listesi Mac'te tutulur; bir kanala tıklamak, numarasını rakam rakam tuşlar. Logolar, kanal adından türetilen anahtarla eşleşir: `"TRT 1 HD"` → `trt1.png`, `"HABERTÜRK HD"` → `haberturk.png`.

## Proje yapısı

```
Sources/Pilsiz/
├── PilsizApp.swift      # Menü çubuğu simgesi + oklu NSPopover
├── TVController.swift   # Durum, komut kuyruğu, ses takibi, keşif, Wake-on-LAN
├── Network.swift        # Minimal HTTP istemcisi (Network.framework), SmartCenter/DIAL, WoL
├── Stores.swift         # Kanal listesi ve aktivite verisi (UserDefaults)
├── RemoteKey.swift      # Tuş kodları
├── RootView.swift       # Başlık, sekme çubuğu, klavye kısayolları
├── Tabs.swift           # Ekranda, Kumanda, Uygulamalar, Aktivite
├── ChannelsTab.swift    # Kanal listesi, düzenleyici, tarama sihirbazı
├── SettingsTab.swift    # Ayarlar
├── ChannelLogo.swift    # Logo eşleştirme ve yedek rozet
├── EPG.swift            # Yayın akışı: indirme, önbellek, XMLTV ayrıştırma, ad eşleştirme
├── Reminders.swift      # Program hatırlatıcıları ve bildirimler
├── CommandPalette.swift # ⌘K hızlı arama
├── HotKeys.swift        # Sistem geneli kısayollar (Carbon)
├── YouTube.swift        # YouTube linki ayrıştırma ve Lounge ile TV'de oynatma
├── Assistant.swift      # Pilsiz'e söyle: kurallar + cihaz içi model, eylemler
├── Voice.swift          # Türkçe cihaz içi konuşma tanıma ve ekranın üstündeki kapsül
├── ShareServer.swift    # TV'deki HbbTV sayfası ve onun bağlandığı yerel sunucu (Range destekli)
├── ScreenShare.swift    # Ekran yakalama, fotoğraf slaytı, video dönüştürme, onay
├── Dashboard.swift      # Pano: haber, hava, piyasa ve kısayol verisi, seçilen kartın işlenmesi
├── DashboardPage.swift  # Panonun TV'de açılan sayfası
├── PanoTouchpad.swift   # Panoyu trackpad kaydırmalarıyla gezdiren alan
├── ShareTab.swift       # TV'de göster sekmesi
├── Remote.swift         # Kumanda sekmesi
├── Components.swift     # Tema ve ortak bileşenler
└── Snapshot.swift       # (yalnızca DEBUG) sekmeleri PNG'ye çizer
Resources/
├── Info.plist
├── tv.png               # "Ekranda" sekmesindeki gerçekçi TV görseli
└── Logos/               # Kanal logoları
```

Debug derlemesinde README görüntülerini yeniden üretmek için:

```bash
swift build && PILSIZ_SNAPSHOT=/tmp/snap .build/debug/Pilsiz
```

## Bilinen sınırlamalar ve yol haritası

- [x] Kanal listesini TV'den **otomatik çekmek**
- [x] Klavye ile metin girişi, touchpad/imleç (protokol çözüldü; arayüzde şu an yok)
- [x] Mac ekranını, fotoğrafları ve videoları TV'de göstermek (HbbTV)
- [ ] Ses seviyesini TV'den **okumak**: telefon uygulaması da yalnızca +/− gönderiyor; protokolde okuma bulunmadı
- [ ] Şu anki kanalı TV'den okumak (telefondan değiştirilen kanalı bilmek)
- [ ] Parlaklık, kontrast gibi görüntü ayarları
- [ ] Girişleri doğrudan seçmek (şu an kaynak menüsü açılıp sıra numarası gönderiliyor)

Kalanlar için sıradaki adım: SmartCenter'ın Android APK'sını REA ile statik olarak incelemek.

## Teşekkürler ve kaynaklar

- [ha-vestel-toshiba-tv](https://github.com/mutlutekir/ha-vestel-toshiba-tv): `/apps/SmartCenter` uç noktası ve tırnaksız kod biçimi
- [pyvesteltv](https://github.com/T3m3z/pyvesteltv) ve [ha-vestel-component](https://github.com/andylynch/ha-vestel-component)
- [node-red-contrib-vestel-tv](https://github.com/hyttysmyrkky/node-red-contrib-vestel-tv): genişletilmiş tuş haritası
- [shkspr.mobi](https://shkspr.mobi/blog/2018/11/telnet-control-of-toshiba-smart-tvs/): Toshiba/Vestel tuş kodları
- Yayın akışı: [epgshare01](https://epgshare01.online/epgshare01/) ve [trology85/iptv-epg-turkey](https://github.com/trology85/iptv-epg-turkey)
- Kanal logoları: [tv-logo/tv-logos](https://github.com/tv-logo/tv-logos). Logolar ilgili yayıncıların tescilli markalarıdır; burada yalnızca kişisel kullanım için yer alır.
- "Ekranda" sekmesindeki TV görseli Higgsfield (GPT Image 2.5) ile üretildi
- Arayüz fikri: [@greco_dev](https://x.com/greco_dev/status/2109842197654692349)'in LG webOS menü çubuğu uygulaması

---

<sub>Vestel, Daewoo ve kanal adları ilgili sahiplerinin markalarıdır. Bu proje onlarla bağlantılı değildir.</sub>

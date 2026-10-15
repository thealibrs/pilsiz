<div align="center">

<img src="docs/icon.png" alt="Pilsiz icon" width="128">

# Pilsiz

**Control your Vestel-based smart TV from the Mac menu bar.**

Remote, channel list, programme guide, voice commands, screen mirroring and a personal dashboard that opens on the TV.<br>
No cloud, no account: the Mac and the TV talk directly over the local network.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-AppKit-0A84FF)
![No dependencies](https://img.shields.io/badge/dependencies-none-2ea44f)
![License: MIT](https://img.shields.io/badge/license-MIT-blue)

<img src="docs/screenshots/hero.png" alt="Left: the Pilsiz dashboard open on the TV. Right: the Show on TV and On Screen tabs of the Pilsiz panel on the Mac" width="100%">

[Features](#features) · [Dashboard](#-dashboard) · [Tell Pilsiz](#-tell-pilsiz) · [Installation](#installation) · [How it works](#how-it-works) · [Contributing](#contributing)

**English** · [Türkçe](README.md)

</div>

---

> **Language note.** The app's interface, the voice commands and the code comments are in Turkish, and the programme guide and news sources are Turkish. The screenshots below show the Turkish interface; tab names are given as *Turkish (English)*. The protocol notes in [How it works](#how-it-works) apply to any Vestel-based TV.

## Why?

When my physical remote broke I had to control the TV with the *TV Smart Centre* app on my phone. This project brings the same control to the Mac. It connects to no cloud; the Mac and the TV talk directly over the local network. The name comes from there: *pilsiz* is Turkish for "without batteries", a remote whose batteries never run out.

It is built for TVs on Vestel's SmartCenter platform; see [Which TVs does it work with?](#which-tvs-does-it-work-with) for details.

## Which TVs does it work with?

Pilsiz talks to smart TVs built on Vestel's **SmartCenter** platform. Many brands made by Vestel use it: Vestel, Regal, Toshiba, Hitachi, Telefunken, JVC, Finlux, Daewoo… If the *Smart Center* phone app can see your TV, Pilsiz most likely can too.

| | |
|---|---|
| ✅ **Expected on every SmartCenter TV** | Finding the TV on the network, remote keys, volume, fetching the channel list from the TV, opening Netflix / Prime Video / YouTube, playing a YouTube link, keyboard and pointer, Wake-on-LAN |
| 🔎 **May vary by model** | Show on TV and the dashboard (the TV's HbbTV browser and port 12345), input selection (the order of the source menu), which screens show the pointer |
| 🇹🇷 **Turkey-specific** | The programme guide (Türksat channels), channel logos, the language of the interface and voice commands (Turkish). Elsewhere, channel switching works; programme info and logos stay empty |

Pilsiz assumes no particular TV: the channel list, model name and MAC address are read from the TV itself. The TV's name, input order, dashboard city and news source are changed in Settings.

The only verified model is the **Daewoo 43DE54F** (Vestel **17MB181TC** mainboard, software 2.85.2.0). If you try another model, sharing its name and what did and did not work in an [issue](https://github.com/thealibrs/pilsiz/issues) helps a lot.

## 📺 Dashboard

The dashboard (*Pano*) is a personal home screen that opens full screen on the TV. You open it with the **Panoyu TV'de aç** (Open dashboard on TV) button in the *TV'de göster* (Show on TV) tab; nothing has to be installed on the TV.

<img src="docs/screenshots/pano.png" alt="Dashboard: Netflix, Prime Video, YouTube, Apps and Mac cards on the left with four YouTube shortcuts and a Live TV row below; news headlines on the right" width="100%">

| | |
|---|---|
| **Apps** | Netflix, Prime Video and YouTube open directly. The *Uygulamalar* (Apps) card opens the TV's own app screen, the *Mac* card starts screen mirroring |
| **YouTube shortcuts** | Four shortcuts with thumbnails. Give a video link and that video plays; give a channel link (`youtube.com/@channel`) and the channel's **current live stream** plays |
| **News** | The latest 12 headlines from an RSS feed. OK opens the story's summary |
| **Weather** | Current conditions, five slots three hours apart, and a three-day forecast |
| **Markets** | US dollar, euro, gram gold and BIST 100, each with an intraday chart |
| **Live TV** | The channel you watched last and the programme on air; selecting it returns to the broadcast |
| **Idle mode** | After three minutes without a key press: a large clock and a rotating headline |

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/pano-hava.png"><br><sub>Weather tab</sub></td>
    <td align="center"><img src="docs/screenshots/pano-piyasa.png"><br><sub>Markets tab</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/pano-haber.png"><br><sub>News summary</sub></td>
    <td align="center"><img src="docs/screenshots/pano-bekleme.png"><br><sub>Idle mode</sub></td>
  </tr>
</table>

**Navigating the dashboard.** While the dashboard is open, Pilsiz's arrow, OK and back keys go to the dashboard instead of the TV. There are three ways:

- **Keyboard:** arrow keys, `Return` and `Delete` (with the panel open, on any tab).
- **Trackpad:** scroll with two fingers on the touch area in the *TV'de göster* tab; focus moves the way your fingers move. A two-finger tap or a click selects.
- **Remote tab:** the on-screen direction keys.

The Mac gathers the data; the TV's browser never goes out to the internet. Sources: the chosen RSS feed for news (Gazete Oksijen, BBC Türkçe, CNN Türk, Habertürk, TRT Haber or any RSS address), [Open-Meteo](https://open-meteo.com) for weather, Yahoo Finance for markets. The city and the news source are set under *Ayarlar › Pano* (Settings › Dashboard); YouTube shortcuts are edited in the *TV'de göster* (Show on TV) tab.

## 🎙 Tell Pilsiz

Speak or type in Turkish; Pilsiz understands and does it on the TV. Hold **⌃⌥⌘ Space** and speak (on a short press it stops when you fall silent), press the 🎙 button in the panel, or type a sentence into ⌘K.

| You say | Pilsiz |
|---|---|
| "TRT biri aç", "kanal 15", "Show TV'yi aç" *(open TRT 1, channel 15, open Show TV)* | Switches to the channel |
| "Sesi biraz kıs", "sesi 20 yap", "sessize al" *(turn it down a bit, set volume to 20, mute)* | Adjusts the volume |
| "Kızılcık Şerbeti ne zaman", "maç hangi kanalda" *(when is this show on, which channel is the match on)* | Finds it in the programme guide and lists it |
| "Haberleri aç", "maçı aç", "Survivor'ı aç" *(put the news on, put the match on)* | Switches to the channel if it is on air; otherwise sets a reminder for the next airing |
| "Bu akşam ne var", "ne izlesem" *(what's on tonight, what should I watch)* | Shows tonight's programmes, ordered by the channels you watch most |
| "Televizyonu kapat" *(turn off the TV)* | Turns the TV off |

**Entirely on device:** speech is transcribed by macOS's on-device Turkish speech recognition; the meaning is extracted by Apple's on-device language model (Foundation Models, macOS 26 + Apple Intelligence). No internet, account or API key is needed, and audio never leaves the Mac. Frequent commands (numbers, volume, on/off, "tonight") are resolved instantly by rules without reaching the model. Channel and programme information always comes from the app's own data; the model only works out the intent and never invents a channel or a programme. Without Apple Intelligence the simple commands still work.

## Features

| | |
|---|---|
| 🖥 **Ekranda** (On Screen) | What is on the TV right now: channel logo, **the programme on air**, its progress and what is next; or Netflix/Prime Video/YouTube. Volume, favourite channels, apps, inputs |
| 🎮 **Kumanda** (Remote) | A body that looks like the TV's own remote and needs no scrolling: direction keys + OK, home, back, menu, exit, media keys, channel ±, digits, colour keys. Keys repeat while held |
| 📺 **TV'de göster** (Show on TV) | Open the [dashboard](#-dashboard), mirror the Mac screen to the TV (full HD, ~15 frames per second), show photos as a slideshow, play a video. Without AirPlay, using HbbTV |
| 📋 **Kanallar** (Channels) | A list or a logo grid. The list shows the programme on air, time left and progress; the channel on screen stays pinned at the top. Favourites, most watched, search by channel, number or programme, editing and a channel scan wizard |
| 🔲 **Uygulamalar** (Apps) | Open Netflix, Prime Video and YouTube with one click; today's usage is shown on each card. Close the running app and go back to live TV with one click |
| 📊 **Aktivite** (Activity) | How long the TV was on, most watched channels, time per app (today / 7 days / 30 days) |
| ⚙️ **Ayarlar** (Settings) | TV menu shortcuts, IP/MAC, input order, launch at login, raw key code testing |

Also:

- 🔔 **Programme reminders:** Set a reminder from the calendar button in the channel list or the bell on the "up next" row. The **Kanala geç** (Switch to channel) button in the notification that arrives 5 minutes before the start turns the TV on first if it is off, then switches to the channel.
- ▶️ **Open a YouTube link on the TV:** Paste the link into the card in the Apps tab, drag it onto the panel, or paste it into ⌘K; the video (with its timestamp and playlist, if any) starts in YouTube on the TV. A link on the clipboard is suggested automatically.
- 📡 **Channel list from the TV:** The ⟳ button in the Channels tab (and once a day automatically) adds every channel on the TV (except radio) to the list; names you edited and your favourites are kept.
- 🔎 **Quick search (⌘K):** Search by channel name, number or **the name of the programme on air**; choose with ↑↓, switch with ↩.
- 🧷 **Channel in the menu bar:** Next to the icon, the logo of the current channel, optionally with the name of the programme on air (chosen in Settings). Channels without a logo and running apps show a name instead.
- ⌨️ **Global shortcuts** (they work with the panel closed; can be turned off in Settings):

  | Shortcut | Action |
  |---|---|
  | `⌃⌥⌘ ↑` / `⌃⌥⌘ ↓` | Volume |
  | `⌃⌥⌘ →` / `⌃⌥⌘ ←` | Channel + / − |
  | `⌃⌥⌘ M` | Mute |
  | `⌃⌥⌘ K` | Open the panel with channel search |
  | `⌃⌥⌘ Space` | Tell Pilsiz (hold and speak) |

  ⌃⌥⌘ was chosen because ⌥⌘←/→ switches tabs in browsers.

- 🔍 **Automatic discovery:** Finds the TV on the local network by itself and learns its MAC address.
- 🔊 **Draggable volume slider:** The TV does not report its volume over the network, so the level is tracked in the app. The slider sends as many +/− presses as the difference.
- ⚡ **Wake-on-LAN:** When the TV is off, the power key sends a wake packet over the network.
- ⌨️ **Panel shortcuts** (in the On Screen and Remote tabs; while the dashboard is open, direction, OK and back work on every tab):

  | Key | Action | Key | Action |
  |---|---|---|---|
  | ← ↑ → ↓ | Direction | `Return` | OK |
  | `Delete` | Back | `Space` | Play |
  | `+` / `-` | Volume | `m` | Mute |
  | `]` / `[` | Channel ± | `0`–`9` | Digit |
  | `h` | Home | `s` | Source |
  | `i` | Info | `e` | Exit |

## Screenshots

<table>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/ekranda.png" width="260"><br><sub>On Screen</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/kumanda.png" width="260"><br><sub>Remote</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/kanallar.png" width="260"><br><sub>Channels</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/tvde-goster.png" width="260"><br><sub>Show on TV (dashboard open)</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/uygulamalar.png" width="260"><br><sub>Apps</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/aktivite.png" width="260"><br><sub>Activity</sub></td>
  </tr>
</table>

## Installation

**Requirements:** macOS 14 or later to run (macOS 26 and Apple Intelligence for the language model behind "Tell Pilsiz"). Xcode 26 (macOS 26 SDK, Swift 6) to build. No external dependencies.

```bash
git clone https://github.com/thealibrs/pilsiz.git
cd pilsiz
./build.sh
```

`build.sh` does the following:

1. Builds with `swift build -c release`.
2. Assembles the `.app` bundle in a temporary folder, adds the logos and the dashboard fonts, and compiles the app icon with `actool`.
3. Signs it with the first **Apple Development** certificate in the keychain (ad-hoc if there is none).
4. Installs it as `/Applications/Pilsiz.app` and launches it.

> **Why a fixed certificate?** macOS ties the *Local Network* permission to the app's signature. An ad-hoc signature changes with every build, so the permission is reset each time. To use a different certificate: `SIGN_IDENTITY="..." ./build.sh`

### First launch

1. macOS asks for permission to **find devices on the local network** → **Allow**. (Later: *System Settings › Privacy & Security › Local Network*)
2. The app searches the network and finds the TV. If it does not, enter the IP address by hand under *Ayarlar › Bağlantı* (Settings › Connection).
3. If the TV is on, the channel list is fetched from it automatically. To fetch it later: *Kanallar › … › Kanal listesini TV'den eşitle* (Channels › … › Sync from TV).
4. To be able to turn the TV on while it is off, enable **Networked Standby Mode** in the TV's network settings (called *Wake On LAN* on some models).

Other permissions, asked for by the feature that needs them: *Screen & System Audio Recording* for screen mirroring, *Microphone* and *Speech Recognition* for "Tell Pilsiz", *Notifications* for reminders.

### Privacy

Pilsiz has no server, account or telemetry of its own. Requests leave the Mac only for: programme guide files, sending a video to YouTube, and (while the dashboard is open) news, weather, market data and YouTube thumbnails. Voice commands are processed on device. The channel list, favourites and viewing statistics stay on the Mac in `UserDefaults`.

The small server on the Mac (port 8765) starts on the first share or when the dashboard opens, and stops when the screen on the TV is closed. While it runs, any device on the local network can reach it; there is no authentication. Do not use screen mirroring or the dashboard on networks you do not trust.

## How it works

Vestel TVs run a DIAL server on port **56789** for the SmartCenter mobile app. Pilsiz talks to this server over plain HTTP.

```
┌──────────────────┐       HTTP (local network)    ┌────────────────────────┐
│  Pilsiz          │  POST /apps/SmartCenter  ───▶ │  Vestel TV  :56789     │
│  (menu bar)      │  POST /apps/Netflix      ───▶ │  DIAL + virtual remote │
│                  │  GET  /apps/<app>        ───▶ │                        │
│                  │  UDP :9  Wake-on-LAN     ───▶ │  (in standby)          │
└──────────────────┘                               └────────────────────────┘
```

### Sending keys

```http
POST /apps/SmartCenter HTTP/1.1
Content-Type: application/xml
Connection: close

<remote><key code=1016 /></remote>
```

> ⚠️ The `code` value must be sent **without quotes**. Also, the TV's embedded server can stall when connections are reused, so every request opens its own TCP connection and commands are sent one after another.

<details>
<summary><b>Key codes</b></summary>

| Key | Code | Key | Code | Key | Code |
|---|---|---|---|---|---|
| 0–9 | 1000–1009 | Power | 1012 | Mute | 1013 |
| Back | 1010 | Volume + | 1016 | Volume − | 1017 |
| Info | 1018 | Down | 1019 | Up | 1020 |
| Left | 1021 | Right | 1022 | OK | 1053 |
| Stop | 1024 | Play | 1025 | Pause | 1049 |
| Rewind | 1027 | Fast forward | 1028 | Subtitles | 1031 |
| Channel + | 1032 | Channel − | 1033 | Previous channel | 1034 |
| Exit | 1037 | Channel list | 1045 | Home | 1046 |
| Guide (EPG) | 1047 | Menu | 1048 | Source | 1056 |
| Red | 1055 | Green | 1054 | Yellow | 1050 |
| Blue | 1052 | Media | 1057 | Internet | 1065 |
| Settings | 1067 | Quick menu | 1043 | Aspect ratio | 1011 |

</details>

### Show on TV (HbbTV)

The TV's Vewd DIAL server (port **12345**) exposes an `HbbTV` application (HbbTV 2.0 "companion screen"). When an application description (an XML AIT) is posted to it, the TV opens the web page at the given address as a full-screen HbbTV application:

```http
POST http://<tv>:12345/apps/HbbTV
Content-Type: text/plain; charset=utf-8

<mhp:ServiceDiscovery …><mhp:URLBase>http://<mac>:8765/</mhp:URLBase>…<mhp:applicationLocation>index.html</mhp:applicationLocation>…
```

- On every launch the TV asks a **Yes/No** question (with "Yes" preselected) and only downloads the page after consent. Pilsiz sends OK after 1.5 s and retries at 4.5 and 8 s if the page has not been fetched. While the page stays open, later shares are not asked about again.
- Pilsiz runs a small server on the Mac (port **8765**); the page on the TV asks `/state` twice a second, receives frames over a single persistent MJPEG connection (`/stream.mjpg`) and the video from `/video.mp4` (with Range support).
- The browser is Opera based on Chrome 108 (Vewd OMI); it parses the page as **strict XHTML**: scripts must be inside `CDATA`, otherwise they silently do not run.
- Adding a video from JavaScript or starting it with `play()` makes the TV close the application; video plays on a separate page where the `<video autoplay>` tag is written directly.
- The TV's video decoder is limited to 1920×1080: portrait iPhone videos (1280 px tall at the 720p setting) do not play; Pilsiz converts portrait videos to 540×960 and landscape ones to 1280×720 H.264 MP4.
- Screen mirroring uses ScreenCaptureKit's continuous capture (SCStream) and sends JPEG frames 1920 pixels wide; Pilsiz's own panel is excluded. The TV's browser updates an MJPEG stream at most ~15 times per second, so the frame rate is held at 15. It suits presentations and web pages, not films.

### Dashboard: page, navigation and data

The dashboard is a single 1280×720 XHTML page ([`DashboardPage.swift`](Sources/Pilsiz/DashboardPage.swift)) that opens on the same HbbTV screen as "Show on TV".

```
        Pilsiz (Mac)                                         TV (HbbTV page)
  ┌───────────────────────┐   GET /pano.json, /pano/img/…   ┌──────────────────┐
  │ Dashboard             │ ◀────────────────────────────── │ data and images  │
  │  news · weather ·     │   GET /pano/poll  (held open)   │                  │
  │  markets · shortcuts  │ ◀────────────────────────────── │ waiting for a key│
  │                       │ ──── {"keys":["right"]} ──────▶ │ focus moves right│
  │ arrow key / trackpad  │   GET /pano/act?id=app:netflix  │                  │
  │ opens Netflix on TV   │ ◀────────────────────────────── │ OK was pressed   │
  └───────────────────────┘                                 └──────────────────┘
```

- **Keys come from the Mac, not the TV.** Remote keys sent over the network do not reach an HbbTV page. So the page keeps a `/pano/poll` request open (long polling); when a direction key is pressed in Pilsiz the request is answered immediately and focus moves on the page. The navigation logic lives in the page: the nearest card in the given direction.
- **The selection is reported to the Mac.** On OK the page calls `/pano/act?id=…`. The Mac first closes the dashboard (the TV returns to the broadcast), then opens the app over DIAL or sends the video through YouTube Lounge.
- **The TV makes no outside requests.** The Mac gathers news, weather, market data and YouTube thumbnails; the fonts (`Resources/Fonts`) are served from the Mac too.
- **Live stream shortcuts.** A channel link is resolved to the current video from the `canonical` address on the channel's `/live` page, and refreshed every half hour.
- **Gram gold** is calculated from the ounce price and the dollar rate; it can differ slightly from the Grand Bazaar price.
- **Development.** `PILSIZ_PANO=1 PILSIZ_PORT=8791 swift run` serves the dashboard without touching the TV; open `http://localhost:8791/` in a browser and navigate with the keyboard's arrow keys. Because the TV parses the page as strict XHTML, the same strictness applies locally: a malformed tag fails in the browser straight away.

### Commands, keyboard and pointer

The following were found by recording the traffic of the *TV Smart Centre* phone app with mitmproxy and analysing it with [REA](https://github.com/morluto/rea). They all go to the same endpoint; commands carry the header `application_name: tv smart centre`, as the phone app does.

| Purpose | Request body |
|---|---|
| Channel list | `<?xml version='1.0'?><command>activechannellist</command>` |
| TV capabilities | `<?xml version='1.0'?><command>specialportalapps</command>` |
| Text (one character at a time) | `<?xml version='1.0' ?><keyboard><key value='116'/></keyboard>` (ASCII/Unicode code) |
| Pointer (~60 Hz) | `<?xml version='1.0'?><mouseevent><event_data dx='8.0' dy='-29.3' button='0'/></mouseevent>` |

The HTTP response to a command is empty; **the result is published on the TV's WebSocket on port 7681**. The channel list arrives like this (the TV does not escape `&` in names, so it is parsed leniently):

```xml
<active_list network='None' count='614' total_size='67979'>
  <service rsn='1' name='TRT 1 HD' handle='715' onid='0' tsid='7' sid='10601' type='25' is_encrypted='0'/>
  …
```

`rsn` is the channel number on the TV; `type` 25/22/1 is broadcast, 2 is radio, 131 is an internet channel. The TV sends the list only to clients connected at that moment, so the WebSocket must be opened **before** the command.

### Sending a video to YouTube

Sending `v=<id>` over DIAL opens YouTube but does not play the video. Instead Pilsiz uses the **YouTube Lounge** channel behind the "Watch on TV" button on phones:

1. **Pairing (once):** `POST /apps/YouTube` with the body `pairingCode=<uuid>&theme=cl` → YouTube on the TV registers with this code; `POST https://www.youtube.com/api/lounge/pairing/get_screen` (`pairing_code=<uuid>`) returns a permanent `screenId`. No code has to be typed on the TV.
2. **Token:** `POST …/pairing/get_lounge_token_batch` (`screen_ids=<screenId>`) → `loungeToken`.
3. **Session:** `POST …/bc/bind?…&loungeIdToken=…` with the body `count=0` → `SID`, `gsessionid`, `AID` from the response.
4. **Play:** to the same endpoint, `req0__sc=setPlaylist&req0_videoId=<id>&req0_currentTime=<s>…`.

The Lounge API is undocumented; it is used the same way as open-source clients do (e.g. pyytlounge).

### Apps (DIAL)

| App | Endpoint | Note |
|---|---|---|
| Netflix | `POST /apps/Netflix` | No extra header needed |
| Prime Video | `POST /apps/AmazonInstantVideo` | No extra header needed |
| YouTube | `POST /apps/YouTube` | Returns **403** without `Origin: https://www.youtube.com` |

The running app is tracked through `<state>running</state>` in the response to `GET /apps/<name>`.

### Programme guide

Programmes are merged from two open XMLTV sources: **[epgshare01](https://epgshare01.online/epgshare01/)** (178 channels, 3 days; gzip, decompressed with macOS's built-in DEFLATE decoder) and, for channels it lacks, **[iptv-epg-turkey](https://github.com/trology85/iptv-epg-turkey)** (the current day only). Both carry the same broadcast data; a third source (iptv-epg.org) was not used because its times were wrong. The guide is refreshed every 6 hours and when the day changes, and cached under `~/Library/Application Support/Pilsiz/`. Channels are matched by name (`"STAR TV HD"` ↔ `"Star"`, `"HABERTÜRK HD"` ↔ `"HABERTÜRK TV"`).

### Switching channels

There is no command for switching to a channel by name. So the channel list is kept on the Mac, and clicking a channel types its number digit by digit. Logos are matched with a key derived from the channel name: `"TRT 1 HD"` → `trt1.png`, `"HABERTÜRK HD"` → `haberturk.png`.

## Project structure

```
Sources/Pilsiz/
├── PilsizApp.swift      # Menu bar icon + NSPopover with an arrow
├── TVController.swift   # State, command queue, volume tracking, discovery, Wake-on-LAN
├── Network.swift        # Minimal HTTP client (Network.framework), SmartCenter/DIAL, WoL
├── Stores.swift         # Channel list and activity data (UserDefaults)
├── RemoteKey.swift      # Key codes
├── RootView.swift       # Header, tab bar, keyboard shortcuts
├── Tabs.swift           # On Screen, Activity
├── AppsTab.swift        # Apps tab
├── ChannelsTab.swift    # Channel list and grid, editor, scan wizard
├── SettingsTab.swift    # Settings
├── ChannelLogo.swift    # Logo matching and fallback badge
├── EPG.swift            # Programme guide: download, cache, XMLTV parsing, name matching
├── Reminders.swift      # Programme reminders and notifications
├── CommandPalette.swift # ⌘K quick search
├── HotKeys.swift        # Global shortcuts (Carbon)
├── YouTube.swift        # YouTube link parsing and playing on the TV through Lounge
├── Assistant.swift      # Tell Pilsiz: rules + on-device model, actions
├── Voice.swift          # On-device Turkish speech recognition and the capsule at the top of the screen
├── ShareServer.swift    # The HbbTV page on the TV and the local server it connects to (Range support)
├── ScreenShare.swift    # Screen capture, photo slideshow, video conversion, consent
├── Dashboard.swift      # Dashboard: news, weather, market and shortcut data; handling the selected card
├── DashboardPage.swift  # The dashboard page that opens on the TV
├── PanoTouchpad.swift   # The area that drives the dashboard with trackpad swipes
├── ShareTab.swift       # Show on TV tab
├── Remote.swift         # Remote tab
├── Components.swift     # Theme and shared components
└── Snapshot.swift       # (DEBUG only) renders the tabs to PNG
Resources/
├── Info.plist
├── tv.png               # The realistic TV image in the On Screen tab
├── Fonts/               # Dashboard fonts (Figtree, Bricolage Grotesque; SIL OFL)
└── Logos/               # Channel logos
```

To regenerate the panel screenshots in this README with a debug build (it works with the TV off; the panel is drawn in its "connected" state):

```bash
swift build && PILSIZ_SNAPSHOT=/tmp/snap .build/debug/Pilsiz
```

The dashboard screenshots are taken from a browser with a 1280×720 window while the local dashboard server (`PILSIZ_PANO=1`) is running.

## Known limitations and roadmap

- [x] **Fetch the channel list** from the TV automatically
- [x] Text entry from the keyboard, touchpad/pointer (protocol decoded; not in the interface at the moment)
- [x] Show the Mac screen, photos and videos on the TV (HbbTV)
- [x] A dashboard on the TV; navigation with the keyboard and the trackpad
- [ ] Choose the dashboard city and news source in settings (fixed in code for now)
- [ ] Verification on other Vestel-based models (tested only on the Daewoo 43DE54F)
- [ ] Open apps other than Netflix, Prime Video and YouTube directly: this TV's DIAL service knows no other app, the rest are reachable only through the TV's own app screen
- [ ] **Read** the volume from the TV: the phone app only sends +/− too; no read was found in the protocol
- [ ] Read the current channel from the TV (to know about a channel changed from the phone)
- [ ] Picture settings such as brightness and contrast
- [ ] Select inputs directly (for now the source menu is opened and the position number is sent)

Next step for the remaining items: static analysis of SmartCenter's Android APK with REA.

## Contributing

Bug reports, test results from other TV models and proposed changes are welcome.

- **If you tried it on another TV,** write the model, the mainboard code (if you know it) and what worked and what did not in an [issue](https://github.com/thealibrs/pilsiz/issues). This is the most valuable contribution.
- **For code changes,** fork the repository, make sure it builds with `swift build`, and open a pull request. Try not to add external dependencies; the project is dependency-free on purpose.
- The code comments and the interface are in Turkish; contributions are preferred the same way, but issues and pull requests in English are fine.

## Credits and sources

- [ha-vestel-toshiba-tv](https://github.com/mutlutekir/ha-vestel-toshiba-tv): the `/apps/SmartCenter` endpoint and the unquoted code format
- [pyvesteltv](https://github.com/T3m3z/pyvesteltv) and [ha-vestel-component](https://github.com/andylynch/ha-vestel-component)
- [node-red-contrib-vestel-tv](https://github.com/hyttysmyrkky/node-red-contrib-vestel-tv): extended key map
- [shkspr.mobi](https://shkspr.mobi/blog/2018/11/telnet-control-of-toshiba-smart-tvs/): Toshiba/Vestel key codes
- Programme guide: [epgshare01](https://epgshare01.online/epgshare01/) and [trology85/iptv-epg-turkey](https://github.com/trology85/iptv-epg-turkey)
- Dashboard data: the chosen news site's RSS feed (default [Gazete Oksijen](https://gazeteoksijen.com)), [Open-Meteo](https://open-meteo.com) (weather and city search), Yahoo Finance (markets)
- Dashboard fonts: [Figtree](https://github.com/erikdkennedy/figtree) and [Bricolage Grotesque](https://github.com/ateliertriay/bricolage), under the SIL Open Font License 1.1 (license texts are in `Resources/Fonts`)
- Channel logos: [tv-logo/tv-logos](https://github.com/tv-logo/tv-logos)
- The TV image in the On Screen tab was generated with Higgsfield (GPT Image 2.5)
- Interface idea: the LG webOS menu bar app by [@greco_dev](https://x.com/greco_dev/status/2109842197654692349)

## License

The code is released under the [MIT license](LICENSE). The fonts are distributed under their own license (SIL OFL 1.1).

The channel logos and the names Netflix, Prime Video, YouTube and other brands are trademarks of their respective owners; they are used here only to identify the channel or the app and are not covered by the MIT license. They will be removed at the rights holder's request.

This project is not affiliated with or endorsed by Vestel, Daewoo, Google, Netflix, Amazon, Yahoo or any broadcaster named here. The YouTube Lounge, Yahoo Finance and SmartCenter endpoints are undocumented interfaces; they can change or disappear without notice.

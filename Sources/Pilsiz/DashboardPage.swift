import Foundation

extension ShareServer {
    /// TV'deki pano sayfası (1280×720). Veriyi `/pano.json`'dan alır; kumanda tuşları TV'den değil,
    /// Mac'ten `/pano/poll` uzun yoklamasıyla gelir (ağdan gönderilen tuşlar HbbTV sayfasına ulaşmıyor).
    /// Seçilen kart `/pano/act?id=…` ile Mac'e bildirilir, işi Mac yapar.
    ///
    /// Sayfa katı XHTML olarak okunur: her etiket kapalı, betik CDATA içinde, veriler `textContent` ile yazılır.
    static let panoPage = #"""
    <!DOCTYPE html PUBLIC "-//HbbTV//1.1.1//EN" "http://www.hbbtv.org/dtd/HbbTV-1.1.1.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml">
    <head>
    <meta http-equiv="Content-Type" content="application/vnd.hbbtv.xhtml+xml; charset=UTF-8" />
    <title>Pilsiz</title>
    <style>
      /* Fontlar Mac'ten gelir (Resources/Fonts); Türkçe harfler latin-ext dosyalarındadır. */
      @font-face { font-family: 'Figtree'; font-weight: 400 800; src: url(/pano/font/figtree-latin.woff2) format('woff2'); unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD; }
      @font-face { font-family: 'Figtree'; font-weight: 400 800; src: url(/pano/font/figtree-latin-ext.woff2) format('woff2'); unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C4, U+2113, U+2C60-2C7F, U+A720-A7FF; }
      @font-face { font-family: 'Bricolage Grotesque'; font-weight: 500 800; src: url(/pano/font/bricolage-latin.woff2) format('woff2'); unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD; }
      @font-face { font-family: 'Bricolage Grotesque'; font-weight: 500 800; src: url(/pano/font/bricolage-latin-ext.woff2) format('woff2'); unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C4, U+2113, U+2C60-2C7F, U+A720-A7FF; }
      * { box-sizing: border-box; }
      body { margin: 0; width: 1280px; height: 720px; overflow: hidden; background: #0b0c10; color: #f4f1ec; font-family: 'Figtree', sans-serif; }
      .mark, .clock b, .weather b, .wnow > b, .mrow .v b, #sheet h2, #idle .big, #idle .hl { font-family: 'Bricolage Grotesque', 'Figtree', sans-serif; }
      #tv { position: absolute; left: 0; top: 0; width: 1280px; height: 720px; overflow: hidden;
        background: radial-gradient(620px 340px at 18% 30%, rgba(238, 46, 69, 0.18), rgba(238, 46, 69, 0) 70%), #0b0c10; }
      .dim { color: #a8abb5; }

      .top { position: absolute; left: 64px; right: 64px; top: 36px; height: 64px; display: flex; align-items: center; justify-content: space-between; }
      .mark { font-weight: bold; font-size: 36px; letter-spacing: -1px; }
      .mark i { font-style: normal; color: #ee2e45; }
      .status { display: flex; align-items: center; }
      .weather { display: flex; align-items: center; color: #a8abb5; font-size: 22px; margin-right: 40px; }
      .weather b { color: #f4f1ec; font-size: 30px; margin: 0 12px; }
      .clock { text-align: right; line-height: 1.05; }
      .clock b { display: block; font-size: 46px; letter-spacing: -1px; }
      .clock span { font-size: 20px; color: #a8abb5; }

      .f { transition: transform 120ms ease-out; }
      .focus { transform: scale(1.05); box-shadow: 0 0 0 3px #fff, 0 14px 36px rgba(0, 0, 0, 0.55); position: relative; z-index: 2; }

      .grid { position: absolute; left: 64px; top: 124px; width: 660px; }
      .app { float: left; width: 209px; height: 132px; margin: 0 16px 16px 0; border-radius: 20px; font-size: 25px; font-weight: bold;
        display: flex; flex-direction: column; align-items: center; justify-content: center; }
      .app.end { margin-right: 0; }
      .app.wide { width: 434px; }
      .app.wide.focus { transform: scale(1.03); }
      .netflix { background: #000; color: #e50914; font-size: 38px; letter-spacing: 1px; }
      .prime { background: linear-gradient(160deg, #1a2b3c, #0f171e); color: #fff; line-height: 1; }
      .prime b { font-size: 36px; }
      .prime i { font-style: normal; font-weight: normal; font-size: 25px; color: #d7eaf5; }
      .youtube { background: #fff; color: #0f0f0f; font-size: 27px; }
      .play { width: 50px; height: 36px; border-radius: 10px; background: #ff0033; margin-bottom: 8px; display: flex; align-items: center; justify-content: center; }
      .plain { background: #1d2028; border: 1px solid rgba(255, 255, 255, 0.08); }
      .plain svg { margin-bottom: 8px; }

      .yt { position: absolute; left: 64px; top: 420px; width: 660px; }
      .lbl { display: block; font-size: 20px; font-weight: bold; color: #a8abb5; height: 32px; }
      .short { float: left; width: 153px; height: 118px; margin-right: 16px; border-radius: 16px; overflow: hidden; background: #15171d; border: 1px solid rgba(255, 255, 255, 0.08); }
      .short.end { margin-right: 0; }
      .short .th { height: 78px; background: #2a1414 center / cover no-repeat; display: flex; align-items: center; justify-content: center; }
      .short .th i { width: 38px; height: 27px; border-radius: 8px; background: #ff0033; display: flex; align-items: center; justify-content: center; }
      .short b { display: block; font-size: 20px; padding: 7px 10px 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

      .livebar { position: absolute; left: 64px; top: 588px; width: 660px; height: 68px; border-radius: 16px; background: #15171d; border: 1px solid rgba(255, 255, 255, 0.08);
        display: flex; align-items: center; padding: 0 18px 0 12px; font-size: 22px; }
      .livebar.focus { transform: scale(1.02); }
      .plate { width: 76px; height: 46px; margin-right: 16px; border-radius: 8px; background: #f6f4f0 center / contain no-repeat; background-origin: content-box; padding: 5px 9px; flex: none; }
      #livetext { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      #liveleft { font-size: 20px; color: #a8abb5; flex: none; margin-left: 12px; }

      .panel { position: absolute; left: 748px; right: 64px; top: 124px; height: 532px; background: #15171d; border: 1px solid rgba(255, 255, 255, 0.08); border-radius: 22px; padding: 12px 10px 10px; }
      .tabs { height: 44px; padding: 0 4px; }
      .tab { float: left; font-size: 21px; font-weight: bold; color: #a8abb5; padding: 8px 18px; border-radius: 22px; margin-right: 8px; }
      .tab.on { background: rgba(255, 255, 255, 0.13); color: #f4f1ec; }
      .tab.focus { transform: none; box-shadow: 0 0 0 3px #fff; }
      .pane { position: absolute; left: 10px; right: 10px; top: 64px; bottom: 10px; display: none; }
      .pane.on { display: block; }
      .empty { font-size: 22px; color: #a8abb5; padding: 20px 14px; }

      .item { height: 112px; border-radius: 14px; padding: 12px 14px 0; }
      .item.focus { transform: none; box-shadow: none; background: rgba(255, 255, 255, 0.12); }
      .cat { font-size: 20px; color: #a8abb5; }
      .cat b { color: #ee2e45; }
      .hl { font-size: 24px; line-height: 29px; font-weight: bold; margin-top: 5px; max-height: 58px; overflow: hidden; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2; }
      .more { position: absolute; right: 14px; bottom: -4px; font-size: 18px; color: #6b6f7b; }

      .wnow { display: flex; align-items: center; padding: 10px 14px 0; height: 96px; }
      .wnow > b { font-size: 80px; line-height: 1; margin: 0 18px; }
      .wnow div b { display: block; font-size: 24px; }
      .wnow div span { font-size: 20px; color: #a8abb5; }
      .hours { display: flex; margin: 16px 14px 0; padding: 14px 0; border-top: 1px solid rgba(255, 255, 255, 0.08); border-bottom: 1px solid rgba(255, 255, 255, 0.08); }
      .hours div { flex: 1; text-align: center; }
      .hours span { display: block; font-size: 20px; color: #a8abb5; margin-bottom: 6px; }
      .hours b { display: block; font-size: 24px; margin-top: 4px; }
      .day { display: flex; align-items: center; height: 48px; font-size: 23px; margin: 0 14px; }
      .day .n { flex: 1; }
      .day .t { width: 124px; text-align: right; }

      .mrow { display: flex; align-items: center; height: 114px; margin: 0 14px; border-top: 1px solid rgba(255, 255, 255, 0.08); }
      .mrow.first { border-top: 0; }
      .mrow .n { flex: 1; min-width: 0; }
      .mrow .n b { display: block; font-size: 24px; white-space: nowrap; }
      .mrow .n span { font-size: 20px; color: #a8abb5; }
      .mrow svg { margin: 0 14px; }
      .mrow .v { width: 132px; text-align: right; }
      .mrow .v b { display: block; font-size: 30px; letter-spacing: -1px; }
      .mrow .v span { font-size: 20px; font-weight: bold; }
      .up { color: #3ccf7a; }
      .down { color: #ff6b6b; }

      #toast { position: absolute; left: 340px; width: 600px; top: 318px; text-align: center; display: none; z-index: 9; }
      #toast span { display: inline-block; background: rgba(12, 13, 17, 0.95); border: 1px solid rgba(255, 255, 255, 0.14); padding: 16px 28px; border-radius: 14px; font-size: 24px; font-weight: bold; }

      #sheet { position: absolute; left: 0; top: 0; width: 1280px; height: 720px; background: rgba(5, 6, 8, 0.86); display: none; z-index: 8; }
      #sheet .box { position: absolute; left: 190px; top: 130px; width: 900px; background: #1d2028; border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 26px; padding: 36px 44px 30px; }
      #sheet .cat { font-size: 22px; }
      #sheet h2 { font-size: 40px; line-height: 46px; margin: 12px 0 18px; }
      #sheet p { font-size: 26px; line-height: 36px; color: #d3d5dc; margin: 0; max-height: 252px; overflow: hidden; }
      #sheet .hint { font-size: 20px; color: #6b6f7b; margin-top: 26px; }

      #idle { position: absolute; left: 0; top: 0; width: 1280px; height: 720px; display: none; z-index: 10; color: #f3efe6;
        background: radial-gradient(760px 420px at 12% 18%, rgba(255, 122, 89, 0.13), rgba(255, 122, 89, 0) 70%), #0d1513; }
      #idle .big { position: absolute; left: 60px; top: 50px; font-size: 270px; line-height: 1; letter-spacing: -8px; font-weight: bold; }
      #idle .when { position: absolute; left: 64px; top: 344px; font-size: 30px; color: #a9b7b0; }
      #idle .when b { color: #f3efe6; font-weight: normal; margin-right: 22px; }
      #idle .one { position: absolute; left: 64px; right: 64px; top: 452px; border-top: 1px solid rgba(243, 239, 230, 0.14); padding-top: 26px; }
      #idle .cat { font-size: 22px; color: #a9b7b0; }
      #idle .cat b { color: #ff7a59; }
      #idle .hl { font-size: 48px; line-height: 54px; max-height: 108px; -webkit-line-clamp: 2; margin-top: 10px; }
      #idle .hint { position: absolute; right: 64px; bottom: 40px; font-size: 20px; color: #a9b7b0; }
    </style>
    </head>
    <body>
    <object type="application/oipfApplicationManager" id="appmgr" style="position:absolute;width:0;height:0"></object>
    <div id="tv">
      <div class="top">
        <span class="mark">Pilsiz<i>.</i></span>
        <div class="status">
          <div class="weather"><span id="wicon"></span><b id="wtemp"></b><span id="wtext"></span></div>
          <div class="clock"><b id="clock"></b><span id="date"></span></div>
        </div>
      </div>

      <div class="grid">
        <div class="app netflix f" data-act="app:netflix" data-say="Netflix açılıyor…">NETFLIX</div>
        <div class="app prime f" data-act="app:prime" data-say="Prime Video açılıyor…"><b>prime</b><i>video</i></div>
        <div class="app youtube f end" data-act="app:youtube" data-say="YouTube açılıyor…"><span class="play"><svg xmlns="http://www.w3.org/2000/svg" width="14" height="15" viewBox="0 0 12 13"><path d="M0 0l12 6.5L0 13z" fill="#fff"/></svg></span>YouTube</div>
        <div class="app plain wide f" data-act="app:portal" data-say="Uygulamalar açılıyor…"><svg xmlns="http://www.w3.org/2000/svg" width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="#a8abb5" stroke-width="1.6"><rect x="3.5" y="3.5" width="7" height="7" rx="1.6"/><rect x="13.5" y="3.5" width="7" height="7" rx="1.6"/><rect x="3.5" y="13.5" width="7" height="7" rx="1.6"/><rect x="13.5" y="13.5" width="7" height="7" rx="1.6"/></svg>Uygulamalar</div>
        <div class="app plain f end" data-act="app:mac" data-say="Mac ekranı yansıtılıyor…"><svg xmlns="http://www.w3.org/2000/svg" width="36" height="33" viewBox="0 0 26 24" fill="none" stroke="#a8abb5" stroke-width="1.6"><rect x="4" y="4" width="18" height="12" rx="1.8"/><path d="M1.5 19.5h23"/></svg>Mac</div>
      </div>

      <div class="yt" id="yt">
        <span class="lbl">YouTube kısayolları</span>
        <div class="short f" id="s0"><div class="th"><i><svg xmlns="http://www.w3.org/2000/svg" width="12" height="13" viewBox="0 0 12 13"><path d="M0 0l12 6.5L0 13z" fill="#fff"/></svg></i></div><b></b></div>
        <div class="short f" id="s1"><div class="th"><i><svg xmlns="http://www.w3.org/2000/svg" width="12" height="13" viewBox="0 0 12 13"><path d="M0 0l12 6.5L0 13z" fill="#fff"/></svg></i></div><b></b></div>
        <div class="short f" id="s2"><div class="th"><i><svg xmlns="http://www.w3.org/2000/svg" width="12" height="13" viewBox="0 0 12 13"><path d="M0 0l12 6.5L0 13z" fill="#fff"/></svg></i></div><b></b></div>
        <div class="short f end" id="s3"><div class="th"><i><svg xmlns="http://www.w3.org/2000/svg" width="12" height="13" viewBox="0 0 12 13"><path d="M0 0l12 6.5L0 13z" fill="#fff"/></svg></i></div><b></b></div>
      </div>

      <div class="livebar f" id="live" data-act="live" data-say="Canlı yayına dönülüyor…">
        <span class="plate" id="liveplate"></span><span id="livetext"></span><span id="liveleft"></span>
      </div>

      <div class="panel">
        <div class="tabs">
          <span class="tab f on" id="tab-news" data-tab="news">Haberler</span>
          <span class="tab f" id="tab-weather" data-tab="weather">Hava</span>
          <span class="tab f" id="tab-market" data-tab="market">Piyasa</span>
        </div>
        <div class="pane on" id="pane-news">
          <div class="item f" id="n0"><span class="cat"></span><div class="hl"></div></div>
          <div class="item f" id="n1"><span class="cat"></span><div class="hl"></div></div>
          <div class="item f" id="n2"><span class="cat"></span><div class="hl"></div></div>
          <div class="item f" id="n3"><span class="cat"></span><div class="hl"></div></div>
          <span class="more" id="more"></span>
        </div>
        <div class="pane" id="pane-weather"></div>
        <div class="pane" id="pane-market"></div>
      </div>

      <div id="toast"><span id="toasttext"></span></div>
      <div id="sheet"><div class="box"><span class="cat" id="sheetcat"></span><h2 id="sheettitle"></h2><p id="sheetsum"></p><div class="hint">Kapatmak için OK ya da Geri</div></div></div>
      <div id="idle">
        <div class="big" id="idleclock"></div>
        <div class="when"><b id="idledate"></b><span id="idleweather"></span></div>
        <div class="one"><span class="cat" id="idlecat"></span><div class="hl" id="idlehl"></div></div>
        <div class="hint">Bir tuşa basınca pano geri gelir</div>
      </div>
    </div>
    <script type="text/javascript">//<![CDATA[
      var app = null;
      try { app = document.getElementById('appmgr').getOwnerApplication(document); app.show(); } catch (e) {}

      var SVG = 'http://www.w3.org/2000/svg';
      var IDLE_AFTER = 180000;   // 3 dk tuşa basılmazsa bekleme ekranı
      var DAYS = ['Pazar', 'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi'];
      var MONTHS = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

      var D = { news: [], shorts: [], market: [], weather: null, live: null, tz: 180, city: '' };
      var dataVersion = -1, seq = -1, skew = 0;
      var current = null, newsOffset = 0, sheetOpen = false, idle = false, idleIndex = 0;
      var lastKey = new Date().getTime(), toastTimer = null, leaving = false;

      function $(id) { return document.getElementById(id); }
      function text(el, value) { el.textContent = value === null || value === undefined ? '' : String(value); }
      function now() { return new Date().getTime() + skew; }
      function two(n) { return n < 10 ? '0' + n : '' + n; }

      // Hava simgeleri: clear, moon, partly, cloud, rain, snow, storm
      function icon(kind, w) {
        var cloud = '<path d="M9 22h16a6 6 0 0 0 0-12 8 8 0 0 0-15 3 4.5 4.5 0 0 0-1 9z" fill="#d9dde6"/>';
        var body = cloud;
        if (kind === 'clear') { body = '<circle cx="17" cy="14" r="8" fill="#ffc542"/>'; }
        if (kind === 'moon') { body = '<path d="M22 20a9 9 0 0 1-9-13 9 9 0 1 0 12 12 9 9 0 0 1-3 1z" fill="#cfd6e6"/>'; }
        if (kind === 'partly') { body = '<circle cx="12" cy="10" r="6" fill="#ffc542"/><path d="M11 24h15a6 6 0 0 0 0-12 8 8 0 0 0-15 3 4.5 4.5 0 0 0 0 9z" fill="#d9dde6"/>'; }
        if (kind === 'rain') { body = '<path d="M9 18h16a6 6 0 0 0 0-12 8 8 0 0 0-15 3 4.5 4.5 0 0 0-1 9z" fill="#d9dde6"/><path d="M12 21l-2 5M18 21l-2 5M24 21l-2 5" stroke="#6fb1ff" stroke-width="2" stroke-linecap="round"/>'; }
        if (kind === 'snow') { body = '<path d="M9 18h16a6 6 0 0 0 0-12 8 8 0 0 0-15 3 4.5 4.5 0 0 0-1 9z" fill="#d9dde6"/><circle cx="11" cy="24" r="1.6" fill="#fff"/><circle cx="17" cy="24" r="1.6" fill="#fff"/><circle cx="23" cy="24" r="1.6" fill="#fff"/>'; }
        if (kind === 'storm') { body = '<path d="M9 18h16a6 6 0 0 0 0-12 8 8 0 0 0-15 3 4.5 4.5 0 0 0-1 9z" fill="#d9dde6"/><path d="M18 18l-4 6h3l-2 4 6-7h-3l2-3z" fill="#ffc542"/>'; }
        return '<svg xmlns="' + SVG + '" width="' + w + '" height="' + Math.round(w * 28 / 34) + '" viewBox="0 0 34 28">' + body + '</svg>';
      }

      function make(tag, cls, value) {
        var el = document.createElement(tag);
        if (cls) { el.className = cls; }
        if (value !== undefined) { text(el, value); }
        return el;
      }

      function ago(time) {
        var minutes = Math.floor((now() - time) / 60000);
        if (minutes < 1) { return 'az önce'; }
        if (minutes < 60) { return minutes + ' dk önce'; }
        if (minutes < 1440) { return Math.floor(minutes / 60) + ' sa önce'; }
        return Math.floor(minutes / 1440) + ' gün önce';
      }

      function setCat(el, item) {
        el.textContent = '';
        el.appendChild(make('b', null, item.cat));
        el.appendChild(document.createTextNode(' · ' + ago(item.time)));
      }

      // MARK: çizim

      function renderClock() {
        var d = new Date(now() + D.tz * 60000);
        var clock = two(d.getUTCHours()) + ':' + two(d.getUTCMinutes());
        var date = DAYS[d.getUTCDay()] + ', ' + d.getUTCDate() + ' ' + MONTHS[d.getUTCMonth()];
        text($('clock'), clock); text($('date'), date);
        text($('idleclock'), clock); text($('idledate'), date);
      }

      function renderNews() {
        var i, item, slot;
        if (newsOffset > Math.max(0, D.news.length - 4)) { newsOffset = Math.max(0, D.news.length - 4); }
        for (i = 0; i < 4; i++) {
          slot = $('n' + i);
          item = D.news[newsOffset + i];
          slot.style.display = item ? 'block' : 'none';
          if (item) { setCat(slot.firstChild, item); text(slot.lastChild, item.title); }
        }
        text($('more'), D.news.length > 4 ? (newsOffset + 1) + '–' + Math.min(newsOffset + 4, D.news.length) + ' / ' + D.news.length : '');
      }

      function renderWeather() {
        var pane = $('pane-weather'), w = D.weather, i, box, row, span;
        pane.textContent = '';
        $('wicon').innerHTML = w ? icon(w.icon, 38) : '';
        text($('wtemp'), w ? w.temp + '°' : '');
        text($('wtext'), w ? w.text : '');
        text($('idleweather'), w ? w.temp + '° ' + w.text + ' · ' + D.city : '');
        if (!w) { pane.appendChild(make('div', 'empty', 'Hava durumu alınamadı.')); return; }
        box = make('div', 'wnow');
        span = make('span'); span.innerHTML = icon(w.icon, 92); box.appendChild(span);
        box.appendChild(make('b', null, w.temp + '°'));
        row = make('div');
        row.appendChild(make('b', null, w.text));
        row.appendChild(make('span', null, 'Hissedilen ' + w.feels + '°'));
        box.appendChild(row);
        pane.appendChild(box);
        box = make('div', 'hours');
        for (i = 0; i < w.hours.length; i++) {
          row = make('div');
          row.appendChild(make('span', null, w.hours[i].t));
          span = make('i'); span.innerHTML = icon(w.hours[i].icon, 38); row.appendChild(span);
          row.appendChild(make('b', null, w.hours[i].temp + '°'));
          box.appendChild(row);
        }
        pane.appendChild(box);
        for (i = 0; i < w.days.length; i++) {
          row = make('div', 'day');
          row.appendChild(make('span', 'n', w.days[i].name));
          span = make('span'); span.innerHTML = icon(w.days[i].icon, 38); row.appendChild(span);
          span = make('span', 't', w.days[i].max + '° ');
          span.appendChild(make('span', 'dim', '/ ' + w.days[i].min + '°'));
          row.appendChild(span);
          pane.appendChild(row);
        }
      }

      function spark(points, up) {
        var svg = document.createElementNS(SVG, 'svg'), line = document.createElementNS(SVG, 'polyline'), i, out = [];
        svg.setAttribute('width', '104'); svg.setAttribute('height', '36'); svg.setAttribute('viewBox', '0 0 104 36');
        for (i = 0; i < points.length; i++) {
          out.push((points.length > 1 ? Math.round(i * 104 / (points.length - 1)) : 0) + ',' + Math.round(33 - points[i] * 30));
        }
        line.setAttribute('points', out.join(' '));
        line.setAttribute('fill', 'none'); line.setAttribute('stroke', up ? '#3ccf7a' : '#ff6b6b');
        line.setAttribute('stroke-width', '2.5'); line.setAttribute('stroke-linecap', 'round'); line.setAttribute('stroke-linejoin', 'round');
        svg.appendChild(line);
        return svg;
      }

      function renderMarket() {
        var pane = $('pane-market'), i, m, row, box;
        pane.textContent = '';
        if (!D.market.length) { pane.appendChild(make('div', 'empty', 'Piyasa verisi alınamadı.')); return; }
        for (i = 0; i < D.market.length && i < 4; i++) {
          m = D.market[i];
          row = make('div', i === 0 ? 'mrow first' : 'mrow');
          box = make('div', 'n'); box.appendChild(make('b', null, m.name)); box.appendChild(make('span', null, m.unit)); row.appendChild(box);
          row.appendChild(spark(m.points, m.up));
          box = make('div', 'v'); box.appendChild(make('b', null, m.value));
          box.appendChild(make('span', m.up ? 'up' : 'down', (m.up ? '▲ ' : '▼ ') + m.change)); row.appendChild(box);
          pane.appendChild(row);
        }
      }

      function renderShorts() {
        var i, tile, s, any = false;
        for (i = 0; i < 4; i++) {
          tile = $('s' + i);
          s = D.shorts[i];
          tile.style.display = s ? 'block' : 'none';
          if (!s) { continue; }
          any = true;
          tile.setAttribute('data-act', 'yt:' + i);
          tile.setAttribute('data-say', 'YouTube\'da açılıyor: ' + s.name);
          text(tile.lastChild, s.name);
          tile.firstChild.style.backgroundImage = s.img ? 'url(' + s.img + ')' : 'none';
          tile.firstChild.firstChild.style.display = s.img ? 'none' : 'flex';   // küçük resim varsa oynat rozeti gizlenir
        }
        $('yt').style.display = any ? 'block' : 'none';
      }

      function renderLive() {
        var live = D.live, plate = $('liveplate'), label = $('livetext');
        label.textContent = '';
        label.appendChild(make('b', null, live ? 'Canlı TV' : 'Canlı TV\'ye dön'));
        if (live) { label.appendChild(document.createTextNode(' · ' + live.name + (live.prog ? ' · ' + live.prog : ''))); }
        text($('liveleft'), live ? live.left : '');
        plate.style.display = live && live.logo ? 'block' : 'none';
        plate.style.backgroundImage = live && live.logo ? 'url(' + live.logo + ')' : 'none';
      }

      function renderIdle() {
        var item = D.news.length ? D.news[idleIndex % D.news.length] : null;
        if (item) { setCat($('idlecat'), item); text($('idlehl'), item.title); }
        else { text($('idlecat'), ''); text($('idlehl'), ''); }
      }

      function render() {
        renderClock(); renderNews(); renderWeather(); renderMarket(); renderShorts(); renderLive(); renderIdle();
        if (!current || !visible(current)) { focus(document.querySelector('.netflix')); }
      }

      // MARK: odak ve gezinme

      function visible(el) { return el.offsetWidth > 0 && el.offsetHeight > 0; }
      function center(el) { var r = el.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; }

      function showTab(name) {
        var names = ['news', 'weather', 'market'], i;
        for (i = 0; i < names.length; i++) {
          $('tab-' + names[i]).className = 'tab f' + (names[i] === name ? ' on' : '') + ($('tab-' + names[i]) === current ? ' focus' : '');
          $('pane-' + names[i]).className = 'pane' + (names[i] === name ? ' on' : '');
        }
      }

      function focus(el) {
        if (!el) { return; }
        if (current) { current.className = current.className.replace(' focus', ''); }
        current = el;
        current.className += ' focus';
        if (el.getAttribute('data-tab')) { showTab(el.getAttribute('data-tab')); }
      }

      // Verilen yöndeki en yakın görünür öğe.
      function move(dx, dy) {
        var slot = current && current.id.charAt(0) === 'n' && current.className.indexOf('item') >= 0 ? parseInt(current.id.charAt(1), 10) : -1;
        // Haber listesi dört satırlık bir pencere: uçlarda odak yerinde kalır, liste kayar.
        if (slot === 3 && dy > 0 && newsOffset + 4 < D.news.length) { newsOffset++; renderNews(); return; }
        if (slot === 0 && dy < 0 && newsOffset > 0) { newsOffset--; renderNews(); return; }
        if (slot === 0 && dy < 0) { focus(document.querySelector('.tab.on')); return; }
        // Yukarı-aşağı gidişler aynı sütunda kalır: sol (uygulamalar) ya da sağ (panel).
        var side = center(current).x > 740;
        var items = document.querySelectorAll('.f'), c = center(current), best = null, bestScore = Infinity, i, p, vx, vy, score;
        for (i = 0; i < items.length; i++) {
          if (items[i] === current || !visible(items[i])) { continue; }
          p = center(items[i]); vx = p.x - c.x; vy = p.y - c.y;
          if (dx && (vx * dx <= 4)) { continue; }
          if (dy && (vy * dy <= 4 || (p.x > 740) !== side)) { continue; }
          score = dx ? Math.abs(vx) + Math.abs(vy) * 2.5 : Math.abs(vy) + Math.abs(vx) * 0.6;
          if (score < bestScore) { bestScore = score; best = items[i]; }
        }
        focus(best);
      }

      function toast(message) {
        text($('toasttext'), message);
        $('toast').style.display = 'block';
        clearTimeout(toastTimer);
        toastTimer = setTimeout(function () { $('toast').style.display = 'none'; }, 4000);
      }

      function act(id) {
        var x = new XMLHttpRequest();
        x.open('GET', '/pano/act?id=' + encodeURIComponent(id) + '&t=' + new Date().getTime());
        x.send(null);
      }

      function openSheet(item) {
        setCat($('sheetcat'), item);
        text($('sheettitle'), item.title);
        text($('sheetsum'), item.sum || 'Bu haberin özeti yok.');
        $('sheet').style.display = 'block';
        sheetOpen = true;
      }

      function closeSheet() { $('sheet').style.display = 'none'; sheetOpen = false; }

      function activate() {
        if (!current) { return; }
        if (current.className.indexOf('item') >= 0) {
          var item = D.news[newsOffset + parseInt(current.id.charAt(1), 10)];
          if (item) { openSheet(item); }
          return;
        }
        var id = current.getAttribute('data-act');
        if (!id) { return; }
        toast(current.getAttribute('data-say') || '');
        act(id);
      }

      function setIdle(on) {
        idle = on;
        $('idle').style.display = on ? 'block' : 'none';
      }

      function key(name) {
        lastKey = new Date().getTime();
        if (idle) { setIdle(false); return; }   // ilk tuş yalnızca panoyu geri getirir
        if (sheetOpen) { if (name === 'ok' || name === 'back') { closeSheet(); } return; }
        if (name === 'left') { move(-1, 0); }
        else if (name === 'right') { move(1, 0); }
        else if (name === 'up') { move(0, -1); }
        else if (name === 'down') { move(0, 1); }
        else if (name === 'ok') { activate(); }
        else if (name === 'back') { act('close'); }
      }

      // MARK: Mac ile konuşma

      function load() {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
          if (x.readyState !== 4 || x.status !== 200) { return; }
          try {
            var d = JSON.parse(x.responseText);
            // Mac veriyi henüz toplamadıysa alanlar eksik gelebilir.
            D = { news: d.news || [], shorts: d.shorts || [], market: d.market || [], weather: d.weather || null,
                  live: d.live || null, tz: d.tz === undefined ? 180 : d.tz, city: d.city || '' };
            render();
          } catch (e) {}
        };
        x.open('GET', '/pano.json?t=' + new Date().getTime());
        x.send(null);
      }

      function poll() {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
          if (x.readyState !== 4 || leaving) { return; }
          if (x.status !== 200) { setTimeout(poll, 1000); return; }
          try {
            var s = JSON.parse(x.responseText), i;
            skew = s.now - new Date().getTime();
            seq = s.seq;
            if (s.mode === 'close') { leaving = true; try { app.destroyApplication(); } catch (e) {} return; }
            if (s.mode !== 'dashboard') { leaving = true; location.href = '/'; return; }
            if (s.data !== dataVersion) { dataVersion = s.data; load(); }
            for (i = 0; i < s.keys.length; i++) { key(s.keys[i]); }
          } catch (e) {}
          setTimeout(poll, 20);
        };
        x.open('GET', '/pano/poll?seq=' + seq + '&data=' + dataVersion + '&t=' + new Date().getTime());
        x.send(null);
      }

      // Geliştirme sırasında masaüstü tarayıcıda klavyeyle denemek için.
      document.onkeydown = function (e) {
        var names = { 37: 'left', 38: 'up', 39: 'right', 40: 'down', 13: 'ok', 8: 'back', 27: 'back' };
        if (names[e.keyCode]) { key(names[e.keyCode]); if (e.preventDefault) { e.preventDefault(); } }
      };

      setInterval(function () {
        renderClock();
        if (!idle && !sheetOpen && new Date().getTime() - lastKey > IDLE_AFTER) { setIdle(true); }
      }, 1000);
      setInterval(function () { idleIndex++; renderIdle(); if (!idle) { renderNews(); } }, 20000);

      focus(document.querySelector('.netflix'));
      renderClock();
      poll();
    //]]></script>
    </body>
    </html>
    """#
}

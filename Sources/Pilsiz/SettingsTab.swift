import AppKit
import SwiftUI

struct SettingsTab: View {
    @Environment(TVController.self) private var tv
    @State private var customCode = ""
    @AppStorage("menuBarStyle") private var menuBarStyle = MenuBarStyle.channel.rawValue

    var body: some View {
        @Bindable var tv = tv
        VStack(spacing: 10) {
            Card("TV menüleri", icon: "slider.horizontal.3") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                    menuButton("gearshape", "Ayarlar", 1067)
                    menuButton("bolt", "Hızlı menü", 1043)
                    menuButton("aspectratio", "Görüntü oranı", 1011)
                    menuButton("moon.zzz", "Uyku zamanlayıcı", 1042)
                    menuButton("captions.bubble", "Altyazı", 1031)
                    menuButton("waveform", "Ses dili", 1015)
                }
                Text("Parlaklık, kontrast gibi değerler bu TV'de henüz ağdan okunup yazılamıyor; bu tuşlar TV'nin kendi menüsünü açar.")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Card("Menü çubuğu", icon: "menubar.rectangle") {
                Picker("Simgenin yanında", selection: $menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            ShortcutsCard()
            PanoSettingsCard()

            Card("Bağlantı", icon: "wifi") {
                field("TV adı") { TextField("Salon", text: $tv.name).textFieldStyle(.roundedBorder) }
                field("IP adresi") {
                    HStack {
                        TextField("192.168.1.x", text: $tv.host).textFieldStyle(.roundedBorder)
                        Button {
                            Task { await tv.discover() }
                        } label: {
                            if tv.status == .searching { ProgressView().controlSize(.small) } else { Text("Ağda ara") }
                        }
                        .disabled(tv.status == .searching)
                    }
                }
                field("MAC (kapalıyken açmak için)") {
                    TextField("otomatik öğrenilir", text: $tv.mac)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                Text("TV'yi ağdan açabilmek için TV'de Ayarlar › Ağ › “Ağda Uyandırma” açık olmalı.")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Card("Girişler", icon: "cable.connector") {
                field("Kaynak menüsündeki sırayla, virgülle") {
                    TextField("TV, HDMI 1, HDMI 2", text: $tv.inputsText).textFieldStyle(.roundedBorder)
                }
            }

            Card("Gelişmiş", icon: "wrench.and.screwdriver") {
                field("Tuş kodu dene") {
                    HStack {
                        TextField("ör. 1046", text: $customCode)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(sendCustom)
                        Button("Gönder", action: sendCustom).disabled(Int(customCode) == nil)
                    }
                }
                Toggle("Oturum açılışında başlat", isOn: $tv.launchAtLogin)
                    .font(.system(size: 12))
                Button("Uygulamadan çık") { NSApp.terminate(nil) }
            }
        }
    }

    private func sendCustom() {
        if let code = Int(customCode) { tv.send(code: code) }
    }

    private func menuButton(_ symbol: String, _ title: String, _ code: Int) -> some View {
        RemoteButton(symbol: symbol, title: title, height: 34) { tv.send(code: code) }
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
            content()
        }
    }
}

/// Panodaki hava durumunun şehri ve haberlerin kaynağı.
private struct PanoSettingsCard: View {
    @Environment(TVController.self) private var tv
    @State private var query = ""
    @State private var searching = false
    @State private var notFound = false
    @State private var customFeed = ""
    @State private var wantsCustom = false

    private var pano: Dashboard { tv.dashboard }
    private var isCustom: Bool { !NewsSource.presets.contains { $0.url == pano.newsFeed } }

    var body: some View {
        Card("Pano", icon: "square.grid.2x2") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hava durumu şehri").font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    TextField(pano.city.name, text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(findCity)
                    Button(action: findCity) {
                        if searching { ProgressView().controlSize(.small) } else { Text("Bul") }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                }
                Text(notFound ? "“\(query)” bulunamadı. Şehrin adını kontrol et." : "Şu an: \(pano.city.name)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(notFound ? Theme.accent : .secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Haber kaynağı").font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("Haber kaynağı", selection: Binding(
                    get: { isCustom || wantsCustom ? nil : pano.newsFeed },
                    set: { url in
                        wantsCustom = url == nil
                        if let url { pano.newsFeed = url } else if isCustom { customFeed = pano.newsFeed.absoluteString }
                    }
                )) {
                    ForEach(NewsSource.presets, id: \.url) { Text($0.name).tag(Optional($0.url)) }
                    Divider()
                    Text("Başka bir RSS adresi").tag(URL?.none)
                }
                .labelsHidden()
                if isCustom || wantsCustom {
                    TextField("https://…/rss", text: $customFeed)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if let url = URL(string: customFeed.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true {
                                pano.newsFeed = url
                            }
                        }
                    Text("RSS adresini yazıp Enter'a bas.").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { if isCustom { customFeed = pano.newsFeed.absoluteString } }
    }

    private func findCity() {
        let name = query.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        searching = true
        notFound = false
        Task {
            if let city = await Dashboard.findCity(name) {
                pano.city = city
                query = ""
            } else {
                notFound = true
            }
            searching = false
        }
    }
}

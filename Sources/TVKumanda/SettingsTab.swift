import AppKit
import SwiftUI

struct SettingsTab: View {
    @Environment(TVController.self) private var tv
    @State private var customCode = ""

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

import AppKit
import SwiftUI

/// Panoyu trackpad ile gezdiren alan: iki parmakla kaydırmak odağı o yöne taşır;
/// iki parmakla dokunmak ya da tıklamak seçer.
struct PanoTouchpad: NSViewRepresentable {
    let onKey: (RemoteKey) -> Void

    func makeNSView(context: Context) -> SwipeView {
        let view = SwipeView()
        view.onKey = onKey
        return view
    }

    func updateNSView(_ view: SwipeView, context: Context) {
        view.onKey = onKey
    }

    final class SwipeView: NSView {
        var onKey: ((RemoteKey) -> Void)?
        /// Bir adım için gereken kaydırma (punto). Uzun bir kaydırma birden çok adım atar.
        private let step: CGFloat = 45
        private var travelX: CGFloat = 0
        private var travelY: CGFloat = 0
        // İki parmakla dokunma: parmakların konduğu an ve o andan beri kaydırılan toplam yol.
        private var tapStart: TimeInterval?
        private var tapTravel: CGFloat = 0
        private var lastSelect: TimeInterval = 0

        override init(frame: NSRect) {
            super.init(frame: frame)
            // Trackpad'e değen parmakları tıklama olmadan da görebilmek için.
            allowedTouchTypes = [.indirect]
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmıyor") }

        // Klavye odağı panelde kalır ki ok tuşları çalışmaya devam etsin; kaydırma olayları imlecin altındaki görünüme gelir.
        override var acceptsFirstResponder: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        // Boş bırakılmazsa tıklama üst görünümlere geçer ve mouseUp buraya ulaşmaz.
        override func mouseDown(with event: NSEvent) {}
        override func rightMouseDown(with event: NSEvent) {}

        override func scrollWheel(with event: NSEvent) {
            // Parmaklar kalktıktan sonra süren "momentum" olayları sayılmaz; yoksa odak kendiliğinden kayar.
            guard event.momentumPhase.isEmpty else { return }
            if event.phase.contains(.began) { travelX = 0; travelY = 0 }
            // Odak parmağın gittiği yöne gitmeli: "doğal kaydırma" kapalıysa deltalar ters gelir.
            let direction: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            guard event.hasPreciseScrollingDeltas else {
                // Fare tekerleği: her tık bir adım.
                if event.scrollingDeltaY != 0 { onKey?(event.scrollingDeltaY * direction > 0 ? .down : .up) }
                else if event.scrollingDeltaX != 0 { onKey?(event.scrollingDeltaX * direction > 0 ? .right : .left) }
                return
            }
            travelX += event.scrollingDeltaX * direction
            travelY += event.scrollingDeltaY * direction
            tapTravel += abs(event.scrollingDeltaX) + abs(event.scrollingDeltaY)
            // Baskın eksen adım atar; öteki eksendeki küçük sapma sıfırlanır ki çapraz kaymasın.
            if abs(travelX) >= step, abs(travelX) >= abs(travelY) {
                onKey?(travelX > 0 ? .right : .left)
                travelX -= travelX > 0 ? step : -step
                travelY = 0
            } else if abs(travelY) >= step {
                onKey?(travelY > 0 ? .down : .up)
                travelY -= travelY > 0 ? step : -step
                travelX = 0
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) { travelX = 0; travelY = 0 }
        }

        // MARK: seçme

        override func touchesBegan(with event: NSEvent) {
            let count = event.touches(matching: .touching, in: self).count
            if count == 2 {
                tapStart = event.timestamp
                tapTravel = 0
            } else if count > 2 {
                tapStart = nil
            }
        }

        override func touchesEnded(with event: NSEvent) {
            guard event.touches(matching: .touching, in: self).isEmpty, let start = tapStart else { return }
            tapStart = nil
            // Kısa süren ve kaydırmaya dönüşmeyen iki parmak teması dokunmadır.
            if event.timestamp - start < 0.35, tapTravel < 12 { select(at: event.timestamp) }
        }

        override func touchesCancelled(with event: NSEvent) { tapStart = nil }

        override func mouseUp(with event: NSEvent) {
            if bounds.contains(convert(event.locationInWindow, from: nil)) { select(at: event.timestamp) }
        }

        /// Sistem ayarında "iki parmakla dokun: ikincil tıklama" açıksa aynı dokunma buraya da gelir.
        override func rightMouseUp(with event: NSEvent) { select(at: event.timestamp) }

        /// Aynı dokunma hem temas hem tıklama olarak gelebildiği için kısa aralıkla ikinci kez seçilmez.
        private func select(at time: TimeInterval) {
            guard time - lastSelect > 0.4 else { return }
            lastSelect = time
            onKey?(.ok)
        }
    }
}

// Të dhënat e Live Activity (Dynamic Island + ekrani i kyçur), të përbashkëta mes app-it dhe widget-it.
// Ky skedar kompilohet në dy target-e: ScienceQuest (app) dhe BrainSparkWidgets (extension).
#if os(iOS)
import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct BrainSparkActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// P.sh. «Fizikë» ose «Fokus».
        var title: String
        /// P.sh. «7A · salla 12» ose «Mëso pa shpërqendrime».
        var subtitle: String
        var start: Date
        var end: Date
        /// Emri i ikonës SF Symbols.
        var symbol: String
        /// 0 = lëndë e panjohur; 1 matematikë, 2 fizikë, 3 kimi, 4 biologji, 5 fokus.
        var colorIndex: Int
    }
    /// "class" (ora e mësimit) ose "focus" (kohëmatësi i studimit).
    var kind: String
}
#endif

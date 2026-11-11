import Foundation
import LocalAuthentication

/// Hapja e app-it me Face ID / Touch ID (ose kodin e pajisjes). Nuk zëvendëson hyrjen në server:
/// mbron seancën e ruajtur në këtë pajisje, që nxënësi të mos shkruajë fjalëkalim dhe kod sa herë hap app-in.
enum BiometricGate {
    static let enabledKey = "biometricLock.v1"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// "Face ID", "Touch ID", "Optic ID" ose nil kur pajisja s'ka biometri.
    static var kindName: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default:
            if #available(iOS 17.0, macOS 14.0, *), context.biometryType == .opticID { return "Optic ID" }
            return nil
        }
    }

    /// true kur përdoruesi u verifikua (biometri ose, si rezervë, kodi/fjalëkalimi i pajisjes).
    static func unlock(reason: String = "Hap BrainSpark") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Anulo"
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

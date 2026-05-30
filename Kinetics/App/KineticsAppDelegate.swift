import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

// MARK: - KineticsAppDelegate

/// `UIApplicationDelegate` adapter wired in via `@UIApplicationDelegateAdaptor`.
///
/// Responsibilities:
/// - Register the device with APNs at launch.
/// - Hand the APNs device token to Firebase Messaging so server-side pushes
///   reach the device through FCM.
/// - Persist the FCM token on the user's Firestore profile so a future Cloud
///   Function (or any backend) can target this user with push notifications.
/// - Bridge `MessagingDelegate` token refreshes back to Firestore.
///
/// Firebase configuration itself happens earlier in `KineticsApp.init()` —
/// we don't re-init it here, we just attach the delegates.
final class KineticsAppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate {

    // MARK: - UIApplicationDelegate

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Hook Firebase Messaging into the APNs flow only when Firebase is configured.
        if FirebaseApp.app() != nil {
            Messaging.messaging().delegate = self
        }
        // Always ask UIKit for an APNs token. Whether the user has granted
        // notification permissions is asked separately via NotificationService —
        // requesting the token early ensures it is available the moment the user
        // grants permission.
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Pass the raw APNs token to Firebase Messaging — FCM uses it to
        // derive the per-app token used for server-side targeting.
        guard FirebaseApp.app() != nil else { return }
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Best-effort logging only — push is an enhancement, not a critical path.
        #if DEBUG
        print("[Kinetics] APNs registration failed: \(error.localizedDescription)")
        #endif
    }

    // MARK: - MessagingDelegate

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard
            let fcmToken,
            FirebaseApp.app() != nil,
            let uid = Auth.auth().currentUser?.uid
        else { return }

        // Persist the FCM token at users/{uid}/devices/{token} so push targeting
        // by user works without juggling individual device IDs in app code.
        let payload: [String: Any] = [
            "fcmToken": fcmToken,
            "platform": "iOS",
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            "updatedAt": FieldValue.serverTimestamp()
        ]

        Firestore.firestore()
            .collection("users").document(uid)
            .collection("devices").document(fcmToken)
            .setData(payload, merge: true) { _ in
                // Fire-and-forget; ignore errors so token refresh churn is silent.
            }
    }
}

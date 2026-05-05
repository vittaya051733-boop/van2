import Flutter
import GoogleMaps
import UserNotifications
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  private let callIntentChannelName = "van.merchant/call_intents"
  private let callIntentMethod = "incoming_call_intent"
  private let drainPendingMethod = "drain_pending_intents"

  private var callIntentChannel: FlutterMethodChannel?
  private var pendingCallPayloads: [[String: Any]] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("AIzaSyABo43mqmfEuAQJ4CKnzl6dePIIoGyyGsU")
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: callIntentChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result([])
          return
        }
        if call.method == self.drainPendingMethod {
          let snapshot = self.pendingCallPayloads
          self.pendingCallPayloads.removeAll()
          result(snapshot)
          return
        }
        result(FlutterMethodNotImplemented)
      }
      callIntentChannel = channel
    }

    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()

    if let launchNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      enqueueCallPayload(from: launchNotification)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    enqueueCallPayload(from: notification.request.content.userInfo)
    completionHandler([.banner, .badge, .sound])
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    enqueueCallPayload(from: response.notification.request.content.userInfo)
    completionHandler()
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    enqueueCallPayload(from: userInfo)
    super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
  }

  private func enqueueCallPayload(from userInfo: [AnyHashable: Any]) {
    let normalized = userInfo.reduce(into: [String: Any]()) { partialResult, element in
      partialResult[String(describing: element.key)] = element.value
    }

    let callType = (normalized["type"] as? String)?.lowercased()
    if callType == "call_cancel" {
      guard let channelId = normalized["channelId"] as? String, !channelId.isEmpty else {
        return
      }
      deliverCallIntent([
        "channelId": channelId,
        "cancelOnly": true,
      ])
      return
    }

    guard callType == "call" else {
      return
    }

    guard
      let channelId = normalized["channelId"] as? String,
      let token = normalized["token"] as? String,
      !channelId.isEmpty,
      !token.isEmpty
    else {
      return
    }

    let callIntentPayload: [String: Any] = [
      "channelId": channelId,
      "token": token,
      "callerId": normalized["callerId"] ?? normalized["caller_id"] ?? "",
      "callerName": normalized["callerName"] ?? "ผู้โทร",
      "callerPhotoUrl": normalized["callerPhotoUrl"] ?? "",
      "isVideo": parseVideoFlag(from: normalized),
      "appWasForeground": UIApplication.shared.applicationState == .active,
    ]
    deliverCallIntent(callIntentPayload)
  }

  private func parseVideoFlag(from payload: [String: Any]) -> Bool {
    if let boolValue = payload["isVideo"] as? Bool {
      return boolValue
    }
    if let stringValue = payload["isVideo"] as? String {
      return stringValue.lowercased() == "true"
    }
    if let callType = payload["callType"] as? String {
      return callType.lowercased() == "video"
    }
    return false
  }

  private func deliverCallIntent(_ payload: [String: Any]) {
    if let channel = callIntentChannel {
      channel.invokeMethod(callIntentMethod, arguments: payload)
    } else {
      pendingCallPayloads.append(payload)
    }
  }
}

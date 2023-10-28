//
//  RemindersApp.swift
//  Reminders
//
//  Created by jacob lee on 10/14/23.
//

import SwiftUI
import UserNotifications

//class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
//    
//    var appState: AppState
//    
//    init(appState: AppState) {
//        self.appState = appState
//    }
//    
//    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
//        if let reminderIDString = response.notification.request.content.userInfo["reminderID"] as? String,
//           let reminderID = UUID(uuidString: reminderIDString) {
//            appState.selectedReminderID = reminderID
//        }
//
//        completionHandler()
//    }
//}

class AppState: ObservableObject {
    @Published var selectedReminderID: UUID?
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onNotificationReceived: ((UUID) -> Void)?
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let reminderID = response.notification.request.content.userInfo["reminderID"] as? String, let uuid = UUID(uuidString: reminderID) {
            print("Notification received with reminderID: \(reminderID)")
            onNotificationReceived?(uuid)
        }
        completionHandler()
    }
}

@main
struct RemindersApp: App {
    
    @StateObject var appState = AppState()
    
    lazy var notificationDelegate: NotificationDelegate = {
        let delegate = NotificationDelegate()
        delegate.onNotificationReceived = { [weak appState] uuid in
            print("Updating AppState with selectedReminderID: \(uuid.uuidString)")
            appState?.selectedReminderID = uuid
        }
        return delegate
    }()
    
    init() {
        UNUserNotificationCenter.current().delegate = self.notificationDelegate
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}


func requestNotificationPermission() {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
        if granted {
            print("Notification permission granted!")
        } else {
            print("Notification permission denied.")
            if let error = error {
                print("Error: \(error)")
            }
        }
    }
}

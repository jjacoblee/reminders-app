//
//  RemindersApp.swift
//  Reminders
//
//  Created by jacob lee on 10/14/23.
//

import SwiftUI
import UserNotifications


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

@main
struct RemindersApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView().onAppear(perform: requestNotificationPermission)
        }
    }
}

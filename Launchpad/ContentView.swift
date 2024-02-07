import SwiftUI
import PushKit

struct ContentView: View {
    @AppStorage("last_registered") var lastRegistered: Double?
    @EnvironmentObject var delegateStateBridge: DelegateStateBridge
    @EnvironmentObject var historyStore: NotificationHistoryStore
    @State private var isAlertPresented = false
    @State private var isNotificationPermissionAlertPresented = false
    @State private var notificationHistorySubtext: String?
    @State private var attemptedFetch = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("APNS"), footer: Text("The APNs token can be used to send notifications to your device. Make sure to keep it secret, as it can't be regenerated.")) {
                    LabeledContent {
                        VStack(alignment: .trailing) {
                            Text(delegateStateBridge.isRegisteredWithAPNS ? "Registered" : "Unregistered")
                        }
                    } label: {
                        Text("APNs State")
                    }
                    if let lastRegistered {
                        if delegateStateBridge.isRegisteredWithAPNS {
                            LabeledContent {
                                HStack(spacing: 4) {
                                    Text(Date(timeIntervalSince1970: lastRegistered).formatted(date: .numeric, time: .omitted))
                                    Text(Date(timeIntervalSince1970: lastRegistered).formatted(date: .omitted, time: .shortened))
                                }
                            } label: {
                                Text("Registration Date")
                            }
                        }
                    }
                    Button(action: {
                        let center = UNUserNotificationCenter.current()
                        Task {
                            do {
                                try await center.requestAuthorization(options: [.alert, .sound, .badge])
                                let settings = await center.notificationSettings()
                                
                                if (settings.authorizationStatus == .authorized) {
                                    UIApplication.shared.registerForRemoteNotifications()
                                }
                                else {
                                    isNotificationPermissionAlertPresented = true
                                }
                            }
                           catch {
                               NSLog("Failed to request notification permission")
                           }
                        }
                    }) {
                        Text(delegateStateBridge.isRegisteredWithAPNS ? "Re-register with APNs" : "Request APNs Registration")
                    }
                    ShareLink(item: UserDefaults.standard.string(forKey: "apns_token") ?? "No value provided") {
                        Text("Export APNs Token")
                    }
                    .disabled(!delegateStateBridge.isRegisteredWithAPNS)
                }
                Section(header: Text("Notifications")) {
                    if attemptedFetch {
                        NavigationLink(destination: NotificationHistoryView()) {
                            VStack(alignment: .leading) {
                                Text("Notification History")
                                if let notificationHistorySubtext {
                                    Text(notificationHistorySubtext)
                                        .foregroundStyle(.gray)
                                        .font(.caption)
                                }
                            }
                        }
                        .disabled(historyStore.history.isEmpty)
                    }
                    else {
                        HStack {
                            Text("Notification History")
                            Spacer()
                            ProgressView()
                        }
                    }
                }
            }
            .navigationTitle("Launchpad")
            .onChange(of: delegateStateBridge.didRegistrationSucceed) { _, newValue in
                NSLog("onChange listener notified of change, got value of \(newValue?.description ?? "nil")")
                isAlertPresented = newValue == false
            }
            .alert(isPresented: $isAlertPresented) {
                Alert(title: Text("Failed to Register with APNs"), message: Text("An error occured while trying to register with APNs. Give it another shot, or try again later."))
            }
            .alert(isPresented: $isNotificationPermissionAlertPresented) {
                Alert(
                    title: Text("Notifications Disabled"),
                    message: Text("We can't register with APNs until you grant the notification permission in Settings. Please enable the permission in order to continue."),
                    primaryButton: .default(Text("Open Settings")) {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    },
                    secondaryButton: .cancel()
                )
            }
            .onAppear {
                if (ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        withAnimation {
                            historyStore.history = NotificationMetadata.sampleData
                            let relativeFormatter = RelativeDateTimeFormatter()
                            notificationHistorySubtext = "Last notification posted \(relativeFormatter.localizedString(for: historyStore.history[0].posted, relativeTo: .now))"
                            
                            attemptedFetch = true
                        }
                    }
                    
                    return
                }
                
                Task {
                    let after = historyStore.history.isEmpty ? nil : historyStore.history[0].posted.timeIntervalSince1970
                    let historyData = try? await fetchNotificationHistory(after: after)
                    guard let historyData else {
                        DispatchQueue.main.async {
                            notificationHistorySubtext = "Unable to get notification history"
                            withAnimation {
                                attemptedFetch = true
                            }
                        }
                        return
                    }
                    
                    let history = try? JSONDecoder().decode([NotificationMetadata].self, from: historyData)
                    guard let history else {
                        DispatchQueue.main.async {
                            notificationHistorySubtext = "Unable to get notification history"
                            withAnimation {
                                attemptedFetch = true
                            }
                        }
                        return
                    }
                    
                    if history.isEmpty {
                        notificationHistorySubtext = "No notifications posted yet"
                    }
                    else {
                        notificationHistorySubtext = "Last notification posted \(RelativeDateTimeFormatter().localizedString(for: history[0].posted, relativeTo: .now))"
                        
                        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                            DispatchQueue.main.async {
                                let relativeFormatter = RelativeDateTimeFormatter()
                                notificationHistorySubtext = "Last notification posted \(relativeFormatter.localizedString(for: history[0].posted, relativeTo: .now))"
                            }
                        }
                    }
                    
                    withAnimation {
                        attemptedFetch = true
                        historyStore.history = history
                    }
                    
                    historyStore.write()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(NotificationHistoryStore())
        .environmentObject(DelegateStateBridge(isRegisteredWithAPNS: false))
        .onAppear {
            UserDefaults.standard.setValue(15700000, forKey: "last_registered")
        }
}

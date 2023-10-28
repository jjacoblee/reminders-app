import SwiftUI
import UserNotifications


struct TimeConstants {
    static let secondsInAMinute: TimeInterval = 60
    static let secondsInAnHour: TimeInterval = 60 * secondsInAMinute
    static let secondsInADay: TimeInterval = 24 * secondsInAnHour
    static let secondsInAWeek: TimeInterval = 7 * secondsInADay
}

enum DayOfWeek: Int, CaseIterable, Identifiable, Codable {
    case Sun = 1, Mon, Tue, Wed, Thu, Fri, Sat
    
    var id: Int { self.rawValue }
    
    var shortName: String {
        switch self {
        case .Sun: return "Sun"
        case .Mon: return "Mon"
        case .Tue: return "Tue"
        case .Wed: return "Wed"
        case .Thu: return "Thu"
        case .Fri: return "Fri"
        case .Sat: return "Sat"
        }
    }
    
    // Custom encoder
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    
    // Custom decoder
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        guard let value = DayOfWeek(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid DayOfWeek rawValue")
        }
        self = value
    }
}

enum RepeatUnit: String, CaseIterable, Identifiable, Codable {
    case sec = "sec"
    case min = "min"
    case hour = "hour"
    case day = "day"
    case week = "week"
    
    var id: String { self.rawValue }
    
    // If you want to convert the unit to seconds for calculations
    var seconds: TimeInterval {
        switch self {
        case .sec:
            return 1
        case .min:
            return TimeConstants.secondsInAMinute
        case .hour:
            return TimeConstants.secondsInAnHour
        case .day:
            return TimeConstants.secondsInADay
        case .week:
            return TimeConstants.secondsInAWeek
        }
    }
    
}

struct Task: Identifiable, Codable {
    var id = UUID()
    var name: String
    var isCompleted: Bool
}

struct Reminder: Identifiable, Codable { // Make Reminder Codable
    var id = UUID()
    var title: String
    var startTime: Date
    var endTime: Date?
    var repeatEvery: String
    var repeatUnit: RepeatUnit
    var repeatDays: [DayOfWeek]
    var active: Bool
    var tasks: [Task] = []
    
    var countdown: TimeInterval = 0
}


class ReminderData: ObservableObject {
    @Published var reminders: [Reminder] = []
    var timers: [UUID: Timer] = [:]
    
    init() {
        loadReminders()
    }
    
    func loadReminders() {
        if let remindersData = UserDefaults.standard.data(forKey: "reminders"),
           let decodedReminders = try? JSONDecoder().decode([Reminder].self, from: remindersData) {
            reminders = decodedReminders
        }
    }
    
    func deleteReminder(at offsets: IndexSet) {
        reminders.remove(atOffsets: offsets)
        saveReminders()
    }
    
    func saveReminders() {
        let center = UNUserNotificationCenter.current()
        
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                self.requestNotificationPermission(completion: {
                    // Continue setting the reminder after permission is requested
                    self.completeReminderSave()
                })
            case .authorized, .provisional:
                // Permission was already granted. Continue setting the reminder.
                self.completeReminderSave()
            default:
                // Permission denied or restricted. Handle accordingly.
                print("Notification permission denied or restricted.")
            }
        }
    }
    
    func requestNotificationPermission(completion: @escaping () -> Void) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("Notification permission granted!")
                DispatchQueue.main.async {
                    completion()
                }
            } else {
                print("Notification permission denied.")
                if let error = error {
                    print("Error: \(error)")
                }
            }
        }
    }
    
    func completeReminderSave() {
        if let encoded = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(encoded, forKey: "reminders")
        }
    }
    
    
    func startCountdowns(for reminder: Reminder? = nil) {
        let calendar = Calendar.current
        let remindersToProcess = reminder != nil ? [reminder!] : reminders
        
        for reminder in remindersToProcess where reminder.active && timers[reminder.id] == nil {
            let dayOfWeek = calendar.component(.weekday, from: Date()) // 1 = Sunday, 7 = Saturday
            
            if !reminder.repeatDays.isEmpty && !reminder.repeatDays.contains(where: { $0.rawValue == dayOfWeek }) {
                continue
            }
            
            let current = Date()
            let start = combineDateAndTime(date: Date(), time: reminder.startTime)
            
            if let end = reminder.endTime, current > end {
                continue
            }
            
            let repeatInSeconds = convertRepeatToSeconds(repeatEvery: reminder.repeatEvery, repeatUnit: reminder.repeatUnit)
            
            // Calculate the initial countdown based on the startTime
            let timeUntilStart = start.timeIntervalSince(current)
            let countdownValue = max(0, timeUntilStart)
            
            // Initialize the countdown value when starting the timer
            if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
                reminders[index].countdown = countdownValue > 0 ? countdownValue : repeatInSeconds
            }
            
            timers[reminder.id] = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                
                if let index = self.reminders.firstIndex(where: { $0.id == reminder.id }) {
                    // Reduce the countdown
                    var updatedReminder = self.reminders[index]
                    updatedReminder.countdown -= 1.0
                    
                    if updatedReminder.countdown <= 0 {
                        self.scheduleNotification(for: reminder)
                        updatedReminder.countdown = repeatInSeconds
                        
                    }
                    
                    self.reminders[index] = updatedReminder
                    
                    if let end = reminder.endTime, Date() > end {
                        self.timers[reminder.id]?.invalidate()
                        self.timers.removeValue(forKey: reminder.id)
                    }
                }
            }
        }
    }
    
    
    
    func stopCountdowns() {
        for timer in timers.values {
            timer.invalidate()
        }
        timers.removeAll()
    }
    
    func scheduleNotification(for reminder: Reminder) {
        let content = UNMutableNotificationContent()
        content.title = "Reminder Alert!"
        content.body = reminder.title
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        let request = UNNotificationRequest(identifier: reminder.id.uuidString, content: content, trigger: trigger)
        
        let center = UNUserNotificationCenter.current()
        center.add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            } else {
                print("Notification scheduled!")
            }
        }
    }
    
    
    private func combineDateAndTime(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        return calendar.date(bySettingHour: timeComponents.hour!, minute: timeComponents.minute!, second: timeComponents.second!, of: date)!
    }
    
    private func convertRepeatToSeconds(repeatEvery: String, repeatUnit: RepeatUnit) -> TimeInterval {
        guard let value = Int(repeatEvery) else { return 0 }
        return TimeInterval(value) * repeatUnit.seconds
    }
    
}

extension TimeInterval {
    func formattedCountdown() -> String {
        let weeks = Int(self) / (3600 * 24 * 7)
        let days = (Int(self) % (3600 * 24 * 7)) / (3600 * 24)
        let hours = (Int(self) % (3600 * 24)) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60
        
        if weeks > 0 {
            return "\(weeks)w \(days)d \(hours)h \(minutes)m \(seconds)s"
        } else if days > 0 {
            return "\(days)d \(hours)h \(minutes)m \(seconds)s"
        } else {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
    }
}


// ReminderView
struct ReminderView: View {
    @Binding var selectedReminder: Reminder?
    @Binding var isModalPresented: Bool  // Add this line
    @ObservedObject var reminderData: ReminderData
    var reminder: Reminder
    @State private var areTasksVisible = false
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                // Chevron Button
                Button(action: {
                    areTasksVisible.toggle()
                }) {
                    Image(systemName: areTasksVisible ? "chevron.down" : "chevron.right")
                        .font(.title2) // Increase font size to make it more pronounced
                        .padding(.trailing, 8) // Add spacing to the right
                }
                
                Text(reminder.title)
                    .onTapGesture {
                        self.selectedReminder = reminder
                        self.isModalPresented = true
                    }
                Spacer()
                
                // Countdown Text
                Text(reminder.countdown.formattedCountdown())
                    .foregroundColor(.gray)
                    .font(.callout)
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { reminder.active },
                    set: { newValue in
                        if let index = reminderData.reminders.firstIndex(where: { $0.id == reminder.id }) {
                            reminderData.reminders[index].active = newValue
                            if newValue {
                                self.reminderData.startCountdowns()
                            }
                            else {
                                self.reminderData.stopCountdowns()
                            }
                        }
                    }
                ))
                .labelsHidden()
                .contentShape(Rectangle())
            }
            
            if areTasksVisible {
                ForEach(reminder.tasks) { task in
                    HStack {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .onTapGesture {
                                // Toggle task completion logic
                                // Note: This might require moving tasks from the Reminder model to an @State or @Binding property for mutability
                            }
                        Text(task.name)
                    }
                }
            }
        }
    }
}



struct ContentView: View {
    
    @State private var isModalPresented = false
    @State private var selectedReminder: Reminder? = nil
    
    @ObservedObject private var reminderData = ReminderData() // Use the ReminderData object
    
    init(isModalPresented: Bool = false, selectedReminder: Reminder? = nil, reminderData: ReminderData = ReminderData()) {
        self.isModalPresented = isModalPresented
        self.selectedReminder = selectedReminder
        self.reminderData = reminderData
        
        
    }
    
    var body: some View {
        NavigationView {
            VStack {
                
                List {
                    ForEach(reminderData.reminders) { reminder in
                        ReminderView(selectedReminder: self.$selectedReminder,
                                     isModalPresented: self.$isModalPresented,  // Pass the Binding to ReminderView
                                     reminderData: self.reminderData,
                                     reminder: reminder)
                    }
                    .onDelete(perform: reminderData.deleteReminder)
                }
                .navigationBarTitle("Reminders")
                .sheet(isPresented: $isModalPresented, onDismiss: {
                    selectedReminder = nil // Reset the selected reminder when the modal is dismissed
                }) {
                    ModalView(isModalPresented: self.$isModalPresented, reminderData: self.reminderData, reminderToEdit: self.selectedReminder)
                }
                
                
                Button(action: {
                    // Show the modal when the button is tapped
                    self.isModalPresented.toggle()
                }) {
                    HStack {
                        Image(systemName: "plus")
                            .foregroundColor(.white)
                        Text("Add New")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                    }
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }
            }
            .onAppear {
                // Load reminders when the ContentView appears
                self.reminderData.loadReminders()
                self.reminderData.startCountdowns()
            }
        }
    }
}

struct ModalView: View {
    
    @Binding var isModalPresented: Bool
    @ObservedObject var reminderData: ReminderData // Use the ReminderData object
    
    var reminderToEdit: Reminder?
    
    
    // Reminder fields
    @State private var name = "New Event"
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var selectedRepeatOption:RepeatUnit = .hour
    @State private var isRepeatDaysOn = false
    @State private var selectedRepeatDays: [DayOfWeek] = []
    @State private var isEndTimeEnabled = false
    @State private var repeatEvery = "1"
    @State private var taskName = ""
    @State private var tasks: [Task] = []
    
    
    let repeatOptions = RepeatUnit.allCases
    let abbreviatedDaysOfWeek = DayOfWeek.allCases
    
    
    var body: some View {
        
        NavigationView {
            
            ScrollView{
                VStack {
                    VStack(spacing: 20) {
                        // Name
                        VStack(alignment: .leading) {
                            Text("Event Name:")
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            HStack {
                                TextField("Name", text: $name)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .padding(.trailing, name.isEmpty ? 0 : 25) // Space for the X button
                                
                                if !name.isEmpty {
                                    Button(action: {
                                        name = ""
                                    }) {
                                        Image(systemName: "multiply.circle.fill")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 20, height: 20)
                                            .foregroundColor(Color.gray)
                                            .padding(.trailing, 10)
                                    }
                                }
                            }
                        }
                        
                        
                        
                        // Start Date and Time
                        DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                        
                        // End Date and Time
                        Toggle("End Time", isOn: $isEndTimeEnabled)
                        if isEndTimeEnabled {
                            DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                                .onChange(of: endTime, initial: false) { oldValue, newValue in
                                    if newValue <= startTime {
                                        // Set endTime to a value after startTime, e.g., 1 minute after
                                        endTime = startTime.addingTimeInterval(60)
                                    }
                                }
                            
                        }
                        
                        
                        // Repeat Cadence
                        VStack(spacing: 10) {
                            HStack {
                                Text("Repeat Every")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                TextField("", text: $repeatEvery)
                                    .keyboardType(.numberPad)
                                    .frame(width: 80)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                Spacer()  // Pushes the views to the left side of the screen
                            }
                            
                            Picker("Unit", selection: $selectedRepeatOption) {
                                ForEach(repeatOptions, id: \.self) { option in
                                    Text(option.rawValue)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        
                        // Repeat Days
                        Toggle("Repeat Days", isOn: $isRepeatDaysOn)
                        
                        if isRepeatDaysOn {
                            VStack {
                                List {
                                    ForEach(abbreviatedDaysOfWeek, id: \.self) { day in
                                        Toggle(day.shortName, isOn: Binding(
                                            get: {
                                                self.selectedRepeatDays.contains(day)
                                            },
                                            set: { newValue in
                                                if newValue {
                                                    self.selectedRepeatDays.append(day)
                                                } else {
                                                    if let index = self.selectedRepeatDays.firstIndex(of: day) {
                                                        self.selectedRepeatDays.remove(at: index)
                                                    }
                                                }
                                            }
                                        ))
                                    }
                                }
                                .background(Color(.systemBackground)) // Add a background color
                            }.frame(minHeight: 380)
                        }
                        
                        //Task List
                        VStack(alignment: .leading) {
                            Text("Task List")
                                .font(.body)
                                .padding(.bottom, 5)
                            
                            HStack {
                                TextField("Add task", text: $taskName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                Button(action: {
                                    let newTask = Task(name: taskName, isCompleted: false)
                                    tasks.append(newTask)
                                    taskName = ""
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            ScrollView {
                                ForEach(tasks) { task in
                                    HStack {
                                        Text(task.name)
                                        Spacer()
                                        Image(systemName: "pencil")
                                            .onTapGesture {
                                                taskName = task.name
                                                if let taskIndex = tasks.firstIndex(where: { $0.id == task.id }) {
                                                    tasks.remove(at: taskIndex)
                                                }
                                            }
                                        Image(systemName: "trash")
                                            .onTapGesture {
                                                if let taskIndex = tasks.firstIndex(where: { $0.id == task.id }) {
                                                    tasks.remove(at: taskIndex)
                                                }
                                            }
                                    }
                                    .padding()
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                    .padding(.horizontal)
                                }
                            }
                            
                        }
                        
                        
                        
                        Button(action: {
                            // Check if we are editing an existing reminder
                            if let reminder = reminderToEdit {
                                // Find the reminder in the array and update it
                                if let index = reminderData.reminders.firstIndex(where: { $0.id == reminder.id }) {
                                    reminderData.reminders[index].title = name
                                    reminderData.reminders[index].startTime = startTime
                                    reminderData.reminders[index].endTime = isEndTimeEnabled ? endTime : nil
                                    reminderData.reminders[index].repeatEvery =  repeatEvery
                                    reminderData.reminders[index].repeatUnit = selectedRepeatOption
                                    reminderData.reminders[index].repeatDays = isRepeatDaysOn ? selectedRepeatDays : []
                                    reminderData.reminders[index].tasks = tasks
                                }
                            } else {
                                // Save the reminder as a new entry
                                let newReminder = Reminder(
                                    title: name,
                                    startTime: startTime,
                                    endTime: isEndTimeEnabled ? endTime : nil,
                                    repeatEvery:  repeatEvery,
                                    repeatUnit: selectedRepeatOption,
                                    repeatDays: isRepeatDaysOn ? selectedRepeatDays : [],
                                    active: true,
                                    tasks: []
                                ) // Customize with user input
                                reminderData.reminders.append(newReminder)
                                reminderData.startCountdowns(for: newReminder )
                            }
                            reminderData.saveReminders()
                            
                            
                            // Dismiss the modal
                            self.isModalPresented.toggle()
                        }) {
                            Text("Submit")
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        
                    }
                    .padding()
                }
            }
            .navigationBarItems(trailing: Button(action: {
                // Dismiss the modal when the "X" button is tapped
                self.isModalPresented.toggle()
            }) {
                Image(systemName: "xmark")
                    .foregroundColor(.blue)
                    .font(.headline)
            })
            .navigationBarTitle("Event Details")
            .onAppear {
                // Load reminder details if we are editing an existing reminder
                if let reminder = reminderToEdit {
                    self.name = reminder.title
                    self.startTime = reminder.startTime
                    self.endTime = reminder.endTime ?? Date()
                    self.repeatEvery = reminder.repeatEvery
                    self.selectedRepeatOption = reminder.repeatUnit
                    self.selectedRepeatDays = reminder.repeatDays
                    self.isRepeatDaysOn = reminder.repeatDays.count > 0
                    self.isEndTimeEnabled = reminder.endTime != nil ? true : false
                    self.tasks = reminder.tasks
                }
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}




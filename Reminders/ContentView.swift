import SwiftUI

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

struct Reminder: Identifiable, Codable { // Make Reminder Codable
    var id = UUID()
    var title: String
    var startTime: Date
    var endTime: Date?
    var repeatEvery: String
    var repeatUnit: String
    var repeatDays: [DayOfWeek]
    var active: Bool
    
    var countdown: TimeInterval = 0
}


class ReminderData: ObservableObject {
    @Published var reminders: [Reminder] = []
    var timers: [UUID: Timer] = [:]
    
    init() {
        loadReminders()
    }
    
    func saveReminders() {
        if let encoded = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(encoded, forKey: "reminders")
        }
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
    
    func startCountdowns() {
        let calendar = Calendar.current

        for index in reminders.indices where reminders[index].active {
            let reminder = reminders[index]
            let dayOfWeek = calendar.component(.weekday, from: Date()) // 1 = Sunday, 7 = Saturday

            if !reminder.repeatDays.isEmpty && !reminder.repeatDays.contains(where: { $0.rawValue == dayOfWeek }) {
                continue
            }

            let current = Date()
            let start = combineDateAndTime(date: Date(), time: reminder.startTime)
            if let end = reminder.endTime, current > end {
                continue
            }
            if current < start {
                continue
            }

            let repeatInSeconds = convertRepeatToSeconds(repeatEvery: reminder.repeatEvery, repeatUnit: reminder.repeatUnit)

            // Initialize the countdown value when starting the timer
            reminders[index].countdown = repeatInSeconds

            timers[reminder.id]?.invalidate()
            timers[reminder.id] = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                // Reduce the countdown
                var updatedReminder = self.reminders[index]
                updatedReminder.countdown -= 1

                if updatedReminder.countdown <= 0 {
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

    
    func stopCountdowns() {
        for timer in timers.values {
            timer.invalidate()
        }
        timers.removeAll()
    }
    
    private func combineDateAndTime(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        return calendar.date(bySettingHour: timeComponents.hour!, minute: timeComponents.minute!, second: timeComponents.second!, of: date)!
    }
    
    private func convertRepeatToSeconds(repeatEvery: String, repeatUnit: String) -> TimeInterval {
        guard let value = Int(repeatEvery) else { return 0 }
        switch repeatUnit {
        case "sec":
            return TimeInterval(value)
        case "min":
            return TimeInterval(value * 60)
        case "hour":
            return TimeInterval(value * 3600)
        case "day":
            return TimeInterval(value * 3600 * 24)
        default:
            return 0
        }
    }
    
}

extension TimeInterval {
    func formattedCountdown() -> String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

struct ContentView: View {
    @State private var isModalPresented = false
    @State private var selectedReminder: Reminder? = nil

    @ObservedObject private var reminderData = ReminderData() // Use the ReminderData object

    
    var body: some View {
        NavigationView {
            VStack {
                
                List {
                    ForEach(reminderData.reminders) { reminder in
                        HStack {
                            Text(reminder.title)
                                .contentShape(Rectangle()) // Ensure tap only recognized on text
                                .onTapGesture {
                                    selectedReminder = reminder
                                    isModalPresented.toggle()
                                }
                            Spacer()
                            
                            // Countdown Text
                            Text(reminder.countdown.formattedCountdown())
                                .foregroundColor(.gray) // or any other color you prefer
                                .font(.callout)         // or any other font style you prefer
                            
                            Spacer() // Add additional spacing if you want more gap between countdown and toggle
                            
                            Toggle("", isOn: Binding(
                                get: { reminder.active },
                                set: { newValue in
                                    // Update the active status of the reminder
                                    if let index = reminderData.reminders.firstIndex(where: { $0.id == reminder.id }) {
                                        reminderData.reminders[index].active = newValue
                                        if newValue {
                                            self.reminderData.startCountdowns()
                                        }
                                        else{
                                            self.reminderData.stopCountdowns()
                                        }
                                    }
                                }
                            ))
                            .labelsHidden() // Hide the label of the toggle
                            .contentShape(Rectangle()) // Ensure tap only recognized on toggle
                        }
                    }
                    .onDelete(perform: reminderData.deleteReminder) // Adding the swipe to delete functionality
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
    @State private var selectedRepeatOption = "min"
    @State private var isRepeatDaysOn = false
    @State private var selectedRepeatDays: [DayOfWeek] = []
    @State private var isEndTimeEnabled = false
    @State private var repeatEvery = "1"
    
    let repeatOptions = ["sec", "min", "hour", "day", "week"]
    let abbreviatedDaysOfWeek = DayOfWeek.allCases
    
    
    var body: some View {
        
        NavigationView {
            
            ScrollView{
                VStack {
                    VStack(spacing: 20) {
                        // Name
                        TextField("Name", text: $name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        
                        // Start Date and Time
                        DatePicker("Start Time", selection: $startTime, in: Date()..., displayedComponents: .hourAndMinute)
                        
                        // End Date and Time
                        Toggle("End Time", isOn: $isEndTimeEnabled)
                        
                        if isEndTimeEnabled {
                            DatePicker("End Time", selection: $endTime, in: Date()..., displayedComponents: .hourAndMinute)
                        }
                        // Repeat Cadence
                        HStack {
                            Text("Repeat Every")
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            TextField("", text: $repeatEvery)
                                .keyboardType(.numberPad)
                                .frame(width: 80)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Picker("Unit", selection: $selectedRepeatOption) {
                                ForEach(repeatOptions, id: \.self) { option in
                                    Text(option)
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
                                    active: true
                                ) // Customize with user input
                                reminderData.reminders.append(newReminder)
                            }
                            reminderData.saveReminders()
                            reminderData.startCountdowns()

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
    
    
    

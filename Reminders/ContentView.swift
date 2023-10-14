import SwiftUI

struct Reminder: Identifiable, Codable { // Make Reminder Codable
    var id = UUID()
    var title: String
    var active: Bool
}

class ReminderData: ObservableObject {
    @Published var reminders: [Reminder] = []
    
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
                            Spacer() // Add spacing to push the toggle to the right
                            Toggle("", isOn: Binding(
                                get: { reminder.active },
                                set: { newValue in
                                    // Update the active status of the reminder
                                    if let index = reminderData.reminders.firstIndex(where: { $0.id == reminder.id }) {
                                        reminderData.reminders[index].active = newValue
                                    }
                                }
                            ))
                            .labelsHidden() // Hide the label of the toggle
                        }
                        .onTapGesture {
                            selectedReminder = reminder
                            isModalPresented.toggle()
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
            }
        }
    }
}
    
    struct ModalView: View {
        
        @Binding var isModalPresented: Bool
        @ObservedObject var reminderData: ReminderData // Use the ReminderData object
        
        var reminderToEdit: Reminder?
        
        
        // Reminder fields
        @State private var name = ""
        @State private var startDate = Date()
        @State private var startTime = Date()
        @State private var endDate = Date()
        @State private var endTime = Date()
        @State private var isRepeatOn = false
        @State private var selectedRepeatOption = "hour"
        @State private var isRepeatDaysOn = false
        @State private var selectedRepeatDays: [String] = []
        @State private var isEndDateAndTimeEnabled = false
        
        let repeatOptions = ["hour", "day", "week", "month", "year"]
        let abbreviatedDaysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        
        
        var body: some View {
            
            NavigationView {
                
                ScrollView{
                    VStack {
                        VStack(spacing: 20) {
                            // Name
                            TextField("Name", text: $name)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            
                            // Start Date and Time
                            DatePicker("Start Date", selection: $startDate, in: Date()..., displayedComponents: .date)
                            DatePicker("Start Time", selection: $startTime, in: Date()..., displayedComponents: .hourAndMinute)
                            
                            // End Date and Time
                            Toggle("End Date and Time", isOn: $isEndDateAndTimeEnabled)
                            
                            if isEndDateAndTimeEnabled {
                                DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: .date)
                                DatePicker("End Time", selection: $endTime, in: Date()..., displayedComponents: .hourAndMinute)
                            }
                            // Repeat
                            Toggle("Repeat Cadence", isOn: $isRepeatOn)
                            
                            if isRepeatOn {
                                Picker("Repeat Cadence", selection: $selectedRepeatOption) {
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
                                            Toggle(day, isOn: Binding(
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
                                        // Update other fields as necessary
                                    }
                                } else {
                                    // Save the reminder as a new entry
                                    let newReminder = Reminder(title: name, active: true) // Customize with user input
                                    reminderData.reminders.append(newReminder)
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
                        //TODO: Update other fields
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
    
    
    

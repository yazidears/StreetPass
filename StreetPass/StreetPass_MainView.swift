// StreetPass_MainView.swift
// Contains all primary SwiftUI views for the StreetPass application interface.

import SwiftUI

struct StreetPass_MainView: View {
    @StateObject var viewModel: StreetPassViewModel

    var body: some View {
        NavigationView {
            List {
                // Section: My Card Display & Edit Button
                Section {
                    MyEncounterCardView(card: viewModel.myCurrentCard)
                    Button(viewModel.isEditingMyCard ? "Done Editing" : "Edit My Card") {
                        if viewModel.isEditingMyCard {
                            viewModel.saveMyEditedCard()
                        } else {
                            viewModel.prepareCardForEditing()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.primaryColor) // Use theme color
                    .frame(maxWidth: .infinity, alignment: .center)
                } header: {
                    Text("My StreetPass Card")
                        .font(.headline)
                        .foregroundColor(AppTheme.primaryColor) // Use theme color
                }

                // Section: Card Editor (Conditional)
                if viewModel.isEditingMyCard {
                    Section("Card Editor") {
                        EncounterCardEditorView(card: $viewModel.cardForEditor)
                        HStack {
                            Button("Save Changes") { viewModel.saveMyEditedCard() }
                                .buttonStyle(.borderedProminent).tint(AppTheme.positiveColor)
                            Spacer()
                            Button("Cancel") { viewModel.cancelCardEditing() }
                                .buttonStyle(.bordered).tint(.gray)
                        }
                        .padding(.vertical, 5)
                    }
                }

                // Section: Controls & Status
                Section("System Controls") { // Renamed for clarity
                    StreetPassControlsView(viewModel: viewModel)
                    
                    if let errorMsg = viewModel.lastErrorMessage {
                        MessageView(message: errorMsg, type: .error)
                    } else if let infoMsg = viewModel.lastInfoMessage {
                        MessageView(message: infoMsg, type: .info)
                    }
                }

                // Section: Received Encounter Cards
                Section("Recent Encounters (\(viewModel.recentlyEncounteredCards.count))") {
                    if viewModel.recentlyEncounteredCards.isEmpty {
                        Text("No cards received yet. Activate StreetPass and explore!")
                            .foregroundColor(.secondary)
                            .padding()
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(viewModel.recentlyEncounteredCards) { card in
                            ReceivedEncounterCardRowView(card: card)
                        }
                    }
                }

                // Section: Activity Log
                Section("Activity Log (Last 50)") {
                    if viewModel.bleActivityLog.isEmpty {
                        Text("No activity logged yet.").foregroundColor(.secondary)
                    } else {
                        // More compact log display
                        ForEach(Array(viewModel.bleActivityLog.prefix(50).enumerated()), id: \.offset) { _, logMsg in
                            Text(logMsg)
                                .font(.caption) // Slightly larger than caption2 for readability
                                .lineLimit(1)   // Keep it concise per line
                                .foregroundColor(.gray)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
            .navigationTitle("StreetPass")
            .navigationBarTitleDisplayMode(.inline) // More compact title
            .listStyle(.grouped) // Changed from insetGrouped for potentially better feel
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                     Image(systemName: "antenna.radiowaves.left.and.right.circle.fill") // Alternative icon
                        .font(.title2) // Slightly larger
                        .foregroundColor(AppTheme.primaryColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    // Placeholder for potential future actions like settings
                    if #available(iOS 16.0, *) {
                        // Potentially add a menu here later
                    }
                }
            }
            .refreshable {
                viewModel.refreshUIDataFromPull()
            }
            .background(AppTheme.backgroundColor.edgesIgnoringSafeArea(.all)) // Apply background
        }
        .accentColor(AppTheme.primaryColor) // Sets the global accent for NavigationView elements
        .navigationViewStyle(.stack)
    }
}

// MARK: - Sub-views for MainView (StreetPassControlsView)
struct StreetPassControlsView: View {
    @ObservedObject var viewModel: StreetPassViewModel

    var body: some View {
        VStack(spacing: 12) {
            Button {
                viewModel.toggleStreetPassServices()
            } label: {
                Label(viewModel.isScanningActive || viewModel.isAdvertisingActive ? "Stop StreetPass" : "Start StreetPass",
                      systemImage: viewModel.isScanningActive || viewModel.isAdvertisingActive ? "stop.circle.fill" : "play.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isScanningActive || viewModel.isAdvertisingActive ? AppTheme.destructiveColor : AppTheme.primaryColor) // Use theme color
            .frame(maxWidth: .infinity)

            if !viewModel.recentlyEncounteredCards.isEmpty {
                Button {
                    viewModel.clearAllEncounteredCards()
                } label: {
                    Label("Clear All Encounters", systemImage: "trash.fill")
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.negativeColor) // Use theme color
                .frame(maxWidth: .infinity)
            }
            
            HStack {
                StatusIndicatorView(label: "Bluetooth", isOn: viewModel.isBluetoothOn)
                Spacer()
                StatusIndicatorView(label: "Scanning", isOn: viewModel.isScanningActive)
                Spacer()
                StatusIndicatorView(label: "Advertising", isOn: viewModel.isAdvertisingActive)
            }
            .font(.footnote)
            .padding(.top, 5)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - StatusIndicatorView (updated to use theme colors)
struct StatusIndicatorView: View {
    let label: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isOn ? AppTheme.positiveColor : AppTheme.negativeColor) // Use theme color
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundColor(isOn ? AppTheme.positiveColor : AppTheme.negativeColor) // Use theme color
            Text(isOn ? "On" : "Off")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - MessageView (updated to use theme colors)
struct MessageView: View {
    let message: String
    enum MessageType { case info, error, warning } // Added warning type
    let type: MessageType

    private var foregroundColor: Color {
        switch type {
        case .info: return AppTheme.infoColor
        case .error: return AppTheme.negativeColor
        case .warning: return AppTheme.warningColor
        }
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(0.1)
    }

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundColor(foregroundColor)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .cornerRadius(6)
    }
}

// MARK: - Card Display Views (MyEncounterCardView, FlairDisplayRow, ReceivedEncounterCardRowView)
// MyEncounterCardView - using AppTheme.cardBackgroundColor
struct MyEncounterCardView: View {
    let card: EncounterCard
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 15) {
                Image(systemName: card.avatarSymbolName)
                    .font(.system(size: 44))
                    .foregroundColor(AppTheme.primaryColor) // Use theme color
                    .frame(width: 50, height: 50)
                    .background(AppTheme.primaryColor.opacity(0.1)) // Use theme color
                    .clipShape(Circle())
                
                VStack(alignment: .leading) {
                    Text(card.displayName)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("\"\(card.statusMessage)\"")
                        .font(.footnote)
                        .italic()
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }

            if let title1 = card.flairField1Title, let value1 = card.flairField1Value, !title1.isEmpty || !value1.isEmpty {
                FlairDisplayRow(title: title1, value: value1)
            }
            if let title2 = card.flairField2Title, let value2 = card.flairField2Value, !title2.isEmpty || !value2.isEmpty {
                FlairDisplayRow(title: title2, value: value2)
            }
            
            Divider().padding(.vertical, 2)
            
            HStack {
                Text("ID: \(card.userID.prefix(8))...")
                Spacer()
                Text("Schema v\(card.cardSchemaVersion)")
            }
            .font(.caption2)
            .foregroundColor(.gray)
            
            Text("Updated: \(card.lastUpdated, style: .relative) ago")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding()
        .background(AppTheme.cardBackgroundColor) // Use theme defined material
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2) // Subtle shadow
    }
}

// FlairDisplayRow - using theme colors
struct FlairDisplayRow: View {
    let title: String?
    let value: String?

    var body: some View {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
           let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            HStack(alignment: .top) {
                Text(t + ":")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.secondaryColor) // Use theme color
                Text(v)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        } else if let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
             Text(v)
                .font(.caption).italic()
                .foregroundColor(.primary)
        }
    }
}

// ReceivedEncounterCardRowView - using AppTheme.userSpecificColor
struct ReceivedEncounterCardRowView: View {
    let card: EncounterCard

    var body: some View {
        let userColor = AppTheme.userSpecificColor(for: card.userID)
        HStack(spacing: 12) {
            Image(systemName: card.avatarSymbolName)
                .font(.title2)
                .frame(width: 36, height: 36)
                .foregroundColor(userColor)
                .background(userColor.opacity(0.2))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(card.displayName).font(.subheadline).fontWeight(.semibold)
                Text(card.statusMessage).font(.caption).foregroundColor(.secondary).lineLimit(1)
                if let title = card.flairField1Title, let value = card.flairField1Value,
                   !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                     Text("\(title.isEmpty ? "" : title + ": ")\(value)")
                        .font(.caption2)
                        .foregroundColor(userColor.opacity(0.9))
                        .lineLimit(1)
                }
            }
            Spacer()
            // Removed chevron.right, it's usually added by NavigationLink automatically
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Card Editor View (EncounterCardEditorView)
struct EncounterCardEditorView: View {
    @Binding var card: EncounterCard
    
    private let avatarOptions: [String] = [
        "person.fill", "person.crop.circle.fill", "face.smiling.fill", "star.fill",
        "heart.fill", "gamecontroller.fill", "music.note", "book.fill",
        "figure.walk", "pawprint.fill", "leaf.fill", "airplane", "car.fill",
        "desktopcomputer", "paintbrush.pointed.fill", "camera.fill", "gift.fill",
        "network", "globe.americas.fill", "sun.max.fill", "moon.stars.fill",
        "cloud.sleet.fill", "message.fill", "briefcase.fill", "studentdesk"
    ] // Added more options

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Display Name", text: $card.displayName, prompt: Text("Your Public Name"))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Status Message (max 150 chars)")
                    .font(.caption).foregroundColor(.gray)
                TextEditor(text: $card.statusMessage)
                    .frame(height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 5)) // So overlay border follows shape
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                Text("\(card.statusMessage.count) / 150")
                    .font(.caption2).foregroundColor(card.statusMessage.count > 150 ? AppTheme.negativeColor : .gray)
            }
            
            Picker("Avatar Icon", selection: $card.avatarSymbolName) {
                ForEach(avatarOptions, id: \.self) { symbol in
                    HStack {
                        Image(systemName: symbol).frame(width: 25, alignment: .center) // Increased width slightly
                        Text(symbol.split(separator: ".").map{ $0.capitalized }.joined(separator: " ").replacingOccurrences(of: "Fill", with: ""))
                    }.tag(symbol)
                }
            }
            
            // Flair fields made into a sub-view or group for clarity
            FlairEditorSection(titleBinding1: titleBinding(for: \.flairField1Title),
                               valueBinding1: valueBinding(for: \.flairField1Value),
                               titleBinding2: titleBinding(for: \.flairField2Title),
                               valueBinding2: valueBinding(for: \.flairField2Value))
        }
        .textFieldStyle(.roundedBorder)
    }

    // Grouped Flair Editors
    struct FlairEditorSection: View {
        @Binding var titleBinding1: String
        @Binding var valueBinding1: String
        @Binding var titleBinding2: String
        @Binding var valueBinding2: String

        var body: some View {
            DisclosureGroup("Optional Flair Fields") { // Make them collapsible
                VStack(alignment: .leading, spacing: 10) { // Added spacing
                    Text("Flair Field 1").font(.caption).foregroundColor(.gray)
                    TextField("Title (e.g., Hobby)", text: $titleBinding1, prompt: Text("Title 1"))
                    TextField("Value (e.g., Hiking)", text: $valueBinding1, prompt: Text("Value 1"))
                    Divider()
                    Text("Flair Field 2").font(.caption).foregroundColor(.gray)
                    TextField("Title (e.g., Team)", text: $titleBinding2, prompt: Text("Title 2"))
                    TextField("Value (e.g., Blue)", text: $valueBinding2, prompt: Text("Value 2"))
                }
                .padding(.top, 5)
            }
        }
    }


    private func titleBinding(for keyPath: WritableKeyPath<EncounterCard, String?>) -> Binding<String> {
        Binding<String>(
            get: { card[keyPath: keyPath] ?? "" },
            set: { card[keyPath: keyPath] = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }
    private func valueBinding(for keyPath: WritableKeyPath<EncounterCard, String?>) -> Binding<String> {
        Binding<String>(
            get: { card[keyPath: keyPath] ?? "" },
            set: { card[keyPath: keyPath] = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }
}

// MARK: - Previews
struct StreetPass_MainView_Previews: PreviewProvider {
    static var previews: some View {
        let previewVM = StreetPassViewModel(userID: "previewUser123")
        var sampleCard1 = EncounterCard(userID: "userA", displayName: "Gamer Gal", statusMessage: "Looking for co-op!", avatarSymbolName: "gamecontroller.fill")
        sampleCard1.flairField1Title = "Playing"
        sampleCard1.flairField1Value = "Cosmic Crusade"
        var sampleCard2 = EncounterCard(userID: "userB", displayName: "Music Mike", statusMessage: "Jamming out", avatarSymbolName: "music.mic.fill")
        sampleCard2.flairField1Title = "Genre"
        sampleCard2.flairField1Value = "Indie Rock"
        previewVM.bleManager.receivedCards = [sampleCard1, sampleCard2]
        previewVM.bleManager.localUserCard.displayName = "My Preview Card"
        previewVM.bleManager.localUserCard.statusMessage = "This is my card in the preview!"
        previewVM.bleManager.isBluetoothPoweredOn = true
        previewVM.bleManager.isScanning = true
        
        return StreetPass_MainView(viewModel: previewVM)
            .environmentObject(previewVM) // Ensure ViewModel is in environment for previews too
    }
}
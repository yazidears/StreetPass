//
//  StreetPass_MainView.swift
//  StreetPass
//
//  Created by Yazide Arsalan on 18/5/25.
// StreetPass_MainView.swift
// Contains all primary SwiftUI views for the StreetPass application interface.

import SwiftUI

struct StreetPass_MainView: View {
    @StateObject var viewModel: StreetPassViewModel // Changed from AppViewModel to StreetPassViewModel

    var body: some View {
        NavigationView {
            List {
                // Section: My Card Display & Edit Button
                Section {
                    MyEncounterCardView(card: viewModel.myCurrentCard) // Updated name
                    Button(viewModel.isEditingMyCard ? "Done Editing" : "Edit My Card") {
                        if viewModel.isEditingMyCard {
                            viewModel.saveMyEditedCard() // Save if "Done Editing"
                        } else {
                            viewModel.prepareCardForEditing()
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .center)
                } header: {
                    Text("My StreetPass Card")
                        .font(.headline)
                        .foregroundColor(.primary) // Ensure good contrast
                }

                // Section: Card Editor (Conditional)
                if viewModel.isEditingMyCard {
                    Section("Card Editor") {
                        EncounterCardEditorView(card: $viewModel.cardForEditor) // Updated name
                        HStack {
                            Button("Save Changes") { viewModel.saveMyEditedCard() }
                                .buttonStyle(.borderedProminent).tint(.green)
                            Spacer()
                            Button("Cancel") { viewModel.cancelCardEditing() }
                                .buttonStyle(.bordered).tint(.gray)
                        }
                        .padding(.vertical, 5)
                    }
                }

                // Section: Controls & Status
                Section("System") {
                    StreetPassControlsView(viewModel: viewModel) // Extracted to subview
                    
                    // Display last error or info message
                    if let errorMsg = viewModel.lastErrorMessage {
                        MessageView(message: errorMsg, type: .error)
                    } else if let infoMsg = viewModel.lastInfoMessage {
                        MessageView(message: infoMsg, type: .info)
                    }
                }

                // Section: Received Encounter Cards
                Section("Recent Encounters (\(viewModel.recentlyEncounteredCards.count))") {
                    if viewModel.recentlyEncounteredCards.isEmpty {
                        Text("No cards received yet. Make sure StreetPass is active and you're near other users!")
                            .foregroundColor(.secondary)
                            .padding()
                            .multilineTextAlignment(.center)
                    } else {
                        ForEach(viewModel.recentlyEncounteredCards) { card in
                            ReceivedEncounterCardRowView(card: card) // Updated name
                        }
                    }
                }

                // Section: Activity Log
                Section("Activity Log (Last 50)") {
                    if viewModel.bleActivityLog.isEmpty {
                        Text("No activity logged yet.").foregroundColor(.secondary)
                    } else {
                        ForEach(Array(viewModel.bleActivityLog.prefix(50).enumerated()), id: \.offset) { _, logMsg in
                            Text(logMsg)
                                .font(.caption2)
                                .lineLimit(2)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .navigationTitle("StreetPass")
            .listStyle(.insetGrouped)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                     Image(systemName: "person.2.wave.2.fill") // StreetPass icon
                        .foregroundColor(.accentColor)
                }
            }
            .refreshable { // Pull-to-refresh
                viewModel.refreshUIDataFromPull()
            }
        }
        .navigationViewStyle(.stack) // Recommended for iOS
    }
}

// MARK: - Sub-views for MainView

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
            .tint(viewModel.isScanningActive || viewModel.isAdvertisingActive ? .pink : .accentColor)
            .frame(maxWidth: .infinity)

            if !viewModel.recentlyEncounteredCards.isEmpty {
                Button {
                    viewModel.clearAllEncounteredCards()
                } label: {
                    Label("Clear All Encounters", systemImage: "trash.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
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

struct StatusIndicatorView: View {
    let label: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isOn ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundColor(isOn ? .green : .red)
            Text(isOn ? "On" : "Off")
                .foregroundColor(.secondary)
        }
    }
}

struct MessageView: View {
    let message: String
    enum MessageType { case info, error }
    let type: MessageType

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundColor(type == .error ? .red : .blue)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((type == .error ? Color.red : Color.blue).opacity(0.1))
            .cornerRadius(6)
    }
}

// MARK: - Card Display Views (My Card and Received Card Row)

struct MyEncounterCardView: View { // Renamed
    let card: EncounterCard
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 15) {
                Image(systemName: card.avatarSymbolName)
                    .font(.system(size: 44)) // Slightly smaller
                    .foregroundColor(.accentColor)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Circle())
                
                VStack(alignment: .leading) {
                    Text(card.displayName)
                        .font(.title3) // Adjusted size
                        .fontWeight(.bold)
                    Text("\"\(card.statusMessage)\"")
                        .font(.footnote) // Adjusted size
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
        .background(Material.thin) // More modern background
        .cornerRadius(10)
    }
}

struct FlairDisplayRow: View { // Renamed
    let title: String?
    let value: String?

    var body: some View {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
           let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            HStack(alignment: .top) {
                Text(t + ":")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange) // Example flair color
                Text(v)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        } else if let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
             Text(v) // Value only, if title is empty
                .font(.caption).italic()
                .foregroundColor(.primary)
        }
    }
}

struct ReceivedEncounterCardRowView: View { // Renamed
    let card: EncounterCard

    private var userSpecificColor: Color { // Helper for dynamic color
        let hash = abs(card.userID.hashValue)
        return Color(hue: Double(hash % 360) / 360.0, saturation: 0.7, brightness: 0.85)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: card.avatarSymbolName)
                .font(.title2) // Adjusted size
                .frame(width: 36, height: 36)
                .foregroundColor(userSpecificColor)
                .background(userSpecificColor.opacity(0.2))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(card.displayName).font(.subheadline).fontWeight(.semibold)
                Text(card.statusMessage).font(.caption).foregroundColor(.secondary).lineLimit(1)
                if let title = card.flairField1Title, let value = card.flairField1Value, !title.isEmpty {
                     Text("\(title): \(value)").font(.caption2).foregroundColor(userSpecificColor.opacity(0.9))
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.white) // For indicating it's a row
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Card Editor View
struct EncounterCardEditorView: View { // Renamed
    @Binding var card: EncounterCard
    
    private let avatarOptions: [String] = [ // Curated list
        "person.fill", "person.crop.circle.fill", "face.smiling.fill", "star.fill",
        "heart.fill", "gamecontroller.fill", "music.note", "book.fill",
        "figure.walk", "pawprint.fill", "leaf.fill", "airplane", "car.fill",
        "desktopcomputer", "paintbrush.pointed.fill", "camera.fill", "gift.fill"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Display Name", text: $card.displayName, prompt: Text("Your Public Name"))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Status Message (max 150 chars)")
                    .font(.caption).foregroundColor(.gray)
                TextEditor(text: $card.statusMessage)
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                Text("\(card.statusMessage.count) / 150")
                    .font(.caption2).foregroundColor(card.statusMessage.count > 150 ? .red : .gray)
            }
            
            Picker("Avatar Icon", selection: $card.avatarSymbolName) {
                ForEach(avatarOptions, id: \.self) { symbol in
                    HStack {
                        Image(systemName: symbol).frame(width: 20, alignment: .center)
                        Text(symbol.split(separator: ".").map{ $0.capitalized }.joined(separator: " "))
                    }.tag(symbol)
                }
            }
            
            Group {
                TextField("Flair 1 Title (e.g., Hobby)", text: titleBinding(for: \.flairField1Title))
                TextField("Flair 1 Value (e.g., Hiking)", text: valueBinding(for: \.flairField1Value))
            }
            Group {
                TextField("Flair 2 Title (e.g., Team)", text: titleBinding(for: \.flairField2Title))
                TextField("Flair 2 Value (e.g., Blue)", text: valueBinding(for: \.flairField2Value))
            }
        }
        .textFieldStyle(.roundedBorder) // Apply to all textfields in this VStack
    }

    // Helper for binding optional flair strings (makes TextField code cleaner)
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
        // Create a dummy viewModel for preview
        let previewVM = StreetPassViewModel(userID: "previewUser123")
        // Populate with some sample data for a richer preview
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
    }
}

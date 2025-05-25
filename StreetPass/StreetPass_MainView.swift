// StreetPass_MainView.swift
// Contains all primary SwiftUI views for the StreetPass application interface.

import SwiftUI

struct StreetPass_MainView: View {
    @StateObject var viewModel: StreetPassViewModel

    var body: some View {
        NavigationView {
            List {
                Section {
                    // MyEncounterCardView will be updated to show drawing
                    MyEncounterCardView(card: viewModel.myCurrentCard)
                    
                    // Button to open the editor form. Actual save/cancel are in the form.
                    Button(viewModel.isEditingMyCard ? "View/Finalize My Card" : "Edit My Card") {
                        if viewModel.isEditingMyCard {
                            
                        } else {
                            viewModel.prepareCardForEditing()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.primaryColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                } header: {
                    Text("My StreetPass Card")
                        .font(.headline)
                        .foregroundColor(AppTheme.primaryColor)
                }

                if viewModel.isEditingMyCard {
                    Section("Card Editor") {
                        // EncounterCardEditorView will be updated
                        EncounterCardEditorView(
                            card: $viewModel.cardForEditor,
                            onOpenDrawingEditor: viewModel.openDrawingEditor, // Pass action
                            onRemoveDrawing: viewModel.removeDrawingFromCard // Pass action
                        )
                        HStack {
                            Button("Save All Changes") { viewModel.saveMyEditedCard() }
                                .buttonStyle(.borderedProminent).tint(AppTheme.positiveColor)
                            Spacer()
                            Button("Cancel Edits") { viewModel.cancelCardEditing() }
                                .buttonStyle(.bordered).tint(.gray)
                        }
                        .padding(.vertical, 5)
                    }
                }

                Section("System Controls") {
                    StreetPassControlsView(viewModel: viewModel)
                    if let errorMsg = viewModel.lastErrorMessage {
                        MessageView(message: errorMsg, type: .error)
                    } else if let infoMsg = viewModel.lastInfoMessage {
                        MessageView(message: infoMsg, type: .info)
                    }
                }

                Section("Recent Encounters (\(viewModel.recentlyEncounteredCards.count))") {
                    if viewModel.recentlyEncounteredCards.isEmpty {
                        Text("No cards received yet. Activate StreetPass and explore!")
                            .foregroundColor(.secondary).padding().multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    } else {
                        ForEach(viewModel.recentlyEncounteredCards) { card in
                            // ReceivedEncounterCardRowView will be updated for drawing
                            ReceivedEncounterCardRowView(card: card)
                                .padding(.vertical, 2) // Add some padding around rows
                        }
                    }
                }

                Section("Activity Log (Last 50)") {
                    if viewModel.bleActivityLog.isEmpty {
                        Text("No activity logged yet.").foregroundColor(.secondary)
                    } else {
                        ForEach(Array(viewModel.bleActivityLog.prefix(50).enumerated()), id: \.offset) { _, logMsg in
                            Text(logMsg).font(.caption).lineLimit(1).foregroundColor(.gray).truncationMode(.tail)
                        }
                    }
                }
            }
            .navigationTitle("StreetPass")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                     Image(systemName: "wave.3.left.and.right.circle.fill") // Updated icon
                        .font(.title2)
                        .foregroundColor(AppTheme.primaryColor)
                }
            }
            .refreshable { viewModel.refreshUIDataFromPull() }
            .background(AppTheme.backgroundColor.edgesIgnoringSafeArea(.all))
        }
        .accentColor(AppTheme.primaryColor)
        .navigationViewStyle(.stack)
        // Sheet for drawing editor
        .sheet(isPresented: $viewModel.isDrawingSheetPresented) {
            // The drawing data on viewModel.cardForEditor is bound here
            DrawingEditorSheetView(
                isPresented: $viewModel.isDrawingSheetPresented,
                cardDrawingData: $viewModel.cardForEditor.drawingData
            )
        }
    }
}

// MARK: - Sub-views for MainView (StreetPassControlsView) - (No changes from your version)
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
            .tint(viewModel.isScanningActive || viewModel.isAdvertisingActive ? AppTheme.destructiveColor : AppTheme.primaryColor)
            .frame(maxWidth: .infinity)

            if !viewModel.recentlyEncounteredCards.isEmpty {
                Button {
                    viewModel.clearAllEncounteredCards()
                } label: {
                    Label("Clear All Encounters", systemImage: "trash.fill")
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.negativeColor)
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

// MARK: - StatusIndicatorView - (No changes from your version)
struct StatusIndicatorView: View {
    let label: String
    let isOn: Bool
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isOn ? AppTheme.positiveColor : AppTheme.negativeColor)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundColor(isOn ? AppTheme.positiveColor : AppTheme.negativeColor)
            Text(isOn ? "On" : "Off")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - MessageView - (No changes from your version)
struct MessageView: View {
    let message: String
    enum MessageType { case info, error, warning }
    let type: MessageType
    private var foregroundColor: Color { }
    private var backgroundColor: Color {  }
    var body: some View {
        let fgColor: Color
        switch type {
            case .info: fgColor = AppTheme.infoColor
            case .error: fgColor = AppTheme.negativeColor
            case .warning: fgColor = AppTheme.warningColor
        }
        return Text(message)
            .font(.caption)
            .foregroundColor(fgColor)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fgColor.opacity(0.1))
            .cornerRadius(6)
    }
}


// MARK: - Card Display Views (MODIFIED to show drawings)

// MyEncounterCardView - MODIFIED
struct MyEncounterCardView: View {
    let card: EncounterCard
    
    // Defined size for consistency
    private let drawingDisplayMaxHeight: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Display drawing if available
            if let drawingUiImage = card.drawingImage {
                Image(uiImage: drawingUiImage)
                    .resizable()
                    .scaledToFit() // Fit within the bounds, keeping aspect ratio
                    .frame(maxWidth: .infinity) // Take available width
                    .frame(maxHeight: drawingDisplayMaxHeight) // Limit height
                    .background(Color.gray.opacity(0.1)) // Background for the image area
                    .cornerRadius(8)
                    .padding(.bottom, 5)
            } else {
                // Placeholder or message if no drawing
                HStack {
                    Spacer()
                    Text("No Drawing Set For This Card")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: drawingDisplayMaxHeight / 2) // Smaller placeholder
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                .padding(.bottom, 5)
            }
            
            // Existing text content
            HStack(spacing: 15) {
                Image(systemName: card.avatarSymbolName)
                    .font(.system(size: 44))
                    .foregroundColor(AppTheme.primaryColor)
                    .frame(width: 50, height: 50)
                    .background(AppTheme.primaryColor.opacity(0.1))
                    .clipShape(Circle())
                
                VStack(alignment: .leading) {
                    Text(card.displayName)
                        .font(.title3).fontWeight(.bold)
                    Text("\"\(card.statusMessage)\"")
                        .font(.footnote).italic().foregroundColor(.secondary).lineLimit(3)
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
            .font(.caption2).foregroundColor(.gray)
            
            Text("Updated: \(card.lastUpdated, style: .relative) ago")
                .font(.caption2).foregroundColor(.gray)
        }
        .padding()
        .background(AppTheme.cardBackgroundColor)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}

// FlairDisplayRow - (No changes from your version)
struct FlairDisplayRow: View {
    let title: String?
    let value: String?
    var body: some View { /* ... Same as your provided code ... */
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
           let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            HStack(alignment: .top) {
                Text(t + ":")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.secondaryColor)
                Text(v)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        } else if let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
             Text(v)
                .font(.caption).italic()
                .foregroundColor(.primary)
        } else {
            EmptyView()
        }
    }
}

// ReceivedEncounterCardRowView - MODIFIED
struct ReceivedEncounterCardRowView: View {
    let card: EncounterCard
    private let drawingThumbnailSize: CGFloat = 50 // Small thumbnail

    var body: some View {
        let userColor = AppTheme.userSpecificColor(for: card.userID)
        HStack(spacing: 12) {
            // Show drawing thumbnail or avatar
            if let drawingUiImage = card.drawingImage {
                Image(uiImage: drawingUiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill) // Fill the frame, might crop
                    .frame(width: drawingThumbnailSize, height: drawingThumbnailSize)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8)) // Or Circle()
            } else {
                Image(systemName: card.avatarSymbolName) // Fallback to avatar
                    .font(.title) // Larger avatar if no drawing
                    .frame(width: drawingThumbnailSize, height: drawingThumbnailSize)
                    .foregroundColor(userColor)
                    .background(userColor.opacity(0.2))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(card.displayName).font(.headline).fontWeight(.semibold)
                Text(card.statusMessage).font(.caption).foregroundColor(.secondary).lineLimit(2) // Allow two lines for status
                
                // Display one flair field if available
                if let title = card.flairField1Title, let value = card.flairField1Value,
                   !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                     Text("\(title.isEmpty ? "" : title + ": ")\(value)")
                        .font(.caption2)
                        .foregroundColor(userColor.opacity(0.9))
                        .lineLimit(1)
                }
            }
            Spacer() // Pushes content to left
        }
        .padding(.vertical, 6) // More vertical padding for rows
    }
}

// MARK: - Card Editor View (MODIFIED to include drawing options)
struct EncounterCardEditorView: View {
    @Binding var card: EncounterCard
    var onOpenDrawingEditor: () -> Void // Action to open the drawing sheet
    var onRemoveDrawing: () -> Void // Action to remove current drawing
    
    private let avatarOptions: [String] = [ /* ... Same as your provided code ... */
        "person.fill", "person.crop.circle.fill", "face.smiling.fill", "star.fill",
        "heart.fill", "gamecontroller.fill", "music.note", "book.fill",
        "figure.walk", "pawprint.fill", "leaf.fill", "airplane", "car.fill",
        "desktopcomputer", "paintbrush.pointed.fill", "camera.fill", "gift.fill",
        "network", "globe.americas.fill", "sun.max.fill", "moon.stars.fill",
        "cloud.sleet.fill", "message.fill", "briefcase.fill", "studentdesk"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section for Drawing
            VStack(alignment: .leading) {
                Text("Card Drawing").font(.headline.smallCaps())
                if let drawingUiImage = card.drawingImage {
                    Image(uiImage: drawingUiImage)
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 100)
                        .background(Color.gray.opacity(0.1)).cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                        .padding(.bottom, 5)
                } else {
                    Text("No drawing set. Tap 'Draw/Edit' to create one.")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: 60)
                        .background(Color.gray.opacity(0.05)).cornerRadius(6)
                        .padding(.bottom, 5)
                }
                HStack {
                    Button(action: onOpenDrawingEditor) {
                        Label(card.drawingData == nil ? "Draw Card" : "Edit Drawing", systemImage: "paintbrush.pointed.fill")
                    }
                    .buttonStyle(.bordered).tint(AppTheme.primaryColor)
                    
                    if card.drawingData != nil {
                        Spacer()
                        Button(action: onRemoveDrawing) {
                            Label("Remove Drawing", systemImage: "xmark.circle.fill")
                        }
                        .buttonStyle(.bordered).tint(AppTheme.negativeColor)
                    }
                }
            }
            
            Divider()
            Text("Text Details").font(.headline.smallCaps())

            TextField("Display Name", text: $card.displayName, prompt: Text("Your Public Name"))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Status Message (max 150 chars)")
                    .font(.caption).foregroundColor(.gray)
                TextEditor(text: $card.statusMessage)
                    .frame(height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                Text("\(card.statusMessage.count) / 150")
                    .font(.caption2).foregroundColor(card.statusMessage.count > 150 ? AppTheme.negativeColor : .gray)
            }
            
            Picker("Avatar Icon (Fallback)", selection: $card.avatarSymbolName) {
                ForEach(avatarOptions, id: \.self) { symbol in
                    HStack {
                        Image(systemName: symbol).frame(width: 25, alignment: .center)
                        Text(symbol.split(separator: ".").map{ $0.capitalized }.joined(separator: " ").replacingOccurrences(of: "Fill", with: ""))
                    }.tag(symbol)
                }
            }
            Text("Avatar is shown if no drawing is available or for compact views.").font(.caption2).foregroundColor(.gray)
            
            FlairEditorSection(titleBinding1: titleBinding(for: \.flairField1Title),
                               valueBinding1: valueBinding(for: \.flairField1Value),
                               titleBinding2: titleBinding(for: \.flairField2Title),
                               valueBinding2: valueBinding(for: \.flairField2Value))
        }
        .textFieldStyle(.roundedBorder)
    }

    struct FlairEditorSection: View {
        @Binding var titleBinding1: String
        @Binding var valueBinding1: String
        @Binding var titleBinding2: String
        @Binding var valueBinding2: String

        var body: some View {
            DisclosureGroup("Optional Flair Fields") {
                VStack(alignment: .leading, spacing: 10) {
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

    private func titleBinding(for keyPath: WritableKeyPath<EncounterCard, String?>) -> Binding<String> { /* ... */ }
    private func valueBinding(for keyPath: WritableKeyPath<EncounterCard, String?>) -> Binding<String> { /* ... */ }
    /* titleBinding and valueBinding are the same as your provided code */
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
        
        // Create a sample drawing for preview
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 150))
        let sampleDrawing = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 150))
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: UIColor.white]
            ("Sample Drawing" as NSString).draw(with: CGRect(x: 20, y: 60, width: 160, height: 30), options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
        }
        
        previewVM.bleManager.localUserCard.displayName = "My Drawn Card"
        previewVM.bleManager.localUserCard.statusMessage = "This is my card with a drawing!"
        previewVM.bleManager.localUserCard.drawingData = sampleDrawing.pngData() // Add sample drawing data
        previewVM.bleManager.localUserCard.flairField1Title = "Mood"
        previewVM.bleManager.localUserCard.flairField1Value = "Creative!"


        var sampleCard1 = EncounterCard(userID: "userA", displayName: "Artist Anna", statusMessage: "Drawing all day", avatarSymbolName: "paintbrush.fill")
        sampleCard1.flairField1Title = "Tool"
        sampleCard1.flairField1Value = "iPad & Pencil"
        let anotherDrawing = renderer.image { ctx in UIColor.systemGreen.setFill(); ctx.fill(CGRect(x:0,y:0,width:200,height:150)); ("Hi!" as NSString).draw(at: CGPoint(x:80, y:60), withAttributes: attrs)}
        sampleCard1.drawingData = anotherDrawing.jpegData(compressionQuality: 0.7)

        var sampleCard2 = EncounterCard(userID: "userB", displayName: "Text Tom", statusMessage: "Old school, text only!", avatarSymbolName: "text.bubble.fill")

        previewVM.bleManager.receivedCards = [sampleCard1, sampleCard2]
        previewVM.bleManager.isBluetoothPoweredOn = true
        previewVM.bleManager.isScanning = true
        
        // For previewing editor
        // previewVM.isEditingMyCard = true
        // previewVM.prepareCardForEditing()
        
        return StreetPass_MainView(viewModel: previewVM)
            // .environmentObject(previewVM)
    }
}

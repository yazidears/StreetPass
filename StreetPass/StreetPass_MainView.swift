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
                    
                    Button(viewModel.isEditingMyCard ? "Manage My Card" : "Edit My Card") {
                        if viewModel.isEditingMyCard {
                            // User is already in editor mode; this button's action could be refined
                            // For now, it doesn't need to do anything new if editor is open
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

                // Section: Card Editor (Conditional)
                if viewModel.isEditingMyCard {
                    Section("Card Editor") {
                        EncounterCardEditorView( // Defined further down in this file
                            card: $viewModel.cardForEditor,
                            onOpenDrawingEditor: viewModel.openDrawingEditor,
                            onRemoveDrawing: viewModel.removeDrawingFromCard
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

                // Section: Controls & Status
                Section("System Controls") {
                    StreetPassControlsView(viewModel: viewModel) // Defined further down
                    
                    if let errorMsg = viewModel.lastErrorMessage {
                        MessageView(message: errorMsg, type: .error) // Defined further down
                    } else if let infoMsg = viewModel.lastInfoMessage {
                        MessageView(message: infoMsg, type: .info) // Defined further down
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
                            ReceivedEncounterCardRowView(card: card) // Defined further down
                                .padding(.vertical, 2)
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
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundColor(.gray)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
            .navigationTitle("StreetPass")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.grouped)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Image(systemName: "camera")
                        .font(.title2)
                        .foregroundColor(AppTheme.primaryColor)
                }
            }
            .refreshable { viewModel.refreshUIDataFromPull() }
            .background(AppTheme.backgroundColor.edgesIgnoringSafeArea(.all))
        }
        .accentColor(AppTheme.primaryColor)
        .navigationViewStyle(.stack)
        .sheet(isPresented: $viewModel.isDrawingSheetPresented) {
            // DrawingEditorSheetView is defined in DrawingCanvasView.swift
            // Ensure that DrawingCanvasView.swift is part of your target
            DrawingEditorSheetView(
                isPresented: $viewModel.isDrawingSheetPresented,
                cardDrawingData: $viewModel.cardForEditor.drawingData
            )
            .interactiveDismissDisabled()
        }
    }
}

// MARK: - StreetPassControlsView (Sub-view for MainView)
struct StreetPassControlsView: View {
    @ObservedObject var viewModel: StreetPassViewModel
    var body: some View {
        VStack(spacing: 12) {
            Button { viewModel.toggleStreetPassServices() } label: {
                Label(viewModel.isScanningActive || viewModel.isAdvertisingActive ? "Stop StreetPass" : "Start StreetPass",
                      systemImage: viewModel.isScanningActive || viewModel.isAdvertisingActive ? "stop.circle.fill" : "play.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isScanningActive || viewModel.isAdvertisingActive ? AppTheme.destructiveColor : AppTheme.primaryColor)
            .frame(maxWidth: .infinity)

            if !viewModel.recentlyEncounteredCards.isEmpty {
                Button { viewModel.clearAllEncounteredCards() } label: {
                    Label("Clear All Encounters", systemImage: "trash.fill")
                }
                .buttonStyle(.bordered).tint(AppTheme.negativeColor).frame(maxWidth: .infinity)
            }
            
            HStack {
                StatusIndicatorView(label: "Bluetooth", isOn: viewModel.isBluetoothOn); Spacer() // Defined below
                StatusIndicatorView(label: "Scanning", isOn: viewModel.isScanningActive); Spacer() // Defined below
                StatusIndicatorView(label: "Advertising", isOn: viewModel.isAdvertisingActive) // Defined below
            }
            .font(.footnote).padding(.top, 5)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - StatusIndicatorView (Sub-view for MainView)
struct StatusIndicatorView: View {
    let label: String
    let isOn: Bool
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(isOn ? AppTheme.positiveColor : AppTheme.negativeColor).frame(width: 8, height: 8)
            Text(label).foregroundColor(isOn ? AppTheme.positiveColor : AppTheme.negativeColor)
            Text(isOn ? "On" : "Off").foregroundColor(.secondary)
        }
    }
}

// MARK: - MessageView (Sub-view for MainView)
struct MessageView: View {
    let message: String
    enum MessageType { case info, error, warning }
    let type: MessageType
    
    private var fgColor: Color {
        switch type {
        case .info: return AppTheme.infoColor
        case .error: return AppTheme.negativeColor
        case .warning: return AppTheme.warningColor
        }
    }
    var body: some View {
        Text(message).font(.caption).foregroundColor(fgColor)
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(fgColor.opacity(0.1)).cornerRadius(6)
    }
}

// MARK: - MyEncounterCardView (Card Display View)
struct MyEncounterCardView: View {
    let card: EncounterCard
    private let drawingDisplayMaxHeight: CGFloat = 150 // Or your preferred height
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let drawingUiImage = card.drawingImage {
                Image(uiImage: drawingUiImage).resizable().scaledToFit()
                    .frame(maxWidth: .infinity).frame(maxHeight: drawingDisplayMaxHeight)
                    .background(Color.gray.opacity(0.1)).cornerRadius(8).padding(.bottom, 5)
            } else {
                HStack {
                    Spacer()
                    VStack {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.largeTitle)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No Drawing Yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity).frame(height: drawingDisplayMaxHeight / 1.5)
                .background(Color.gray.opacity(0.05)).cornerRadius(8).padding(.bottom, 5)
            }
            
            HStack(spacing: 15) {
                Image(systemName: card.avatarSymbolName).font(.system(size: 44)).foregroundColor(AppTheme.primaryColor)
                    .frame(width: 50, height: 50).background(AppTheme.primaryColor.opacity(0.1)).clipShape(Circle())
                VStack(alignment: .leading) {
                    Text(card.displayName).font(.title3).fontWeight(.bold)
                    Text("\"\(card.statusMessage)\"").font(.footnote).italic().foregroundColor(.secondary).lineLimit(3)
                }
            }
            // Using the file-local `trimming` extension on String
            if let t1 = card.flairField1Title, let v1 = card.flairField1Value, !t1.trimming.isEmpty || !v1.trimming.isEmpty { FlairDisplayRow(title: t1, value: v1) } // FlairDisplayRow defined below
            if let t2 = card.flairField2Title, let v2 = card.flairField2Value, !t2.trimming.isEmpty || !v2.trimming.isEmpty { FlairDisplayRow(title: t2, value: v2) } // FlairDisplayRow defined below
            Divider().padding(.vertical, 2)
            HStack { Text("ID: \(card.userID.prefix(8))..."); Spacer(); Text("Schema v\(card.cardSchemaVersion)") }
            .font(.caption2).foregroundColor(.gray)
            Text("Updated: \(card.lastUpdated, style: .relative) ago").font(.caption2).foregroundColor(.gray)
        }
        .padding().background(AppTheme.cardBackgroundColor).cornerRadius(10).shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}

// MARK: - FlairDisplayRow (Card Display View)
struct FlairDisplayRow: View {
    let title: String?
    let value: String?
    var body: some View {
        // Using the file-local `trimming` extension on String
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
           let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            HStack(alignment: .top) {
                Text(t + ":").font(.caption).fontWeight(.semibold).foregroundColor(AppTheme.secondaryColor)
                Text(v).font(.caption).foregroundColor(.primary)
            }
        } else if let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
             Text(v).font(.caption).italic().foregroundColor(.primary)
        } else { EmptyView() }
    }
}

// MARK: - ReceivedEncounterCardRowView (Card Display View)
struct ReceivedEncounterCardRowView: View {
    let card: EncounterCard
    private let drawingThumbnailSize: CGFloat = 50
    var body: some View {
        let userColor = AppTheme.userSpecificColor(for: card.userID)
        HStack(spacing: 12) {
            if let img = card.drawingImage {
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: drawingThumbnailSize, height: drawingThumbnailSize)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: card.avatarSymbolName).font(.title)
                    .frame(width: drawingThumbnailSize, height: drawingThumbnailSize)
                    .foregroundColor(userColor).background(userColor.opacity(0.2)).clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(card.displayName).font(.headline).fontWeight(.semibold)
                Text(card.statusMessage).font(.caption).foregroundColor(.secondary).lineLimit(2)
                // Using the file-local `trimming` extension on String
                if let t = card.flairField1Title, let v = card.flairField1Value, !t.trimming.isEmpty || !v.trimming.isEmpty {
                     Text("\(t.isEmpty ? "" : t + ": ")\(v)").font(.caption2).foregroundColor(userColor.opacity(0.9)).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - EncounterCardEditorView (Card Editor)
struct EncounterCardEditorView: View {
    @Binding var card: EncounterCard
    var onOpenDrawingEditor: () -> Void
    var onRemoveDrawing: () -> Void
    
    // Ensure this list matches your original full list of avatar options
    private let avatarOptions: [String] = [
        "person.fill", "person.crop.circle.fill", "face.smiling.fill", "star.fill",
        "heart.fill", "gamecontroller.fill", "music.note", "book.fill",
        "figure.walk", "pawprint.fill", "leaf.fill", "airplane", "car.fill",
        "desktopcomputer", "paintbrush.pointed.fill", "camera.fill", "gift.fill",
        "network", "globe.americas.fill", "sun.max.fill", "moon.stars.fill",
        "cloud.sleet.fill", "message.fill", "briefcase.fill", "studentdesk"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                Text("Card Drawing").font(.callout).fontWeight(.medium)
                if let img = card.drawingImage {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 120)
                        .background(Color.secondary.opacity(0.1)).cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                        .padding(.bottom, 5)
                } else {
                    Text("No drawing. Tap below to create one.").font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60).padding()
                        .background(Color.secondary.opacity(0.05)).cornerRadius(6).padding(.bottom, 5)
                }
                HStack {
                    Button(action: onOpenDrawingEditor) { Label(card.drawingData == nil ? "Draw Card" : "Edit Drawing", systemImage: "paintbrush.pointed.fill") }
                    .buttonStyle(.bordered).tint(AppTheme.primaryColor)
                    if card.drawingData != nil { Spacer(); Button(action: onRemoveDrawing) { Label("Remove", systemImage: "xmark.circle") }.buttonStyle(.bordered).tint(AppTheme.negativeColor) }
                }
            }
            Divider()
            Text("Text Details").font(.callout).fontWeight(.medium)
            TextField("Display Name", text: $card.displayName, prompt: Text("Your Public Name"))
            VStack(alignment: .leading, spacing: 4) {
                Text("Status Message (max 150 chars)").font(.caption).foregroundColor(.gray)
                TextEditor(text: $card.statusMessage).frame(height: 70).clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                Text("\(card.statusMessage.count) / 150").font(.caption2).foregroundColor(card.statusMessage.count > 150 ? AppTheme.negativeColor : .gray)
            }
            Picker("Avatar Icon (Fallback)", selection: $card.avatarSymbolName) {
                ForEach(avatarOptions, id: \.self) { symbol in
                    HStack { Image(systemName: symbol).frame(width: 25, alignment: .center); Text(symbol.split(separator: ".").map{ $0.capitalized }.joined(separator: " ").replacingOccurrences(of: "Fill", with: "")) }.tag(symbol)
                }
            }
            Text("Avatar shown if no drawing exists or in compact views.").font(.caption2).foregroundColor(.gray)
            
            // FlairEditorSection is defined as a nested struct below
            FlairEditorSection(
                titleBinding1: titleBinding(for: \.flairField1Title),
                valueBinding1: valueBinding(for: \.flairField1Value),
                titleBinding2: titleBinding(for: \.flairField2Title),
                valueBinding2: valueBinding(for: \.flairField2Value)
            )
        }
        .textFieldStyle(.roundedBorder)
    }

    // Nested struct for Flair Editor
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

    // Helper bindings, defined ONCE within EncounterCardEditorView
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
} // End of EncounterCardEditorView


// MARK: - Previews
struct StreetPass_MainView_Previews: PreviewProvider {
    static var previews: some View {
        let previewVM = StreetPassViewModel(userID: "previewUser123")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 150))
        
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: UIColor.white]

        let sampleDrawing = renderer.image { ctx in
            UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 150))
            ("Sample Drawing" as NSString).draw(with: CGRect(x: 20, y: 60, width: 160, height: 30), options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
        }
        previewVM.bleManager.localUserCard.displayName = "My Drawn Card Preview" // Changed for clarity
        previewVM.bleManager.localUserCard.statusMessage = "This is my card with a drawing!"
        previewVM.bleManager.localUserCard.drawingData = sampleDrawing.pngData()
        previewVM.bleManager.localUserCard.flairField1Title = "Mood"; previewVM.bleManager.localUserCard.flairField1Value = "Creative!"

        var sampleCard1 = EncounterCard(userID: "userA", displayName: "Artist Anna", statusMessage: "Drawing all day", avatarSymbolName: "paintbrush.fill")
        sampleCard1.flairField1Title = "Tool"; sampleCard1.flairField1Value = "iPad & Pencil"
        let anotherDrawing = renderer.image { ctx in UIColor.systemGreen.setFill(); ctx.fill(CGRect(x:0,y:0,width:200,height:150)); ("Hi!" as NSString).draw(at: CGPoint(x:80, y:60), withAttributes: attrs)}
        sampleCard1.drawingData = anotherDrawing.jpegData(compressionQuality: 0.7)

        var sampleCard2 = EncounterCard(userID: "userB", displayName: "Text Tom", statusMessage: "Old school, text only!", avatarSymbolName: "text.bubble.fill")
        previewVM.bleManager.receivedCards = [sampleCard1, sampleCard2]
        previewVM.bleManager.isBluetoothPoweredOn = true; previewVM.bleManager.isScanning = true
        
        // To preview the editor already open:
        // previewVM.isEditingMyCard = true
        // previewVM.prepareCardForEditing() // This makes sure cardForEditor is current for the preview
        
        return StreetPass_MainView(viewModel: previewVM)
    }
}

// File-local String extension helper for trimming, used by views in this file
fileprivate extension String {
    var trimming: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

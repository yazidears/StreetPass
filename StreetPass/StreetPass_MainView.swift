import SwiftUI

struct StreetPass_MainView: View {
    @StateObject var viewModel: StreetPassViewModel

    private func formattedEncountersSectionHeader() -> String {
        if viewModel.recentlyEncounteredCards.isEmpty {
            return "Recent Encounters"
        } else {
            return "Recent Encounters (\(viewModel.recentlyEncounteredCards.count))"
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    MyEncounterCardView(card: viewModel.myCurrentCard)

                    Button(viewModel.isEditingMyCard ? "Manage My Card" : "Edit My Card") {
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
                        EncounterCardEditorView(
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
                    .transition(.asymmetric(insertion: .offset(y: -15).combined(with: .opacity), removal: .offset(y: -15).combined(with: .opacity)))
                }

                Section("System Controls") {
                    StreetPassControlsView(viewModel: viewModel)

                    if let errorMsg = viewModel.lastErrorMessage {
                        MessageView(message: errorMsg, type: .error)
                    } else if let infoMsg = viewModel.lastInfoMessage {
                        MessageView(message: infoMsg, type: .info)
                    }
                }

                Section(formattedEncountersSectionHeader()) {
                    if viewModel.recentlyEncounteredCards.isEmpty {
                        Text("No cards received yet. Activate StreetPass and explore!")
                            .foregroundColor(.secondary)
                            .padding()
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(viewModel.recentlyEncounteredCards) { card in
                            ReceivedEncounterCardRowView(card: card)
                                .padding(.vertical, 2)
                        }
                    }
                }

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
            .animation(.easeInOut(duration: 0.3), value: viewModel.isEditingMyCard)
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
            DrawingEditorSheetView(
                isPresented: $viewModel.isDrawingSheetPresented,
                cardDrawingData: $viewModel.cardForEditor.drawingData
            )
            .interactiveDismissDisabled()
        }
    }
}

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
                StatusIndicatorView(label: "Bluetooth", isOn: viewModel.isBluetoothOn); Spacer()
                StatusIndicatorView(label: "Scanning", isOn: viewModel.isScanningActive); Spacer()
                StatusIndicatorView(label: "Advertising", isOn: viewModel.isAdvertisingActive)
            }
            .font(.footnote).padding(.top, 5)
        }
        .padding(.vertical, 8)
    }
}

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

struct MyEncounterCardView: View {
    let card: EncounterCard
    private let drawingDisplayMaxHeight: CGFloat = 150

    private func shouldShowFlairSection() -> Bool {
        let f1t = card.flairField1Title?.trimming ?? ""
        let f1v = card.flairField1Value?.trimming ?? ""
        let f2t = card.flairField2Title?.trimming ?? ""
        let f2v = card.flairField2Value?.trimming ?? ""
        return !f1t.isEmpty || !f1v.isEmpty || !f2t.isEmpty || !f2v.isEmpty
    }

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

            if shouldShowFlairSection() {
                if let t1 = card.flairField1Title, let v1 = card.flairField1Value, !t1.trimming.isEmpty || !v1.trimming.isEmpty { FlairDisplayRow(title: t1, value: v1) }
                if let t2 = card.flairField2Title, let v2 = card.flairField2Value, !t2.trimming.isEmpty || !v2.trimming.isEmpty { FlairDisplayRow(title: t2, value: v2) }
            }

            Divider().padding(.vertical, 2)
            HStack { Text("ID: \(card.userID.prefix(8))..."); Spacer(); Text("Schema v\(card.cardSchemaVersion)") }
            .font(.caption2).foregroundColor(.gray)
            Text("Updated: \(card.lastUpdated, style: .relative) ago").font(.caption2).foregroundColor(.gray)
        }
        .padding().background(AppTheme.cardBackgroundColor).cornerRadius(10).shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}

struct FlairDisplayRow: View {
    let title: String?
    let value: String?
    var body: some View {
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
            VStack(alignment: .leading, spacing: 2) {
                Text(card.displayName).font(.headline).fontWeight(.semibold)
                Text(card.statusMessage).font(.caption).foregroundColor(.secondary).lineLimit(2)
                if let t = card.flairField1Title, let v = card.flairField1Value, !t.trimming.isEmpty || !v.trimming.isEmpty {
                     Text("\(t.isEmpty ? "" : t + ": ")\(v)").font(.caption2).foregroundColor(userColor.opacity(0.9)).lineLimit(1)
                }
                Text("Card updated: \(card.lastUpdated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

struct EncounterCardEditorView: View {
    @Binding var card: EncounterCard
    var onOpenDrawingEditor: () -> Void
    var onRemoveDrawing: () -> Void

    private let avatarOptions: [String] = [
        "person.fill", "person.crop.circle.fill", "face.smiling.fill", "star.fill",
        "heart.fill", "gamecontroller.fill", "music.note", "book.fill",
        "figure.walk", "pawprint.fill", "leaf.fill", "airplane", "car.fill",
        "desktopcomputer", "paintbrush.pointed.fill", "camera.fill", "gift.fill",
        "network", "globe.americas.fill", "sun.max.fill", "moon.stars.fill",
        "cloud.sleet.fill", "message.fill", "briefcase.fill", "studentdesk"
    ]

    private func isDisplayNameValid() -> Bool {
        return !card.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func characterCountColor(for count: Int, max: Int) -> Color {
        return count > max ? AppTheme.negativeColor : .gray
    }

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
                .overlay(
                    HStack {
                        Spacer()
                        if !isDisplayNameValid() {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppTheme.negativeColor)
                                .padding(.trailing, 8)
                        }
                    }
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Status Message (max 150 chars)").font(.caption).foregroundColor(.gray)
                TextEditor(text: $card.statusMessage).frame(height: 70).clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                Text("\(card.statusMessage.count) / 150").font(.caption2).foregroundColor(characterCountColor(for: card.statusMessage.count, max: 150))
            }
            Picker("Avatar Icon (Fallback)", selection: $card.avatarSymbolName) {
                ForEach(avatarOptions, id: \.self) { symbol in
                    HStack { Image(systemName: symbol).frame(width: 25, alignment: .center); Text(symbol.split(separator: ".").map{ $0.capitalized }.joined(separator: " ").replacingOccurrences(of: "Fill", with: "")) }.tag(symbol)
                }
            }
            Text("Avatar shown if no drawing exists or in compact views.").font(.caption2).foregroundColor(.gray)

            FlairEditorSection(
                titleBinding1: titleBinding(for: \.flairField1Title),
                valueBinding1: valueBinding(for: \.flairField1Value),
                titleBinding2: titleBinding(for: \.flairField2Title),
                valueBinding2: valueBinding(for: \.flairField2Value)
            )
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


struct StreetPass_MainView_Previews: PreviewProvider {
    static var previews: some View {
        let previewVM = StreetPassViewModel(userID: "previewUser123")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 150))

        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: UIColor.white]

        let sampleDrawing = renderer.image { ctx in
            UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 150))
            ("Sample Drawing" as NSString).draw(with: CGRect(x: 20, y: 60, width: 160, height: 30), options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
        }
        previewVM.bleManager.localUserCard.displayName = "My Drawn Card"
        previewVM.bleManager.localUserCard.statusMessage = "This is my card with a drawing!"
        previewVM.bleManager.localUserCard.drawingData = sampleDrawing.pngData()
        previewVM.bleManager.localUserCard.flairField1Title = "Mood"; previewVM.bleManager.localUserCard.flairField1Value = "Creative!"
        previewVM.bleManager.localUserCard.flairField2Title = "Project"; previewVM.bleManager.localUserCard.flairField2Value = "StreetPass App"


        var sampleCard1 = EncounterCard(userID: "userA", displayName: "Artist Anna", statusMessage: "Drawing all day", avatarSymbolName: "paintbrush.fill")
        sampleCard1.flairField1Title = "Tool"; sampleCard1.flairField1Value = "iPad & Pencil"
        let anotherDrawing = renderer.image { ctx in UIColor.systemGreen.setFill(); ctx.fill(CGRect(x:0,y:0,width:200,height:150)); ("Hi!" as NSString).draw(at: CGPoint(x:80, y:60), withAttributes: attrs)}
        sampleCard1.drawingData = anotherDrawing.jpegData(compressionQuality: 0.7)
        sampleCard1.lastUpdated = Calendar.current.date(byAdding: .minute, value: -5, to: Date())!


        var sampleCard2 = EncounterCard(userID: "userB", displayName: "Text Tom", statusMessage: "Old school, text only!", avatarSymbolName: "text.bubble.fill")
        sampleCard2.lastUpdated = Calendar.current.date(byAdding: .hour, value: -2, to: Date())!

        var sampleCard3 = EncounterCard(userID: "userC", displayName: "Newbie Nick", statusMessage: "Just joined!", avatarSymbolName: "figure.wave")
        sampleCard3.lastUpdated = Calendar.current.date(byAdding: .day, value: -1, to: Date())!


        previewVM.bleManager.receivedCards = [sampleCard1, sampleCard2, sampleCard3]
        previewVM.bleManager.isBluetoothPoweredOn = true; previewVM.bleManager.isScanning = true

        previewVM.prepareCardForEditing()

        return StreetPass_MainView(viewModel: previewVM)
    }
}

fileprivate extension String {
    var trimming: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
// i added a subtle animation for the card editor section appearing and disappearing
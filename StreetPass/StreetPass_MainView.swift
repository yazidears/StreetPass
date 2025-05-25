import SwiftUI

struct StreetPass_MainView: View {
    @StateObject var viewModel: StreetPassViewModel
    @State private var showingClearEncountersAlert: Bool = false

    @State private var searchText: String = ""
    @State private var sortOption: SortOption = .lastUpdatedDescending

    enum SortOption: String, CaseIterable, Identifiable {
        case lastUpdatedDescending = "Date (Newest First)"
        case lastUpdatedAscending = "Date (Oldest First)"
        case nameAscending = "Name (A-Z)"
        case nameDescending = "Name (Z-A)"

        var id: String { self.rawValue }
    }

    private var filteredAndSortedCards: [EncounterCard] {
        let filtered = viewModel.recentlyEncounteredCards.filter { card in
            if searchText.isEmpty {
                return true
            }
            let lowercasedSearchText = searchText.lowercased()
            return card.displayName.lowercased().contains(lowercasedSearchText) ||
                   card.statusMessage.lowercased().contains(lowercasedSearchText) ||
                   (card.flairField1Title?.lowercased().contains(lowercasedSearchText) ?? false) ||
                   (card.flairField1Value?.lowercased().contains(lowercasedSearchText) ?? false) ||
                   (card.flairField2Title?.lowercased().contains(lowercasedSearchText) ?? false) ||
                   (card.flairField2Value?.lowercased().contains(lowercasedSearchText) ?? false)
        }

        switch sortOption {
        case .lastUpdatedDescending:
            return filtered.sorted { $0.lastUpdated > $1.lastUpdated }
        case .lastUpdatedAscending:
            return filtered.sorted { $0.lastUpdated < $1.lastUpdated }
        case .nameAscending:
            return filtered.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        case .nameDescending:
            return filtered.sorted { $0.displayName.lowercased() > $1.displayName.lowercased() }
        }
    }

    private func encountersSectionHeaderView() -> some View {
        HStack {
            Text("Recent Encounters")
                .font(.headline)
                .foregroundColor(AppTheme.primaryColor)
            Spacer()
             if !viewModel.recentlyEncounteredCards.isEmpty {
                Menu {
                    Picker("Sort By", selection: $sortOption) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundColor(AppTheme.primaryColor)
                }
            }
        }
    }


    var body: some View {
        NavigationView {
            List {
                Section {
                    MyEncounterCardView(card: viewModel.myCurrentCard)
                        .padding(.vertical, 8)

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
                    .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .scale(scale: 0.95).combined(with: .opacity)))
                }

                Section("System Controls") {
                    StreetPassControlsView(viewModel: viewModel, showingClearAlert: $showingClearEncountersAlert)

                    if let errorMsg = viewModel.lastErrorMessage {
                        MessageView(message: errorMsg, type: .error)
                    } else if let infoMsg = viewModel.lastInfoMessage {
                        MessageView(message: infoMsg, type: .info)
                    }
                }

                Section {
                    if !viewModel.recentlyEncounteredCards.isEmpty {
                        TextField("Search encounters...", text: $searchText)
                            .padding(.vertical, 8)
                            .textFieldStyle(.roundedBorder)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    }

                    if viewModel.recentlyEncounteredCards.isEmpty {
                        Text("No cards received yet. Activate StreetPass and explore!")
                            .foregroundColor(.secondary)
                            .padding()
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    } else if filteredAndSortedCards.isEmpty {
                         VStack(alignment: .center, spacing: 8) {
                             Image(systemName: "magnifyingglass.circle")
                                 .font(.system(size: 40))
                                 .foregroundColor(.secondary.opacity(0.5))
                            Text("No Encounters Match")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(searchText.isEmpty ? "Try a different sort option." : "Try adjusting your search or sort criteria.")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(filteredAndSortedCards) { card in
                            NavigationLink(destination: ReceivedCardDetailView(card: card)) {
                                ReceivedEncounterCardRowView(card: card)
                            }
                             .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 16))
                        }
                        if !searchText.isEmpty || sortOption != .lastUpdatedDescending {
                            HStack {
                                Spacer()
                                Text("Showing \(filteredAndSortedCards.count) of \(viewModel.recentlyEncounteredCards.count) encounters")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Spacer()
                            }.padding(.vertical, 4)
                        }
                    }
                } header: {
                   encountersSectionHeaderView()
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
            .animation(.smooth(duration: 0.35), value: viewModel.isEditingMyCard)
            .animation(.default, value: filteredAndSortedCards)
            .navigationTitle("StreetPass")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.insetGrouped)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Image(systemName: "wave.3.left.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.primaryColor.gradient)
                }
                 ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Text(viewModel.myCurrentCard.userID.prefix(6))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .background(Material.ultraThin)
                        .clipShape(Capsule())
                }
            }
            .refreshable { viewModel.refreshUIDataFromPull() }
            .background(AppTheme.backgroundColor.edgesIgnoringSafeArea(.all))
            .alert("Confirm Clear", isPresented: $showingClearEncountersAlert) {
                Button("Clear All Encounters", role: .destructive) {
                    viewModel.clearAllEncounteredCards()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete all encountered cards? This action cannot be undone.")
            }
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

struct CardSectionHeader: View {
    let title: String
    let systemImage: String?

    var body: some View {
        HStack {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .foregroundColor(AppTheme.secondaryColor)
            }
            Text(title)
                .font(.headline)
                .foregroundColor(AppTheme.primaryColor)
            Spacer()
        }
        .padding(.bottom, 4)
    }
}

struct CardDetailSection<Content: View>: View {
    let title: String
    let systemImage: String?
    @ViewBuilder let content: Content

    init(title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardSectionHeader(title: title, systemImage: systemImage)
            content
        }
        .padding()
        .background(AppTheme.cardBackgroundColor)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 3)
    }
}


struct ReceivedCardDetailView: View {
    let card: EncounterCard
    private let drawingDisplayMaxHeight: CGFloat = 250
    private let userColor: Color

    init(card: EncounterCard) {
        self.card = card
        self.userColor = AppTheme.userSpecificColor(for: card.userID)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let drawingUiImage = card.drawingImage {
                    Image(uiImage: drawingUiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: drawingDisplayMaxHeight)
                        .background(Color.white)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(userColor.opacity(0.5), lineWidth: 2)
                        )
                        .shadow(color: userColor.opacity(0.3), radius: 6, x: 0, y: 4)
                        .padding(.horizontal)
                } else {
                    VStack {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 60))
                            .foregroundColor(userColor.opacity(0.6))
                        Text("No Drawing Shared")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(userColor.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, minHeight: drawingDisplayMaxHeight * 0.6)
                    .background(userColor.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }

                VStack(spacing: 10) {
                    Image(systemName: card.avatarSymbolName)
                        .font(.system(size: 60))
                        .padding(15)
                        .foregroundColor(userColor)
                        .background(userColor.opacity(0.15).gradient)
                        .clipShape(Circle())
                        .shadow(color: userColor.opacity(0.3), radius: 5, x:0, y:3)

                    Text(card.displayName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)

                    Text("\"\(card.statusMessage)\"")
                        .font(.title3)
                        .italic()
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                .padding(.horizontal)

                if card.flairField1Title != nil || card.flairField1Value != nil || card.flairField2Title != nil || card.flairField2Value != nil {
                    CardDetailSection(title: "Flair", systemImage: "sparkles") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let t1 = card.flairField1Title, let v1 = card.flairField1Value, !t1.trimming.isEmpty || !v1.trimming.isEmpty {
                                FlairDisplayRow(title: t1, value: v1, icon: "rosette", iconColor: userColor)
                            }
                            if (card.flairField1Title != nil || card.flairField1Value != nil) && (card.flairField2Title != nil || card.flairField2Value != nil) {
                                 Divider().padding(.vertical, 4)
                            }
                            if let t2 = card.flairField2Title, let v2 = card.flairField2Value, !t2.trimming.isEmpty || !v2.trimming.isEmpty {
                                FlairDisplayRow(title: t2, value: v2, icon: "star.circle", iconColor: userColor)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                CardDetailSection(title: "Card Info", systemImage: "info.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "person.text.rectangle").foregroundColor(userColor)
                            Text("User ID: \(card.userID)")
                                .font(.caption).foregroundColor(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        HStack {
                             Image(systemName: "number.square").foregroundColor(userColor)
                             Text("Schema Version: \(card.cardSchemaVersion)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        HStack {
                             Image(systemName: "clock.arrow.circlepath").foregroundColor(userColor)
                             Text("Last Updated by User: \(card.lastUpdated, style: .datetime)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
                Spacer(minLength: 20)
            }
            .padding(.top)
        }
        .background(Color(UIColor.systemGray6).edgesIgnoringSafeArea(.all))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
             ToolbarItem(placement: .principal) {
                HStack {
                    Image(systemName: card.avatarSymbolName).foregroundColor(userColor)
                    Text(card.displayName).font(.headline)
                }
            }
        }
    }
}


struct StreetPassControlsView: View {
    @ObservedObject var viewModel: StreetPassViewModel
    @Binding var showingClearAlert: Bool
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
                Button { showingClearAlert = true } label: {
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
    private let drawingDisplayMaxHeight: CGFloat = 180

    private func shouldShowFlairSection() -> Bool {
        let f1t = card.flairField1Title?.trimming ?? ""
        let f1v = card.flairField1Value?.trimming ?? ""
        let f2t = card.flairField2Title?.trimming ?? ""
        let f2v = card.flairField2Value?.trimming ?? ""
        return !f1t.isEmpty || !f1v.isEmpty || !f2t.isEmpty || !f2v.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                if let drawingUiImage = card.drawingImage {
                    Image(uiImage: drawingUiImage).resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: drawingDisplayMaxHeight)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.black.opacity(0.4), Color.clear, Color.clear]),
                                startPoint: .bottom,
                                endPoint: .center
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        )
                } else {
                     RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.primaryColor.opacity(0.1).gradient)
                        .frame(maxWidth: .infinity).frame(height: drawingDisplayMaxHeight * 0.6)
                        .overlay(
                            VStack {
                                Image(systemName: "swirl.circle.righthalf.filled")
                                    .font(.system(size: 40))
                                    .foregroundColor(AppTheme.primaryColor.opacity(0.7))
                                Text("Your Drawing Shows Here")
                                    .font(.callout)
                                    .foregroundColor(AppTheme.primaryColor.opacity(0.9))
                            }
                        )
                }

                HStack {
                    Image(systemName: card.avatarSymbolName).font(.system(size: 30)).foregroundColor(.white)
                        .padding(8)
                        .background(AppTheme.primaryColor.opacity(0.7))
                        .clipShape(Circle())
                        .shadow(radius: 3)

                    Text(card.displayName).font(.title2).fontWeight(.bold).foregroundColor(.white)
                        .shadow(radius: 3)
                }
                .padding(12)
            }

            Text("\"\(card.statusMessage)\"").font(.callout).italic().foregroundColor(.secondary).lineLimit(3)
                .padding(.horizontal, 4)

            if shouldShowFlairSection() {
                 VStack(alignment: .leading, spacing: 6) {
                    if let t1 = card.flairField1Title, let v1 = card.flairField1Value, !t1.trimming.isEmpty || !v1.trimming.isEmpty { FlairDisplayRow(title: t1, value: v1) }
                    if let t2 = card.flairField2Title, let v2 = card.flairField2Value, !t2.trimming.isEmpty || !v2.trimming.isEmpty { FlairDisplayRow(title: t2, value: v2) }
                 }
                 .padding(.horizontal, 4)
            }

            Divider()
            HStack {
                Text("My ID: \(card.userID.prefix(8))...").font(.caption2).foregroundColor(.gray)
                Spacer()
                Text("Card Updated: \(card.lastUpdated, style: .relative) ago").font(.caption2).foregroundColor(.gray)
            }
            .padding(.horizontal, 4)
        }
        .padding()
        .background(AppTheme.cardBackgroundColor)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 4)
    }
}

struct FlairDisplayRow: View {
    let title: String?
    let value: String?
    var icon: String? = nil
    var iconColor: Color = AppTheme.secondaryColor

    var body: some View {
        Group {
            if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
               let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    if let icon = icon {
                         Image(systemName: icon).foregroundColor(iconColor.opacity(0.8)).frame(width: 20)
                    }
                    Text(t + ":").font(.callout).fontWeight(.medium).foregroundColor(AppTheme.secondaryColor)
                    Text(v).font(.callout).foregroundColor(.primary).multilineTextAlignment(.leading)
                    Spacer()
                }
            } else if let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    if let icon = icon {
                        Image(systemName: icon).foregroundColor(iconColor.opacity(0.8)).frame(width:20)
                    }
                    Text(v).font(.callout).italic().foregroundColor(.primary).multilineTextAlignment(.leading)
                    Spacer()
                }
            } else { EmptyView() }
        }
    }
}


struct ReceivedEncounterCardRowView: View {
    let card: EncounterCard
    private let drawingThumbnailSize: CGFloat = 55
    var body: some View {
        let userColor = AppTheme.userSpecificColor(for: card.userID)
        HStack(spacing: 15) {
            Group {
                if let img = card.drawingImage {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: drawingThumbnailSize, height: drawingThumbnailSize)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 2)
                } else {
                    Image(systemName: card.avatarSymbolName).font(.system(size: 28))
                        .frame(width: drawingThumbnailSize, height: drawingThumbnailSize)
                        .foregroundColor(userColor)
                        .background(userColor.opacity(0.15).gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 2)
                }
            }
            .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(card.displayName).font(.headline).fontWeight(.semibold)
                    .lineLimit(1)
                Text(card.statusMessage).font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.tail)

                HStack(spacing: 4) {
                    Image(systemName: "clock.fill").font(.caption2).foregroundColor(.gray.opacity(0.7))
                    Text("\(card.lastUpdated, style: .relative)")
                    .font(.caption2)
                    .foregroundColor(.gray)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.secondary.opacity(0.5))
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
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 225))

        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 28), .foregroundColor: UIColor.white]

        let sampleDrawing = renderer.image { ctx in
            UIColor.systemIndigo.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 225))
            let path = UIBezierPath(roundedRect: CGRect(x:10, y:10, width: 280, height: 205), cornerRadius: 12)
            UIColor.white.withAlphaComponent(0.2).setStroke()
            path.lineWidth = 5
            path.stroke()
            ("Modern UI" as NSString).draw(with: CGRect(x: 50, y: 90, width: 200, height: 40), options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
        }
        previewVM.bleManager.localUserCard.displayName = "Designer Dave"
        previewVM.bleManager.localUserCard.statusMessage = "Crafting beautiful interfaces and seamless experiences for all!"
        previewVM.bleManager.localUserCard.drawingData = sampleDrawing.pngData()
        previewVM.bleManager.localUserCard.avatarSymbolName = "paintbrush.fill"
        previewVM.bleManager.localUserCard.flairField1Title = "Software"; previewVM.bleManager.localUserCard.flairField1Value = "SwiftUI, Figma"
        previewVM.bleManager.localUserCard.flairField2Title = "Likes"; previewVM.bleManager.localUserCard.flairField2Value = "Clean Code, Good Coffee, Pixel Perfection"


        var sampleCard1 = EncounterCard(userID: "userA", displayName: "Artist Anna", statusMessage: "Drawing all day and exploring the world of digital art!", avatarSymbolName: "camera.macro")
        sampleCard1.flairField1Title = "Tool"; sampleCard1.flairField1Value = "iPad & Pencil"
        sampleCard1.flairField2Title = "Inspiration"; sampleCard1.flairField2Value = "Nature, Dreams, Technology"
        let anotherDrawing = renderer.image { ctx in
            let gradColors = [UIColor.systemPink.cgColor, UIColor.systemPurple.cgColor]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors as CFArray, locations: [0.0, 1.0])!
            ctx.cgContext.drawLinearGradient(gradient, start: CGPoint.zero, end: CGPoint(x:0, y:225), options: [])
             ("Art <3" as NSString).draw(at: CGPoint(x:100, y:90), withAttributes: attrs)
        }
        sampleCard1.drawingData = anotherDrawing.jpegData(compressionQuality: 0.8)
        sampleCard1.lastUpdated = Calendar.current.date(byAdding: .minute, value: -15, to: Date())!


        var sampleCard2 = EncounterCard(userID: "userB", displayName: "Gamer Greg", statusMessage: "Always up for a co-op adventure or a competitive match. What are you playing?", avatarSymbolName: "gamecontroller.fill")
        sampleCard2.flairField1Title = "Favorite Genres"; sampleCard2.flairField1Value = "RPG, Strategy, Indie"
        sampleCard2.flairField2Title = "Current Game"; sampleCard2.flairField2Value = "CyberQuest X"
        sampleCard2.lastUpdated = Calendar.current.date(byAdding: .hour, value: -3, to: Date())!

        var sampleCard3 = EncounterCard(userID: "userC", displayName: "Explorer Eve", statusMessage: "Just joined! Excited to meet everyone and share travel stories.", avatarSymbolName: "map.fill")
        sampleCard3.lastUpdated = Calendar.current.date(byAdding: .day, value: -2, to: Date())!

        var sampleCard4 = EncounterCard(userID: "userD", displayName: "Zen Zack", statusMessage: "Mindfulness and meditation. Finding peace in the everyday.", avatarSymbolName: "timelapse")
        sampleCard4.flairField1Title = "Practice"; sampleCard4.flairField1Value = "Vipassanā"
        sampleCard4.lastUpdated = Calendar.current.date(byAdding: .hour, value: -1, to: Date())!



        previewVM.bleManager.receivedCards = [sampleCard1, sampleCard2, sampleCard3, sampleCard4].sorted(by: { $0.lastUpdated > $1.lastUpdated })
        previewVM.bleManager.isBluetoothPoweredOn = true; previewVM.bleManager.isScanning = true

        previewVM.prepareCardForEditing()

        return Group {
            StreetPass_MainView(viewModel: previewVM)
                .previewDisplayName("Main View (Filtering/Sorting)")

            NavigationView {
                ReceivedCardDetailView(card: sampleCard1)
            }.previewDisplayName("Received Card Detail (Anna)")

        }
    }
}

fileprivate extension String {
    var trimming: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
// i added filtering and sorting capabilities to the recent encounters list for improved usability

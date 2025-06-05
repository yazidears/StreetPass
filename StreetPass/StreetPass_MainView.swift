//
//  StreetPass_MainView.swift
//  StreetPass
//
//  Created by You on 2025/06/04.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Share Sheet (Used by Old UI)
struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Main View
struct StreetPass_MainView: View {
    @EnvironmentObject private var viewModel: StreetPassViewModel
    @State private var searchText: String = ""
    private let isForSwiftUIPreview: Bool

    @AppStorage("favorite_user_ids_json_v1") private var _appStorageFavoriteUserIDsJSON: String = "[]"
    private var favoriteUserIDs: Set<String> {
        get {
            if isForSwiftUIPreview {
                if let data = UserDefaults.standard
                    .string(forKey: "favorite_user_ids_json_v1")?
                    .data(using: .utf8),
                   let ids = try? JSONDecoder().decode(Set<String>.self, from: data) {
                    return ids
                }
                return ["userA_old"]
            }
            guard let data = _appStorageFavoriteUserIDsJSON.data(using: .utf8),
                  let ids = try? JSONDecoder().decode(Set<String>.self, from: data) else {
                return []
            }
            return ids
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue),
               let stringified = String(data: encoded, encoding: .utf8) {
                _appStorageFavoriteUserIDsJSON = stringified
            } else {
                _appStorageFavoriteUserIDsJSON = "[]"
            }
        }
    }


    private func cardMatchesSearchText(card: EncounterCard, lowercasedSearchText: String) -> Bool {
        if card.displayName.lowercased().contains(lowercasedSearchText) { return true }
        if card.statusMessage.lowercased().contains(lowercasedSearchText) { return true }
        if let f1 = card.flairField1Title?.lowercased(), f1.contains(lowercasedSearchText) { return true }
        if let v1 = card.flairField1Value?.lowercased(), v1.contains(lowercasedSearchText) { return true }
        if let f2 = card.flairField2Title?.lowercased(), f2.contains(lowercasedSearchText) { return true }
        if let v2 = card.flairField2Value?.lowercased(), v2.contains(lowercasedSearchText) { return true }
        return false
    }

    init(isForSwiftUIPreview: Bool = false) {
        self.isForSwiftUIPreview = isForSwiftUIPreview
    }

    var body: some View {
        // 1) Start by filtering & sorting early, outside of any Section
        let allCards = viewModel.recentlyEncounteredCards

        // 1a) Filter by search text if needed
        let lowercasedSearchText = searchText.trimming.lowercased()
        let filteredCards: [EncounterCard] = {
            guard !lowercasedSearchText.isEmpty else { return allCards }
            return allCards.filter { cardMatchesSearchText(card: $0, lowercasedSearchText: lowercasedSearchText) }
        }()

        // 2) Sort: Favorites first, then alphabetically by displayName
        let sortedCards = filteredCards.sorted { a, b in
            let aFav = favoriteUserIDs.contains(a.userID)
            let bFav = favoriteUserIDs.contains(b.userID)
            if aFav && !bFav { return true }
            if !aFav && bFav { return false }
            return a.displayName < b.displayName
        }

        return NavigationStack {
            mainContent(sortedCards: sortedCards)
        }
    }

    @ViewBuilder
    private func mainContent(sortedCards: [EncounterCard]) -> some View {
        VStack(spacing: 0) {
            headerSection()
            connectionsSection(sortedCards: sortedCards)
        }
        .background(AppTheme.backgroundColor)
    }

    @ViewBuilder
    private func headerSection() -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [AppTheme.spGradientStart, AppTheme.spGradientMid, AppTheme.spGradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 170)
                .ignoresSafeArea(edges: .top)

                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: viewModel.myCurrentCard.avatarSymbolName)
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.white.opacity(0.25))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hi, \(viewModel.greetingName.capitalized)!")
                            .font(.title.bold())
                            .foregroundColor(.white)

                        if viewModel.newCardsCountForBanner > 0 {
                            Text("You have \(viewModel.newCardsCountForBanner) new cards")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }

            searchBar

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: - Recent Cards Swapped Section
                    RecentCardsSwappedSectionView(
                        viewModel: viewModel,
                        primaryTextColor: AppTheme.primaryColor
                    ) {
                        viewModel.showInfoMessage("view all recent cards tapped!")
                    }

                    // MARK: - Status Section
                    StatusSectionView(viewModel: viewModel, primaryTextColor: AppTheme.primaryColor)

                    // MARK: - Draw / Edit My Card Button
                    Button("draw / edit my card") {
                        viewModel.prepareCardForEditing()
                        viewModel.openDrawingEditor()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.primaryColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding([.horizontal])
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.backgroundColor)
        }
        .navigationTitle("StreetPass")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.showInfoMessage("Settings tapped")
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(AppTheme.primaryColor)
                }
            }
        }
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack {
            TextField("Search encounters...", text: $searchText)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            if !searchText.isEmpty {
                Button(action: { self.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private func connectionsSection(sortedCards: [EncounterCard]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // MARK: - Connections List
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Connections")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Button(action: {
                        // Example: Show detailed listing
                    }) {
                        Text("See All")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.primaryColor)
                    }
                }
                .padding([.horizontal])

                ForEach(sortedCards) { card in
                    NavigationLink(destination:
                        ReceivedCardDetailView(
                            card: card,
                            isFavorite: favoriteUserIDs.contains(card.userID),
                            toggleFavoriteAction: {
                                changeFavorite(userID: card.userID)
                            }
                        )
                    ) {
                        HStack(spacing: 12) {
                            card.getPlaceholderDrawingView()
                                .frame(width: 50, height: 70)
                                .background(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.gray, lineWidth: 1)
                                )
                                .cornerRadius(6)
                                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.displayName)
                                    .font(.headline)
                                Text(card.statusMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if favoriteUserIDs.contains(card.userID) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal)
                        .background(AppTheme.spContentBackground)
                        .cornerRadius(10)
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
                    }
                    Divider()
                        .padding(.leading, 72)
                }
            }

            Spacer(minLength: 20)
        }
    }

    // Toggle favorite for a userID
    private func changeFavorite(userID: String) {
        var updated = favoriteUserIDs
        if updated.contains(userID) {
            updated.remove(userID)
        } else {
            updated.insert(userID)
        }
        if let encoded = try? JSONEncoder().encode(updated),
           let stringified = String(data: encoded, encoding: .utf8) {
            _appStorageFavoriteUserIDsJSON = stringified
        }
    }
}

// MARK: - RecentCardsSwappedSectionView
struct RecentCardsSwappedSectionView: View {
    @ObservedObject var viewModel: StreetPassViewModel
    let primaryTextColor: Color
    var onTapAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("recent cards swapped")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(primaryTextColor)
                Spacer()
                Button(action: onTapAll) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(primaryTextColor.opacity(0.7))
                }
            }
            .padding([.horizontal])

            let displayCards: [EncounterCard] = {
                if viewModel.recentlyEncounteredCards.isEmpty {
                    return [
                        EncounterCard.placeholderCard(drawingIdentifier: "s_squiggle"),
                        EncounterCard.placeholderCard(drawingIdentifier: "lines_and_block"),
                        EncounterCard.placeholderCard(drawingIdentifier: "flower_simple"),
                        EncounterCard.placeholderCard(drawingIdentifier: "smiley_face")
                    ]
                } else {
                    return Array(viewModel.recentlyEncounteredCards.prefix(4))
                }
            }()

            if displayCards.isEmpty {
                Text("no cards swapped yet…")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(displayCards) { card in
                            RecentCardItemView(card: card) {
                                viewModel.showInfoMessage("tapped on card id: \(card.id.uuidString.prefix(4))")
                            }
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical)
    }
}

// MARK: - RecentCardItemView
struct RecentCardItemView: View {
    let card: EncounterCard
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                card.getPlaceholderDrawingView()
                    .frame(width: 85, height: 120)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black, lineWidth: 2.5)
                    )
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)

                Circle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 10, height: 10)
            }
        }
    }
}

// MARK: - StatusSectionView
struct StatusSectionView: View {
    @ObservedObject var viewModel: StreetPassViewModel
    let primaryTextColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("status")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(primaryTextColor)

            HStack(spacing: 12) {
                StatusBoxView(
                    title: viewModel.isBluetoothOn ? "connected" : "offline",
                    subtitle: viewModel.isBluetoothOn ? "currently" : "check bluetooth",
                    mainColor: primaryTextColor
                )
                StatusBoxView(
                    title: "\(viewModel.recentlyEncounteredCards.count)",
                    subtitle: "connections",
                    mainColor: primaryTextColor
                )
                let adStatus = viewModel.isAdvertisingActive ? "on" : "off"
                let scanStatus = viewModel.isScanningActive ? "on" : "off"
                let spassStatus = (viewModel.isAdvertisingActive || viewModel.isScanningActive) ? "on" : "off"

                StatusBoxFullWidthView(
                    text: "advertising \(adStatus), scanning \(scanStatus), spass \(spassStatus)".lowercased(),
                    mainColor: primaryTextColor
                )
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
}

struct StatusBoxView: View {
    let title: String
    let subtitle: String
    let mainColor: Color

    var body: some View {
        VStack {
            Text(title.uppercased())
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(mainColor)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(mainColor.opacity(0.1))
        .cornerRadius(8)
    }
}

struct StatusBoxFullWidthView: View {
    let text: String
    let mainColor: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(mainColor)
            .padding()
            .frame(maxWidth: .infinity)
            .background(mainColor.opacity(0.05))
            .cornerRadius(8)
    }
}

// MARK: - ReceivedCardDetailView
struct ReceivedCardDetailView: View {
    let card: EncounterCard
    @State var isFavorite: Bool
    let toggleFavoriteAction: () -> Void

    private let drawingDisplayMaxHeight: CGFloat = 250
    private let userColor: Color

    init(
        card: EncounterCard,
        isFavorite: Bool,
        toggleFavoriteAction: @escaping () -> Void
    ) {
        self.card = card
        self._isFavorite = State(initialValue: isFavorite)
        self.toggleFavoriteAction = toggleFavoriteAction
        self.userColor = AppTheme.userSpecificColor(for: card.userID)
    }

    private var drawingSection: some View {
        Group {
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
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                drawingSection

                VStack(spacing: 10) {
                    Image(systemName: card.avatarSymbolName)
                        .font(.system(size: 60))
                        .padding(15)
                        .foregroundColor(userColor)
                        .background(userColor.opacity(0.15).gradient)
                        .clipShape(Circle())
                        .shadow(color: userColor.opacity(0.3), radius: 5, x: 0, y: 3)

                    Text(card.displayName)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(card.statusMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

                VStack(spacing: 8) {
                    if let t1 = card.flairField1Title,
                       let v1 = card.flairField1Value,
                       !t1.trimming.isEmpty || !v1.trimming.isEmpty {
                        FlairDisplayRow(title: t1, value: v1, icon: "rosette", iconColor: userColor)
                    }
                    if (card.flairField1Title != nil || card.flairField1Value != nil) &&
                       (card.flairField2Title != nil || card.flairField2Value != nil) {
                        Divider().padding(.vertical, 4)
                    }
                    if let t2 = card.flairField2Title,
                       let v2 = card.flairField2Value,
                       !t2.trimming.isEmpty || !v2.trimming.isEmpty {
                        FlairDisplayRow(title: t2, value: v2, icon: "star.circle", iconColor: userColor)
                    }
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "number.square")
                            .foregroundColor(userColor)
                        Text("Schema Version: \(card.cardSchemaVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(userColor)
                        // Changed `.datetime` to `.date`
                        Text("Last Updated by User: \(card.lastUpdated, style: .date)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                HStack {
                    Button {
                        toggleFavoriteAction()
                        self.isFavorite.toggle()
                    } label: {
                        Label(
                            isFavorite ? "Unfavorite" : "Favorite",
                            systemImage: isFavorite ? "star.fill" : "star"
                        )
                    }
                    .tint(isFavorite ? .yellow : AppTheme.primaryColor)

                    Spacer()

                    Button {
                        // Example action: share card
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .tint(AppTheme.primaryColor)
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle("Card Details")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    toggleFavoriteAction()
                    self.isFavorite.toggle()
                } label: {
                    Label(
                        isFavorite ? "Unfavorite" : "Favorite",
                        systemImage: isFavorite ? "star.fill" : "star"
                    )
                }
                .tint(isFavorite ? .yellow : AppTheme.primaryColor)
            }
        }
    }
}

// MARK: - FlairDisplayRow
struct FlairDisplayRow: View {
    let title: String
    let value: String
    let icon: String
    let iconColor: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Text(value)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

fileprivate extension String {
    var trimming: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


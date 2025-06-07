// StreetPass_MainView.swift
// this is the main screen, the whole damn thing.

import SwiftUI
import UniformTypeIdentifiers

struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

fileprivate class HapticManager {
    static let shared = HapticManager()
    private init() {}

    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

fileprivate struct PulsatingModifier: ViewModifier {
    @State private var isPulsing = false
    let active: Bool
    let duration: Double
    let minOpacity: Double
    let maxScale: Double

    func body(content: Content) -> some View {
        content
            .opacity(active && isPulsing ? minOpacity : 1.0)
            .scaleEffect(active && isPulsing ? maxScale : 1.0)
            .onChange(of: active, initial: true) { oldActive, newActive in
                if newActive {
                    isPulsing = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        withAnimation(Animation.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }
                } else {
                    withAnimation(.easeInOut(duration: duration / 2)) {
                        isPulsing = false
                    }
                }
            }
    }
}

fileprivate extension View {
    func pulsating(active: Bool, duration: Double = 1.2, minOpacity: Double = 0.5, maxScale: Double = 1.1) -> some View {
        self.modifier(PulsatingModifier(active: active, duration: duration, minOpacity: minOpacity, maxScale: maxScale))
    }
}

fileprivate struct GlassBackgroundModifier: ViewModifier {
    var cornerRadius: CGFloat
    var material: Material
    var strokeColor: Color
    var strokeWidth: CGFloat
    var customShadow: ShadowStyle

    enum ShadowStyle {
        case none
        case soft
        case medium
        case custom(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)
    }

    func body(content: Content) -> some View {
        let base = content
            .background(material)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(strokeColor, lineWidth: strokeWidth)
            )
        
        switch customShadow {
        case .none:
            return base.shadow(color: .clear, radius: 0, x: 0, y: 0)
        case .soft:
            return base.shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 2)
        case .medium:
            return base.shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        case .custom(let color, let radius, let x, let y):
            return base.shadow(color: color, radius: radius, x: x, y: y)
        }
    }
}

fileprivate extension View {
    func glassBackground(
        cornerRadius: CGFloat = 15,
        material: Material = AppTheme.glassMaterialThin,
        strokeColor: Color = AppTheme.glassBorder,
        strokeWidth: CGFloat = 1,
        shadow: GlassBackgroundModifier.ShadowStyle = .medium
    ) -> some View {
        self.modifier(GlassBackgroundModifier(cornerRadius: cornerRadius, material: material, strokeColor: strokeColor, strokeWidth: strokeWidth, customShadow: shadow))
    }
}


struct StreetPass_MainView: View {
    @EnvironmentObject private var viewModel: StreetPassViewModel
    @State private var searchText: String = ""
    private let isForSwiftUIPreview: Bool

    @State private var showHeaderAvatar = false
    @State private var showHeaderGreeting = false
    @State private var showMainContent = false
    @State private var scrollOffset: CGFloat = 0
    @State private var timeBasedGreeting: String = ""
    @State private var showResetAlert: Bool = false


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
        _timeBasedGreeting = State(initialValue: getTimeBasedGreetingLogic())
        print("streetpass_mainview: init happening! am i the problem?") // <-- this one
    }
    
    private func getTimeBasedGreetingLogic() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greetings: [String]

        switch hour {
        case 4..<7: // Early Morning (4 AM - 6:59 AM)
            greetings = [
                "Early bird, huh?", "Sun's barely up, good to see ya!", "Morning's quiet magic is here.",
                "Hope you've got coffee brewing!", "Dawn's breaking, how are you?", "A fresh start to the day!",
                "Quiet moments before the rush.", "Wishing you a peaceful morning."
            ]
        case 7..<12: // Morning (7 AM - 11:59 AM)
            greetings = [
                "Good mornin'!", "Hope your day's off to a great start!", "Bright morning to ya!",
                "What's the plan for today?", "Enjoying the morning vibes?", "Hello there, sunshine!",
                "May your coffee be strong today!", "Ready to seize the day?"
            ]
        case 12..<17: // Afternoon (12 PM - 4:59 PM)
            greetings = [
                "Good afternoon!", "Hope your afternoon is going well.", "How's the day treating you?",
                "Taking a break, or powering through?", "Afternoon vibes are in full swing!", "Sun's high, hope your spirits are too!",
                "Keep that energy up!", "Making the most of the afternoon?"
            ]
        case 17..<21: // Evening (5 PM - 8:59 PM)
            greetings = [
                "Good evening!", "How's the evening treating you?", "Winding down, or just getting started?",
                "Hope you had a wonderful day.", "Evening's here, time to relax a bit!", "The stars will be out soon.",
                "Enjoy the evening calm.", "What's cookin' tonight? Smells good!"
            ]
        default: // Late Night (9 PM - 3:59 AM)
            greetings = [
                "Burning the midnight oil?", "Late night explorer, I see.", "Hope you're having a peaceful night.",
                "The world's quiet now, isn't it?", "Sweet dreams, or more adventures ahead?", "Night owl greetings to you!",
                "Wishing you a restful night's journey.", "Almost tomorrow, or still today for you?"
            ]
        }
        return greetings.randomElement() ?? "Hello there!"
    }


    var body: some View {
        // this view doesn't decide what to show anymore. it just shows itself.
        // the logic is now up in streetpassapp.swift, where it belongs.
        // print("streetpass_mainview: body evaluating") // keep this for now, or remove if too noisy

        let allCards = viewModel.recentlyEncounteredCards
        let lowercasedSearchText = searchText.trimming.lowercased()
        let filteredCards: [EncounterCard] = {
            guard !lowercasedSearchText.isEmpty else { return allCards }
            return allCards.filter { cardMatchesSearchText(card: $0, lowercasedSearchText: lowercasedSearchText) }
        }()

        let sortedCards = filteredCards.sorted { a, b in
            let aFav = favoriteUserIDs.contains(a.userID)
            let bFav = favoriteUserIDs.contains(b.userID)
            if aFav && !bFav { return true }
            if !aFav && bFav { return false }
            return a.displayName.lowercased() < b.displayName.lowercased()
        }

        return NavigationStack {
            mainContent(sortedCards: sortedCards) // we'll simplify mainContent's onAppear animations next if needed
                .background(AppTheme.backgroundColor.ignoresSafeArea())
                // .background(DeviceShakeView()) // <-- temporarily commented out
                .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                    print("streetpass_mainview: device did shake notification received")
                    showResetAlert = true
                }
                .alert("Reset StreetPass?", isPresented: $showResetAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) { viewModel.resetAllData() }
                } message: {
                    Text("This will erase all data and restart StreetPass.")
                }
                .onAppear {
                    print("streetpass_mainview: main body .onappear triggered")
                    timeBasedGreeting = getTimeBasedGreetingLogic()
                    // initial animations are a common source of startup lag.
                    // let's disable them for a sec to see if the core view loads.
                    // if this works, we can re-enable them more carefully, maybe with a slight delay.
                    
                    // withAnimation(.interpolatingSpring(stiffness: 100, damping: 12).delay(0.1)) {
                    //     showHeaderAvatar = true
                    // }
                    // withAnimation(.interpolatingSpring(stiffness: 100, damping: 12).delay(0.25)) {
                    //     showHeaderGreeting = true
                    // }
                    // withAnimation(.interpolatingSpring(stiffness: 100, damping: 15).delay(0.4)) {
                    //      showMainContent = true
                    // }
                    
                    // instead, set them directly for now
                    showHeaderAvatar = true
                    showHeaderGreeting = true
                    showMainContent = true
                    print("streetpass_mainview: onappear - flags set directly (no animation)")
                }
        }
    }

    @ViewBuilder
    private func mainContent(sortedCards: [EncounterCard]) -> some View {
        ScrollViewOffsetTracker(scrollOffset: $scrollOffset) {
            ScrollView {
                VStack(spacing: 0) {
                    headerSection()
                    
                    searchBar
                        .padding(.top, -30)
                        .zIndex(1)
                        .opacity(showMainContent ? 1 : 0)
                        .offset(y: showMainContent ? 0 : 20)
                        .animation(.interpolatingSpring(stiffness: 100, damping: 15).delay(showMainContent ? 0.1 : 0.4), value: showMainContent)

                    LazyVStack(alignment: .leading, spacing: 24) {
                        RecentCardsSwappedSectionView(
                            viewModel: viewModel
                        ) {
                            viewModel.showInfoMessage("view all recent cards tapped!")
                            HapticManager.shared.impact(style: .light)
                        }

                        StatusSectionView(viewModel: viewModel)

                        Button {
                            viewModel.prepareCardForEditing()
                            viewModel.openDrawingEditor()
                            HapticManager.shared.impact(style: .medium)
                        } label: {
                            Label("Draw / Edit My Card", systemImage: "pencil.and.scribble")
                                .font(.headline.weight(.semibold))
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(AppTheme.spAccentYellow)
                                .foregroundColor(AppTheme.spPrimaryText)
                                .cornerRadius(12)
                                .shadow(color: AppTheme.spAccentYellow.opacity(0.5), radius: 8, y: 4)
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                        .buttonStyle(ScaleDownButtonStyle(scaleFactor: 0.95, opacityFactor: 0.9))
                        
                        connectionsSection(sortedCards: sortedCards)
                    }
                    .padding(.top)
                    .opacity(showMainContent ? 1 : 0)
                    .offset(y: showMainContent ? 0 : 20)
                    .animation(.interpolatingSpring(stiffness: 100, damping: 15).delay(showMainContent ? 0.2 : 0.4), value: showMainContent)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func headerSection() -> some View {
        let parallaxFactor: CGFloat = 0.3
        let headerHeight: CGFloat = 200
        let dynamicHeight = max(headerHeight, headerHeight - scrollOffset * parallaxFactor)
        
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [AppTheme.spGradientStart, AppTheme.spGradientMid, AppTheme.spGradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: dynamicHeight)
                .clipShape(RoundedCornersShape(corners: [.bottomLeft, .bottomRight], radius: 30))
                .shadow(color: AppTheme.spGradientEnd.opacity(0.6), radius: 12, y: 6)
                .offset(y: scrollOffset > 0 ? -scrollOffset * parallaxFactor : 0)

                HStack(alignment: .center, spacing: 15) {
                    Image(systemName: viewModel.myCurrentCard.avatarSymbolName)
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                        .padding(15)
                        .background(
                            Circle().fill(Color.white.opacity(0.2))
                                .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                        )
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2))
                        .opacity(showHeaderAvatar ? 1 : 0)
                        .scaleEffect(showHeaderAvatar ? 1 : 0.7)
                        .offset(x: showHeaderAvatar ? 0 : -25, y: showHeaderAvatar ? 0 : 10)


                    VStack(alignment: .leading, spacing: 6) {
                        Text(timeBasedGreeting)
                            .font(.title.bold())
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)


                        if viewModel.newCardsCountForBanner > 0 {
                            Label("You have \(viewModel.newCardsCountForBanner) new cards", systemImage: "sparkles.square.filled.on.square")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(AppTheme.spAccentYellow)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(Color.black.opacity(0.35))
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        }
                    }
                    .opacity(showHeaderGreeting ? 1 : 0)
                    .offset(x: showHeaderGreeting ? 0 : -25)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 55)
                .offset(y: scrollOffset > 0 ? -scrollOffset * (parallaxFactor * 0.8) : 0)
            }
        }
        .frame(minHeight: headerHeight)
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppTheme.spSecondaryText)
            TextField("Search encounters...", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundColor(AppTheme.spPrimaryText)
            if !searchText.isEmpty {
                Button(action: { self.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.spSecondaryText.opacity(0.8))
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: searchText.isEmpty)
        .padding(12)
        .glassBackground(cornerRadius: 12, material: AppTheme.glassMaterialUltraThin, strokeColor: AppTheme.glassBorderSubtle, shadow: .soft)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func connectionsSection(sortedCards: [EncounterCard]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Encounters")
                    .font(.title2.bold())
                    .foregroundColor(AppTheme.spPrimaryText)
                Spacer()
                if !sortedCards.isEmpty {
                    Button(action: {
                        viewModel.showInfoMessage("See All Encounters tapped")
                        HapticManager.shared.impact(style: .light)
                    }) {
                        Text("See All")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(AppTheme.primaryColor)
                    }
                }
            }
            .padding(.horizontal)

            if sortedCards.isEmpty && searchText.isEmpty {
                 VStack(spacing: 12) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 50))
                        .foregroundColor(AppTheme.spSecondaryText.opacity(0.6))
                        .padding(20)
                        .background(AppTheme.spSecondaryText.opacity(0.05))
                        .clipShape(Circle())
                    Text("No Encounters Yet")
                        .font(.title3.weight(.medium))
                    Text("Start exploring to meet new people!")
                        .font(.callout)
                        .foregroundColor(AppTheme.spSecondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .glassBackground(cornerRadius: 15, material: AppTheme.cardBackgroundColor, shadow: .soft)
                .padding(.horizontal)

            } else if sortedCards.isEmpty && !searchText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(AppTheme.spSecondaryText.opacity(0.6))
                        .padding(20)
                        .background(AppTheme.spSecondaryText.opacity(0.05))
                        .clipShape(Circle())
                    Text("No Results Found")
                        .font(.title3.weight(.medium))
                    Text("Try a different search term for '\(searchText)'.")
                        .font(.callout)
                        .foregroundColor(AppTheme.spSecondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .glassBackground(cornerRadius: 15, material: AppTheme.cardBackgroundColor, shadow: .soft)
                .padding(.horizontal)
            } else {
                LazyVStack(spacing: 12) {
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
                            HStack(spacing: 15) {
                                card.getPlaceholderDrawingView()
                                    .frame(width: 55, height: 75)
                                    .background(AppTheme.userSpecificColor(for: card.userID).opacity(0.1))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(AppTheme.userSpecificColor(for: card.userID), lineWidth: 2)
                                    )
                                    .shadow(color: AppTheme.userSpecificColor(for: card.userID).opacity(0.25), radius: 3, y: 1)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(card.displayName)
                                        .font(.headline.weight(.semibold))
                                        .foregroundColor(AppTheme.spPrimaryText)
                                        .lineLimit(1)
                                    Text(card.statusMessage)
                                        .font(.subheadline)
                                        .foregroundColor(AppTheme.spSecondaryText)
                                        .lineLimit(2)
                                }
                                Spacer()
                                if favoriteUserIDs.contains(card.userID) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(AppTheme.spAccentYellow)
                                        .font(.title3)
                                        .shadow(color: AppTheme.spAccentYellow.opacity(0.5), radius: 3)
                                        .transition(.scale(scale: 1.4).combined(with: .opacity))
                                }
                                Image(systemName: "chevron.right")
                                    .foregroundColor(AppTheme.spTertiaryText)
                            }
                            .padding()
                            .glassBackground(cornerRadius: 15, material: AppTheme.cardBackgroundColor, strokeColor: AppTheme.glassBorderSubtle, shadow: .soft)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: favoriteUserIDs.contains(card.userID))
                    }
                }
                .padding(.horizontal)
            }
            Spacer(minLength: 20)
        }
    }

    private func changeFavorite(userID: String) {
        HapticManager.shared.impact(style: .medium)
        var updated = favoriteUserIDs
        let isAdding = !updated.contains(userID)
        
        if isAdding {
            updated.insert(userID)
            HapticManager.shared.notification(type: .success)
        } else {
            updated.remove(userID)
        }
        
        if let encoded = try? JSONEncoder().encode(updated),
           let stringified = String(data: encoded, encoding: .utf8) {
            _appStorageFavoriteUserIDsJSON = stringified
        }
    }
}

struct RecentCardsSwappedSectionView: View {
    @ObservedObject var viewModel: StreetPassViewModel
    var onTapAll: () -> Void
    @State private var cardAppeared: [UUID: Bool] = [:]
    @State private var sectionVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Swaps")
                    .font(.title2.bold())
                    .foregroundColor(AppTheme.spPrimaryText)
                Spacer()
                Button(action: onTapAll) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundColor(AppTheme.primaryColor.opacity(0.8))
                }
            }
            .padding(.horizontal)
            .opacity(sectionVisible ? 1 : 0)
            .offset(y: sectionVisible ? 0 : 15)

            let displayCards: [EncounterCard] = {
                if viewModel.recentlyEncounteredCards.isEmpty {
                    return [
                        EncounterCard.placeholderCard(drawingIdentifier: "s_squiggle"),
                        EncounterCard.placeholderCard(drawingIdentifier: "lines_and_block"),
                        EncounterCard.placeholderCard(drawingIdentifier: "flower_simple"),
                        EncounterCard.placeholderCard(drawingIdentifier: "smiley_face")
                    ]
                } else {
                    return Array(viewModel.recentlyEncounteredCards.prefix(6))
                }
            }()

            if displayCards.isEmpty {
                Text("Swap cards with others to see them here!")
                    .font(.callout)
                    .foregroundColor(AppTheme.spSecondaryText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .glassBackground(cornerRadius: 10, material: AppTheme.cardBackgroundColor, shadow: .soft)
                    .padding(.horizontal)
                    .opacity(sectionVisible ? 1 : 0)
                    .offset(y: sectionVisible ? 0 : 15)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 15) {
                        ForEach(Array(displayCards.enumerated()), id: \.element.id) { index, card in
                            RecentCardItemView(card: card) {
                                viewModel.showInfoMessage("tapped on card id: \(card.id.uuidString.prefix(4))")
                                HapticManager.shared.impact(style: .light)
                            }
                            .opacity(cardAppeared[card.id, default: false] ? 1 : 0)
                            .rotation3DEffect(
                                .degrees(cardAppeared[card.id, default: false] ? 0 : -15),
                                axis: (x: 0, y: 1, z: 0),
                                anchor: .leading
                            )
                            .offset(y: cardAppeared[card.id, default: false] ? 0 : 15)
                            .onAppear {
                                if sectionVisible {
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.08 * Double(index))) {
                                        cardAppeared[card.id] = true
                                    }
                                }
                            }
                            .onChange(of: sectionVisible) { _, newVisible in
                                if newVisible {
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.08 * Double(index))) {
                                        cardAppeared[card.id] = true
                                    }
                                } else {
                                    cardAppeared[card.id] = false
                                }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal)
                }
            }
        }
        .onAppear {
            withAnimation(.interpolatingSpring(stiffness: 100, damping: 15).delay(0.1)) {
                sectionVisible = true
            }
        }
    }
}

struct RecentCardItemView: View {
    let card: EncounterCard
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                card.getPlaceholderDrawingView()
                    .frame(width: 90, height: 130)
                    .background(AppTheme.userSpecificColor(for: card.userID).opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.userSpecificColor(for: card.userID), lineWidth: 2.5)
                    )
                    .cornerRadius(12)
                    .glassBackground(cornerRadius: 12, material: AppTheme.glassMaterialUltraThin, strokeColor: AppTheme.userSpecificColor(for: card.userID).opacity(0.7), strokeWidth: 1.5, shadow: .custom(color: AppTheme.userSpecificColor(for: card.userID).opacity(0.3), radius: 6, x:0, y:3))
                    

                Text(card.displayName.isEmpty ? "Encounter" : card.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.spPrimaryText)
                    .lineLimit(1)
                    .frame(width: 90)
            }
        }
        .buttonStyle(ScaleDownButtonStyle(scaleFactor: 0.94, opacityFactor: 0.9))
    }
}

struct StatusSectionView: View {
    @ObservedObject var viewModel: StreetPassViewModel
    @State private var sectionVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device Status")
                .font(.title2.bold())
                .foregroundColor(AppTheme.spPrimaryText)
                .padding(.horizontal)
                .opacity(sectionVisible ? 1 : 0)
                .offset(y: sectionVisible ? 0 : 15)


            VStack(spacing: 10) {
                StatusBoxView(
                    title: viewModel.isBluetoothOn ? "Bluetooth Active" : "Bluetooth Offline",
                    subtitle: viewModel.isBluetoothOn ? "Ready to connect" : "Enable Bluetooth for StreetPass",
                    iconName: viewModel.isBluetoothOn ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right.slash.circle.fill",
                    mainColor: viewModel.isBluetoothOn ? AppTheme.positiveColor : AppTheme.warningColor,
                    isPulsingActive: viewModel.isBluetoothOn
                )
                .opacity(sectionVisible ? 1 : 0)
                .offset(y: sectionVisible ? 0 : 15)
                .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(sectionVisible ? 0.1 : 0), value: sectionVisible)
                
                let adStatus = viewModel.isAdvertisingActive ? "ON" : "OFF"
                let scanStatus = viewModel.isScanningActive ? "ON" : "OFF"
                let spassOverallStatus = (viewModel.isAdvertisingActive || viewModel.isScanningActive)
                
                StatusBoxView(
                    title: "StreetPass \(spassOverallStatus ? "Active" : "Inactive")",
                    subtitle: "Advertising: \(adStatus), Scanning: \(scanStatus)",
                    iconName: spassOverallStatus ? "network.badge.shield.half.filled" : "network.slash",
                    mainColor: spassOverallStatus ? AppTheme.positiveColor : AppTheme.primaryColor.opacity(0.8),
                    isPulsingActive: spassOverallStatus
                )
                .opacity(sectionVisible ? 1 : 0)
                .offset(y: sectionVisible ? 0 : 15)
                .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(sectionVisible ? 0.2 : 0), value: sectionVisible)
            }
            .padding(.horizontal)
        }
        .onAppear {
            withAnimation(.interpolatingSpring(stiffness: 100, damping: 15).delay(0.2)) {
                sectionVisible = true
            }
        }
    }
}

struct StatusBoxView: View {
    let title: String
    let subtitle: String
    let iconName: String
    let mainColor: Color
    let isPulsingActive: Bool

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: iconName)
                .font(.title)
                .foregroundColor(mainColor)
                .frame(width: 35, height: 35)
                .padding(8)
                .background(mainColor.opacity(0.15))
                .clipShape(Circle())
                .pulsating(active: isPulsingActive, duration: 1.5, minOpacity: 0.3, maxScale: 1.25)
                .shadow(color: mainColor.opacity(0.3), radius: isPulsingActive ? 8 : 3, y: 2)
                

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(AppTheme.spPrimaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppTheme.spSecondaryText)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .glassBackground(cornerRadius: 12, material: AppTheme.cardBackgroundColor, strokeColor: mainColor.opacity(0.3), strokeWidth: 1, shadow: .custom(color: mainColor.opacity(0.1), radius: 4, x:0, y:2))
    }
}

struct ReceivedCardDetailView: View {
    let card: EncounterCard
    @State var isFavorite: Bool
    let toggleFavoriteAction: () -> Void

    private let drawingDisplayMaxHeight: CGFloat = 300
    private let userColor: Color
    @State private var showAvatarAndName = false
    @State private var showFlair = false
    @State private var showInfo = false
    @State private var showActions = false
    @State private var showDrawing = false


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
                    .cornerRadius(15)
                    .glassBackground(cornerRadius:15, material: AppTheme.glassMaterialUltraThin, strokeColor: userColor.opacity(0.5), strokeWidth: 2, shadow: .custom(color: userColor.opacity(0.3), radius: 10, x:0, y:6))
                    .padding()
                    
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash.circle.fill")
                        .font(.system(size: 70))
                        .foregroundColor(userColor.opacity(0.7))
                    Text("No Drawing Shared")
                        .font(.title2.weight(.medium))
                        .foregroundColor(userColor.opacity(0.9))
                    Text("This user hasn't shared a drawing on their card.")
                        .font(.callout)
                        .foregroundColor(AppTheme.spSecondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, minHeight: drawingDisplayMaxHeight * 0.6)
                .background(userColor.opacity(0.1))
                .glassBackground(cornerRadius: 15, material: AppTheme.glassMaterialUltraThin, strokeColor: userColor.opacity(0.15), strokeWidth: 1.5, shadow: .soft)
                .padding()
            }
        }
        .opacity(showDrawing ? 1 : 0)
        .scaleEffect(showDrawing ? 1 : 0.85)
        .offset(y: showDrawing ? 0 : 20)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                drawingSection

                VStack(spacing: 12) {
                    Image(systemName: card.avatarSymbolName)
                        .font(.system(size: 70))
                        .padding(20)
                        .foregroundColor(userColor)
                        .background(
                            Circle()
                                .fill(userColor.opacity(0.1))
                                .glassBackground(cornerRadius: 60, material: AppTheme.glassMaterialThin, strokeColor: userColor.opacity(0.3), strokeWidth: 2, shadow: .custom(color: userColor.opacity(0.2), radius:5, x:0,y:3))
                        )
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(userColor, lineWidth: 3.5))
                        .shadow(color: userColor.opacity(0.4), radius: 8, x:0, y:4)


                    Text(card.displayName)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(AppTheme.spPrimaryText)

                    Text(card.statusMessage)
                        .font(.title3)
                        .foregroundColor(AppTheme.spSecondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical)
                .opacity(showAvatarAndName ? 1 : 0)
                .offset(y: showAvatarAndName ? 0 : 15)

                if card.flairField1Title != nil || card.flairField1Value != nil || card.flairField2Title != nil || card.flairField2Value != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        if let t1 = card.flairField1Title, let v1 = card.flairField1Value, !t1.trimming.isEmpty || !v1.trimming.isEmpty {
                            FlairDisplayRow(title: t1, value: v1, icon: "rosette", iconColor: userColor)
                        }
                        if (card.flairField1Title != nil || card.flairField1Value != nil) &&
                           (card.flairField2Title != nil || card.flairField2Value != nil) &&
                           !(card.flairField1Title?.trimming.isEmpty ?? true && card.flairField1Value?.trimming.isEmpty ?? true) &&
                           !(card.flairField2Title?.trimming.isEmpty ?? true && card.flairField2Value?.trimming.isEmpty ?? true) {
                            Divider().padding(.vertical, 4)
                        }
                        if let t2 = card.flairField2Title, let v2 = card.flairField2Value, !t2.trimming.isEmpty || !v2.trimming.isEmpty {
                            FlairDisplayRow(title: t2, value: v2, icon: "star.circle.fill", iconColor: userColor)
                        }
                    }
                    .padding()
                    .glassBackground(cornerRadius: 15, material: AppTheme.cardBackgroundColor, shadow: .soft)
                    .padding(.horizontal)
                    .opacity(showFlair ? 1 : 0)
                    .offset(y: showFlair ? 0 : 15)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Label {
                        Text("Schema Version: \(card.cardSchemaVersion)")
                    } icon: {
                        Image(systemName: "number.square.fill")
                            .foregroundColor(userColor)
                    }
                    .font(.caption)
                    .foregroundColor(AppTheme.spSecondaryText)

                    Label {
                        Text("Last Updated: \(card.lastUpdated, style: .date) at \(card.lastUpdated, style: .time)")
                    } icon: {
                        Image(systemName: "clock.fill")
                             .foregroundColor(userColor)
                    }
                    .font(.caption)
                    .foregroundColor(AppTheme.spSecondaryText)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassBackground(cornerRadius: 15, material: AppTheme.cardBackgroundColor, shadow: .soft)
                .padding(.horizontal)
                .opacity(showInfo ? 1 : 0)
                .offset(y: showInfo ? 0 : 15)

                HStack(spacing: 15) {
                    Button {
                        HapticManager.shared.impact(style: .medium)
                        let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                        impactHeavy.prepare()
                        
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                            toggleFavoriteAction()
                            self.isFavorite.toggle()
                            if self.isFavorite {
                                impactHeavy.impactOccurred()
                            }
                        }
                    } label: {
                        Label(
                            isFavorite ? "Favorited" : "Favorite",
                            systemImage: isFavorite ? "star.fill" : "star"
                        )
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isFavorite ? AppTheme.spAccentYellow : userColor.opacity(0.85))
                    .controlSize(.large)
                    .shadow(color: (isFavorite ? AppTheme.spAccentYellow : userColor).opacity(0.4), radius: isFavorite ? 10 : 5, y: isFavorite ? 5 : 2)


                    Button {
                        HapticManager.shared.impact(style: .light)
                        print("Share card \(card.id.uuidString.prefix(4)) tapped - (placeholder action)")
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(userColor)
                    .controlSize(.large)
                }
                .padding([.horizontal, .bottom])
                .opacity(showActions ? 1 : 0)
                .offset(y: showActions ? 0 : 15)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.05)) { showDrawing = true }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.15)) { showAvatarAndName = true }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.25)) { showFlair = true }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.35)) { showInfo = true }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.45)) { showActions = true }
        }
        .background(
            LinearGradient(
                colors: [userColor.opacity(0.15), AppTheme.backgroundColor, AppTheme.backgroundColor],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(card.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    HapticManager.shared.impact(style: .medium)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                        toggleFavoriteAction()
                        self.isFavorite.toggle()
                    }
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .imageScale(.large)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isFavorite ? AppTheme.spAccentYellow : AppTheme.primaryColor, isFavorite ? AppTheme.spAccentYellow.opacity(0.5) : AppTheme.primaryColor.opacity(0.3))
                }
                .font(.title2)
                .scaleEffect(isFavorite ? 1.1 : 1.0)
            }
        }
    }
}

struct FlairDisplayRow: View {
    let title: String
    let value: String
    let icon: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2.weight(.medium))
                .foregroundColor(iconColor)
                .frame(width: 30, alignment: .center)
                .shadow(color: iconColor.opacity(0.3), radius: 2)
            VStack(alignment: .leading) {
                Text(title.isEmpty ? "Info" : title)
                    .font(.headline)
                    .foregroundColor(AppTheme.spPrimaryText)
                Text(value.isEmpty ? "Not specified" : value)
                    .font(.callout)
                    .foregroundColor(AppTheme.spSecondaryText)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

struct ScaleDownButtonStyle: ButtonStyle {
    var scaleFactor: CGFloat = 0.97
    var opacityFactor: CGFloat = 0.9
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleFactor : 1.0)
            .opacity(configuration.isPressed ? opacityFactor : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct RoundedCornersShape: Shape {
    var corners: UIRectCorner
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

struct ScrollViewOffsetTracker<Content: View>: View {
    @Binding var scrollOffset: CGFloat
    let content: () -> Content

    var body: some View {
        content()
            .background(GeometryReader { geo -> Color in
                DispatchQueue.main.async {
                    self.scrollOffset = -geo.frame(in: .named("scrollView")).origin.y
                }
                return Color.clear
            })
            .coordinateSpace(name: "scrollView")
    }
}


fileprivate extension String {
    var trimming: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

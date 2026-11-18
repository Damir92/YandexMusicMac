import Foundation

/// Rotor Station ("Моя волна") Service actor.
/// Supports Rotor Session v2 (POST /rotor/session/new, /tracks, /feedback) with structured 4-level fallback to Rotor v1.
/// Manages batch fetching, queue pagination, strict deduplication, session history, wave vibes,
/// personal wave recommendations, diagnostics telemetry, and radio feedback events.
public actor RotorService {
    public static let shared = RotorService()

    private static let apiModeDefaultsKey = "ym_rotor_api_mode"

    private let networkClient: YMNetworkClient
    private var currentSessionId: String?
    private var currentBatchId: String?
    private var seenTrackIds: Set<String> = []
    private var seenTrackIdList: [String] = []
    private var recentQueueIdentifiers: [String] = []
    private let isoFormatter: ISO8601DateFormatter
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var activeContext: YMWaveContext = .myWaveDefault
    private var activeVibe: YMWaveVibePreset = .defaultWave

    public private(set) var diagnostics: YMRotorDiagnostics = YMRotorDiagnostics()
    public var preferredAPIMode: YMRotorAPIMode {
        didSet {
            UserDefaults.standard.set(preferredAPIMode.rawValue, forKey: Self.apiModeDefaultsKey)
            let updatedMode = preferredAPIMode
            Task { @MainActor in
                if RotorDiagnosticsStore.shared.preferredAPIMode != updatedMode {
                    RotorDiagnosticsStore.shared.preferredAPIMode = updatedMode
                }
            }
        }
    }

    // 15-minute in-memory caches for personalized dashboard waves and on-demand full catalog
    private var cachedRecommendedWaves: [YMPersonalWaveStation] = []
    private var recommendedWavesCachedAt: Date? = nil
    private var cachedCatalogWaves: [YMPersonalWaveStation] = []
    private var catalogWavesCachedAt: Date? = nil
    private let recommendedWavesTTL: TimeInterval = 15 * 60

    public init(networkClient: YMNetworkClient = .shared) {
        self.networkClient = networkClient
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter

        if let raw = UserDefaults.standard.string(forKey: Self.apiModeDefaultsKey),
           let saved = YMRotorAPIMode(rawValue: raw) {
            self.preferredAPIMode = saved
        } else {
            self.preferredAPIMode = .auto
        }
    }

    public func setPreferredAPIMode(_ mode: YMRotorAPIMode) {
        self.preferredAPIMode = mode
    }

    public func getPreferredAPIMode() -> YMRotorAPIMode {
        preferredAPIMode
    }

    public func getDiagnostics() -> YMRotorDiagnostics {
        diagnostics
    }

    public func getActiveContext() -> YMWaveContext {
        activeContext
    }

    public func getActiveVibe() -> YMWaveVibePreset {
        activeVibe
    }

    public func getCurrentSessionId() -> String? {
        currentSessionId
    }

    public func setSessionId(_ sessionId: String?) {
        self.currentSessionId = sessionId
    }

    public func getCurrentBatchId() -> String? {
        currentBatchId
    }

    public func setBatchId(_ batchId: String?) {
        self.currentBatchId = batchId
    }

    public func resetSession() {
        self.currentSessionId = nil
        self.currentBatchId = nil
        self.seenTrackIds.removeAll()
        self.seenTrackIdList.removeAll()
        self.recentQueueIdentifiers.removeAll()
        self.diagnostics = YMRotorDiagnostics()
        publishDiagnostics()
    }

    // MARK: - Personal Waves Discovery

    /// Fetches ONLY personalized wave stations from `GET /rotor/stations/dashboard` (up to 14 unique cards,
    /// excluding `user:onyourwave`). Falls back to `GET /rotor/stations/list` (max 6 popular stations)
    /// strictly as an emergency fallback if the dashboard fails or returns fewer than 3 cards.
    /// Cached in actor memory for 15 minutes to stay well within the 40–65 MB RAM budget.
    public func fetchRecommendedWaves(forceRefresh: Bool = false) async -> [YMPersonalWaveStation] {
        if !forceRefresh,
           !cachedRecommendedWaves.isEmpty,
           let cachedAt = recommendedWavesCachedAt,
           Date().timeIntervalSince(cachedAt) < recommendedWavesTTL {
            return cachedRecommendedWaves
        }

        var stations: [YMPersonalWaveStation] = []
        var seenIds: Set<String> = ["user:onyourwave"]
        let maxDashboardStations = 14

        // 1. Personalized dashboard stations only
        do {
            let dashboard: YMRotorDashboardResponse = try await networkClient.request(
                endpoint: "/rotor/stations/dashboard",
                cachePolicy: .useProtocolCachePolicy
            )
            for item in dashboard.stations {
                if let station = item.toPersonalWaveStation(),
                   !seenIds.contains(station.id) {
                    seenIds.insert(station.id)
                    stations.append(station)
                    if stations.count >= maxDashboardStations { break }
                }
            }
        } catch {
            print("[RotorService] Dashboard fetch failed: \(error.localizedDescription)")
        }

        // 2. Emergency fallback ONLY if dashboard failed or returned fewer than 3 cards (cap at 6)
        if stations.count < 3 {
            do {
                let listItems: [YMRotorDashboardStationItem] = try await networkClient.request(
                    endpoint: "/rotor/stations/list",
                    cachePolicy: .useProtocolCachePolicy
                )
                for item in listItems {
                    if let station = item.toPersonalWaveStation(),
                       !seenIds.contains(station.id) {
                        seenIds.insert(station.id)
                        stations.append(station)
                        if stations.count >= 6 { break }
                    }
                }
            } catch {
                print("[RotorService] Emergency stations list fallback failed: \(error.localizedDescription)")
            }
        }

        if !stations.isEmpty {
            self.cachedRecommendedWaves = stations
            self.recommendedWavesCachedAt = Date()
        }
        return stations
    }

    /// Loads the full Yandex Music Rotor stations catalog (`GET /rotor/stations/list`) on explicit user demand
    /// (when opening the "Все жанры" sheet). Cached in actor memory for 15 minutes.
    public func fetchAllCatalogWaves(forceRefresh: Bool = false) async -> [YMPersonalWaveStation] {
        if !forceRefresh,
           !cachedCatalogWaves.isEmpty,
           let cachedAt = catalogWavesCachedAt,
           Date().timeIntervalSince(cachedAt) < recommendedWavesTTL {
            return cachedCatalogWaves
        }

        var stations: [YMPersonalWaveStation] = []
        var seenIds: Set<String> = ["user:onyourwave"]

        do {
            let listItems: [YMRotorDashboardStationItem] = try await networkClient.request(
                endpoint: "/rotor/stations/list",
                cachePolicy: .useProtocolCachePolicy
            )
            for item in listItems {
                if let station = item.toPersonalWaveStation(),
                   !seenIds.contains(station.id) {
                    seenIds.insert(station.id)
                    stations.append(station)
                }
            }
        } catch {
            print("[RotorService] Full catalog stations fetch failed: \(error.localizedDescription)")
        }

        if !stations.isEmpty {
            self.cachedCatalogWaves = stations
            self.catalogWavesCachedAt = Date()
        }
        return stations
    }

    // MARK: - Station Loading (4-Level Fallback Chain)

    /// Starts "Моя волна" station using Rotor Session v2 with structured fallback to v1.
    /// Resets duplicate tracking and session history.
    public func startWave(
        context: YMWaveContext = .myWaveDefault,
        vibe: YMWaveVibePreset? = nil
    ) async throws -> [YMTrack] {
        resetSession()
        self.activeContext = context
        self.activeVibe = vibe ?? .defaultWave

        var effectiveSeeds = context.seeds
        if let vibeSeed = activeVibe.seedParameter, !effectiveSeeds.contains(vibeSeed) {
            effectiveSeeds.append(vibeSeed)
        }

        var lastFallbackReason: String? = nil
        var lastError: Error? = nil

        // Level 1: Primary Rotor Session v2 (POST /rotor/session/new)
        if preferredAPIMode != .v1Fallback {
            do {
                let requestPayload = YMRotorSessionNewRequest(seeds: effectiveSeeds)
                let body = try encoder.encode(requestPayload)

                let result: YMRotorStationTracksResult = try await networkClient.request(
                    endpoint: "/rotor/session/new",
                    method: "POST",
                    body: body,
                    headers: ["Content-Type": "application/json"],
                    cachePolicy: .reloadIgnoringLocalCacheData
                )

                recordTrackInsights(from: result.sequence)
                let rawTracks = result.sequence.compactMap(\.track)
                let (uniqueTracks, duplicatesFiltered) = filterUniqueTracksWithStats(rawTracks)
                if !uniqueTracks.isEmpty {
                    self.currentSessionId = result.radioSessionId
                    self.currentBatchId = result.batchId
                    updateDiagnostics(
                        activeProtocol: "Rotor Session v2 (POST /rotor/session/new)",
                        isFallbackActive: false,
                        activeLevel: 1,
                        activeSeeds: effectiveSeeds,
                        fetchedDelta: uniqueTracks.count,
                        duplicatesDelta: duplicatesFiltered,
                        lastFallbackReason: nil
                    )

                    try? await sendFeedback(type: .radioStarted, trackId: nil)
                    return uniqueTracks
                } else {
                    lastFallbackReason = "Session v2 вернул пустой список треков"
                }
            } catch {
                lastError = error
                lastFallbackReason = "Session v2 ошибка: \(error.localizedDescription)"
                print("[RotorService] Level 1 Session v2 start error: \(error)")
            }

            // Level 2: Rotor Session v2 with Simplified Seeds
            let simplifiedSeeds = buildSimplifiedSeeds(for: context, vibe: activeVibe)
            if !simplifiedSeeds.isEmpty && simplifiedSeeds != effectiveSeeds {
                do {
                    let retryPayload = YMRotorSessionNewRequest(seeds: simplifiedSeeds)
                    let retryBody = try encoder.encode(retryPayload)

                    let result: YMRotorStationTracksResult = try await networkClient.request(
                        endpoint: "/rotor/session/new",
                        method: "POST",
                        body: retryBody,
                        headers: ["Content-Type": "application/json"],
                        cachePolicy: .reloadIgnoringLocalCacheData
                    )

                    recordTrackInsights(from: result.sequence)
                    let rawTracks = result.sequence.compactMap(\.track)
                    let (uniqueTracks, duplicatesFiltered) = filterUniqueTracksWithStats(rawTracks)
                    if !uniqueTracks.isEmpty {
                        self.currentSessionId = result.radioSessionId
                        self.currentBatchId = result.batchId
                        updateDiagnostics(
                            activeProtocol: "Rotor Session v2 (Simplified Seeds)",
                            isFallbackActive: true,
                            activeLevel: 2,
                            activeSeeds: simplifiedSeeds,
                            fetchedDelta: uniqueTracks.count,
                            duplicatesDelta: duplicatesFiltered,
                            lastFallbackReason: lastFallbackReason
                        )

                        try? await sendFeedback(type: .radioStarted, trackId: nil)
                        return uniqueTracks
                    }
                } catch {
                    lastError = error
                    lastFallbackReason = "Session v2 Simplified ошибка: \(error.localizedDescription)"
                    print("[RotorService] Level 2 Session v2 simplified retry failed: \(error)")
                }
            }

            // If user strictly locked mode to v2Only, do not fall back to v1
            if preferredAPIMode == .v2Only {
                updateDiagnostics(
                    activeProtocol: "Ошибка Rotor Session v2",
                    isFallbackActive: true,
                    activeLevel: 0,
                    activeSeeds: effectiveSeeds,
                    fetchedDelta: 0,
                    duplicatesDelta: 0,
                    lastFallbackReason: lastFallbackReason
                )
                throw lastError ?? YMAPIError.emptyResult
            }
        } else {
            lastFallbackReason = "Выбран ручной режим Rotor Radio v1"
        }

        // Level 3: Rotor Station v1 (GET /rotor/station/{stationId}/tracks?settings2=true + activeVibe params)
        var v1QueryItems = [URLQueryItem(name: "settings2", value: "true")]
        v1QueryItems.append(contentsOf: activeVibe.v1QueryItems)

        var response: YMRotorStationTracksResult?
        var usedBaseWaveFallback = false

        do {
            response = try await networkClient.request(
                endpoint: "/rotor/station/\(YMNetworkClient.escapePath(context.fallbackStationId))/tracks",
                queryItems: v1QueryItems,
                cachePolicy: .reloadIgnoringLocalCacheData
            )
        } catch {
            print("[RotorService] Level 3 Rotor v1 station \(context.fallbackStationId) failed: \(error). Falling back to user:onyourwave...")
            lastFallbackReason = "Station v1 (\(context.fallbackStationId)): \(error.localizedDescription)"

            // Level 4: Base Wave Fallback (GET /rotor/station/user:onyourwave/tracks?settings2=true)
            if context.fallbackStationId != "user:onyourwave" {
                usedBaseWaveFallback = true
                response = try await networkClient.request(
                    endpoint: "/rotor/station/user:onyourwave/tracks",
                    queryItems: v1QueryItems,
                    cachePolicy: .reloadIgnoringLocalCacheData
                )
            } else {
                updateDiagnostics(
                    activeProtocol: "Ошибка Rotor Station v1",
                    isFallbackActive: true,
                    activeLevel: 0,
                    activeSeeds: [context.fallbackStationId],
                    fetchedDelta: 0,
                    duplicatesDelta: 0,
                    lastFallbackReason: lastFallbackReason
                )
                throw error
            }
        }

        guard let validResponse = response else {
            return []
        }

        self.currentSessionId = validResponse.radioSessionId
        self.currentBatchId = validResponse.batchId
        recordTrackInsights(from: validResponse.sequence)
        let rawTracks = validResponse.sequence.compactMap(\.track)
        let (uniqueTracks, duplicatesFiltered) = filterUniqueTracksWithStats(rawTracks)

        let protocolLabel = usedBaseWaveFallback
            ? "Base Wave Fallback (GET /rotor/station/user:onyourwave/tracks)"
            : "Rotor Station v1 (GET /rotor/station/\(context.fallbackStationId)/tracks)"

        updateDiagnostics(
            activeProtocol: protocolLabel,
            isFallbackActive: true,
            activeLevel: usedBaseWaveFallback ? 4 : 3,
            activeSeeds: usedBaseWaveFallback ? ["user:onyourwave"] : [context.fallbackStationId],
            fetchedDelta: uniqueTracks.count,
            duplicatesDelta: duplicatesFiltered,
            lastFallbackReason: lastFallbackReason
        )

        try? await sendFeedback(type: .radioStarted, trackId: nil)

        return uniqueTracks
    }

    /// Fetches next batch of tracks using v2 if radioSessionId is present, otherwise v1.
    /// Passes up to 25 recent track identifiers and current `batchId` to the API, filtering duplicates and updating diagnostics.
    public func fetchNextBatch(lastTrackId: String, queueHistory: [String] = []) async throws -> [YMTrack] {
        var queueList: [String] = []
        if !queueHistory.isEmpty {
            queueList = Array(queueHistory.suffix(25))
        } else if !recentQueueIdentifiers.isEmpty {
            queueList = Array(recentQueueIdentifiers.suffix(25))
        } else {
            queueList = [lastTrackId]
        }

        var fallbackReason: String? = diagnostics.lastFallbackReason

        // Try Rotor Session v2 if sessionId is active and mode permits v2
        if let sessionId = currentSessionId, preferredAPIMode != .v1Fallback {
            do {
                let payload = YMRotorSessionNextTracksRequest(queue: queueList, batchId: currentBatchId)
                let body = try encoder.encode(payload)

                let result: YMRotorStationTracksResult = try await networkClient.request(
                    endpoint: "/rotor/session/\(YMNetworkClient.escapePath(sessionId))/tracks",
                    method: "POST",
                    body: body,
                    headers: ["Content-Type": "application/json"],
                    cachePolicy: .reloadIgnoringLocalCacheData
                )

                if let newBatchId = result.batchId {
                    self.currentBatchId = newBatchId
                }
                recordTrackInsights(from: result.sequence)
                let rawTracks = result.sequence.compactMap(\.track)
                let (uniqueTracks, duplicatesFiltered) = filterUniqueTracksWithStats(rawTracks)
                if !uniqueTracks.isEmpty {
                    updateDiagnostics(
                        activeProtocol: diagnostics.activeLevel == 2
                            ? "Rotor Session v2 (Simplified Seeds)"
                            : "Rotor Session v2 (POST /rotor/session/new)",
                        isFallbackActive: diagnostics.activeLevel == 2,
                        activeLevel: diagnostics.activeLevel == 2 ? 2 : 1,
                        activeSeeds: diagnostics.activeSeeds,
                        fetchedDelta: uniqueTracks.count,
                        duplicatesDelta: duplicatesFiltered,
                        lastFallbackReason: diagnostics.lastFallbackReason
                    )
                    return uniqueTracks
                }
            } catch {
                fallbackReason = "Session v2 next batch ошибка: \(error.localizedDescription)"
                print("[RotorService] Session v2 next batch error: \(error). Falling back to v1...")
                if preferredAPIMode == .v2Only {
                    throw error
                }
            }
        }

        // Fallback to Rotor v1: GET /rotor/station/\(activeContext.fallbackStationId)/tracks
        let queueParam = queueList.joined(separator: ",")
        var queryItems = [
            URLQueryItem(name: "settings2", value: "true"),
            URLQueryItem(name: "queue", value: queueParam)
        ]
        queryItems.append(contentsOf: activeVibe.v1QueryItems)

        var response: YMRotorStationTracksResult?
        var usedBaseWaveFallback = false
        do {
            response = try await networkClient.request(
                endpoint: "/rotor/station/\(YMNetworkClient.escapePath(activeContext.fallbackStationId))/tracks",
                queryItems: queryItems,
                cachePolicy: .reloadIgnoringLocalCacheData
            )
        } catch {
            fallbackReason = "Station v1 (\(activeContext.fallbackStationId)): \(error.localizedDescription)"
            if activeContext.fallbackStationId != "user:onyourwave" {
                usedBaseWaveFallback = true
                response = try await networkClient.request(
                    endpoint: "/rotor/station/user:onyourwave/tracks",
                    queryItems: queryItems,
                    cachePolicy: .reloadIgnoringLocalCacheData
                )
            } else {
                throw error
            }
        }

        if let newBatchId = response?.batchId {
            self.currentBatchId = newBatchId
        }

        let sequence = response?.sequence ?? []
        recordTrackInsights(from: sequence)
        let rawTracks = sequence.compactMap(\.track)
        let (uniqueTracks, duplicatesFiltered) = filterUniqueTracksWithStats(rawTracks)

        updateDiagnostics(
            activeProtocol: usedBaseWaveFallback
                ? "Base Wave Fallback (GET /rotor/station/user:onyourwave/tracks)"
                : "Rotor Station v1 (GET /rotor/station/\(activeContext.fallbackStationId)/tracks)",
            isFallbackActive: true,
            activeLevel: usedBaseWaveFallback ? 4 : 3,
            activeSeeds: usedBaseWaveFallback ? ["user:onyourwave"] : [activeContext.fallbackStationId],
            fetchedDelta: uniqueTracks.count,
            duplicatesDelta: duplicatesFiltered,
            lastFallbackReason: fallbackReason
        )

        return uniqueTracks
    }

    // MARK: - Helpers

    private func buildSimplifiedSeeds(for context: YMWaveContext, vibe: YMWaveVibePreset) -> [String] {
        var trackSeeds = context.seeds.filter { $0.hasPrefix("track:") }
        if !trackSeeds.isEmpty && context.seeds.count > 1 {
            if let vibeSeed = vibe.seedParameter {
                trackSeeds.append(vibeSeed)
            }
            return trackSeeds
        }

        var baseSeeds = ["user:onyourwave"]
        if let vibeSeed = vibe.seedParameter {
            baseSeeds.append(vibeSeed)
        }
        return baseSeeds
    }

    private func filterUniqueTracksWithStats(_ tracks: [YMTrack]) -> (unique: [YMTrack], duplicatesFiltered: Int) {
        var result: [YMTrack] = []
        var duplicates = 0
        for track in tracks {
            let cleanId = track.id.components(separatedBy: ":").first ?? track.id
            if !seenTrackIds.contains(cleanId) && !seenTrackIds.contains(track.id) {
                seenTrackIds.insert(cleanId)
                seenTrackIdList.append(cleanId)
                if track.id != cleanId {
                    seenTrackIds.insert(track.id)
                    seenTrackIdList.append(track.id)
                }
                recentQueueIdentifiers.append(track.rotorTrackIdentifier)
                result.append(track)
            } else {
                duplicates += 1
            }
        }
        if seenTrackIdList.count > 500 {
            let overflow = seenTrackIdList.count - 500
            for id in seenTrackIdList.prefix(overflow) {
                seenTrackIds.remove(id)
            }
            seenTrackIdList.removeFirst(overflow)
        }
        if recentQueueIdentifiers.count > 100 {
            recentQueueIdentifiers.removeFirst(recentQueueIdentifiers.count - 100)
        }
        return (result, duplicates)
    }

    private func recordTrackInsights(from sequence: [YMRotorSequenceItem]) {
        var collected: [(trackId: String, insight: YMRotorTrackInsight)] = []
        for item in sequence {
            guard let track = item.track else { continue }
            let insight = YMRotorTrackInsight(
                trackParameters: item.trackParameters,
                description: item.description,
                waveText: item.waveText
            )
            if insight.formattedInsight != nil {
                collected.append((track.id, insight))
            }
        }
        guard !collected.isEmpty else { return }
        let itemsToRecord = collected
        Task { @MainActor in
            RotorDiagnosticsStore.shared.recordTrackInsights(itemsToRecord)
        }
    }

    private func updateDiagnostics(
        activeProtocol: String,
        isFallbackActive: Bool,
        activeLevel: Int,
        activeSeeds: [String],
        fetchedDelta: Int,
        duplicatesDelta: Int,
        lastFallbackReason: String?
    ) {
        diagnostics = YMRotorDiagnostics(
            activeProtocol: activeProtocol,
            isFallbackActive: isFallbackActive,
            activeLevel: activeLevel,
            sessionId: currentSessionId,
            batchId: currentBatchId,
            activeSeeds: activeSeeds,
            fetchedTracksCount: diagnostics.fetchedTracksCount + fetchedDelta,
            filteredDuplicatesCount: diagnostics.filteredDuplicatesCount + duplicatesDelta,
            lastFallbackReason: lastFallbackReason,
            lastUpdated: Date()
        )
        publishDiagnostics()
    }

    private func publishDiagnostics() {
        let snapshot = diagnostics
        Task { @MainActor in
            RotorDiagnosticsStore.shared.updateDiagnostics(snapshot)
        }
    }

    // MARK: - Telemetry Feedback

    public func sendRadioStarted(initialTrack: YMTrack? = nil) async throws {
        try await sendFeedback(type: .radioStarted, trackId: nil)
    }

    public func sendTrackStarted(track: YMTrack) async throws {
        try await sendFeedback(type: .trackStarted, trackId: track.rotorTrackIdentifier)
    }

    public func sendTrackFinished(track: YMTrack, totalPlayedSeconds: Double) async throws {
        try await sendFeedback(type: .trackFinished, trackId: track.rotorTrackIdentifier, totalPlayedSeconds: totalPlayedSeconds)
    }

    public func sendTrackSkipped(track: YMTrack, playedSeconds: Double) async throws {
        try await sendFeedback(type: .skip, trackId: track.rotorTrackIdentifier, totalPlayedSeconds: playedSeconds)
    }

    /// Сигнал "Больше похожих треков": отправляет алгоритму радио события like + trackFinished (100% прослушивание),
    /// не добавляя трек в библиотеку "Мне нравится" пользователя.
    public func sendAlgorithmicMoreLikeThis(track: YMTrack) async throws {
        let fullDuration = Double(track.durationMs ?? 180_000) / 1000.0
        try? await sendFeedback(type: .like, trackId: track.rotorTrackIdentifier)
        try await sendFeedback(type: .trackFinished, trackId: track.rotorTrackIdentifier, totalPlayedSeconds: max(120.0, fullDuration))
    }

    /// Сигнал "Меньше таких треков": отправляет алгоритму радио события dislike + skip с минимальным временем.
    public func sendAlgorithmicLessLikeThis(track: YMTrack, playedSeconds: Double) async throws {
        try? await sendFeedback(type: .dislike, trackId: track.rotorTrackIdentifier)
        try await sendFeedback(type: .skip, trackId: track.rotorTrackIdentifier, totalPlayedSeconds: min(playedSeconds, 2.0))
    }

    private func sendFeedback(
        type: YMRotorEventType,
        trackId: String? = nil,
        totalPlayedSeconds: Double? = nil
    ) async throws {
        let fromValue = "mobile-home-rup_main-\(activeContext.seeds.first?.replacingOccurrences(of: ":", with: "-") ?? "user-onyourwave")-default"
        let event = YMRotorFeedbackEvent(
            type: type,
            timestamp: isoFormatter.string(from: Date()),
            trackId: trackId,
            totalPlayedSeconds: totalPlayedSeconds,
            from: fromValue
        )

        if let sessionId = currentSessionId {
            // Rotor Session v2 feedback: POST /rotor/session/{radioSessionId}/feedback
            let v2Payload = YMRotorSessionFeedbackRequest(event: event, batchId: currentBatchId)
            let body = try encoder.encode(v2Payload)
            let _: (Data, HTTPURLResponse) = try await networkClient.performRawRequest(
                endpoint: "/rotor/session/\(YMNetworkClient.escapePath(sessionId))/feedback",
                method: "POST",
                body: body,
                headers: ["Content-Type": "application/json"]
            )
            return
        }

        // Rotor v1 feedback: POST /rotor/station/\(activeContext.fallbackStationId)/feedback?batch-id={batchId}
        guard let batchId = currentBatchId else {
            print("[RotorService] Skipping v1 feedback \(type): batchId is nil")
            return
        }

        let payload = YMRotorFeedbackPayload(event: event)
        let body = try encoder.encode(payload)
        let queryItems = [
            URLQueryItem(name: "batch-id", value: batchId)
        ]

        let _: (Data, HTTPURLResponse) = try await networkClient.performRawRequest(
            endpoint: "/rotor/station/\(YMNetworkClient.escapePath(activeContext.fallbackStationId))/feedback",
            method: "POST",
            queryItems: queryItems,
            body: body,
            headers: ["Content-Type": "application/json"]
        )
    }
}

import SwiftUI
import GoogleSignIn

@main
struct AnyRankApp: App {

    @State private var repository: Repository
    @State private var authSession: AuthSession
    @State private var syncCoordinator: SyncCoordinator
    @State private var importStore = ImportStore(fileURL: ImportStore.defaultLocation())
    @State private var router = AppRouter()

    /// Concrete Places service chosen at launch based on whether a Google
    /// Places API key is configured. Live when the key is present, Mock
    /// otherwise — the search screen layers a sign-in gate on top of
    /// whichever service is in play.
    private let placesService: any PlacesSearchService

    /// Concrete Movie service chosen at launch based on whether a TMDB
    /// read token is configured. Live when the token is present, Mock
    /// otherwise. No sign-in gate on Movies — TMDB is unaffiliated with
    /// Google, so tying it to sign-in would be misleading.
    private let movieService: any MovieSearchService

    /// TV shows come from TMDB too, through the same client and token.
    private let tvService: any TVSearchService

    /// Concrete Game service — live IGDB when Twitch credentials are
    /// configured, mock otherwise.
    private let gameService: any GameSearchService

    /// BoardGameGeek when a token is configured, mock otherwise.
    private let boardGameService: any BoardGameSearchService

    /// Concrete album service: Spotify (client credentials) when
    /// configured, mock otherwise.
    private let musicService: any MusicSearchService

    /// Steam library reader for imports — live Web API when a key is
    /// configured, a sample library otherwise.
    private let steamService: any SteamLibraryService

    /// Scene phase at the App level. Drives the background-flush behavior:
    /// when the user backgrounds the app we force any pending Sheets push
    /// to run immediately, since the contract is "when the user stops
    /// interacting, the Sheet matches local."
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppAppearance.configure()

        // Cover art goes through ArtworkCache, which keeps its own
        // thumbnails. The account avatar in Settings still loads through
        // AsyncImage, which leans on URLCache.
        URLCache.shared = URLCache(
            memoryCapacity: 48 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )

        // Build the storage layer first — it's the source of truth.
        let storage = FileListStorage(baseDirectory: FileListStorage.defaultLocation())
        let repo = Repository(storage: storage)

        // Build auth. If no client ID is configured, fall back to the mock
        // driver so the app stays usable in local-only mode.
        let driver: AuthDriver
        if Secrets.googleOAuthClientID != nil {
            driver = GoogleAuthDriver()
        } else {
            driver = MockAuthDriver()
        }
        let auth = AuthSession(driver: driver)

        // Build the sync coordinator and wire it as the repository's observer.
        let sync = SyncCoordinator(repository: repo, auth: auth)
        repo.syncObserver = sync

        // Provision the Places SDK if the key is present. The bootstrap
        // returns nil when no key is configured — that's the signal to
        // fall back to the mock search service so dev/preview/test stay
        // usable without a real key.
        if GooglePlacesBootstrap.configure() != nil {
            self.placesService = LivePlacesSearchService()
            PlacePhotos.loader = { placeID in await LivePlacesSearchService.photo(forPlaceID: placeID) }
        } else {
            self.placesService = MockPlacesSearchService()
        }

        // Same pattern for TMDB — `LiveMovieSearchService.init?()` returns
        // nil when the token is missing, which is our signal to hand out
        // the mock instead.
        if let live = LiveMovieSearchService() {
            self.movieService = live
            self.tvService = live
        } else {
            self.movieService = MockMovieSearchService()
            self.tvService = MockTVSearchService()
        }

        // IGDB via Twitch client credentials — same failable-init
        // pattern; missing secrets fall back to the mock.
        if let live = LiveIGDBSearchService() {
            self.gameService = live
        } else {
            self.gameService = MockGameSearchService()
        }

        // Spotify (client-credentials, shared refresh via
        // `AppOAuthTokenStore`). Same failable-init contract.
        if let live = LiveBGGSearchService() {
            self.boardGameService = live
        } else {
            self.boardGameService = MockBoardGameSearchService()
        }

        if let live = LiveSpotifyMusicService() {
            self.musicService = live
        } else {
            self.musicService = MockMusicSearchService()
        }

        if let live = LiveSteamLibraryService() {
            self.steamService = live
        } else {
            self.steamService = SampleSteamLibraryService()
        }

        _repository = State(initialValue: repo)
        _authSession = State(initialValue: auth)
        _syncCoordinator = State(initialValue: sync)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.accent)
                .environment(repository)
                .environment(authSession)
                .environment(syncCoordinator)
                .environment(\.placesService, placesService)
                .environment(\.movieService, movieService)
                .environment(\.tvService, tvService)
                // Open Library is keyless and rate-limit-friendly, so the
                // Live book service is safe to inject unconditionally.
                // Previews and tests still override with the mock via
                // environment injection when they need a canned dataset.
                .environment(\.bookService, LiveBookSearchService())
                // AniList is also keyless — same reasoning.
                .environment(\.animeService, LiveAniListSearchService())
                .environment(\.mangaService, LiveAniListSearchService())
                .environment(\.gameService, gameService)
                .environment(\.boardGameService, boardGameService)
                .environment(\.musicService, musicService)
                // Deezer's artist search is keyless, so always live.
                .environment(\.artistService, LiveDeezerArtistService())
                .environment(\.steamLibraryService, steamService)
                .environment(\.importStore, importStore)
                .environment(\.router, router)
                .task {
                    await repository.loadAll()
                    // Forget imports whose list no longer exists. Skipped when
                    // nothing loaded, so a failed read can't wipe the queues.
                    if !repository.lists.isEmpty {
                        importStore.prune(keeping: Set(repository.lists.map(\.id)))
                    }
                    #if DEBUG
                    if DemoSeed.isRequested { DemoSeed.seedIfEmpty(repository) }
                    #endif
                    await authSession.attemptSilentRestore()
                    await syncCoordinator.bootstrapIfReady()
                }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // The user "stopping interacting" = the scene going background.
            // Flush any pending Sheets push so the Sheet matches local at
            // rest. Best-effort: iOS gives us roughly 30s of background time;
            // if a push doesn't complete it'll get retried next session.
            if newPhase == .background {
                Task { await syncCoordinator.flushNow() }
            }
        }
    }
}

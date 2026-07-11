// SpeedTypeView.swift
// Monkeys
//
// A monkey-themed typing speed challenge game.
// Type words and phrases as fast as possible to measure your WPM!
// Features 4 difficulty levels: Beginner, Intermediate, Expert, Master

import Cocoa

final class SpeedTypeView: NSView {

    // MARK: - Types

    enum GamePhase {
        case waiting    // Level selection screen
        case countdown  // 3-2-1 pre-game countdown
        case playing    // Active typing
        case finished   // Results screen
    }

    struct Confetto {
        var position: CGPoint
        var velocity: CGVector
        var color: NSColor
        var size: CGFloat
        var spin: CGFloat
        var spinSpeed: CGFloat
    }

    enum DifficultyLevel: Int, CaseIterable {
        case beginner = 1
        case intermediate = 2
        case expert = 3
        case master = 4

        var locKey: String {
            switch self {
            case .beginner: return "st_beginner"
            case .intermediate: return "st_intermediate"
            case .expert: return "st_expert"
            case .master: return "st_master"
            }
        }

        var emoji: String {
            switch self {
            case .beginner: return "🌱"
            case .intermediate: return "🌿"
            case .expert: return "🌴"
            case .master: return "👑"
            }
        }

        var color: NSColor {
            switch self {
            case .beginner: return NSColor(red: 0.4, green: 0.9, blue: 0.4, alpha: 1.0)
            case .intermediate: return NSColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)
            case .expert: return NSColor(red: 1.0, green: 0.5, blue: 0.2, alpha: 1.0)
            case .master: return NSColor(red: 1.0, green: 0.2, blue: 0.4, alpha: 1.0)
            }
        }

        var highScoreKey: String {
            return "MonkeysSpeedTypeWPM_\(rawValue)"
        }

        var gameDuration: TimeInterval {
            switch self {
            case .beginner: return 60.0
            case .intermediate: return 60.0
            case .expert: return 60.0
            case .master: return 90.0
            }
        }
    }

    // MARK: - Callbacks

    var onStartMusic: (() -> Void)?
    var onStopMusic: (() -> Void)?
    var onPlaySuccessSound: (() -> Void)?
    var onPlayFailSound: (() -> Void)?
    var onPlayComboSound: ((Int) -> Void)?
    var onPlayLevelUpSound: (() -> Void)?
    var onPlayCountdownTick: (() -> Void)?
    var onPlayCountdownGo: (() -> Void)?
    var onPlayRecordSound: (() -> Void)?

    // MARK: - Word Banks (Beginner: single words)

    private let italianBeginner: [String] = [
        "banana", "scimmia", "albero", "giungla", "liana",
        "cocco", "palma", "foglia", "ramo", "frutto",
        "salto", "mango", "bosco", "zampa", "coda",
        "nido", "sole", "luna", "vento", "pioggia",
        "fiore", "erba", "roccia", "acqua", "fuoco",
        "cielo", "terra", "mare", "ponte", "casa",
        "verde", "rosso", "giallo", "blu", "corsa",
    ]

    private let englishBeginner: [String] = [
        "banana", "monkey", "tree", "jungle", "vine",
        "coconut", "palm", "leaf", "branch", "fruit",
        "jump", "mango", "forest", "paw", "tail",
        "nest", "sun", "moon", "wind", "rain",
        "flower", "grass", "rock", "water", "fire",
        "sky", "earth", "sea", "bridge", "house",
        "green", "red", "yellow", "blue", "run",
    ]

    private let spanishBeginner: [String] = [
        "banana", "mono", "\u{00E1}rbol", "selva", "liana",
        "coco", "palma", "hoja", "rama", "fruta",
        "salto", "mango", "bosque", "pata", "cola",
        "nido", "sol", "luna", "viento", "lluvia",
        "flor", "hierba", "roca", "agua", "fuego",
        "cielo", "tierra", "mar", "puente", "casa",
    ]

    private let frenchBeginner: [String] = [
        "banane", "singe", "arbre", "jungle", "liane",
        "noix", "palme", "feuille", "branche", "fruit",
        "saut", "mangue", "for\u{00EA}t", "patte", "queue",
        "nid", "soleil", "lune", "vent", "pluie",
        "fleur", "herbe", "roche", "eau", "feu",
        "ciel", "terre", "mer", "pont", "maison",
    ]

    private let germanBeginner: [String] = [
        "Banane", "Affe", "Baum", "Dschungel", "Liane",
        "Kokos", "Palme", "Blatt", "Ast", "Frucht",
        "Sprung", "Mango", "Wald", "Pfote", "Schwanz",
        "Nest", "Sonne", "Mond", "Wind", "Regen",
        "Blume", "Gras", "Felsen", "Wasser", "Feuer",
        "Himmel", "Erde", "Meer", "Br\u{00FC}cke", "Haus",
    ]

    private let portugueseBeginner: [String] = [
        "banana", "macaco", "\u{00E1}rvore", "selva", "cip\u{00F3}",
        "coco", "palma", "folha", "galho", "fruta",
        "salto", "manga", "floresta", "pata", "cauda",
        "ninho", "sol", "lua", "vento", "chuva",
        "flor", "grama", "rocha", "\u{00E1}gua", "fogo",
        "c\u{00E9}u", "terra", "mar", "ponte", "casa",
    ]

    // MARK: - Word Banks (Intermediate: short phrases)

    private let italianIntermediate: [String] = [
        "la scimmia salta", "banana matura", "nella giungla",
        "sopra il ramo", "mangia il frutto", "corre veloce",
        "sotto la palma", "tra le foglie", "gioca felice",
        "salta in alto", "ride contenta", "cerca il cibo",
        "balla con gioia", "guarda il cielo", "nuota nel fiume",
        "scala la montagna", "trova il tesoro", "suona il tamburo",
    ]

    private let englishIntermediate: [String] = [
        "the monkey jumps", "ripe banana", "in the jungle",
        "on the branch", "eat the fruit", "runs fast",
        "under the palm", "between leaves", "plays happy",
        "jumps high", "laughing loud", "looking for food",
        "dancing with joy", "watching the sky", "swimming in river",
        "climbing the mountain",
    ]

    private let spanishIntermediate: [String] = [
        "el mono salta", "banana madura", "en la selva",
        "sobre la rama", "come la fruta", "corre r\u{00E1}pido",
        "bajo la palma", "entre las hojas", "juega feliz",
        "salta alto", "busca comida", "baila contento",
    ]

    private let frenchIntermediate: [String] = [
        "le singe saute", "banane m\u{00FB}re", "dans la jungle",
        "sur la branche", "mange le fruit", "court vite",
        "sous le palmier", "entre les feuilles", "joue content",
        "saute haut", "cherche la nourriture", "danse joyeux",
    ]

    private let germanIntermediate: [String] = [
        "der Affe springt", "reife Banane", "im Dschungel",
        "auf dem Ast", "isst die Frucht", "rennt schnell",
        "unter der Palme", "zwischen Bl\u{00E4}ttern", "spielt fr\u{00F6}hlich",
        "springt hoch", "sucht Nahrung", "tanzt lustig",
    ]

    private let portugueseIntermediate: [String] = [
        "o macaco pula", "banana madura", "na selva",
        "sobre o galho", "come a fruta", "corre r\u{00E1}pido",
        "sob a palma", "entre as folhas", "brinca feliz",
        "pula alto", "procura comida", "danca contente",
    ]

    // MARK: - Word Banks (Expert: full sentences)

    private let italianExpert: [String] = [
        "la scimmia mangia una banana gialla",
        "salta da un albero all'altro velocemente",
        "nella giungla tropicale piove forte",
        "le scimmie giocano tra i rami alti",
        "il piccolo gorilla cerca sua madre",
        "banane fresche sotto la grande palma",
        "la giungla si risveglia al mattino presto",
        "le scimmie urlano quando arriva la pioggia",
        "il tramonto colora la foresta di arancione",
        "una famiglia di scimmie riposa sugli alberi",
    ]

    private let englishExpert: [String] = [
        "the monkey eats a yellow banana",
        "jumping from one tree to another quickly",
        "in the tropical jungle it rains heavily",
        "the monkeys play between the tall branches",
        "the little gorilla looks for his mother",
        "fresh bananas under the big palm tree",
        "the jungle wakes up early in the morning",
        "the monkeys scream when the rain arrives",
        "the sunset colors the forest in orange",
        "a family of monkeys rests on the trees",
    ]

    private let spanishExpert: [String] = [
        "el mono come una banana amarilla",
        "saltando de un \u{00E1}rbol a otro r\u{00E1}pidamente",
        "en la selva tropical llueve fuerte",
        "los monos juegan entre las ramas altas",
        "el peque\u{00F1}o gorila busca a su madre",
        "bananas frescas bajo la gran palmera",
        "la selva se despierta temprano por la ma\u{00F1}ana",
        "los monos gritan cuando llega la lluvia",
    ]

    private let frenchExpert: [String] = [
        "le singe mange une banane jaune",
        "sautant d'un arbre \u{00E0} l'autre rapidement",
        "dans la jungle tropicale il pleut fort",
        "les singes jouent entre les hautes branches",
        "le petit gorille cherche sa m\u{00E8}re partout",
        "des bananes sous le grand palmier vert",
        "la jungle se reveille tot le matin",
        "les singes crient quand la pluie arrive",
    ]

    private let germanExpert: [String] = [
        "der Affe isst eine gelbe Banane",
        "von einem Baum zum anderen springen",
        "im tropischen Dschungel regnet es stark",
        "die Affen spielen zwischen den hohen \u{00C4}sten",
        "der kleine Gorilla sucht seine Mutter",
        "frische Bananen unter der grossen Palme",
        "der Dschungel erwacht fr\u{00FC}h am Morgen",
        "die Affen schreien wenn der Regen kommt",
    ]

    private let portugueseExpert: [String] = [
        "o macaco come uma banana amarela",
        "pulando de uma \u{00E1}rvore para outra rapidamente",
        "na selva tropical chove forte",
        "os macacos brincam entre os galhos altos",
        "o pequeno gorila procura sua m\u{00E3}e",
        "bananas frescas sob a grande palmeira",
        "a selva acorda cedo pela manh\u{00E3}",
        "os macacos gritam quando a chuva chega",
    ]

    // MARK: - Word Banks (Master: long complex sentences with punctuation)

    private let italianMaster: [String] = [
        "la vecchia scimmia saggia osserva il tramonto dalla cima dell'albero piu alto della giungla",
        "durante la stagione delle piogge, le scimmie costruiscono ripari con foglie e rami intrecciati",
        "il giovane gorilla impara a riconoscere i frutti velenosi da quelli commestibili nella foresta",
        "all'alba, il canto degli uccelli risveglia la giungla e le scimmie iniziano la loro giornata",
        "una colonia di scimmie attraversa il fiume impetuoso saltando da una roccia all'altra con agilita",
        "il vecchio albero di banane, piegato dal vento e dalla pioggia, offre ancora frutti dolcissimi",
        "nella profondita della foresta pluviale, dove la luce del sole filtra appena tra le foglie dense",
        "le scimmie comunicano tra loro con una serie complessa di suoni, gesti e espressioni facciali",
        "sotto il cielo stellato della giungla, gli animali notturni escono dalle loro tane per cacciare",
        "il piccolo macaco si aggrappa alla schiena della madre mentre lei salta agilmente tra i rami alti",
    ]

    private let englishMaster: [String] = [
        "the wise old monkey watches the sunset from the top of the tallest tree in the jungle",
        "during the rainy season, the monkeys build shelters using leaves and intertwined branches",
        "the young gorilla learns to distinguish poisonous fruits from edible ones in the deep forest",
        "at dawn, the birds' singing wakes up the entire jungle and the monkeys begin their daily routine",
        "a colony of monkeys crosses the rushing river by jumping from one slippery rock to another",
        "the ancient banana tree, bent by wind and rain, still offers its sweet golden fruits to all",
        "in the depths of the tropical rainforest, where sunlight barely filters through the dense canopy",
        "monkeys communicate with each other through a complex series of sounds, gestures and facial expressions",
        "under the starry sky of the jungle, nocturnal creatures emerge from their dens to hunt for food",
        "the little macaque clings tightly to its mother's back while she leaps gracefully between tall branches",
    ]

    private let spanishMaster: [String] = [
        "el viejo mono sabio observa la puesta de sol desde la copa del arbol mas alto de la selva",
        "durante la temporada de lluvias, los monos construyen refugios con hojas y ramas entrelazadas",
        "el joven gorila aprende a distinguir los frutos venenosos de los comestibles en el bosque profundo",
        "al amanecer, el canto de los pajaros despierta toda la selva y los monos comienzan su rutina diaria",
        "una colonia de monos cruza el rio caudaloso saltando de una roca resbaladiza a otra con gran agilidad",
        "el viejo arbol de bananas, doblado por el viento y la lluvia, aun ofrece sus dulces frutos dorados",
        "en las profundidades de la selva tropical, donde la luz del sol apenas se filtra entre el denso follaje",
        "los monos se comunican entre si a traves de una serie compleja de sonidos, gestos y expresiones faciales",
    ]

    private let frenchMaster: [String] = [
        "le vieux singe sage observe le coucher du soleil depuis le sommet de l'arbre le plus haut de la jungle",
        "pendant la saison des pluies, les singes construisent des abris avec des feuilles et des branches entrelacees",
        "le jeune gorille apprend a distinguer les fruits venimeux des fruits comestibles dans la foret profonde",
        "a l'aube, le chant des oiseaux reveille toute la jungle et les singes commencent leur routine quotidienne",
        "une colonie de singes traverse la riviere tumultueuse en sautant d'un rocher glissant a l'autre avec agilite",
        "le vieil arbre a bananes, courbe par le vent et la pluie, offre encore ses doux fruits dores a tous",
        "les singes communiquent entre eux a travers une serie complexe de sons, gestes et expressions faciales",
        "sous le ciel etoile de la jungle, les creatures nocturnes sortent de leurs tannieres pour chasser la nuit",
    ]

    private let germanMaster: [String] = [
        "der alte weise Affe beobachtet den Sonnenuntergang von der Spitze des hoechsten Baumes im Dschungel",
        "waehrend der Regenzeit bauen die Affen Unterschlupf aus Blaettern und verflochtenen Aesten im Wald",
        "der junge Gorilla lernt giftige Fruechte von essbaren im tiefen Wald zu unterscheiden und zu erkennen",
        "bei Tagesanbruch weckt der Vogelgesang den gesamten Dschungel und die Affen beginnen ihren Tagesablauf",
        "eine Kolonie von Affen ueberquert den reissenden Fluss indem sie von einem rutschigen Felsen zum naechsten springt",
        "der alte Bananenbaum vom Wind und Regen gebeugt bietet immer noch seine suessen goldenen Fruechte an",
        "die Affen kommunizieren miteinander durch eine komplexe Reihe von Lauten und Gesichtsausdruecken",
        "unter dem Sternenhimmel des Dschungels kommen die nachtaktiven Tiere aus ihren Hoehlen zum Jagen heraus",
    ]

    private let portugueseMaster: [String] = [
        "o velho macaco sabio observa o por do sol do topo da arvore mais alta da selva tropical inteira",
        "durante a estacao das chuvas, os macacos constroem abrigos usando folhas e galhos entrelocados",
        "o jovem gorila aprende a distinguir frutos venenosos dos comestiveis na floresta tropical profunda",
        "ao amanhecer, o canto dos passaros acorda toda a selva e os macacos comecam sua rotina diaria",
        "uma colonia de macacos atravessa o rio caudaloso pulando de uma pedra escorregadia para outra com agilidade",
        "a velha arvore de bananas, curvada pelo vento e pela chuva, ainda oferece seus doces frutos dourados",
        "os macacos se comunicam entre si atraves de uma serie complexa de sons, gestos e expressoes faciais",
        "sob o ceu estrelado da selva, as criaturas noturnas saem de suas tocas para cacar durante a noite inteira",
    ]

    // MARK: - Word Bank Selection

    private func wordBanksForCurrentLanguage() -> (beginner: [String], intermediate: [String], expert: [String], master: [String]) {
        switch L.shared.current {
        case .it:
            return (italianBeginner, italianIntermediate, italianExpert, italianMaster)
        case .es:
            return (spanishBeginner, spanishIntermediate, spanishExpert, spanishMaster)
        case .fr:
            return (frenchBeginner, frenchIntermediate, frenchExpert, frenchMaster)
        case .de:
            return (germanBeginner, germanIntermediate, germanExpert, germanMaster)
        case .pt:
            return (portugueseBeginner, portugueseIntermediate, portugueseExpert, portugueseMaster)
        default:
            return (englishBeginner, englishIntermediate, englishExpert, englishMaster)
        }
    }

    // MARK: - Game State

    private var phase: GamePhase = .waiting
    private var currentText: String = ""
    private var typedText: String = ""
    private var wordsCompleted: Int = 0
    private var totalCharsTyped: Int = 0
    private var correctChars: Int = 0
    private var wrongChars: Int = 0
    private var combo: Int = 0
    private var bestCombo: Int = 0

    // Chosen level
    private var selectedLevel: DifficultyLevel = .beginner
    private var selectedLevelIndex: Int = 0  // For UI navigation

    // Timer
    private var gameDuration: TimeInterval = 60.0
    private var startTime: Date?
    private var timeRemaining: TimeInterval = 60.0

    // Animation
    private var gameTimer: Timer?
    private var frameCount: Int = 0

    // Monkey reactions
    private var monkeyEmoji: String = "🐵"
    private var monkeyReactionFrames: Int = 0

    // Floating bananas for decoration
    private var floatingBananas: [(x: CGFloat, y: CGFloat, speed: CGFloat, phase: CGFloat)] = []

    // High scores per level
    private var highScoreWPM: Int = 0

    // Level selection hover
    private var hoveredLevel: Int = -1

    // Pre-game countdown (3-2-1-GO)
    private var countdownFrames: Int = 0

    // WPM sampled once per second while playing, for the results chart
    private var wpmHistory: [Int] = []

    // New-record celebration
    private var finishedAsRecord: Bool = false
    private var confetti: [Confetto] = []

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        generateFloatingBananas()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        generateFloatingBananas()
    }

    private func generateFloatingBananas() {
        floatingBananas = (0..<8).map { _ in
            (
                x: CGFloat.random(in: 0...500),
                y: CGFloat.random(in: 100...450),
                speed: CGFloat.random(in: 0.2...0.6),
                phase: CGFloat.random(in: 0...(.pi * 2))
            )
        }
    }

    // MARK: - Game Control

    func resetGame() {
        phase = .waiting
        typedText = ""
        wordsCompleted = 0
        totalCharsTyped = 0
        correctChars = 0
        wrongChars = 0
        combo = 0
        bestCombo = 0
        timeRemaining = 60.0
        startTime = nil
        monkeyEmoji = "🐵"
        monkeyReactionFrames = 0
        selectedLevelIndex = 0
        countdownFrames = 0
        wpmHistory = []
        finishedAsRecord = false
        confetti.removeAll()
        loadHighScore()
        pickNewText()

        gameTimer?.invalidate()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.gameTick()
            }
        }
    }

    private func loadHighScore() {
        highScoreWPM = UserDefaults.standard.integer(forKey: selectedLevel.highScoreKey)
    }

    private func beginCountdown() {
        phase = .countdown
        countdownFrames = 180 // 3 seconds at 60 fps
        onPlayCountdownTick?()
        onStartMusic?()
    }

    private func startPlaying() {
        phase = .playing
        gameDuration = selectedLevel.gameDuration
        timeRemaining = gameDuration
        startTime = Date()
        typedText = ""
        wordsCompleted = 0
        totalCharsTyped = 0
        correctChars = 0
        wrongChars = 0
        combo = 0
        bestCombo = 0
        wpmHistory = []
        finishedAsRecord = false
        confetti.removeAll()
        loadHighScore()
        pickNewText()
    }

    private func pickNewText() {
        let banks = wordBanksForCurrentLanguage()
        switch selectedLevel {
        case .beginner:
            currentText = banks.beginner.randomElement()!
        case .intermediate:
            currentText = banks.intermediate.randomElement()!
        case .expert:
            currentText = banks.expert.randomElement()!
        case .master:
            currentText = banks.master.randomElement()!
        }
        typedText = ""
    }

    private func gameTick() {
        frameCount += 1

        // Update floating bananas
        for i in 0..<floatingBananas.count {
            floatingBananas[i].x += floatingBananas[i].speed
            if floatingBananas[i].x > bounds.width + 30 {
                floatingBananas[i].x = -30
                floatingBananas[i].y = CGFloat.random(in: 100...450)
            }
        }

        // Monkey reaction timer
        if monkeyReactionFrames > 0 {
            monkeyReactionFrames -= 1
            if monkeyReactionFrames == 0 {
                monkeyEmoji = "🐵"
            }
        }

        // Countdown phase: tick every second, then GO
        if phase == .countdown {
            countdownFrames -= 1
            if countdownFrames == 120 || countdownFrames == 60 {
                onPlayCountdownTick?()
            } else if countdownFrames <= 0 {
                onPlayCountdownGo?()
                startPlaying()
            }
        }

        if phase == .playing, let start = startTime {
            let elapsed = Date().timeIntervalSince(start)
            timeRemaining = max(0, gameDuration - elapsed)

            // Sample live WPM once per second for the results chart
            if frameCount % 60 == 0 {
                wpmHistory.append(calculateWPM())
            }

            if timeRemaining <= 0 {
                endGame()
            }
        }

        // Confetti physics on the results screen
        if phase == .finished && !confetti.isEmpty {
            for i in 0..<confetti.count {
                confetti[i].position.x += confetti[i].velocity.dx
                confetti[i].position.y += confetti[i].velocity.dy
                confetti[i].velocity.dy -= 0.06
                confetti[i].velocity.dx *= 0.99
                confetti[i].spin += confetti[i].spinSpeed
            }
            confetti.removeAll { $0.position.y < -20 }
        }

        setNeedsDisplay(bounds)
    }

    private func endGame() {
        phase = .finished
        onStopMusic?()
        let wpm = calculateWPM()
        wpmHistory.append(wpm)
        if wpm > highScoreWPM && wpm > 0 {
            highScoreWPM = wpm
            UserDefaults.standard.set(highScoreWPM, forKey: selectedLevel.highScoreKey)
            finishedAsRecord = true
            spawnConfetti()
            onPlayRecordSound?()
        }
    }

    private func spawnConfetti() {
        let palette: [NSColor] = [
            NSColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0),
            NSColor(red: 0.4, green: 1.0, blue: 0.5, alpha: 1.0),
            NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0),
            NSColor(red: 1.0, green: 0.45, blue: 0.55, alpha: 1.0),
            NSColor(red: 0.85, green: 0.55, blue: 1.0, alpha: 1.0),
        ]
        confetti = (0..<70).map { _ in
            Confetto(
                position: CGPoint(x: CGFloat.random(in: 0...bounds.width),
                                  y: bounds.height + CGFloat.random(in: 0...120)),
                velocity: CGVector(dx: CGFloat.random(in: -0.8...0.8),
                                   dy: CGFloat.random(in: -2.2 ... -0.8)),
                color: palette.randomElement()!,
                size: CGFloat.random(in: 4...8),
                spin: CGFloat.random(in: 0...(.pi * 2)),
                spinSpeed: CGFloat.random(in: -0.15...0.15)
            )
        }
    }

    private func calculateWPM() -> Int {
        guard let start = startTime else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return 0 }
        // Standard: 1 word = 5 characters
        let minutes = elapsed / 60.0
        return Int(Double(correctChars) / 5.0 / minutes)
    }

    private func calculateAccuracy() -> Int {
        guard totalCharsTyped > 0 else { return 100 }
        return Int(Double(correctChars) / Double(totalCharsTyped) * 100)
    }

    // MARK: - Key Input

    /// Called from SpeedTypeWindow for arrow key navigation (by keyCode)
    func navigateLevel(direction: Int) {
        guard phase == .waiting else { return }
        if direction < 0 {
            // Up: move selection upward (lower index)
            selectedLevelIndex = max(selectedLevelIndex - 1, 0)
        } else {
            // Down: move selection downward (higher index)
            selectedLevelIndex = min(selectedLevelIndex + 1, DifficultyLevel.allCases.count - 1)
        }
        selectedLevel = DifficultyLevel.allCases[selectedLevelIndex]
        loadHighScore()
    }

    func handleKeyTyped(_ char: Character) {
        if phase == .waiting {
            // Number keys 1-4 to select level directly
            if let num = char.wholeNumberValue, num >= 1 && num <= 4 {
                selectedLevelIndex = num - 1
                selectedLevel = DifficultyLevel.allCases[selectedLevelIndex]
                loadHighScore()
                return
            }
            // Enter or Space to start
            if char == "\r" || char == " " || char == "\n" {
                beginCountdown()
                return
            }
            return
        }

        if phase == .countdown {
            return
        }

        if phase == .finished {
            resetGame()
            return
        }

        guard phase == .playing else { return }

        // Handle backspace (delete character 127 or 8)
        if char == "\u{7F}" || char == "\u{08}" {
            if !typedText.isEmpty {
                typedText.removeLast()
            }
            return
        }

        // Ignore non-printable characters
        guard char.isPrintableCharacter else { return }

        let targetIndex = typedText.count
        guard targetIndex < currentText.count else { return }

        let targetChar = currentText[currentText.index(currentText.startIndex, offsetBy: targetIndex)]
        typedText.append(char)
        totalCharsTyped += 1

        if char == targetChar {
            correctChars += 1
            combo += 1
            if combo > bestCombo { bestCombo = combo }

            // Word completed?
            if typedText.count == currentText.count {
                wordsCompleted += 1
                onPlaySuccessSound?()

                if combo >= 5 {
                    onPlayComboSound?(combo)
                    monkeyEmoji = "🙉"
                } else {
                    monkeyEmoji = "🐒"
                }
                monkeyReactionFrames = 30

                pickNewText()
            }
        } else {
            wrongChars += 1
            combo = 0
            monkeyEmoji = "🙈"
            monkeyReactionFrames = 20
            onPlayFailSound?()
        }
    }

    // MARK: - Drawing

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width
        let h = bounds.height

        drawBackground(ctx: ctx, w: w, h: h)
        drawFloatingBananas(ctx: ctx)

        switch phase {
        case .waiting:
            drawStartScreen(ctx: ctx, w: w, h: h)
        case .countdown:
            drawCountdownScreen(ctx: ctx, w: w, h: h)
        case .playing:
            drawGameScreen(ctx: ctx, w: w, h: h)
        case .finished:
            drawResultsScreen(ctx: ctx, w: w, h: h)
        }
    }

    // MARK: - Countdown Screen

    private func drawCountdownScreen(ctx: CGContext, w: CGFloat, h: CGFloat) {
        // Difficulty badge at top
        let diffStr = "\(selectedLevel.emoji) \(L.shared.s(selectedLevel.locKey))"
        drawCentered(diffStr, y: h - 90, size: 16, color: selectedLevel.color, in: w)

        // "Get ready…"
        drawCentered(L.shared.s("st_get_ready"), y: h / 2 + 80, size: 20, bold: true,
                     color: NSColor(white: 0.9, alpha: 1.0), in: w)

        // Big countdown number with a pop-in scale each second
        let secondsLeft = (max(countdownFrames, 1) - 1) / 60 + 1
        let frameInSecond = (max(countdownFrames, 1) - 1) % 60
        let popScale = 1.0 + 0.5 * (CGFloat(frameInSecond) / 60.0)
        let numberSize = 72.0 * popScale
        let alpha = 0.4 + 0.6 * (CGFloat(frameInSecond) / 60.0)

        let numberStr = "\(secondsLeft)" as NSString
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: numberSize),
            .foregroundColor: selectedLevel.color.withAlphaComponent(alpha),
        ]
        let ns = numberStr.size(withAttributes: numberAttrs)
        numberStr.draw(at: NSPoint(x: w / 2 - ns.width / 2, y: h / 2 - ns.height / 2), withAttributes: numberAttrs)

        // Monkey warming up its paws
        drawCentered("🐵⌨️", y: h / 2 - 120, size: 34, color: .white, in: w)
    }

    // MARK: - Background

    private func drawBackground(ctx: CGContext, w: CGFloat, h: CGFloat) {
        // Jungle gradient
        let topColor = NSColor(red: 0.05, green: 0.18, blue: 0.08, alpha: 1.0)
        let bottomColor = NSColor(red: 0.02, green: 0.08, blue: 0.03, alpha: 1.0)
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [bottomColor.cgColor, topColor.cgColor] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])

        // Vine decorations on sides
        let vineColor = NSColor(red: 0.15, green: 0.45, blue: 0.12, alpha: 0.3)
        ctx.setFillColor(vineColor.cgColor)
        for i in stride(from: 0, to: Int(h), by: 40) {
            let sway = sin(CGFloat(frameCount) * 0.02 + CGFloat(i) * 0.1) * 8
            ctx.fillEllipse(in: CGRect(x: sway - 5, y: CGFloat(i), width: 12, height: 25))
            ctx.fillEllipse(in: CGRect(x: w - 8 + sway, y: CGFloat(i) + 20, width: 12, height: 25))
        }
    }

    private func drawFloatingBananas(ctx: CGContext) {
        for banana in floatingBananas {
            let yOffset = sin(CGFloat(frameCount) * 0.03 + banana.phase) * 10
            let alpha = 0.15 + 0.1 * sin(CGFloat(frameCount) * 0.02 + banana.phase)
            let alphaAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 18),
                .foregroundColor: NSColor(white: 1.0, alpha: alpha),
            ]
            ("🍌" as NSString).draw(at: NSPoint(x: banana.x, y: banana.y + yOffset), withAttributes: alphaAttrs)
        }
    }

    // MARK: - Start Screen (Level Selection)

    private func drawStartScreen(ctx: CGContext, w: CGFloat, h: CGFloat) {
        // Big monkey
        let monkeyStr = "🐵" as NSString
        let monkeyAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 55)]
        let ms = monkeyStr.size(withAttributes: monkeyAttrs)
        monkeyStr.draw(at: NSPoint(x: w / 2 - ms.width / 2, y: h - 80), withAttributes: monkeyAttrs)

        // Title
        drawCentered(L.shared.s("st_title"), y: h - 100, size: 22, bold: true,
                     color: NSColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0), in: w)

        // Subtitle
        drawCentered(L.shared.s("st_choose_level"), y: h - 130, size: 14,
                     color: NSColor(white: 0.8, alpha: 1.0), in: w)

        // Draw level cards
        let cardWidth: CGFloat = w - 60
        let cardHeight: CGFloat = 56
        let cardSpacing: CGFloat = 8
        let totalCardsHeight = CGFloat(DifficultyLevel.allCases.count) * (cardHeight + cardSpacing)
        let startY = h / 2 + totalCardsHeight / 2 - 30

        for (index, level) in DifficultyLevel.allCases.enumerated() {
            let cardY = startY - CGFloat(index) * (cardHeight + cardSpacing)
            let cardRect = CGRect(x: 30, y: cardY, width: cardWidth, height: cardHeight)
            let isSelected = index == selectedLevelIndex

            // Card background
            if isSelected {
                // Glowing selected card
                let glowAlpha = 0.15 + 0.05 * sin(CGFloat(frameCount) * 0.05)
                ctx.setFillColor(level.color.withAlphaComponent(glowAlpha).cgColor)
                let glowRect = cardRect.insetBy(dx: -3, dy: -3)
                let glowPath = CGPath(roundedRect: glowRect, cornerWidth: 14, cornerHeight: 14, transform: nil)
                ctx.addPath(glowPath)
                ctx.fillPath()

                ctx.setFillColor(NSColor(white: 0.12, alpha: 0.95).cgColor)
            } else {
                ctx.setFillColor(NSColor(white: 0.08, alpha: 0.7).cgColor)
            }

            let cardPath = CGPath(roundedRect: cardRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
            ctx.addPath(cardPath)
            ctx.fillPath()

            // Selected indicator border
            if isSelected {
                ctx.setStrokeColor(level.color.withAlphaComponent(0.8).cgColor)
                ctx.setLineWidth(2.0)
                ctx.addPath(cardPath)
                ctx.strokePath()
            }

            // Level emoji + name
            let levelName = "\(level.emoji) \(L.shared.s(level.locKey))"
            let nameColor = isSelected ? level.color : NSColor(white: 0.7, alpha: 1.0)
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: isSelected ? 17 : 15),
                .foregroundColor: nameColor,
            ]
            (levelName as NSString).draw(at: NSPoint(x: cardRect.minX + 15, y: cardRect.minY + cardHeight / 2 - 2), withAttributes: nameAttrs)

            // Level description
            let descKey = "st_desc_\(level.rawValue)"
            let desc = L.shared.s(descKey)
            let descAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor(white: 0.5, alpha: isSelected ? 1.0 : 0.7),
            ]
            (desc as NSString).draw(at: NSPoint(x: cardRect.minX + 15, y: cardRect.minY + 8), withAttributes: descAttrs)

            // High score for this level
            let lvlScore = UserDefaults.standard.integer(forKey: level.highScoreKey)
            if lvlScore > 0 {
                let scoreStr = "🏆 \(lvlScore) WPM" as NSString
                let scoreAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor(red: 1.0, green: 0.85, blue: 0.3, alpha: isSelected ? 1.0 : 0.6),
                ]
                let scoreSize = scoreStr.size(withAttributes: scoreAttrs)
                scoreStr.draw(at: NSPoint(x: cardRect.maxX - scoreSize.width - 15, y: cardRect.midY - scoreSize.height / 2), withAttributes: scoreAttrs)
            }

            // Number shortcut
            let numStr = "\(index + 1)" as NSString
            let numAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor(white: 0.4, alpha: 0.6),
            ]
            let numSize = numStr.size(withAttributes: numAttrs)
            numStr.draw(at: NSPoint(x: cardRect.maxX - numSize.width - 8, y: cardRect.minY + 5), withAttributes: numAttrs)
        }

        // Navigation hint
        let navHintY = startY - CGFloat(DifficultyLevel.allCases.count) * (cardHeight + cardSpacing) - 10
        drawCentered(L.shared.s("st_nav_hint"), y: navHintY, size: 11,
                     color: NSColor(white: 0.45, alpha: 0.8), in: w)

        // Pulsing start
        let pulse = 0.5 + 0.5 * sin(CGFloat(frameCount) * 0.06)
        drawCentered(L.shared.s("g_press_start"), y: navHintY - 25, size: 15,
                     color: NSColor(white: 1.0, alpha: pulse), in: w)

        // Keyboard decoration
        drawCentered("⌨️🐒🍌", y: navHintY - 60, size: 26,
                     color: .white, in: w)
    }

    // MARK: - Game Screen

    private func drawGameScreen(ctx: CGContext, w: CGFloat, h: CGFloat) {
        // Top HUD bar
        ctx.setFillColor(NSColor(white: 0.0, alpha: 0.5).cgColor)
        ctx.fill(CGRect(x: 0, y: h - 50, width: w, height: 50))

        // Timer
        let timeStr = String(format: "⏱ %.0f", timeRemaining)
        let timeColor: NSColor = timeRemaining < 10 ?
            NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0) :
            NSColor(white: 1.0, alpha: 1.0)
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .bold),
            .foregroundColor: timeColor,
        ]
        (timeStr as NSString).draw(at: NSPoint(x: 15, y: h - 40), withAttributes: timeAttrs)

        // Live WPM
        let liveWPM = calculateWPM()
        let wpmStr = "\(liveWPM) WPM" as NSString
        let wpmAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor(red: 0.4, green: 1.0, blue: 0.5, alpha: 1.0),
        ]
        let wpmSize = wpmStr.size(withAttributes: wpmAttrs)
        wpmStr.draw(at: NSPoint(x: w / 2 - wpmSize.width / 2, y: h - 40), withAttributes: wpmAttrs)

        // Words completed
        let wordsStr = "✅ \(wordsCompleted)" as NSString
        let wordsAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.white,
        ]
        let wordsSize = wordsStr.size(withAttributes: wordsAttrs)
        wordsStr.draw(at: NSPoint(x: w - wordsSize.width - 15, y: h - 38), withAttributes: wordsAttrs)

        // Timer progress bar
        let barY = h - 52
        let progress = CGFloat(timeRemaining / gameDuration)
        ctx.setFillColor(NSColor(white: 0.2, alpha: 0.5).cgColor)
        ctx.fill(CGRect(x: 0, y: barY, width: w, height: 3))
        let barColor: NSColor = timeRemaining < 10 ?
            NSColor(red: 1.0, green: 0.3, blue: 0.2, alpha: 1.0) :
            NSColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1.0)
        ctx.setFillColor(barColor.cgColor)
        ctx.fill(CGRect(x: 0, y: barY, width: w * progress, height: 3))

        // Difficulty badge
        let diffStr = "\(selectedLevel.emoji) \(L.shared.s(selectedLevel.locKey))"
        let diffAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: selectedLevel.color,
        ]
        (diffStr as NSString).draw(at: NSPoint(x: 15, y: h - 65), withAttributes: diffAttrs)

        // Monkey emoji (reactive)
        let monkeyStr = monkeyEmoji as NSString
        let monkeyAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 50)]
        let mSize = monkeyStr.size(withAttributes: monkeyAttrs)
        let bounce = monkeyReactionFrames > 0 ? sin(CGFloat(monkeyReactionFrames) * 0.5) * 5 : 0
        monkeyStr.draw(at: NSPoint(x: w / 2 - mSize.width / 2, y: h - 135 + bounce), withAttributes: monkeyAttrs)

        // Combo indicator
        if combo >= 3 {
            let comboStr = "🔥 \(combo)x" as NSString
            let comboAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 16),
                .foregroundColor: NSColor(red: 1.0, green: 0.6, blue: 0.1, alpha: 1.0),
            ]
            let cSize = comboStr.size(withAttributes: comboAttrs)
            comboStr.draw(at: NSPoint(x: w / 2 - cSize.width / 2, y: h - 155), withAttributes: comboAttrs)
        }

        // Target text area (the text to type)
        let textAreaY = h / 2 + 10
        let textAreaH: CGFloat = 60
        let textAreaRect = CGRect(x: 20, y: textAreaY, width: w - 40, height: textAreaH)

        // Background panel
        ctx.setFillColor(NSColor(white: 0.0, alpha: 0.4).cgColor)
        let panelPath = CGPath(roundedRect: textAreaRect.insetBy(dx: -10, dy: -10),
                               cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.addPath(panelPath)
        ctx.fillPath()

        // Draw target text with colored characters
        drawTargetText(in: textAreaRect, w: w)

        // Input area (what user has typed)
        let inputY = h / 2 - 70
        let inputRect = CGRect(x: 30, y: inputY, width: w - 60, height: 36)

        // Input background
        ctx.setFillColor(NSColor(white: 0.1, alpha: 0.6).cgColor)
        let inputPath = CGPath(roundedRect: inputRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.addPath(inputPath)
        ctx.fillPath()

        // Cursor blink
        let cursorVisible = Int(frameCount / 30) % 2 == 0
        let inputStr = typedText + (cursorVisible ? "▏" : " ")
        let inputAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .regular),
            .foregroundColor: NSColor(white: 0.9, alpha: 1.0),
        ]
        (inputStr as NSString).draw(at: NSPoint(x: inputRect.minX + 8, y: inputRect.minY + 8), withAttributes: inputAttrs)

        // Accuracy display
        let accuracy = calculateAccuracy()
        let accStr = "🎯 \(accuracy)%" as NSString
        let accColor: NSColor = accuracy >= 95 ?
            NSColor(red: 0.4, green: 1.0, blue: 0.5, alpha: 1.0) :
            accuracy >= 80 ?
            NSColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1.0) :
            NSColor(red: 1.0, green: 0.4, blue: 0.3, alpha: 1.0)
        let accAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: accColor,
        ]
        let accSize = accStr.size(withAttributes: accAttrs)
        accStr.draw(at: NSPoint(x: w / 2 - accSize.width / 2, y: inputY - 30), withAttributes: accAttrs)

        // Hint at bottom
        drawCentered(L.shared.s("st_hint"), y: 20, size: 11,
                     color: NSColor(white: 0.5, alpha: 0.7), in: w)
    }

    private func drawTargetText(in rect: CGRect, w: CGFloat) {
        let targetChars = Array(currentText)
        let typedChars = Array(typedText)

        // For master level, use smaller font to fit long sentences
        let fontSize: CGFloat = selectedLevel == .master ? 18 : 24

        var xOffset: CGFloat = rect.minX
        var yPos = rect.minY + (selectedLevel == .master ? 30 : 15)
        let lineHeight: CGFloat = fontSize + 6

        for (i, targetChar) in targetChars.enumerated() {
            let charStr = String(targetChar) as NSString

            let color: NSColor
            let fontWeight: NSFont.Weight
            if i < typedChars.count {
                if typedChars[i] == targetChar {
                    color = NSColor(red: 0.3, green: 1.0, blue: 0.4, alpha: 1.0) // correct - green
                    fontWeight = .bold
                } else {
                    color = NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0) // wrong - red
                    fontWeight = .bold
                }
            } else if i == typedChars.count {
                color = NSColor(red: 1.0, green: 0.95, blue: 0.5, alpha: 1.0) // current - bright yellow
                fontWeight = .bold
            } else {
                color = NSColor(white: 0.6, alpha: 0.8) // upcoming - dim
                fontWeight = .regular
            }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: fontWeight),
                .foregroundColor: color,
            ]
            let charSize = charStr.size(withAttributes: attrs)

            // Wrap to next line if needed (for long master-level texts)
            if xOffset + charSize.width > rect.maxX {
                xOffset = rect.minX
                yPos -= lineHeight
            }

            // Blinking block highlight behind the character to type next
            if i == typedChars.count, let ctx = NSGraphicsContext.current?.cgContext {
                let blink = 0.25 + 0.15 * sin(CGFloat(frameCount) * 0.12)
                ctx.setFillColor(NSColor(red: 1.0, green: 0.95, blue: 0.5, alpha: blink).cgColor)
                let cursorRect = CGRect(x: xOffset - 1, y: yPos - 2,
                                        width: max(charSize.width, fontSize * 0.55) + 2,
                                        height: charSize.height + 2)
                let cursorPath = CGPath(roundedRect: cursorRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
                ctx.addPath(cursorPath)
                ctx.fillPath()
            }

            charStr.draw(at: NSPoint(x: xOffset, y: yPos), withAttributes: attrs)
            xOffset += charSize.width
        }
    }

    // MARK: - Results Screen

    private func drawResultsScreen(ctx: CGContext, w: CGFloat, h: CGFloat) {
        // Dark overlay
        ctx.setFillColor(NSColor(white: 0.0, alpha: 0.5).cgColor)
        ctx.fill(bounds)

        let wpm = calculateWPM()
        let accuracy = calculateAccuracy()
        let isRecord = wpm >= highScoreWPM && wpm > 0

        // Monkey reaction
        let bigMonkey: String
        if wpm >= 80 { bigMonkey = "🦍" }
        else if wpm >= 50 { bigMonkey = "🐒" }
        else if wpm >= 30 { bigMonkey = "🐵" }
        else { bigMonkey = "🙈" }

        let monkeyAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 60)]
        let ms = (bigMonkey as NSString).size(withAttributes: monkeyAttrs)
        (bigMonkey as NSString).draw(at: NSPoint(x: w / 2 - ms.width / 2, y: h / 2 + 140), withAttributes: monkeyAttrs)

        // Title
        let title = isRecord ? L.shared.s("g_new_record") : L.shared.s("st_time_up")
        let titleColor = isRecord ?
            NSColor(red: 1.0, green: 0.85, blue: 0.1, alpha: 1.0) :
            NSColor(white: 1.0, alpha: 1.0)
        drawCentered(title, y: h / 2 + 105, size: 24, bold: true, color: titleColor, in: w)

        // Level played
        let levelStr = "\(selectedLevel.emoji) \(L.shared.s(selectedLevel.locKey))"
        drawCentered(levelStr, y: h / 2 + 80, size: 14,
                     color: selectedLevel.color, in: w)

        // WPM (big)
        drawCentered("\(wpm) WPM", y: h / 2 + 40, size: 42, bold: true,
                     color: NSColor(red: 0.4, green: 1.0, blue: 0.5, alpha: 1.0), in: w)

        // Stats
        drawCentered(L.shared.sf("st_accuracy", accuracy), y: h / 2 + 5, size: 18,
                     color: NSColor(white: 0.9, alpha: 1.0), in: w)
        drawCentered(L.shared.sf("st_words_done", wordsCompleted), y: h / 2 - 20, size: 16,
                     color: NSColor(white: 0.85, alpha: 1.0), in: w)
        drawCentered(L.shared.sf("st_best_combo", bestCombo), y: h / 2 - 45, size: 16,
                     color: NSColor(red: 1.0, green: 0.7, blue: 0.3, alpha: 0.9), in: w)
        drawCentered(L.shared.sf("g_best_score", highScoreWPM), y: h / 2 - 70, size: 14,
                     color: NSColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 0.8), in: w)

        // WPM-over-time chart
        drawWPMChart(ctx: ctx, w: w, h: h)

        // Performance message
        let msg: String
        if wpm >= 80 { msg = L.shared.s("st_living_typewriter") }
        else if wpm >= 60 { msg = L.shared.s("st_fire_fingers") }
        else if wpm >= 40 { msg = L.shared.s("st_great_job") }
        else if wpm >= 20 { msg = L.shared.s("st_good_start") }
        else { msg = L.shared.s("st_keep_trying") }

        drawCentered(msg, y: h / 2 - 150, size: 14,
                     color: NSColor(white: 0.8, alpha: 0.9), in: w)

        // Restart hint
        let pulse = 0.5 + 0.5 * sin(CGFloat(frameCount) * 0.06)
        drawCentered(L.shared.s("g_press_restart"), y: h / 2 - 180, size: 14,
                     color: NSColor(white: 1.0, alpha: pulse), in: w)

        // Confetti on a new record — drawn on top of everything
        drawConfetti(ctx: ctx)
    }

    /// Draws a small line chart of the WPM sampled each second of the run.
    private func drawWPMChart(ctx: CGContext, w: CGFloat, h: CGFloat) {
        guard wpmHistory.count >= 3 else { return }

        let chartW: CGFloat = 220
        let chartH: CGFloat = 34
        let originX = w / 2 - chartW / 2
        let originY = h / 2 - 125

        // Panel
        ctx.setFillColor(NSColor(white: 0.0, alpha: 0.35).cgColor)
        let panel = CGPath(roundedRect: CGRect(x: originX - 8, y: originY - 6, width: chartW + 16, height: chartH + 12),
                           cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.addPath(panel)
        ctx.fillPath()

        let maxWPM = max(wpmHistory.max() ?? 1, 1)
        let stepX = chartW / CGFloat(wpmHistory.count - 1)

        // Line
        ctx.setStrokeColor(NSColor(red: 0.4, green: 1.0, blue: 0.5, alpha: 0.9).cgColor)
        ctx.setLineWidth(2.0)
        ctx.setLineJoin(.round)
        ctx.beginPath()
        for (i, wpmValue) in wpmHistory.enumerated() {
            let x = originX + CGFloat(i) * stepX
            let y = originY + chartH * CGFloat(wpmValue) / CGFloat(maxWPM)
            if i == 0 {
                ctx.move(to: CGPoint(x: x, y: y))
            } else {
                ctx.addLine(to: CGPoint(x: x, y: y))
            }
        }
        ctx.strokePath()

        // End dot
        if let last = wpmHistory.last {
            let x = originX + CGFloat(wpmHistory.count - 1) * stepX
            let y = originY + chartH * CGFloat(last) / CGFloat(maxWPM)
            ctx.setFillColor(NSColor(red: 0.4, green: 1.0, blue: 0.5, alpha: 1.0).cgColor)
            ctx.fillEllipse(in: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
        }
    }

    private func drawConfetti(ctx: CGContext) {
        for piece in confetti {
            ctx.saveGState()
            ctx.translateBy(x: piece.position.x, y: piece.position.y)
            ctx.rotate(by: piece.spin)
            ctx.setFillColor(piece.color.cgColor)
            ctx.fill(CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2))
            ctx.restoreGState()
        }
    }

    // MARK: - Helpers

    private func drawCentered(_ text: String, y: CGFloat, size: CGFloat, bold: Bool = false,
                              color: NSColor = .white, in width: CGFloat) {
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = text as NSString
        let strSize = str.size(withAttributes: attrs)
        str.draw(at: NSPoint(x: width / 2 - strSize.width / 2, y: y), withAttributes: attrs)
    }
}

// MARK: - Character Extension

private extension Character {
    var isPrintableCharacter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        // Allow letters, digits, punctuation, spaces
        return scalar.value >= 32 && scalar.value < 127 ||
               CharacterSet.letters.contains(scalar) ||
               CharacterSet.decimalDigits.contains(scalar)
    }
}

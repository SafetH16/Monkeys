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
        case sprint = 5        // 15 seconds, one breath — the menu-bar snack
        case beginner = 1
        case intermediate = 2
        case expert = 3
        case master = 4
        case drill = 6         // words weighted toward your weakest keys

        var locKey: String {
            switch self {
            case .sprint: return "st_sprint"
            case .drill: return "st_drill"
            case .beginner: return "st_beginner"
            case .intermediate: return "st_intermediate"
            case .expert: return "st_expert"
            case .master: return "st_master"
            }
        }

        var emoji: String {
            switch self {
            case .sprint: return "⚡"
            case .drill: return "🎯"
            case .beginner: return "🌱"
            case .intermediate: return "🌿"
            case .expert: return "🌴"
            case .master: return "👑"
            }
        }

        var color: NSColor {
            switch self {
            case .sprint: return NSColor(red: 0.4, green: 0.85, blue: 1.0, alpha: 1.0)
            case .drill: return NSColor(red: 0.75, green: 0.55, blue: 1.0, alpha: 1.0)
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
            case .sprint: return 15.0
            case .drill: return 60.0
            case .beginner: return 60.0
            case .intermediate: return 60.0
            case .expert: return 60.0
            case .master: return 90.0
            }
        }

        /// GameProgress medal mode key.
        var medalMode: String { self == .sprint ? "speed_sprint" : "speed" }
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
    /// Success chime pitched by the flow tier (semitones up).
    var onPlaySuccessSemitone: ((Int) -> Void)?

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
        "dorme sul ramo", "sbuccia la banana", "chiama gli amici",
        "attraversa il fiume", "raccoglie i frutti", "salta la liana",
        "si nasconde bene", "corre nel bosco", "ride di gusto",
        "vola tra i rami", "beve alla fonte", "gioca a nascondino",
        "insegue la farfalla", "ascolta il vento", "osserva le stelle",
        "costruisce il nido", "difende il territorio", "esplora la valle",
    ]

    private let englishIntermediate: [String] = [
        "the monkey jumps", "ripe banana", "in the jungle",
        "on the branch", "eat the fruit", "runs fast",
        "under the palm", "between leaves", "plays happy",
        "jumps high", "laughing loud", "looking for food",
        "dancing with joy", "watching the sky", "swimming in river",
        "climbing the mountain", "sleeping on the branch", "peeling a banana",
        "calling the friends", "crossing the river", "picking the fruits",
        "grabbing the vine", "hiding really well", "running in the woods",
        "laughing out loud", "flying between trees", "drinking from the spring",
        "playing hide and seek", "chasing the butterfly", "listening to the wind",
        "watching the stars", "building the nest", "guarding the territory",
        "exploring the valley", "sharing the mango", "waking up early",
    ]

    private let spanishIntermediate: [String] = [
        "el mono salta", "banana madura", "en la selva",
        "sobre la rama", "come la fruta", "corre r\u{00E1}pido",
        "bajo la palma", "entre las hojas", "juega feliz",
        "salta alto", "busca comida", "baila contento",
        "duerme en la rama", "pela la banana", "llama a sus amigos",
        "cruza el r\u{00ED}o", "recoge la fruta", "corre en el bosque",
        "r\u{00ED}e con ganas", "mira las estrellas", "explora el valle",
        "construye el nido", "escucha el viento", "comparte el mango",
    ]

    private let frenchIntermediate: [String] = [
        "le singe saute", "banane m\u{00FB}re", "dans la jungle",
        "sur la branche", "mange le fruit", "court vite",
        "sous le palmier", "entre les feuilles", "joue content",
        "saute haut", "cherche la nourriture", "danse joyeux",
        "dort sur la branche", "\u{00E9}pluche la banane", "appelle ses amis",
        "traverse la rivi\u{00E8}re", "cueille les fruits", "court dans les bois",
        "rit aux \u{00E9}clats", "regarde les \u{00E9}toiles", "explore la vall\u{00E9}e",
        "construit le nid", "\u{00E9}coute le vent", "partage la mangue",
    ]

    private let germanIntermediate: [String] = [
        "der Affe springt", "reife Banane", "im Dschungel",
        "auf dem Ast", "isst die Frucht", "rennt schnell",
        "unter der Palme", "zwischen Bl\u{00E4}ttern", "spielt fr\u{00F6}hlich",
        "springt hoch", "sucht Nahrung", "tanzt lustig",
        "schl\u{00E4}ft auf dem Ast", "sch\u{00E4}lt die Banane", "ruft die Freunde",
        "\u{00FC}berquert den Fluss", "pfl\u{00FC}ckt die Fr\u{00FC}chte", "rennt durch den Wald",
        "lacht sehr laut", "schaut die Sterne", "erkundet das Tal",
        "baut das Nest", "h\u{00F6}rt den Wind", "teilt die Mango",
    ]

    private let portugueseIntermediate: [String] = [
        "o macaco pula", "banana madura", "na selva",
        "sobre o galho", "come a fruta", "corre r\u{00E1}pido",
        "sob a palma", "entre as folhas", "brinca feliz",
        "pula alto", "procura comida", "danca contente",
        "dorme no galho", "descasca a banana", "chama os amigos",
        "atravessa o rio", "colhe as frutas", "corre na floresta",
        "ri com vontade", "olha as estrelas", "explora o vale",
        "constr\u{00F3}i o ninho", "escuta o vento", "divide a manga",
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

    // WPM captured at the exact moment the game ends: the live formula uses
    // wall-clock elapsed time and would keep shrinking on the results screen.
    private var finalWPM: Int = 0

    // Next phrase, shown dimmed under the input so there's no dead time
    private var upcomingText: String = ""

    // Green flash on the text panel when a phrase is completed
    private var wordFlashFrames: Int = 0

    // Anti-repeat window for the word banks
    private var recentTexts: [String] = []

    // Flow tiers (consecutive correct characters): 0 none, 1 bronze,
    // 2 silver, 3 gold, 4 plasma. Feeds the border tint and the chime pitch.
    private var flowTier: Int {
        if combo >= 70 { return 4 }
        if combo >= 45 { return 3 }
        if combo >= 25 { return 2 }
        if combo >= 10 { return 1 }
        return 0
    }

    private func tierColor(_ tier: Int) -> NSColor {
        switch tier {
        case 1: return NSColor(red: 0.80, green: 0.52, blue: 0.28, alpha: 1.0) // bronze
        case 2: return NSColor(red: 0.75, green: 0.78, blue: 0.83, alpha: 1.0) // silver
        case 3: return NSColor(red: 1.00, green: 0.80, blue: 0.20, alpha: 1.0) // gold
        case 4: return NSColor(red: 0.45, green: 0.90, blue: 1.00, alpha: 1.0) // plasma
        default: return NSColor(white: 0.4, alpha: 1.0)
        }
    }

    // White flash right after "GO!"
    private var goFlashFrames: Int = 0

    // ── Weak-key drill ──
    /// Injected by AppDelegate: all-time per-key counts from the local
    /// heatmap. Used only in Drill mode, never leaves the process.
    var weakKeyProvider: (() -> [Int64: Int])?
    private var drillWords: [String] = []

    private static let letterByKeyCode: [Int64: Character] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h",
        34: "i", 38: "j", 40: "k", 37: "l", 46: "m", 45: "n", 31: "o",
        35: "p", 12: "q", 15: "r", 1: "s", 17: "t", 32: "u", 9: "v",
        13: "w", 7: "x", 16: "y", 6: "z",
    ]

    /// Words containing your least-pressed letters get duplicated in the
    /// pool proportionally to how many weak letters they contain.
    private func computeDrillWords() -> [String] {
        let counts = weakKeyProvider?() ?? [:]
        var letterCounts: [Character: Int] = [:]
        for (code, letter) in Self.letterByKeyCode {
            letterCounts[letter] = counts[code] ?? 0
        }
        let weak = Set(letterCounts.sorted { $0.value < $1.value }.prefix(9).map { $0.key })
        let banks = wordBanksForCurrentLanguage()
        let pool = banks.beginner + banks.intermediate
        var weighted: [String] = []
        for word in pool {
            let score = word.lowercased().reduce(0) { $0 + (weak.contains($1) ? 1 : 0) }
            for _ in 0..<score { weighted.append(word) }
        }
        return weighted.isEmpty ? pool : weighted
    }

    /// Fires when the flow tier changes (drives the layered music).
    var onFlowTierChanged: ((Int) -> Void)?
    private var lastFlowTier: Int = 0

    private func notifyFlowTier() {
        let tier = flowTier
        if tier != lastFlowTier {
            lastFlowTier = tier
            onFlowTierChanged?(tier)
        }
    }

    // Staggered results reveal
    private var resultsFrame: Int = 0
    private var earnedMedal: Medal = .none
    private var earnedMedalIsNew: Bool = false

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
        resultsFrame = 0
        goFlashFrames = 0
        earnedMedal = .none
        earnedMedalIsNew = false
        loadHighScore()
        pickNewText()

        gameTimer?.invalidate()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.gameTick()
            }
        }
    }

    /// Stops the game loop entirely — call when the window closes so the
    /// 60 fps timer doesn't keep burning CPU in the background.
    func stopGame() {
        gameTimer?.invalidate()
        gameTimer = nil
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
        if selectedLevel == .drill {
            drillWords = computeDrillWords()
        }
        lastFlowTier = 0
        onFlowTierChanged?(0)
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
        wordFlashFrames = 0
        upcomingText = "" // force a fresh pick for the selected difficulty
        loadHighScore()
        pickNewText()
    }

    private func randomText() -> String {
        let banks = wordBanksForCurrentLanguage()
        let pool: [String]
        switch selectedLevel {
        case .sprint:       pool = banks.intermediate
        case .drill:        pool = drillWords.isEmpty ? banks.intermediate : drillWords
        case .beginner:     pool = banks.beginner
        case .intermediate: pool = banks.intermediate
        case .expert:       pool = banks.expert
        case .master:       pool = banks.master
        }
        // Anti-repeat window: never serve a recently seen text
        let fresh = pool.filter { !recentTexts.contains($0) }
        let picked = (fresh.isEmpty ? pool : fresh).randomElement() ?? "banana"
        recentTexts.append(picked)
        if recentTexts.count > 6 { recentTexts.removeFirst() }
        return picked
    }

    private func pickNewText() {
        // Promote the previewed phrase, avoiding immediate repeats
        if upcomingText.isEmpty || upcomingText == currentText {
            currentText = randomText()
        } else {
            currentText = upcomingText
        }
        var next = randomText()
        var attempts = 0
        while next == currentText && attempts < 5 {
            next = randomText()
            attempts += 1
        }
        upcomingText = next
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

        // Word-complete flash decay
        if wordFlashFrames > 0 { wordFlashFrames -= 1 }

        // Countdown phase: tick every second, then GO
        if phase == .countdown {
            countdownFrames -= 1
            if countdownFrames == 120 || countdownFrames == 60 {
                onPlayCountdownTick?()
            } else if countdownFrames <= 0 {
                onPlayCountdownGo?()
                goFlashFrames = 8
                startPlaying()
            }
        }
        if goFlashFrames > 0 { goFlashFrames -= 1 }

        // Staggered results reveal, one tick per landing element
        if phase == .finished {
            resultsFrame += 1
            if [1, 12, 40, 55, 70, 85].contains(resultsFrame) {
                onPlayCountdownTick?()
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
        resultsFrame = 0
        onStopMusic?()
        let wpm = calculateWPM()
        finalWPM = wpm
        wpmHistory.append(wpm)

        // Medal + daily mission + streak
        let result = GameProgress.shared.recordRun(mode: selectedLevel.medalMode, score: wpm)
        earnedMedal = result.medal
        earnedMedalIsNew = result.isNewBest
        GameProgress.shared.registerWPM(wpm)

        // Keep the last 5 runs for this difficulty
        let historyKey = "MonkeysSpeedHistory_\(selectedLevel.rawValue)"
        var recent = UserDefaults.standard.array(forKey: historyKey) as? [Int] ?? []
        recent.insert(wpm, at: 0)
        if recent.count > 5 { recent = Array(recent.prefix(5)) }
        UserDefaults.standard.set(recent, forKey: historyKey)
        if wpm > highScoreWPM && wpm > 0 {
            highScoreWPM = wpm
            UserDefaults.standard.set(highScoreWPM, forKey: selectedLevel.highScoreKey)
            // Persist this run's curve: it becomes the ghost to race next time
            UserDefaults.standard.set(wpmHistory, forKey: "MonkeysBestCurve_\(selectedLevel.rawValue)")
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
            if let num = char.wholeNumberValue, num >= 1 && num <= DifficultyLevel.allCases.count {
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
            if resultsFrame >= 60 { resetGame() }
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
            notifyFlowTier()

            // Word completed?
            if typedText.count == currentText.count {
                wordsCompleted += 1
                wordFlashFrames = 18
                if let pitched = onPlaySuccessSemitone {
                    pitched(flowTier * 3)
                } else {
                    onPlaySuccessSound?()
                }

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
            notifyFlowTier()
            monkeyEmoji = "🙈"
            monkeyReactionFrames = 20
            onPlayFailSound?()
        }
    }

    // MARK: - Mouse Input

    /// Frame of the difficulty card at `index` — single source of truth for
    /// both drawing and mouse hit-testing.
    private func levelCardRect(index: Int) -> CGRect {
        let w = bounds.width
        let h = bounds.height
        let cardWidth: CGFloat = w - 60
        let cardHeight: CGFloat = 56
        let cardSpacing: CGFloat = 8
        let totalCardsHeight = CGFloat(DifficultyLevel.allCases.count) * (cardHeight + cardSpacing)
        let startY = h / 2 + totalCardsHeight / 2 - 46
        let cardY = startY - CGFloat(index) * (cardHeight + cardSpacing)
        return CGRect(x: 30, y: cardY, width: cardWidth, height: cardHeight)
    }

    private func levelCardIndex(at point: CGPoint) -> Int? {
        for index in 0..<DifficultyLevel.allCases.count where levelCardRect(index: index).contains(point) {
            return index
        }
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        guard phase == .waiting else { return }
        let point = convert(event.locationInWindow, from: nil)
        let newHover = levelCardIndex(at: point) ?? -1
        if newHover != hoveredLevel {
            hoveredLevel = newHover
            NSCursor.pointingHand.set()
            if newHover == -1 { NSCursor.arrow.set() }
            setNeedsDisplay(bounds)
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredLevel = -1
        NSCursor.arrow.set()
        setNeedsDisplay(bounds)
    }

    override func mouseDown(with event: NSEvent) {
        switch phase {
        case .waiting:
            let point = convert(event.locationInWindow, from: nil)
            if let index = levelCardIndex(at: point) {
                if index == selectedLevelIndex {
                    // Click on the already-selected card starts the game
                    NSCursor.arrow.set()
                    beginCountdown()
                } else {
                    selectedLevelIndex = index
                    selectedLevel = DifficultyLevel.allCases[index]
                    loadHighScore()
                    setNeedsDisplay(bounds)
                }
            }
        case .finished:
            if resultsFrame >= 60 { resetGame() }
        case .countdown, .playing:
            break
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
        let frac = CGFloat(frameInSecond) / 60.0
        let popScale = 1.0 + 0.85 * frac * frac // punch-in, eases hard
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
        // Clean header: title + subtitle only, the cards are the protagonists
        drawCentered(L.shared.s("st_title"), y: h - 52, size: 22, bold: true,
                     color: NSColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0), in: w)
        drawCentered(L.shared.s("st_choose_level"), y: h - 80, size: 12,
                     color: NSColor(white: 0.75, alpha: 1.0), in: w)

        // Draw level cards
        let cardHeight: CGFloat = 56
        let cardSpacing: CGFloat = 8
        let totalCardsHeight = CGFloat(DifficultyLevel.allCases.count) * (cardHeight + cardSpacing)
        let startY = h / 2 + totalCardsHeight / 2 - 46

        for (index, level) in DifficultyLevel.allCases.enumerated() {
            let cardRect = levelCardRect(index: index)
            let isSelected = index == selectedLevelIndex
            let isHovered = index == hoveredLevel

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
            } else if isHovered {
                ctx.setFillColor(NSColor(white: 0.14, alpha: 0.85).cgColor)
            } else {
                ctx.setFillColor(NSColor(white: 0.08, alpha: 0.7).cgColor)
            }

            let cardPath = CGPath(roundedRect: cardRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
            ctx.addPath(cardPath)
            ctx.fillPath()

            // Selected/hovered indicator border
            if isSelected {
                ctx.setStrokeColor(level.color.withAlphaComponent(0.8).cgColor)
                ctx.setLineWidth(2.0)
                ctx.addPath(cardPath)
                ctx.strokePath()
            } else if isHovered {
                ctx.setStrokeColor(level.color.withAlphaComponent(0.35).cgColor)
                ctx.setLineWidth(1.5)
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

        // Background panel — flashes green when a phrase is completed
        ctx.setFillColor(NSColor(white: 0.0, alpha: 0.4).cgColor)
        let panelPath = CGPath(roundedRect: textAreaRect.insetBy(dx: -10, dy: -10),
                               cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.addPath(panelPath)
        ctx.fillPath()
        if wordFlashFrames > 0 {
            let flashAlpha = CGFloat(wordFlashFrames) / 18.0
            ctx.setStrokeColor(NSColor(red: 0.3, green: 1.0, blue: 0.4, alpha: 0.8 * flashAlpha).cgColor)
            ctx.setLineWidth(2.5)
            ctx.addPath(panelPath)
            ctx.strokePath()
        }

        // Draw target text with colored characters
        drawTargetText(in: textAreaRect, w: w)

        // Next phrase preview, dimmed, under the text panel
        if !upcomingText.isEmpty {
            let previewStr = "→ \(upcomingText)" as NSString
            let previewAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor(white: 0.55, alpha: 0.55),
            ]
            var pSize = previewStr.size(withAttributes: previewAttrs)
            var drawStr = previewStr
            // Truncate if too wide for the window
            if pSize.width > w - 60 {
                let maxChars = Int((w - 80) / (pSize.width / CGFloat(previewStr.length)))
                drawStr = (String(("→ " + upcomingText).prefix(maxChars)) + "…") as NSString
                pSize = drawStr.size(withAttributes: previewAttrs)
            }
            drawStr.draw(at: NSPoint(x: w / 2 - pSize.width / 2, y: textAreaY - 32), withAttributes: previewAttrs)
        }

        // (The old duplicate input box is gone: the colored target text with
        // its block cursor already carries all the information.)
        let inputY = h / 2 - 70

        // Flow bar: 4 tiers filled by consecutive correct characters
        let flowBarW: CGFloat = 180
        let flowBarX = w / 2 - flowBarW / 2
        let flowBarY = inputY + 6
        let tier = flowTier
        for i in 0..<4 {
            let segW = (flowBarW - 3 * 4) / 4
            let segRect = CGRect(x: flowBarX + CGFloat(i) * (segW + 4), y: flowBarY, width: segW, height: 5)
            let segPath = CGPath(roundedRect: segRect, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
            if i < tier {
                ctx.setFillColor(tierColor(i + 1).cgColor)
            } else if i == tier {
                // Partial progress toward the next tier
                let tierSpans: [(Int, Int)] = [(0, 10), (10, 25), (25, 45), (45, 70)]
                let (lo, hi) = tierSpans[min(i, 3)]
                let f = max(0, min(1, CGFloat(combo - lo) / CGFloat(hi - lo)))
                ctx.setFillColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
                ctx.addPath(segPath)
                ctx.fillPath()
                if f > 0 {
                    let fillRect = CGRect(x: segRect.minX, y: segRect.minY, width: segRect.width * f, height: segRect.height)
                    ctx.setFillColor(tierColor(i + 1).withAlphaComponent(0.8).cgColor)
                    ctx.fill(fillRect)
                }
                continue
            } else {
                ctx.setFillColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
            }
            ctx.addPath(segPath)
            ctx.fillPath()
        }

        // Border tint rises with the flow tier (plasma pulses)
        if tier > 0 {
            let pulse: CGFloat = tier == 4 ? 0.16 + 0.10 * sin(CGFloat(frameCount) * 0.15) : 0.16
            ctx.setStrokeColor(tierColor(tier).withAlphaComponent(pulse).cgColor)
            ctx.setLineWidth(5)
            ctx.stroke(bounds.insetBy(dx: 3, dy: 3))
        }

        // "GO!" white flash
        if goFlashFrames > 0 {
            ctx.setFillColor(NSColor(white: 1.0, alpha: CGFloat(goFlashFrames) / 8.0 * 0.45).cgColor)
            ctx.fill(bounds)
        }

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

        let wpm = finalWPM
        let accuracy = calculateAccuracy()
        let isRecord = finishedAsRecord
        let rf = resultsFrame

        // ── Staggered reveal: title → WPM count-up → stats → delta →
        // chart+ghost → medal → restart. Each step lands with a tick. ──

        // Title + level (frame 0+)
        let title = isRecord ? L.shared.s("g_new_record") : L.shared.s("st_time_up")
        let titleColor = isRecord ?
            NSColor(red: 1.0, green: 0.85, blue: 0.1, alpha: 1.0) :
            NSColor(white: 1.0, alpha: 1.0)
        drawCentered(title, y: h / 2 + 150, size: 24, bold: true, color: titleColor, in: w)
        drawCentered("\(selectedLevel.emoji) \(L.shared.s(selectedLevel.locKey))", y: h / 2 + 124, size: 13,
                     color: selectedLevel.color, in: w)

        // WPM counts up (frame 12+)
        if rf >= 12 {
            let progress = min(1.0, CGFloat(rf - 12) / 26.0)
            let eased = 1.0 - (1.0 - progress) * (1.0 - progress)
            let shown = Int((CGFloat(wpm) * eased).rounded())
            drawCentered("\(shown) WPM", y: h / 2 + 76, size: 42, bold: true,
                         color: NSColor(red: 0.4, green: 1.0, blue: 0.5, alpha: 1.0), in: w)
        }

        // Accuracy + words + combo (frame 40+)
        if rf >= 40 {
            drawCentered(L.shared.sf("st_accuracy", accuracy), y: h / 2 + 46, size: 16,
                         color: NSColor(white: 0.9, alpha: 1.0), in: w)
            drawCentered(L.shared.sf("st_words_done", wordsCompleted), y: h / 2 + 22, size: 14,
                         color: NSColor(white: 0.85, alpha: 1.0), in: w)
            drawCentered(L.shared.sf("st_best_combo", bestCombo), y: h / 2 - 2, size: 14,
                         color: NSColor(red: 1.0, green: 0.7, blue: 0.3, alpha: 0.9), in: w)
        }

        // Delta vs previous run + best (frame 55+)
        if rf >= 55 {
            let historyKey = "MonkeysSpeedHistory_\(selectedLevel.rawValue)"
            if let recent = UserDefaults.standard.array(forKey: historyKey) as? [Int], recent.count > 1 {
                let delta = recent[0] - recent[1]
                let deltaText = delta > 0 ? "▲ +\(delta) WPM" : (delta < 0 ? "▼ \(delta) WPM" : "＝")
                let deltaColor = delta > 0 ?
                    NSColor(red: 0.45, green: 0.95, blue: 0.5, alpha: 1.0) :
                    (delta < 0 ? NSColor(red: 1.0, green: 0.5, blue: 0.45, alpha: 1.0) : NSColor(white: 0.7, alpha: 1.0))
                drawCentered(deltaText, y: h / 2 - 28, size: 14, bold: true, color: deltaColor, in: w)
            }
            drawCentered(L.shared.sf("g_best_score", highScoreWPM), y: h / 2 - 52, size: 12,
                         color: NSColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 0.8), in: w)
        }

        // WPM chart with the ghost of your best run (frame 70+)
        if rf >= 70 {
            drawWPMChart(ctx: ctx, w: w, h: h)
        }

        // Medal stamp with scale-in (frame 85+)
        if rf >= 85 && earnedMedal != .none {
            let stampProgress = min(1.0, CGFloat(rf - 85) / 6.0)
            let stampScale = 1.7 - 0.7 * stampProgress
            let medalText = earnedMedalIsNew ? "\(earnedMedal.emoji)✨" : earnedMedal.emoji
            let medalStr = medalText as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 30 * stampScale)]
            let msz = medalStr.size(withAttributes: attrs)
            medalStr.draw(at: NSPoint(x: w / 2 + 96 - msz.width / 2, y: h / 2 + 70), withAttributes: attrs)
        }

        // Performance message + restart (frame 85/100+)
        if rf >= 85 {
            let msg: String
            if wpm >= 80 { msg = L.shared.s("st_living_typewriter") }
            else if wpm >= 60 { msg = L.shared.s("st_fire_fingers") }
            else if wpm >= 40 { msg = L.shared.s("st_great_job") }
            else if wpm >= 20 { msg = L.shared.s("st_good_start") }
            else { msg = L.shared.s("st_keep_trying") }
            drawCentered(msg, y: h / 2 - 168, size: 13,
                         color: NSColor(white: 0.8, alpha: 0.9), in: w)
        }
        if rf >= 100 {
            let pulse = 0.5 + 0.5 * sin(CGFloat(frameCount) * 0.06)
            drawCentered(L.shared.s("g_press_restart"), y: h / 2 - 194, size: 13,
                         color: NSColor(white: 1.0, alpha: pulse), in: w)
        }

        // Confetti on a new record — drawn on top of everything
        drawConfetti(ctx: ctx)
    }

    /// Draws a small line chart of the WPM sampled each second of the run.
    private func drawWPMChart(ctx: CGContext, w: CGFloat, h: CGFloat) {
        guard wpmHistory.count >= 3 else { return }

        let chartW: CGFloat = 220
        let chartH: CGFloat = 34
        let originX = w / 2 - chartW / 2
        let originY = h / 2 - 128

        // Panel
        ctx.setFillColor(NSColor(white: 0.0, alpha: 0.35).cgColor)
        let panel = CGPath(roundedRect: CGRect(x: originX - 8, y: originY - 6, width: chartW + 16, height: chartH + 12),
                           cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.addPath(panel)
        ctx.fillPath()

        let ghost = UserDefaults.standard.array(forKey: "MonkeysBestCurve_\(selectedLevel.rawValue)") as? [Int] ?? []
        let maxWPM = max(max(wpmHistory.max() ?? 1, ghost.max() ?? 1), 1)
        let stepX = chartW / CGFloat(wpmHistory.count - 1)

        // Ghost: the curve of your best run, to race against
        if ghost.count >= 2 {
            let ghostStep = chartW / CGFloat(ghost.count - 1)
            ctx.setStrokeColor(NSColor(white: 0.65, alpha: 0.45).cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [3, 3])
            ctx.beginPath()
            for (i, value) in ghost.enumerated() {
                let x = originX + CGFloat(i) * ghostStep
                let y = originY + chartH * CGFloat(value) / CGFloat(maxWPM)
                if i == 0 { ctx.move(to: CGPoint(x: x, y: y)) } else { ctx.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

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

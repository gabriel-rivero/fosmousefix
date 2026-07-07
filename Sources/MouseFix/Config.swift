import Foundation

struct Mapping: Codable {
    let button: Int
    let trigger: String
    let action: ActionDef
}

enum ActionDef: Codable, Equatable {
    case system(String)
    case keyCombo(KeyCombo)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .system(str)
        } else {
            self = .keyCombo(try container.decode(KeyCombo.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .system(let name): try container.encode(name)
        case .keyCombo(let combo): try container.encode(combo)
        }
    }
}

struct KeyCombo: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: [String]
}

struct SmoothScrollingConfig: Codable {
    var enabled: Bool = true
    var intensity: Double = 0.7

    init(enabled: Bool = true, intensity: Double = 0.7) {
        self.enabled = enabled; self.intensity = intensity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 0.7
    }
}

struct ScrollDirectionConfig: Codable {
    var flipVertical: Bool = false
    var flipHorizontal: Bool = false

    init(flipVertical: Bool = false, flipHorizontal: Bool = false) {
        self.flipVertical = flipVertical; self.flipHorizontal = flipHorizontal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        flipVertical = try c.decodeIfPresent(Bool.self, forKey: .flipVertical) ?? false
        flipHorizontal = try c.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? false
    }
}

struct AppConfig: Codable {
    var smoothScrolling: SmoothScrollingConfig = .init()
    var scrollDirection: ScrollDirectionConfig = .init()
    var mappings: [Mapping] = [
        .init(button: 3, trigger: "click", action: .system("mission_control")),
        .init(button: 4, trigger: "click", action: .system("back")),
        .init(button: 5, trigger: "click", action: .system("forward")),
    ]

    init(
        smoothScrolling: SmoothScrollingConfig = .init(),
        scrollDirection: ScrollDirectionConfig = .init(),
        mappings: [Mapping] = [
            .init(button: 3, trigger: "click", action: .system("mission_control")),
            .init(button: 4, trigger: "click", action: .system("back")),
            .init(button: 5, trigger: "click", action: .system("forward")),
        ]
    ) {
        self.smoothScrolling = smoothScrolling
        self.scrollDirection = scrollDirection
        self.mappings = mappings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        smoothScrolling = try c.decodeIfPresent(SmoothScrollingConfig.self, forKey: .smoothScrolling) ?? .init()
        scrollDirection = try c.decodeIfPresent(ScrollDirectionConfig.self, forKey: .scrollDirection) ?? .init()
        mappings = try c.decodeIfPresent([Mapping].self, forKey: .mappings) ?? [
            .init(button: 3, trigger: "click", action: .system("mission_control")),
            .init(button: 4, trigger: "click", action: .system("back")),
            .init(button: 5, trigger: "click", action: .system("forward")),
        ]
    }
}

func defaultConfigPath() -> String {
    NSHomeDirectory() + "/.config/mousefix/config.json"
}

func loadConfig(path: String? = nil) -> AppConfig {
    let path = path ?? defaultConfigPath()
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let config = try? JSONDecoder().decode(AppConfig.self, from: data)
    else {
        return AppConfig()
    }
    return config
}

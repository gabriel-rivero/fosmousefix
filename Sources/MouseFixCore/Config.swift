import Foundation

public struct Mapping: Codable {
    public var button: Int
    public var trigger: String
    public var action: ActionDef

    public init(button: Int, trigger: String, action: ActionDef) {
        self.button = button; self.trigger = trigger; self.action = action
    }
}

public enum ActionDef: Codable, Equatable, Hashable {
    case system(String)
    case keyCombo(KeyCombo)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .system(str)
        } else {
            self = .keyCombo(try container.decode(KeyCombo.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .system(let name): try container.encode(name)
        case .keyCombo(let combo): try container.encode(combo)
        }
    }
}

public struct KeyCombo: Codable, Equatable, Hashable {
    public let keyCode: UInt16
    public let modifiers: [String]

    public init(keyCode: UInt16, modifiers: [String]) {
        self.keyCode = keyCode; self.modifiers = modifiers
    }
}

public struct SmoothScrollingConfig: Codable {
    public var enabled: Bool = true
    public var intensity: Double = 0.7

    public init(enabled: Bool = true, intensity: Double = 0.7) {
        self.enabled = enabled; self.intensity = intensity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 0.7
    }
}

public struct ScrollDirectionConfig: Codable {
    public var flipVertical: Bool = false
    public var flipHorizontal: Bool = false

    public init(flipVertical: Bool = false, flipHorizontal: Bool = false) {
        self.flipVertical = flipVertical; self.flipHorizontal = flipHorizontal
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        flipVertical = try c.decodeIfPresent(Bool.self, forKey: .flipVertical) ?? false
        flipHorizontal = try c.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? false
    }
}

public struct AppConfig: Codable {
    public var smoothScrolling: SmoothScrollingConfig = .init()
    public var scrollDirection: ScrollDirectionConfig = .init()
    public var mappings: [Mapping] = [
        .init(button: 3, trigger: "click", action: .system("back")),
        .init(button: 4, trigger: "click", action: .system("forward")),
        .init(button: 5, trigger: "click", action: .system("mission_control")),
    ]

    public init(
        smoothScrolling: SmoothScrollingConfig = .init(),
        scrollDirection: ScrollDirectionConfig = .init(),
        mappings: [Mapping] = [
            .init(button: 3, trigger: "click", action: .system("back")),
            .init(button: 4, trigger: "click", action: .system("forward")),
            .init(button: 5, trigger: "click", action: .system("mission_control")),
        ]
    ) {
        self.smoothScrolling = smoothScrolling
        self.scrollDirection = scrollDirection
        self.mappings = mappings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        smoothScrolling = try c.decodeIfPresent(SmoothScrollingConfig.self, forKey: .smoothScrolling) ?? .init()
        scrollDirection = try c.decodeIfPresent(ScrollDirectionConfig.self, forKey: .scrollDirection) ?? .init()
        mappings = try c.decodeIfPresent([Mapping].self, forKey: .mappings) ?? [
            .init(button: 3, trigger: "click", action: .system("back")),
            .init(button: 4, trigger: "click", action: .system("forward")),
            .init(button: 5, trigger: "click", action: .system("mission_control")),
        ]
    }
}

public func defaultConfigPath() -> String {
    NSHomeDirectory() + "/.config/mousefix/config.json"
}

public func loadConfig(path: String? = nil) -> AppConfig {
    let path = path ?? defaultConfigPath()
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let config = try? decoder.decode(AppConfig.self, from: data)
    else {
        return AppConfig()
    }
    return config
}

public func encodeConfig(_ config: AppConfig) -> Data? {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try? encoder.encode(config)
}

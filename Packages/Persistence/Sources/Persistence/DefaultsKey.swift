import Foundation

/// A typed UserDefaults key: name + default value + how to (de)serialize, declared once.
/// Replaces scattered `defaults.object(forKey:) as? T ?? fallback` and manual
/// `Codable`-as-`Data` glue with a single source of truth per preference.
public struct DefaultsKey<Value>: Sendable where Value: Sendable {
    public let name: String
    public let defaultValue: Value

    private let read: @Sendable (UserDefaults) -> Value
    private let write: @Sendable (UserDefaults, Value) -> Void

    fileprivate init(
        name: String,
        defaultValue: Value,
        read: @escaping @Sendable (UserDefaults) -> Value,
        write: @escaping @Sendable (UserDefaults, Value) -> Void
    ) {
        self.name = name
        self.defaultValue = defaultValue
        self.read = read
        self.write = write
    }

    func readValue(from defaults: UserDefaults) -> Value { read(defaults) }
    func writeValue(_ value: Value, to defaults: UserDefaults) { write(defaults, value) }
}

public extension DefaultsKey {
    /// Property-list-native values: Bool, Int, Double, String, Data, Date,
    /// and arrays/dictionaries thereof. Stored directly. (Not URL — it isn't
    /// a property-list type, so writing one through the generic
    /// `set(_:forKey:)` would raise `NSInvalidArgumentException`; use
    /// `codable` for URLs.)
    static func plist(_ name: String, default defaultValue: Value) -> DefaultsKey<Value> {
        DefaultsKey(
            name: name,
            defaultValue: defaultValue,
            read: { $0.object(forKey: name) as? Value ?? defaultValue },
            write: { $0.set($1, forKey: name) }
        )
    }
}

public extension DefaultsKey where Value: Codable {
    /// Everything else — enums, sets, structs — stored as JSON `Data`.
    static func codable(_ name: String, default defaultValue: Value) -> DefaultsKey<Value> {
        DefaultsKey(
            name: name,
            defaultValue: defaultValue,
            read: { defaults in
                guard let data = defaults.data(forKey: name),
                      let decoded = try? JSONDecoder().decode(Value.self, from: data)
                else { return defaultValue }
                return decoded
            },
            write: { defaults, value in
                guard let data = try? JSONEncoder().encode(value) else { return }
                defaults.set(data, forKey: name)
            }
        )
    }
}

public extension UserDefaults {
    func value<Value>(for key: DefaultsKey<Value>) -> Value { key.readValue(from: self) }
    func set<Value>(_ value: Value, for key: DefaultsKey<Value>) { key.writeValue(value, to: self) }
}

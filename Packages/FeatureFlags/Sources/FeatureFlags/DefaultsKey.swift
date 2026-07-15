import Foundation

struct DefaultsKey<Value>: Sendable where Value: Sendable {
    let name: String
    let defaultValue: Value

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

extension DefaultsKey where Value: Codable {
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

extension UserDefaults {
    func value<Value>(for key: DefaultsKey<Value>) -> Value { key.readValue(from: self) }
    func set<Value>(_ value: Value, for key: DefaultsKey<Value>) { key.writeValue(value, to: self) }
}

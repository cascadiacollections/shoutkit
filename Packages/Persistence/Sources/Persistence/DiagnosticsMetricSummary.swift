import Foundation

// MetricKit payload parsing is inherently verbose (many optional metric
// sub-dictionaries); this parser file exceeds the default length limit.
// swiftlint:disable file_length

public struct DiagnosticsMetricPayloadSummary: Equatable, Sendable {
    public let receivedAt: Date
    public let launch: DiagnosticsAppLaunchSummary?
    public let networkTransactions: [DiagnosticsNetworkTransactionSummary]

    public init(
        receivedAt: Date,
        launch: DiagnosticsAppLaunchSummary?,
        networkTransactions: [DiagnosticsNetworkTransactionSummary]
    ) {
        self.receivedAt = receivedAt
        self.launch = launch
        self.networkTransactions = networkTransactions
    }
}

public struct DiagnosticsAppLaunchSummary: Equatable, Sendable {
    public let meanTimeToFirstDrawMilliseconds: Double?
    public let timeToFirstDrawSampleCount: Int
    public let meanResumeTimeMilliseconds: Double?
    public let resumeSampleCount: Int

    public init(
        meanTimeToFirstDrawMilliseconds: Double?,
        timeToFirstDrawSampleCount: Int,
        meanResumeTimeMilliseconds: Double?,
        resumeSampleCount: Int
    ) {
        self.meanTimeToFirstDrawMilliseconds = meanTimeToFirstDrawMilliseconds
        self.timeToFirstDrawSampleCount = timeToFirstDrawSampleCount
        self.meanResumeTimeMilliseconds = meanResumeTimeMilliseconds
        self.resumeSampleCount = resumeSampleCount
    }

}

public struct DiagnosticsNetworkTransactionSummary: Equatable, Sendable {
    public let host: String
    public let requestCount: Int?
    public let networkProtocol: String?
    public let averageDNSMilliseconds: Double?
    public let averageConnectMilliseconds: Double?
    public let averageTLSMilliseconds: Double?
    public let averageRequestMilliseconds: Double?
    public let averageResponseMilliseconds: Double?
    public let averageTotalMilliseconds: Double?

    public init(
        host: String,
        requestCount: Int?,
        networkProtocol: String?,
        averageDNSMilliseconds: Double?,
        averageConnectMilliseconds: Double?,
        averageTLSMilliseconds: Double?,
        averageRequestMilliseconds: Double?,
        averageResponseMilliseconds: Double?,
        averageTotalMilliseconds: Double?
    ) {
        self.host = host
        self.requestCount = requestCount
        self.networkProtocol = networkProtocol
        self.averageDNSMilliseconds = averageDNSMilliseconds
        self.averageConnectMilliseconds = averageConnectMilliseconds
        self.averageTLSMilliseconds = averageTLSMilliseconds
        self.averageRequestMilliseconds = averageRequestMilliseconds
        self.averageResponseMilliseconds = averageResponseMilliseconds
        self.averageTotalMilliseconds = averageTotalMilliseconds
    }

    var logMessage: String {
        """
        MetricKit network host=\(host) protocol=\(networkProtocol ?? "n/a") \
        count=\(requestCount.map(String.init) ?? "n/a") \
        dnsMs=\(Self.describe(averageDNSMilliseconds)) \
        connectMs=\(Self.describe(averageConnectMilliseconds)) \
        tlsMs=\(Self.describe(averageTLSMilliseconds)) \
        requestMs=\(Self.describe(averageRequestMilliseconds)) \
        responseMs=\(Self.describe(averageResponseMilliseconds)) \
        totalMs=\(Self.describe(averageTotalMilliseconds))
        """
    }

    private static func describe(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.2f", value)
    }
}

// swiftlint:disable:next type_body_length
enum DiagnosticsMetricSummaryExtractor {
    static func summary(from payload: Data, receivedAt: Date) -> DiagnosticsMetricPayloadSummary? {
        guard let json = try? JSONSerialization.jsonObject(with: payload),
              let object = json as? [String: Any] else {
            return nil
        }

        let launch = appLaunchSummary(from: object)
        let networkTransactions = networkTransactionSummaries(from: object)
        guard launch != nil || networkTransactions.isEmpty == false else { return nil }
        return DiagnosticsMetricPayloadSummary(
            receivedAt: receivedAt,
            launch: launch,
            networkTransactions: networkTransactions
        )
    }

    private static func appLaunchSummary(from object: [String: Any]) -> DiagnosticsAppLaunchSummary? {
        guard let launchMetrics = dictionary(
            forKeys: ["applicationLaunchMetrics", "appLaunchMetrics"],
            in: object
        ) else {
            return nil
        }

        let firstDraw = histogramSummary(
            from: launchMetrics,
            keys: ["histogrammedTimeToFirstDraw", "histogrammedTimeToFirstDrawKey"]
        )
        let resume = histogramSummary(
            from: launchMetrics,
            keys: ["histogrammedApplicationResumeTime", "histogrammedApplicationResumeTimeKey"]
        )

        guard firstDraw != nil || resume != nil else { return nil }
        return DiagnosticsAppLaunchSummary(
            meanTimeToFirstDrawMilliseconds: firstDraw?.meanMilliseconds,
            timeToFirstDrawSampleCount: firstDraw?.sampleCount ?? 0,
            meanResumeTimeMilliseconds: resume?.meanMilliseconds,
            resumeSampleCount: resume?.sampleCount ?? 0
        )
    }

    private static func networkTransactionSummaries(
        from object: [String: Any]
    ) -> [DiagnosticsNetworkTransactionSummary] {
        guard let entries = array(forKeys: ["networkTransactionMetrics"], in: object) else {
            return []
        }

        return entries.compactMap { item in
            guard let metric = item as? [String: Any],
                  let host = string(forKeys: ["domain", "host"], in: metric),
                  host.isEmpty == false else {
                return nil
            }

            return DiagnosticsNetworkTransactionSummary(
                host: host,
                requestCount: int(forKeys: ["count"], in: metric),
                networkProtocol: string(forKeys: ["networkProtocolName", "protocolName"], in: metric),
                averageDNSMilliseconds: durationMilliseconds(
                    dictionaryKeys: ["dns"],
                    scalarKeys: ["cumulativeDNSLookupTime", "averageDNSLookupTime"],
                    in: metric
                ),
                averageConnectMilliseconds: durationMilliseconds(
                    dictionaryKeys: ["connect"],
                    scalarKeys: ["cumulativeConnectTime", "cumulativeTCPConnectionTime", "averageConnectTime"],
                    in: metric
                ),
                averageTLSMilliseconds: durationMilliseconds(
                    dictionaryKeys: ["tls"],
                    scalarKeys: ["cumulativeTLSHandshakeTime", "averageTLSHandshakeTime"],
                    in: metric
                ),
                averageRequestMilliseconds: durationMilliseconds(
                    dictionaryKeys: ["request"],
                    scalarKeys: ["cumulativeRequestTime", "averageRequestTime"],
                    in: metric
                ),
                averageResponseMilliseconds: durationMilliseconds(
                    dictionaryKeys: ["response"],
                    scalarKeys: ["cumulativeResponseTime", "averageResponseTime"],
                    in: metric
                ),
                averageTotalMilliseconds: durationMilliseconds(
                    dictionaryKeys: ["cumulative"],
                    scalarKeys: ["cumulativeDuration", "averageDuration"],
                    in: metric
                )
            )
        }
    }

    private static func histogramSummary(from object: [String: Any], keys: [String]) -> HistogramSummary? {
        guard let histogram = dictionary(forKeys: keys, in: object) else {
            return nil
        }

        if let starts = numberArray(forKeys: ["bucketStartTimes"], in: histogram),
           let ends = numberArray(forKeys: ["bucketEndTimes"], in: histogram),
           let counts = numberArray(forKeys: ["bucketCounts"], in: histogram),
           starts.count == ends.count,
           starts.count == counts.count,
           starts.isEmpty == false {
            let multiplier = durationUnitMultiplier(from: histogram["unit"])
            var totalSamples = 0.0
            var weightedTotal = 0.0

            for index in starts.indices {
                let count = counts[index]
                let midpoint = (starts[index] + ends[index]) / 2
                weightedTotal += midpoint * count
                totalSamples += count
            }

            guard totalSamples > 0 else { return nil }
            return HistogramSummary(
                meanMilliseconds: (weightedTotal / totalSamples) * multiplier,
                sampleCount: Int(totalSamples.rounded())
            )
        }

        guard let values = durationValues(forKeys: ["histogramValue", "histogramValues"], in: histogram),
              values.isEmpty == false else {
            return nil
        }

        let total = values.reduce(0, +)
        return HistogramSummary(
            meanMilliseconds: total / Double(values.count),
            sampleCount: values.count
        )
    }

    private static func durationMilliseconds(
        dictionaryKeys: [String],
        scalarKeys: [String],
        in object: [String: Any]
    ) -> Double? {
        if let dictionary = dictionary(forKeys: dictionaryKeys, in: object) {
            if let duration = dictionary["duration"] {
                return durationMilliseconds(from: duration, defaultUnit: .seconds)
            }
            return durationMilliseconds(from: dictionary, defaultUnit: .seconds)
        }

        for key in scalarKeys {
            if let value = object[key] {
                return durationMilliseconds(from: value, defaultUnit: .seconds)
            }
        }

        return nil
    }

    private static func durationMilliseconds(from value: Any, defaultUnit: DurationUnit) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue * defaultUnit.multiplierToMilliseconds
        }
        if let string = value as? String {
            return parseDurationStringMilliseconds(string, defaultUnit: defaultUnit)
        }

        guard let dictionary = value as? [String: Any] else { return nil }
        let explicitUnit = DurationUnit(rawValue: string(forKeys: ["unit"], in: dictionary) ?? "")
        let unit = explicitUnit ?? defaultUnit

        for key in ["value", "average", "measurement", "duration"] {
            if let nested = dictionary[key] {
                return durationMilliseconds(from: nested, defaultUnit: unit)
            }
        }

        return nil
    }

    private static func durationUnitMultiplier(from value: Any?) -> Double {
        guard let unit = DurationUnit(rawValue: value as? String ?? "") else {
            return DurationUnit.milliseconds.multiplierToMilliseconds
        }
        return unit.multiplierToMilliseconds
    }

    private static func dictionary(forKeys keys: [String], in object: [String: Any]) -> [String: Any]? {
        for key in keys {
            if let dictionary = object[key] as? [String: Any] {
                return dictionary
            }
        }
        return nil
    }

    private static func array(forKeys keys: [String], in object: [String: Any]) -> [Any]? {
        for key in keys {
            if let array = object[key] as? [Any] {
                return array
            }
        }
        return nil
    }

    private static func durationValues(forKeys keys: [String], in object: [String: Any]) -> [Double]? {
        for key in keys {
            if let values = object[key] as? [Any] {
                let durations = values.compactMap { durationMilliseconds(from: $0, defaultUnit: .milliseconds) }
                return durations.count == values.count ? durations : nil
            }
            if let values = object[key] as? [String: Any] {
                let indexedValues = values.compactMap { keyValue -> (Int, Any)? in
                    guard let index = Int(keyValue.key) else { return nil }
                    return (index, keyValue.value)
                }
                guard indexedValues.count == values.count else { return nil }
                let sorted = indexedValues.sorted { $0.0 < $1.0 }
                let expectedIndices = 0..<sorted.count
                guard zip(expectedIndices, sorted).allSatisfy({ expected, actual in
                    expected == actual.0
                }) else { return nil }
                let durations = sorted.compactMap {
                    durationMilliseconds(from: $0.1, defaultUnit: .milliseconds)
                }
                return durations.count == sorted.count ? durations : nil
            }
        }
        return nil
    }

    private static func numberArray(forKeys keys: [String], in object: [String: Any]) -> [Double]? {
        guard let values = array(forKeys: keys, in: object) else { return nil }
        let numbers = values.compactMap { ($0 as? NSNumber)?.doubleValue }
        return numbers.count == values.count ? numbers : nil
    }

    private static func string(forKeys keys: [String], in object: [String: Any]) -> String? {
        for key in keys {
            if let string = object[key] as? String {
                return string
            }
        }
        return nil
    }

    private static func int(forKeys keys: [String], in object: [String: Any]) -> Int? {
        for key in keys {
            if let number = object[key] as? NSNumber {
                return number.intValue
            }
        }
        return nil
    }

    private static func parseDurationStringMilliseconds(
        _ raw: String,
        defaultUnit: DurationUnit
    ) -> Double? {
        // Supports "1810", "1810 ms", "+1.5ms", and "-2.3 s".
        // Returns nil for malformed numeric components such as "1.2-3.4ms".
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if let value = Double(trimmed) {
            return value * defaultUnit.multiplierToMilliseconds
        }

        let components = trimmed.split(whereSeparator: \.isWhitespace)
        if components.count >= 2,
           let value = Double(components[0]),
           let unit = DurationUnit(rawValue: String(components[1]).lowercased()) {
            return value * unit.multiplierToMilliseconds
        }

        var index = trimmed.startIndex
        if index < trimmed.endIndex, trimmed[index] == "+" || trimmed[index] == "-" {
            index = trimmed.index(after: index)
        }
        let numberStart = trimmed.startIndex
        let firstNonNumber = trimmed[index...].firstIndex {
            $0.isNumber == false && $0 != "."
        } ?? trimmed.endIndex
        let numberPart = String(trimmed[numberStart..<firstNonNumber])
        guard numberPart.isEmpty == false,
              numberPart != "+",
              numberPart != "-",
              let value = Double(numberPart) else {
            return nil
        }
        let unitSuffix = trimmed[firstNonNumber...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let unit = DurationUnit(rawValue: unitSuffix) ?? defaultUnit
        return value * unit.multiplierToMilliseconds
    }

    private struct HistogramSummary {
        let meanMilliseconds: Double
        let sampleCount: Int
    }

    private enum DurationUnit: String {
        case seconds = "s"
        case milliseconds = "ms"
        case microseconds = "us"
        case nanoseconds = "ns"

        var multiplierToMilliseconds: Double {
            switch self {
            case .seconds:
                return 1_000
            case .milliseconds:
                return 1
            case .microseconds:
                return 0.001
            case .nanoseconds:
                return 0.000_001
            }
        }
    }
}

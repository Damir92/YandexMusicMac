import Foundation

public struct YMAccountStatus: Codable, Sendable {
    public let account: YMAccountInfo?
    public let permissions: YMPermissionsInfo?
    public let plus: YMPlusInfo?
    public let subscription: YMSubscriptionInfo?

    public init(
        account: YMAccountInfo? = nil,
        permissions: YMPermissionsInfo? = nil,
        plus: YMPlusInfo? = nil,
        subscription: YMSubscriptionInfo? = nil
    ) {
        self.account = account
        self.permissions = permissions
        self.plus = plus
        self.subscription = subscription
    }

    public var userId: String? {
        account?.uid
    }

    public var displayName: String {
        account?.displayName ?? account?.fullName ?? account?.login ?? "User"
    }

    public var hasActiveSubscription: Bool {
        let referenceDate = account?.now.flatMap(Self.parseDate) ?? Date()

        // 1. Authoritative Yandex Plus flag from API
        if plus?.hasPlus == true {
            return true
        }

        // 2. Active autoRenewable or familyAutoRenewable subscription
        if let autoRenewable = subscription?.autoRenewable,
           autoRenewable.contains(where: {
               $0.finished != true && ($0.expires == nil || (Self.parseDate($0.expires!) ?? .distantPast) > referenceDate)
           }) {
            return true
        }

        if let familySubs = subscription?.familyAutoRenewable,
           familySubs.contains(where: {
               $0.finished != true && ($0.expires == nil || (Self.parseDate($0.expires!) ?? .distantPast) > referenceDate)
           }) {
            return true
        }

        // Active nonAutoRenewable subscription
        if let nonAuto = subscription?.nonAutoRenewable,
           let end = nonAuto.end,
           let endDate = Self.parseDate(end),
           endDate > referenceDate {
            return true
        }

        // 3. Explicit permissions check
        if let untilStr = permissions?.until,
           let untilDate = Self.parseDate(untilStr),
           untilDate < referenceDate {
            return false
        }

        if let values = permissions?.values {
            if values.contains("play-full-tracks") || values.contains("play-premium-tracks") {
                return true
            }
        }

        return false
    }

    public var hadAnySubscription: Bool {
        subscription?.hadAnySubscription ?? false
    }

    public static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}

public struct YMAccountInfo: Codable, Sendable {
    public let uid: String?
    public let login: String?
    public let fullName: String?
    public let displayName: String?
    public let firstName: String?
    public let secondName: String?
    public let registered: Bool?
    public let now: String?

    public init(
        uid: String? = nil,
        login: String? = nil,
        fullName: String? = nil,
        displayName: String? = nil,
        firstName: String? = nil,
        secondName: String? = nil,
        registered: Bool? = nil,
        now: String? = nil
    ) {
        self.uid = uid
        self.login = login
        self.fullName = fullName
        self.displayName = displayName
        self.firstName = firstName
        self.secondName = secondName
        self.registered = registered
        self.now = now
    }

    enum CodingKeys: String, CodingKey {
        case uid
        case login
        case fullName
        case displayName
        case firstName
        case secondName
        case registered
        case now
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.uid = FlexibleIDDecoder.decodeStringIfPresent(from: container, forKey: .uid)
        self.login = try? container.decodeIfPresent(String.self, forKey: .login)
        self.fullName = try? container.decodeIfPresent(String.self, forKey: .fullName)
        self.displayName = try? container.decodeIfPresent(String.self, forKey: .displayName)
        self.firstName = try? container.decodeIfPresent(String.self, forKey: .firstName)
        self.secondName = try? container.decodeIfPresent(String.self, forKey: .secondName)
        self.registered = try? container.decodeIfPresent(Bool.self, forKey: .registered)
        self.now = try? container.decodeIfPresent(String.self, forKey: .now)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(uid, forKey: .uid)
        try container.encodeIfPresent(login, forKey: .login)
        try container.encodeIfPresent(fullName, forKey: .fullName)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(firstName, forKey: .firstName)
        try container.encodeIfPresent(secondName, forKey: .secondName)
        try container.encodeIfPresent(registered, forKey: .registered)
        try container.encodeIfPresent(now, forKey: .now)
    }
}

public struct YMPermissionsInfo: Codable, Sendable {
    public let until: String?
    public let values: [String]?
    public let defaults: [String]?

    public init(until: String? = nil, values: [String]? = nil, defaults: [String]? = nil) {
        self.until = until
        self.values = values
        self.defaults = defaults
    }

    enum CodingKeys: String, CodingKey {
        case until
        case values
        case defaults = "default"
    }
}

public struct YMPlusInfo: Codable, Sendable {
    public let hasPlus: Bool?
    public let isTutorialCompleted: Bool?

    public init(hasPlus: Bool? = nil, isTutorialCompleted: Bool? = nil) {
        self.hasPlus = hasPlus
        self.isTutorialCompleted = isTutorialCompleted
    }
}

public struct YMAutoRenewableInfo: Codable, Sendable {
    public let expires: String?
    public let finished: Bool?
    public init(expires: String? = nil, finished: Bool? = nil) {
        self.expires = expires
        self.finished = finished
    }
}

public struct YMNonAutoRenewableInfo: Codable, Sendable {
    public let start: String?
    public let end: String?
    public init(start: String? = nil, end: String? = nil) {
        self.start = start
        self.end = end
    }
}

public struct YMSubscriptionInfo: Codable, Sendable {
    public let hadAnySubscription: Bool?
    public let canStartTrial: Bool?
    public let autoRenewable: [YMAutoRenewableInfo]?
    public let familyAutoRenewable: [YMAutoRenewableInfo]?
    public let nonAutoRenewable: YMNonAutoRenewableInfo?

    public init(
        hadAnySubscription: Bool? = nil,
        canStartTrial: Bool? = nil,
        autoRenewable: [YMAutoRenewableInfo]? = nil,
        familyAutoRenewable: [YMAutoRenewableInfo]? = nil,
        nonAutoRenewable: YMNonAutoRenewableInfo? = nil
    ) {
        self.hadAnySubscription = hadAnySubscription
        self.canStartTrial = canStartTrial
        self.autoRenewable = autoRenewable
        self.familyAutoRenewable = familyAutoRenewable
        self.nonAutoRenewable = nonAutoRenewable
    }
}

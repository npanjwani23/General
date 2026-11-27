import FamilyControls
import Foundation

/// A named set of apps, categories and sites to block, such as "Deep Work"
/// or "No Social". One mode is active at a time; locking blocks its list.
struct Mode: Codable, Identifiable, Equatable {
    static let limit = 10

    let id: UUID
    var name: String
    var selection: FamilyActivitySelection

    init(id: UUID = UUID(), name: String, selection: FamilyActivitySelection = FamilyActivitySelection()) {
        self.id = id
        self.name = name
        self.selection = selection
    }

    /// Screen Time silently stops shielding anything once a single shield
    /// list holds more than 50 items, so a bigger mode would "lock" but
    /// block nothing.
    static let perKindLimit = 50

    /// Why this mode can't be saved, or nil if it is fine.
    var problem: String? {
        if appCount > Self.perKindLimit || siteCount > Self.perKindLimit || categoryCount > Self.perKindLimit {
            return "Pick \(Self.perKindLimit) or fewer apps, sites and categories each. "
                + "Screen Time stops blocking anything above that. Use categories to cover more apps."
        }
        return nil
    }

    var appCount: Int { selection.applicationTokens.count }
    var categoryCount: Int { selection.categoryTokens.count }
    var siteCount: Int { selection.webDomainTokens.count }
    var itemCount: Int { appCount + categoryCount + siteCount }

    /// "Blocks 4 apps · 1 site", or a prompt when nothing is chosen yet.
    var summary: String {
        var parts: [String] = []
        if appCount > 0 { parts.append(Self.plural(appCount, "app")) }
        if categoryCount > 0 { parts.append(Self.plural(categoryCount, "category", "categories")) }
        if siteCount > 0 { parts.append(Self.plural(siteCount, "site")) }
        return parts.isEmpty ? "Nothing blocked yet" : "Blocks " + parts.joined(separator: " · ")
    }

    private static func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        "\(n) \(n == 1 ? one : (many ?? one + "s"))"
    }
}

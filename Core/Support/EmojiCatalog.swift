import Foundation

/// Phase 30f: a curated emoji picker (a hand-picked set, not the whole Unicode table). Pure: matching is
/// name/substring; the bar copies the chosen glyph.
struct EmojiEntry: Equatable, Sendable {
    var char: String
    var name: String
}

enum EmojiCatalog {
    /// `glyph name more-words` — the name doubles as the search text.
    private static let raw: [String] = [
        "😀 grinning happy face", "😃 smile open mouth", "😄 smile eyes", "😁 grin beam", "😆 laughing",
        "😅 sweat smile", "🤣 rofl laughing", "😂 joy tears laugh", "🙂 slight smile", "🙃 upside down",
        "😉 wink", "😊 blush smile", "😇 innocent halo", "🥰 love hearts", "😍 heart eyes",
        "😘 kiss", "😗 kissing", "😋 yum tasty", "😜 wink tongue", "🤪 crazy zany",
        "🤨 raised eyebrow", "🧐 monocle", "🤓 nerd glasses", "😎 cool sunglasses", "🥳 party face",
        "😏 smirk", "😒 unamused", "😞 sad disappointed", "😔 pensive", "😟 worried",
        "😕 confused", "🙁 frown", "☹️ frowning", "😣 persevere", "😖 confounded",
        "😫 tired", "😩 weary", "🥺 pleading", "😢 cry sad", "😭 sob crying",
        "😤 triumph", "😠 angry", "😡 rage mad", "🤬 cursing", "🤯 mind blown",
        "😳 flushed", "🥵 hot", "🥶 cold", "😱 scream fear", "😨 fearful",
        "😰 anxious", "😥 sad relieved", "🤗 hug", "🤔 thinking", "🤭 giggle",
        "🤫 shush quiet", "😐 neutral", "😑 expressionless", "😶 no mouth", "🙄 roll eyes",
        "😬 grimace", "🤥 lying", "😴 sleeping", "🤤 drool", "😪 sleepy",
        "😵 dizzy", "🤐 zipper", "🥴 woozy", "🤢 nauseated", "🤮 vomit",
        "🤧 sneeze", "😷 mask", "🤒 sick", "🤕 hurt", "🤑 money mouth",
        "👍 thumbs up like", "👎 thumbs down dislike", "👌 ok perfect", "✌️ victory peace", "🤞 fingers crossed",
        "🤟 love you", "🤘 rock on", "👏 clap", "🙌 raise hands", "🙏 pray thanks",
        "🤝 handshake", "💪 muscle strong", "👋 wave hello", "✋ raised hand", "🖖 vulcan",
        "👀 eyes look", "🧠 brain", "❤️ red heart love", "🧡 orange heart", "💛 yellow heart",
        "💚 green heart", "💙 blue heart", "💜 purple heart", "🖤 black heart", "🤍 white heart",
        "💔 broken heart", "💯 hundred", "🔥 fire lit", "✨ sparkles", "⭐ star",
        "🌟 glowing star", "⚡ zap lightning", "💥 boom", "✅ check done", "❌ cross no",
        "⚠️ warning", "❗ exclamation", "❓ question", "➕ plus", "➖ minus",
        "🎉 party tada", "🎊 confetti", "🎁 gift", "🏆 trophy", "🥇 gold medal",
        "🚀 rocket launch", "💡 idea bulb", "📌 pin", "📎 paperclip", "✏️ pencil",
        "📝 memo note", "📅 calendar date", "⏰ alarm clock", "⏳ hourglass", "🔔 bell",
        "🔍 search magnify", "🔒 lock locked", "🔓 unlock", "🔑 key", "🛠️ tools",
        "✅ done", "🐛 bug", "💻 laptop computer", "⌨️ keyboard", "🖥️ desktop",
        "📱 phone", "☕ coffee", "🍕 pizza", "🍔 burger", "🍎 apple",
        "🎵 music note", "🎬 clapper", "📷 camera", "🎨 art palette", "🌍 globe world",
    ]

    static let entries: [EmojiEntry] = raw.map { line in
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        return EmojiEntry(char: parts.first ?? "", name: parts.count > 1 ? parts[1] : "")
    }

    /// Entries whose name contains every whitespace-separated token of `query` (case-insensitive).
    static func matching(_ query: String) -> [EmojiEntry] {
        let tokens = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard !tokens.isEmpty else { return entries }
        return entries.filter { entry in tokens.allSatisfy { entry.name.contains($0) } }
    }
}

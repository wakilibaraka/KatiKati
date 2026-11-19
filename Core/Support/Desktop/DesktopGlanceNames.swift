import Foundation

/// Display names for Glance facts. Shipped for English, 简体, 繁體, 日本語 and 한국어; every other language
/// falls back to English (the lunar date itself is formatted by the system for any locale).
enum DesktopGlanceNames {
    static func name(of term: DesktopSolarTerm, languageCode: String, script: String? = nil) -> String {
        let row = termNames[term] ?? []
        return pick(row, languageCode: languageCode, script: script)
    }

    static func name(of festival: DesktopFestival, languageCode: String, script: String? = nil) -> String {
        pick(festivalNames[festival] ?? [], languageCode: languageCode, script: script)
    }

    /// Row order: en, zh-Hans, zh-Hant, ja, ko.
    private static func pick(_ row: [String], languageCode: String, script: String?) -> String {
        guard row.count == 5 else { return row.first ?? "" }
        switch languageCode {
        case "zh": return (script == "Hant") ? row[2] : row[1]
        case "ja": return row[3]
        case "ko": return row[4]
        default: return row[0]
        }
    }

    private static let termNames: [DesktopSolarTerm: [String]] = [
        .minorCold: ["Minor Cold", "小寒", "小寒", "小寒", "소한"],
        .majorCold: ["Major Cold", "大寒", "大寒", "大寒", "대한"],
        .startOfSpring: ["Start of Spring", "立春", "立春", "立春", "입춘"],
        .rainWater: ["Rain Water", "雨水", "雨水", "雨水", "우수"],
        .awakeningOfInsects: ["Awakening of Insects", "惊蛰", "驚蟄", "啓蟄", "경칩"],
        .springEquinox: ["Spring Equinox", "春分", "春分", "春分", "춘분"],
        .clearAndBright: ["Clear and Bright", "清明", "清明", "清明", "청명"],
        .grainRain: ["Grain Rain", "谷雨", "穀雨", "穀雨", "곡우"],
        .startOfSummer: ["Start of Summer", "立夏", "立夏", "立夏", "입하"],
        .grainBuds: ["Grain Buds", "小满", "小滿", "小満", "소만"],
        .grainInEar: ["Grain in Ear", "芒种", "芒種", "芒種", "망종"],
        .summerSolstice: ["Summer Solstice", "夏至", "夏至", "夏至", "하지"],
        .minorHeat: ["Minor Heat", "小暑", "小暑", "小暑", "소서"],
        .majorHeat: ["Major Heat", "大暑", "大暑", "大暑", "대서"],
        .startOfAutumn: ["Start of Autumn", "立秋", "立秋", "立秋", "입추"],
        .endOfHeat: ["End of Heat", "处暑", "處暑", "処暑", "처서"],
        .whiteDew: ["White Dew", "白露", "白露", "白露", "백로"],
        .autumnEquinox: ["Autumn Equinox", "秋分", "秋分", "秋分", "추분"],
        .coldDew: ["Cold Dew", "寒露", "寒露", "寒露", "한로"],
        .frostDescent: ["Frost Descent", "霜降", "霜降", "霜降", "상강"],
        .startOfWinter: ["Start of Winter", "立冬", "立冬", "立冬", "입동"],
        .minorSnow: ["Minor Snow", "小雪", "小雪", "小雪", "소설"],
        .majorSnow: ["Major Snow", "大雪", "大雪", "大雪", "대설"],
        .winterSolstice: ["Winter Solstice", "冬至", "冬至", "冬至", "동지"],
    ]

    private static let festivalNames: [DesktopFestival: [String]] = [
        .newYear: ["New Year's Day", "元旦", "元旦", "元日", "신정"],
        .laborDay: ["Labor Day", "劳动节", "勞動節", "メーデー", "노동절"],
        .nationalDay: ["National Day", "国庆节", "國慶日", "国慶節", "국경절"],
        .christmas: ["Christmas", "圣诞节", "聖誕節", "クリスマス", "크리스마스"],
        .valentines: ["Valentine's Day", "情人节", "情人節", "バレンタインデー", "발렌타인데이"],
        .springFestival: ["Spring Festival", "春节", "春節", "春節", "설날"],
        .lanternFestival: ["Lantern Festival", "元宵节", "元宵節", "元宵節", "정월 대보름"],
        .dragonBoat: ["Dragon Boat Festival", "端午节", "端午節", "端午節", "단오"],
        .qixi: ["Qixi Festival", "七夕", "七夕", "七夕", "칠석"],
        .midAutumn: ["Mid-Autumn Festival", "中秋节", "中秋節", "中秋節", "추석"],
        .doubleNinth: ["Double Ninth Festival", "重阳节", "重陽節", "重陽節", "중양절"],
        .laba: ["Laba Festival", "腊八节", "臘八節", "臘八節", "납팔절"],
    ]
}

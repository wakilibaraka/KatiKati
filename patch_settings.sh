#!/bin/bash
# 1. Add NowPlayingTheme enum
sed -i '' -e '/enum DrawerPlacement/i\
enum NowPlayingTheme: String, CaseIterable {\
    case auto\
    case light\
    case dark\
\
    var displayTitle: String {\
        switch self {\
        case .auto: return String(localized: "Auto")\
        case .light: return String(localized: "Light")\
        case .dark: return String(localized: "Dark")\
        }\
    }\
}\
' App/Composition/AppSettingsStore.swift

# 2. Add the published property to AppSettingsStore
sed -i '' -e '/@Published var showTrash: Bool/i\
    @Published var nowPlayingTheme: NowPlayingTheme {\
        didSet {\
            if nowPlayingTheme != oldValue {\
                UserDefaults.standard.set(nowPlayingTheme.rawValue, forKey: Keys.nowPlayingTheme)\
            }\
        }\
    }\
' App/Composition/AppSettingsStore.swift

# 3. Add to init
sed -i '' -e '/self.showTrash = defaults.bool(forKey: Keys.showTrash)/i\
        self.nowPlayingTheme = NowPlayingTheme(rawValue: defaults.string(forKey: Keys.nowPlayingTheme) ?? "") ?? .auto\
' App/Composition/AppSettingsStore.swift

# 4. Add to Keys
sed -i '' -e '/static let showTrash = "com.katikati.showTrash"/a\
    static let nowPlayingTheme = "com.katikati.nowPlayingTheme"\
' App/Composition/AppSettingsStore.swift

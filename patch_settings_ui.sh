#!/bin/bash
awk '
/drawerPlacementPicker/ {
    count++
    if (count == 1) {
        print "                    HStack {"
        print "                        Text(\"Now Playing Theme\")"
        print "                        Spacer(minLength: 12)"
        print "                        Picker(\"\", selection: $store.nowPlayingTheme) {"
        print "                            ForEach(NowPlayingTheme.allCases, id: \\.self) {"
        print "                                Text($0.displayTitle)"
        print "                            }"
        print "                        }"
        print "                        .labelsHidden()"
        print "                        .pickerStyle(.menu)"
        print "                        .fixedSize()"
        print "                    }"
    }
}
{ print }
' App/Scenes/SettingsWindowView.swift > tmp.swift && mv tmp.swift App/Scenes/SettingsWindowView.swift

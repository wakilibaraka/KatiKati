#!/bin/bash
awk '
/case .clock:/ {
    print "                case .media:"
    print "                    NowPlayingChip()"
    print "                        .scaleEffect(dockScale)"
}
{ print }
' App/Scenes/DockStripView.swift > tmp && mv tmp App/Scenes/DockStripView.swift

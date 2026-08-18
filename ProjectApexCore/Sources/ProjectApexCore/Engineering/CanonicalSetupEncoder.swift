//
//  CanonicalSetupEncoder.swift
//  ProjectApexCore
//
//  Deterministic string encoding of a setup, used as hash input.
//  Format: "categoryRaw=optionRaw|categoryRaw=optionRaw|..."
//  Categories sorted by raw value (lexicographic) — stable forever.
//
//  Example:
//  "aerodynamics=aeroLowDrag|brakes=brakesBalanced|cooling=coolingLight|..."
//
//  WIRE-FORMAT WARNING: changing this format or the ID raw values
//  invalidates every stored result hash. Version any future change
//  via simulationVersion, never by mutating this encoding in place.
//

public nonisolated enum CanonicalSetupEncoder {

    public static func encode(_ setup: PlayerSetup) -> String {
        setup.selectedOptions
            .sorted { $0.key < $1.key }
            .map { "\($0.key.rawValue)=\($0.value.rawValue)" }
            .joined(separator: "|")
    }
}

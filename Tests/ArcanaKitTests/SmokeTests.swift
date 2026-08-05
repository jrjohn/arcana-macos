//
//  SmokeTests.swift
//  ArcanaKitTests — the package compiles and the app entry point exists.
//  Layer-by-layer tests (Core / Domain / Data / Sync / Plugins / Presentation) are
//  ported from arcana-ios's Swift Testing suite in the following phases.
//
import Testing
@testable import ArcanaKit

@Suite("ArcanaKit smoke")
struct ArcanaKitSmokeTests {
    @Test("the macOS app entry point is present")
    func appTypeExists() {
        _ = ArcanaApp.self
    }
}

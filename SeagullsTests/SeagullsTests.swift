//
//  SeagullsTests.swift
//  SeagullsTests
//
//  Created by Andy Bader on 2/4/26.
//

import Foundation
import Testing
@testable import Seagulls

struct SeagullsTests {

    private let existingSuggestions = WorkflowSuggestions(
        shootingDay: "8",
        breakName: "PM"
    )

    @Test
    func successfulAMSuggestsPMSameDay() {
        let result = existingSuggestions.suggestionsAfterSuccessfulArchive(
            shootingDay: "1",
            breakName: "AM"
        )

        #expect(
            result == WorkflowSuggestions(
                shootingDay: "1",
                breakName: "PM"
            )
        )
    }

    @Test
    func successfulPMSuggestsAMNextDay() {
        let result = existingSuggestions.suggestionsAfterSuccessfulArchive(
            shootingDay: "1",
            breakName: "PM"
        )

        #expect(
            result == WorkflowSuggestions(
                shootingDay: "2",
                breakName: "AM"
            )
        )
    }

    @Test
    func successfulAllDaySuggestsAMNextDay() {
        let result = existingSuggestions.suggestionsAfterSuccessfulArchive(
            shootingDay: "3",
            breakName: "All Day"
        )

        #expect(
            result == WorkflowSuggestions(
                shootingDay: "4",
                breakName: "AM"
            )
        )
    }

    @Test
    func recognizedBreakNamesAreCaseInsensitive() {
        let result = existingSuggestions.suggestionsAfterSuccessfulArchive(
            shootingDay: "5",
            breakName: "pM"
        )

        #expect(
            result == WorkflowSuggestions(
                shootingDay: "6",
                breakName: "AM"
            )
        )
    }

    @Test
    func surroundingWhitespaceIsIgnoredForProgression() {
        let result = existingSuggestions.suggestionsAfterSuccessfulArchive(
            shootingDay: " 7 ",
            breakName: " am "
        )

        #expect(
            result == WorkflowSuggestions(
                shootingDay: "7",
                breakName: "PM"
            )
        )
    }

    @Test
    func dayZeroDoesNotChangeSuggestions() {
        let result = existingSuggestions.suggestionsAfterSuccessfulArchive(
            shootingDay: "0",
            breakName: "PM"
        )

        #expect(result == existingSuggestions)
    }

    @Test
    func nonNumericDayDoesNotChangeSuggestions() {
        let result = existingSuggestions.suggestionsAfterSuccessfulArchive(
            shootingDay: "Prep",
            breakName: "AM"
        )

        #expect(result == existingSuggestions)
    }

    @Test
    func customBreakNameDoesNotChangeSuggestions() {
        let result = existingSuggestions.suggestionsAfterSuccessfulArchive(
            shootingDay: "4",
            breakName: "Lunch"
        )

        #expect(result == existingSuggestions)
    }

    @Test
    func blankBreakNameDoesNotChangeSuggestions() {
        let result = existingSuggestions.suggestionsAfterSuccessfulArchive(
            shootingDay: "4",
            breakName: ""
        )

        #expect(result == existingSuggestions)
    }

    @Test
    func maximumIntegerDoesNotOverflow() {
        let result = existingSuggestions.suggestionsAfterSuccessfulArchive(
            shootingDay: String(Int.max),
            breakName: "PM"
        )

        #expect(result == existingSuggestions)
    }
    
    @Test
    func workflowSuggestionsCanBeSavedAndReloaded() throws {
        let temporaryFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: temporaryFolder)
        }

        let fileURL = temporaryFolder
            .appendingPathComponent("workflow-suggestions.json")

        let expected = WorkflowSuggestions(
            shootingDay: "12",
            breakName: "PM"
        )

        try WorkflowSuggestionsStore.save(
            expected,
            to: fileURL
        )

        let loaded = WorkflowSuggestionsStore.load(
            from: fileURL
        )

        #expect(loaded == expected)
    }

    @Test
    func missingSuggestionFileReturnsInitialSuggestions() {
        let nonexistentFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("workflow-suggestions.json")

        let loaded = WorkflowSuggestionsStore.load(
            from: nonexistentFileURL
        )

        #expect(loaded == WorkflowSuggestions.initial)
    }

    @Test
    func invalidSuggestionFileReturnsInitialSuggestions() throws {
        let temporaryFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: temporaryFolder)
        }

        try FileManager.default.createDirectory(
            at: temporaryFolder,
            withIntermediateDirectories: true
        )

        let fileURL = temporaryFolder
            .appendingPathComponent("workflow-suggestions.json")

        try Data("This is not valid JSON".utf8).write(
            to: fileURL,
            options: [.atomic]
        )

        let loaded = WorkflowSuggestionsStore.load(
            from: fileURL
        )

        #expect(loaded == WorkflowSuggestions.initial)
    }
}


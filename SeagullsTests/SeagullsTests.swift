//
//  SeagullsTests.swift
//  SeagullsTests
//
//  Created by Andy Bader on 2/4/26.
//

import Testing
@testable import Seagulls

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
}

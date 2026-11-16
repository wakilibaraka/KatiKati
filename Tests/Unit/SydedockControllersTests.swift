import XCTest
@testable import KatiKati

@MainActor
final class SydedockControllersTests: XCTestCase {

    // MARK: - HydrationController Tests

    func testHydrationControllerDrinkNowAndHistory() {
        let hydro = HydrationController()
        hydro.soundEnabled = false
        hydro.setIntervalMinutes(30)
        XCTAssertEqual(hydro.intervalMinutes, 30)

        let initialGlasses = hydro.todayGlasses
        hydro.drinkNow()
        XCTAssertEqual(hydro.todayGlasses, initialGlasses + 1)
        XCTAssertFalse(hydro.isOverdue)
        XCTAssertGreaterThan(hydro.intervalProgress, 0.9)

        let chartData = hydro.last14DaysData()
        XCTAssertEqual(chartData.count, 14)
        XCTAssertTrue(chartData.last?.isToday ?? false)
        XCTAssertEqual(chartData.last?.count, hydro.todayGlasses)
    }

    func testHydrationOverdueLogic() {
        let hydro = HydrationController()
        hydro.soundEnabled = false
        hydro.secondsRemaining = 1
        hydro.isOverdue = false

        hydro.tick()
        XCTAssertEqual(hydro.secondsRemaining, 0)
        XCTAssertTrue(hydro.isOverdue)
    }

    // MARK: - NutritionController Tests

    func testNutritionFastingStartAndProgress() {
        let nutri = NutritionController()
        nutri.soundEnabled = false
        nutri.protocolType = .fast16_8

        nutri.startFast()
        XCTAssertTrue(nutri.isFasting)
        XCTAssertNotNil(nutri.fastStartTime)
        XCTAssertGreaterThanOrEqual(nutri.elapsedFastSeconds, 0)
        XCTAssertEqual(nutri.targetFastSeconds, 16 * 3600)

        nutri.endFast()
        XCTAssertFalse(nutri.isFasting)
        XCTAssertNil(nutri.fastStartTime)
    }

    func testNutritionMealLoggingAndCadence() {
        let nutri = NutritionController()
        nutri.soundEnabled = false
        let initialMeals = nutri.todayMealsCount
        let initialCals = nutri.todayCalories

        nutri.logMeal(calories: 500, protein: 35, carbs: 50, fat: 18)
        XCTAssertEqual(nutri.todayMealsCount, initialMeals + 1)
        XCTAssertEqual(nutri.todayCalories, initialCals + 500)
        XCTAssertGreaterThan(nutri.secondsUntilNextMeal, 0)
        XCTAssertFalse(nutri.formattedNextMealTime.isEmpty)
    }

    // MARK: - HabitStreakStore Tests

    func testHabitStreakStoreMatrixAndToggles() {
        let store = HabitStreakStore()
        let matrix = store.matrix42Days()
        XCTAssertEqual(matrix.count, 42)
        XCTAssertTrue(matrix.last?.isToday ?? false)

        guard let firstHabit = store.habits.first else {
            XCTFail("Expected default habits")
            return
        }

        let wasDone = firstHabit.isDoneToday
        store.toggleHabit(id: firstHabit.id)
        XCTAssertEqual(store.habits.first?.isDoneToday, !wasDone)

        store.addHabit(title: "Drink Green Tea")
        XCTAssertTrue(store.habits.contains { $0.title == "Drink Green Tea" })
    }
}

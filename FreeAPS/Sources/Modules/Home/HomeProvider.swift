import Foundation
import LoopKitUI
import SwiftDate

extension Home {
    final class Provider: BaseProvider, HomeProvider {
        @Injected() var apsManager: APSManager!
        @Injected() var glucoseStorage: GlucoseStorage!
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        @Injected() var tempTargetsStorage: TempTargetsStorage!
        @Injected() var carbsStorage: CarbsStorage!
        @Injected() var announcementStorage: AnnouncementsStorage!

        var suggestion: Suggestion? {
            storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
        }

        var dynamicVariables: DynamicVariables? {
            storage.retrieve(OpenAPS.Monitor.dynamicVariables, as: DynamicVariables.self)
        }

        let overrideStorage = OverrideStorage()

        func overrides() -> [Override] {
            overrideStorage.fetchOverrides(interval: DateFilter().day)
        }

        func overrideHistory() -> [OverrideHistory] {
            overrideStorage.fetchOverrideHistory(interval: DateFilter().day)
        }

        var enactedSuggestion: Suggestion? {
            storage.retrieve(OpenAPS.Enact.enacted, as: Suggestion.self)
        }

        var reasons: [Reasons] {
            CoreDataStorage().fetchReasons(interval: DateFilter().day)
        }

        func iobData(_ data: [Reasons]) -> [IOBData]? {
            guard data.count > 3 else {
                return nil
            }

            return data.compactMap {
                entry -> IOBData in
                IOBData(
                    date: entry.date ?? Date(),
                    iob: (entry.iob ?? 0) as Decimal,
                    cob: (entry.cob ?? 0) as Decimal
                )
            }
        }

        func pumpTimeZone() -> TimeZone? {
            apsManager.pumpManager?.status.timeZone
        }

        func heartbeatNow() {
            apsManager.heartbeat(date: Date())
        }

        func filteredGlucose(hours: Int) -> [BloodGlucose] {
            glucoseStorage.recent().filter {
                $0.dateString.addingTimeInterval(hours.hours.timeInterval) > Date()
            }
        }

        func manualGlucose(hours: Int) -> [BloodGlucose] {
            glucoseStorage.recent().filter {
                $0.type == GlucoseType.manual.rawValue &&
                    $0.dateString.addingTimeInterval(hours.hours.timeInterval) > Date()
            }
        }

        func pumpHistory(hours: Int) -> [PumpHistoryEvent] {
            pumpHistoryStorage.recent().filter {
                $0.timestamp.addingTimeInterval(hours.hours.timeInterval) > Date()
            }
        }

        func tempTargets(hours: Int) -> [TempTarget] {
            tempTargetsStorage.recent().filter {
                $0.createdAt.addingTimeInterval(hours.hours.timeInterval) > Date()
            }
        }

        func tempTarget() -> TempTarget? {
            tempTargetsStorage.current()
        }

        func carbs(hours: Int) -> [CarbsEntry] {
            carbsStorage.recent().filter {
                $0.createdAt.addingTimeInterval(hours.hours.timeInterval) > Date() && $0.carbs > 0
            }
        }

        func announcement(_ hours: Int) -> [Announcement] {
            announcementStorage.validate().filter {
                $0.createdAt.addingTimeInterval(hours.hours.timeInterval) > Date()
            }
        }

        func pumpSettings() -> PumpSettings {
            storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 6, maxBolus: 10, maxBasal: 2)
        }

        func pumpBattery() -> Battery? {
            storage.retrieve(OpenAPS.Monitor.battery, as: Battery.self)
        }

        func pumpReservoir() -> Decimal? {
            storage.retrieve(OpenAPS.Monitor.reservoir, as: Decimal.self)
        }

        func autotunedBasalProfile() -> [BasalProfileEntry] {
            storage.retrieve(OpenAPS.Settings.profile, as: Autotune.self)?.basalProfile
                ?? storage.retrieve(OpenAPS.Settings.pumpProfile, as: Autotune.self)?.basalProfile
                ?? [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1)]
        }

        func basalProfile() -> [BasalProfileEntry] {
            storage.retrieve(OpenAPS.Settings.pumpProfile, as: Autotune.self)?.basalProfile
                ?? [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1)]
        }
    }
}

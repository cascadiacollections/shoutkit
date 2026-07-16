#if canImport(CarPlay)
import CarPlay
import Persistence
import Playback
import RadioDirectory
import UIKit

@MainActor
final class ShoutKitCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private enum Limits {
        static let libraryStations = 25
        static let topStations = 12
    }

    private var interfaceController: CPInterfaceController?
    private var listTemplate: CPListTemplate?
    private var topStationsTask: Task<Void, Never>?
    private let nowPlayingTemplate = CPNowPlayingTemplate.shared

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController

        let services = AppDependencies.bootstrap()
        let template = CPListTemplate(
            title: "ShoutKit",
            sections: sections(topStations: .loading, services: services)
        )
        listTemplate = template
        interfaceController.setRootTemplate(template, animated: false)
        loadTopStations(using: services)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        topStationsTask?.cancel()
        topStationsTask = nil
        listTemplate = nil
        self.interfaceController = nil
    }

    /// Top-station discovery as CarPlay renders it: distinct placeholder rows
    /// for in-flight and failed loads so a directory outage never masquerades
    /// as the user having no stations at all.
    private enum TopStationsState {
        case loading
        case loaded([Station])
        case unavailable
    }

    private func loadTopStations(using services: AppServices) {
        topStationsTask?.cancel()
        topStationsTask = Task { [weak self] in
            guard let self else { return }

            let topStations: TopStationsState
            do {
                topStations = try await .loaded(services.directory.topStations(limit: Limits.topStations))
            } catch {
                guard !Task.isCancelled else { return }
                topStations = .unavailable
            }

            guard !Task.isCancelled else { return }
            self.listTemplate?.updateSections(self.sections(topStations: topStations, services: services))
        }
    }

    private func sections(topStations: TopStationsState, services: AppServices) -> [CPListSection] {
        let libraryStations = services.libraryStore.rankedStations(limit: Limits.libraryStations)
        let libraryStationIDs = Set(libraryStations.map(\.id))

        var sections: [CPListSection] = []
        if libraryStations.isEmpty == false {
            sections.append(
                CPListSection(
                    items: libraryStations.map { stationItem(for: $0, services: services) },
                    header: "Your Stations",
                    sectionIndexTitle: nil
                )
            )
        }

        let topSectionItems = topStationItems(
            for: topStations,
            excluding: libraryStationIDs,
            services: services
        )

        if topSectionItems.isEmpty == false {
            sections.append(
                CPListSection(
                    items: topSectionItems,
                    header: "Top Stations",
                    sectionIndexTitle: nil
                )
            )
        }

        if sections.isEmpty {
            sections.append(
                CPListSection(
                    items: [
                        CPListItem(
                            text: "No Stations Yet",
                            detailText: "Open ShoutKit on iPhone to start listening or add favorites."
                        )
                    ],
                    header: nil,
                    sectionIndexTitle: nil
                )
            )
        }

        return sections
    }

    private func topStationItems(
        for topStations: TopStationsState,
        excluding libraryStationIDs: Set<String>,
        services: AppServices
    ) -> [CPListItem] {
        switch topStations {
        case let .loaded(stations):
            return stations
                .filter { libraryStationIDs.contains($0.id) == false }
                .map { stationItem(for: $0, services: services) }
        case .loading:
            return [CPListItem(text: "Loading Top Stations…", detailText: nil)]
        case .unavailable:
            return [
                CPListItem(
                    text: "Top Stations Unavailable",
                    detailText: "Couldn't reach the station directory. Check the connection and try again."
                )
            ]
        }
    }

    private func stationItem(for station: Station, services: AppServices) -> CPListItem {
        let item = CPListItem(text: station.name, detailText: station.genre)
        item.handler = { [weak self] _, completion in
            guard let self else {
                completion()
                return
            }

            let playback = services.playbackController
            if playback.currentStation?.id == station.id {
                switch playback.phase(for: station) {
                case .paused, .failed:
                    playback.resume()
                case .idle, .loading, .playing:
                    break
                }
            } else {
                playback.play(station)
            }

            self.interfaceController?.presentTemplate(self.nowPlayingTemplate, animated: true)
            completion()
        }
        return item
    }
}
#endif

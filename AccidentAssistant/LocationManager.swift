//
//  LocationManager.swift
//  AccidentAssistant
//
//  Sprint 3: GPS auto-detect + MKLocalSearchCompleter address autocomplete.
//

import Foundation
import CoreLocation
import MapKit
import Combine

class LocationManager: NSObject, ObservableObject {

    // MARK: - Core services
    private let manager = CLLocationManager()
    private var completer = MKLocalSearchCompleter()

    // MARK: - Published state
    @Published var authStatus: CLAuthorizationStatus = .notDetermined
    @Published var resolvedLocation: IncidentLocation?
    @Published var searchQuery: String = ""
    @Published var searchResults: [MKLocalSearchCompletion] = []
    @Published var isFetching: Bool = false

    // MARK: - Init

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        completer.delegate = self
        completer.resultTypes = .address
    }

    // MARK: - Public API

    /// Asks for permission and fires a one-shot location request.
    func requestOneTimeLocation() {
        let currentStatus = manager.authorizationStatus
        DispatchQueue.main.async { self.authStatus = currentStatus }
        
        if currentStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if currentStatus == .authorizedWhenInUse || currentStatus == .authorizedAlways {
            DispatchQueue.main.async { self.isFetching = true }
            manager.requestLocation()
        } else {
            DispatchQueue.main.async { self.isFetching = false }
        }
    }

    /// Feeds a new query string to the completer; results arrive via `searchResults`.
    func updateSearchQuery(_ query: String) {
        completer.queryFragment = query
    }

    /// Resolves a completion suggestion into a full `IncidentLocation`
    func selectLocation(completion: MKLocalSearchCompletion, onComplete: @escaping (IncidentLocation) -> Void) {
        let request = MKLocalSearch.Request(completion: completion)
        MKLocalSearch(request: request).start { response, error in
            
            guard let mapItem = response?.mapItems.first, error == nil else {
                print("📍 selectLocation failed: \(error?.localizedDescription ?? "no items")")
                return
            }
            
            let street = completion.title
            let cityStateParts = completion.subtitle.components(separatedBy: ",")
            let city = cityStateParts.first?.trimmingCharacters(in: .whitespaces) ?? ""
            let state = cityStateParts.count > 1 ? cityStateParts[1].trimmingCharacters(in: .whitespaces) : ""
            
            let coordinate = mapItem.location.coordinate
            
            let location = IncidentLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                street: street,
                city: city,
                state: state
            )
            
            DispatchQueue.main.async { onComplete(location) }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        DispatchQueue.main.async { self.authStatus = newStatus }
        
        if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
            DispatchQueue.main.async { self.isFetching = true }
            manager.requestLocation()
        } else if newStatus != .notDetermined {
            DispatchQueue.main.async { self.isFetching = false }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        manager.stopUpdatingLocation()
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(loc.coordinate.latitude), \(loc.coordinate.longitude)"
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
                    guard let self = self else { return }
                    
                    // 1. Grab the modern mapItem
                    guard let mapItem = response?.mapItems.first else {
                        DispatchQueue.main.async { self.isFetching = false }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        // 👉 FIX: Combine address and addressRepresentations to bridge the Apple API gap
                        self.resolvedLocation = IncidentLocation(
                            latitude: loc.coordinate.latitude,
                            longitude: loc.coordinate.longitude,
                            street: mapItem.address?.shortAddress ?? mapItem.name ?? "",
                            city:   mapItem.addressRepresentations?.cityName ?? "",
                            state:  mapItem.addressRepresentations?.regionName ?? ""
                        )
                        self.isFetching = false
                    }
                }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("📍 GPS failed: \(error.localizedDescription)")
        DispatchQueue.main.async { self.isFetching = false }
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension LocationManager: MKLocalSearchCompleterDelegate {

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async { self.searchResults = completer.results }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("📍 Completer failed: \(error.localizedDescription)")
    }
}

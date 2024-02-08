import CoreLocation
import MapKit
import AVFoundation
import UIKit
import Speech

class MapView: UIViewController, CLLocationManagerDelegate, UISearchBarDelegate, MKMapViewDelegate, SFSpeechRecognizerDelegate {

    @IBOutlet weak var directionLabel: UILabel!
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var endRouteButton: UIButton!
    @IBOutlet weak var searchButton: UIButton!

    let locationManager = CLLocationManager()
    var currentCoordinate: CLLocationCoordinate2D!
    var steps = [MKRoute.Step]()
    let speechSynthesizer = AVSpeechSynthesizer()
    var stepCounter = 0
    let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    var recognitionTask: SFSpeechRecognitionTask?
    let audioEngine = AVAudioEngine()
    var isCurrentLocationAnnounced = false

    override func viewDidLoad() {
        super.viewDidLoad()

        locationManager.requestWhenInUseAuthorization()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.startUpdatingLocation()
        mapView.delegate = self

        endRouteButton.setTitle("End Route", for: .normal)
        endRouteButton.addTarget(self, action: #selector(endRouteButtonPressed(_:)), for: .touchUpInside)

        searchButton.setTitle("Search", for: .normal)
        searchButton.addTarget(self, action: #selector(searchButtonTapped(_:)), for: .touchUpInside)

        guard speechRecognizer != nil else {
            print("Speech recognition is not available for this device")
            return
        }

        // Request authorization for speech recognition
        SFSpeechRecognizer.requestAuthorization { [unowned self] (authStatus) in
            switch authStatus {
            case .authorized:
                // Don't start recording here, wait until the location is updated
                break
            case .denied, .restricted, .notDetermined:
                print("Speech recognition authorization denied")
            @unknown default:
                fatalError()
            }
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord)
            try audioSession.setMode(.default)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            try audioSession.overrideOutputAudioPort(.speaker)
        } catch {
            debugPrint("Unable to start audio engine")
            return
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        manager.stopUpdatingLocation()
        guard let currentLocation = locations.first else { return }
        currentCoordinate = currentLocation.coordinate
        mapView.userTrackingMode = .followWithHeading

        tellCurrentLocation()
    }

    func tellCurrentLocation() {
        guard let currentCoordinate = currentCoordinate else {
            print("Current location not available.")
            return
        }

        let geoCoder = CLGeocoder()
        let location = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)

        geoCoder.reverseGeocodeLocation(location) { (placemarks, error) in
            if let error = error {
                print("Reverse geocoding failed with error: \(error.localizedDescription)")
                return
            }

            guard let placemark = placemarks?.first else {
                print("No placemarks found.")
                return
            }

            if let street = placemark.thoroughfare {
                let message = "Your current location is on \(street) street."
                self.speakMessage(message)
                self.askForDestination()
            } else {
                print("Street name not found.")
            }
        }
    }
    
    func askForDestination() {
        let message = "What is your destination?"
        speakMessage(message)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            guard let self = self else { return }
            do {
                try self.startRecording()
            } catch {
                print("Error starting recording: \(error)")
            }
        }
    }
    
    func startRecording() throws {
        let node = audioEngine.inputNode

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest, resultHandler: { [weak self] (result, error) in
            guard let self = self else { return }
            var isFinal = false

            if let result = result {
                let formattedString = result.bestTranscription.formattedString

                DispatchQueue.main.async { [weak self] in
                    self?.searchBar.text = nil
                    self?.searchBar.text = formattedString
                }

                isFinal = result.isFinal

                if isFinal {
                    DispatchQueue.main.async { [weak self] in
                        self?.searchBar.text = nil
                    }
                }
            }

            if error != nil || isFinal {
                self.audioEngine.stop()
                node.removeTap(onBus: 0)

                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        })

        let recordingFormat = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, _) in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        // Stop recording after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }
            self.stopRecordingAndSearchRoute()
        }
    }

    func stopRecordingAndSearchRoute() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        // Start searching for the route after recording stops
        guard let searchText = searchBar.text, !searchText.isEmpty else {
            // Show an alert or handle empty search text
            return
        }

        let localSearchRequest = MKLocalSearch.Request()
        localSearchRequest.naturalLanguageQuery = searchText

        let localSearch = MKLocalSearch(request: localSearchRequest)
        localSearch.start { [weak self] (response, error) in
            guard let self = self else { return }

            if let error = error {
                print("Error searching for destination: \(error.localizedDescription)")
                // Inform the user about the error
                self.speakMessage("Error searching for destination. Please try again.")
                return
            }

            guard let response = response else {
                print("No response received for destination search.")
                // Inform the user that no response was received
                self.speakMessage("No response received for destination search. Please try again.")
                return
            }

            guard let firstMapItem = response.mapItems.first else {
                // Inform the user that no route was found to the destination
                self.speakMessage("No route found to the destination. Please try another destination.")
                return
            }

            // Start the route to the destination
            self.getDirections(to: firstMapItem)
        }
    }

    func speakMessage(_ message: String) {
        let speechUtterance = AVSpeechUtterance(string: message)
        speechSynthesizer.speak(speechUtterance)
    }

    func getDirections(to destination: MKMapItem) {
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        directionLabel.text = ""
        
        let sourcePlacemark = MKPlacemark(coordinate: currentCoordinate)
        let sourceMapItem = MKMapItem(placemark: sourcePlacemark)
        let directionRequest = MKDirections.Request()
        directionRequest.source = sourceMapItem
        directionRequest.destination = destination
        directionRequest.transportType = .automobile
        
        let directions = MKDirections(request: directionRequest)
        directions.calculate { [weak self] (response, error) in
            guard let self = self else { return }
            guard let response = response else {
                if let error = error {
                    print("Error calculating directions: \(error.localizedDescription)")
                }
                return
            }
            guard let primaryRoute = response.routes.first else {
                print("No routes found.")
                return
            }
            
            self.mapView.addOverlay(primaryRoute.polyline)
            self.locationManager.monitoredRegions.forEach { self.locationManager.stopMonitoring(for: $0) }
            self.steps = primaryRoute.steps
            
            let destinationAnnotation = MKPointAnnotation()
            destinationAnnotation.coordinate = destination.placemark.coordinate
            destinationAnnotation.title = "Destination"
            self.mapView.addAnnotation(destinationAnnotation)
            
            let region = MKCoordinateRegion(center: destination.placemark.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
            self.mapView.setRegion(region, animated: true)
            
            self.speakNextRouteInstruction()
        }
    }

    func speakNextRouteInstruction() {
        guard stepCounter < steps.count else {
            return
        }
        
        let step = steps[stepCounter]
        let distanceString = String(format: "%.2f", step.distance)
        let message = "\(step.instructions) for \(distanceString) meters."
        speakMessage(message)
        stepCounter += 1
        
        if stepCounter < steps.count {
            let nextStep = steps[stepCounter]
            let nextMessage = "In \(String(format: "%.2f", nextStep.distance)) meters, \(nextStep.instructions)."
            self.directionLabel.text = nextMessage
        }
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.endEditing(true)
        
        let localSearchRequest = MKLocalSearch.Request()
        localSearchRequest.naturalLanguageQuery = searchBar.text
        
        let localSearch = MKLocalSearch(request: localSearchRequest)
        localSearch.start { (response, _) in
            guard let response = response else { return }
            guard let firstMapItem = response.mapItems.first else { return }
            self.getDirections(to: firstMapItem)
        }
    }
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay is MKPolyline {
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = .blue
            renderer.lineWidth = 10
            return renderer
        }
        if overlay is MKCircle {
            let renderer = MKCircleRenderer(overlay: overlay)
            renderer.strokeColor = .red
            renderer.fillColor = .red
            renderer.alpha = 0.5
            return renderer
        }
        return MKOverlayRenderer()
    }

    
    @objc func endRouteButtonPressed(_ sender: UIButton) {
        // Stop speech synthesis immediately
        speechSynthesizer.stopSpeaking(at: .immediate)
        
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        
        directionLabel.text = ""
        
        // Stop monitoring any regions
        locationManager.monitoredRegions.forEach { locationManager.stopMonitoring(for: $0) }
        
        // Clear the steps array
        steps.removeAll()

        searchBar.text = nil // Clear the search bar text
        
        // Reset the map view to show the current location if available
        if let currentCoordinate = currentCoordinate {
            let region = MKCoordinateRegion(center: currentCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
            mapView.setRegion(region, animated: true)
        }
    }

    @objc func searchButtonTapped(_ sender: UIButton) {
        guard let searchText = searchBar.text, !searchText.isEmpty else {
            // Show an alert or handle empty search text
            return
        }
        
        searchBar.endEditing(true)
        
        let localSearchRequest = MKLocalSearch.Request()
        localSearchRequest.naturalLanguageQuery = searchText
        
        let localSearch = MKLocalSearch(request: localSearchRequest)
        localSearch.start { [weak self] (response, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("Error searching for destination: \(error.localizedDescription)")
                // Inform the user about the error
                self.speakMessage("Error searching for destination. Please try again.")
                return
            }
            
            guard let response = response else {
                print("No response received for destination search.")
                // Inform the user that no response was received
                self.speakMessage("No response received for destination search. Please try again.")
                return
            }
            
            guard let firstMapItem = response.mapItems.first else {
                // Inform the user that no route was found to the destination
                self.speakMessage("No route found to the destination. Please try another destination.")
                return
            }

            // Start the route to the destination
            self.getDirections(to: firstMapItem)

        }
    }
}

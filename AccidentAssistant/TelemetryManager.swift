//
//  TelemetryManager.swift
//  AccidentAssistant
//
//  Sprint 3: Production-grade, battery-efficient telemetry engine.
//  Architecture: CMMotionActivityManager (low-power gatekeeper) → CLLocationManager +
//  CMMotionManager (high-fidelity tracking) → crash sentinel → latestImpactData snapshot.
//

import Foundation
import CoreLocation
import CoreMotion
import UserNotifications
import UIKit
import Combine // 👉 FIX 1: Required for @Published and ObservableObject

// MARK: - Data Model

/// One point in the 15-second pre-impact rolling buffer.
struct TelemetryPoint: Codable {
    /// Countdown label from the moment of impact: "T-14s" … "T-00s".
    let timeOffset: String
    let speed_mph: Int
    let event: String
}

// MARK: - Engine

@MainActor
final class TelemetryManager: NSObject, ObservableObject {

    // MARK: Singleton
    static let shared = TelemetryManager()

    // MARK: Published state
    @Published var isDriving = false
    @Published var isTestMode = false
    @Published var latestImpactData: [TelemetryPoint]? = nil

    // MARK: Private — hardware managers
    private let locationManager   = CLLocationManager()
    private let activityManager   = CMMotionActivityManager()
    private let motionManager     = CMMotionManager()

    // MARK: Private — rolling buffer
    /// 15-second window; each slot represents one second of data.
    private var rollingBuffer: [TelemetryPoint] = []
    private let bufferCapacity = 15

    /// Timer that ticks every second to commit a new point into the buffer.
    private var bufferTimer: Timer?

    /// Most-recent GPS speed in mph (updated by CLLocationManagerDelegate).
    private var currentSpeedMPH: Int = 0

    // MARK: - Init

    private override init() {
        super.init()
        configureLocationManager()
        scheduleTerminationGuard()
    }

    // MARK: - Configuration

    private func configureLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        // Required entitlements for background speed tracking.
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    /// Registers a UIApplication.willTerminateNotification observer so we can fire
    /// a re-arm push if the user force-quits the app.
    private func scheduleTerminationGuard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    // MARK: - Public API

    /// Entry point. Uses CMMotionActivityManager as a low-power gatekeeper:
    /// only activates high-fidelity hardware when automotive motion is detected.
    func startSmartMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("🏎️ CMMotionActivityManager not available — starting high-fidelity tracking unconditionally.")
            startHighFidelityTracking()
            return
        }

        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            guard !self.isTestMode else { return }

            if activity.automotive {
                if !self.isDriving {
                    print("🏎️ Automotive activity detected — starting high-fidelity tracking.")
                    self.isDriving = true
                    self.startHighFidelityTracking()
                }
            } else if activity.walking || activity.stationary || activity.running {
                if self.isDriving {
                    print("🛑 Non-automotive activity — stopping high-fidelity tracking.")
                    self.isDriving = false
                    self.stopHighFidelityTracking()
                }
            }
            // .unknown and .cycling intentionally left unchanged to avoid false stops.
        }
    }

    /// Stops all monitoring and releases hardware resources.
    func stopMonitoring() {
        activityManager.stopActivityUpdates()
        stopHighFidelityTracking()
        isDriving = false
        print("⏹️ TelemetryManager: all monitoring stopped.")
    }

    // MARK: - High-Fidelity Tracking

    /// Activates GPS speed sampling and 10 Hz accelerometer, maintaining a
    /// rolling 15-second buffer. Pass `isTest: true` to force-start without
    /// waiting for the activity gatekeeper (useful for simulator testing).
    func startHighFidelityTracking(isTest: Bool = false) {
        if isTest {
            isDriving = true
            isTestMode = true
        }

        // ── GPS ──────────────────────────────────────────────────────────────
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()

        // ── Accelerometer at 10 Hz ───────────────────────────────────────────
        guard motionManager.isAccelerometerAvailable else {
            print("⚠️ Accelerometer not available on this device.")
            return
        }
        motionManager.accelerometerUpdateInterval = 0.1   // 10 Hz
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self, let data, error == nil else { return }
            self.evaluateCrash(acceleration: data.acceleration)
        }

        // ── 1-second buffer tick ─────────────────────────────────────────────
                bufferTimer = Timer.scheduledTimer(
                    timeInterval: 1.0,
                    target: self,
                    selector: #selector(handleBufferTick),
                    userInfo: nil,
                    repeats: true
                )
        print("▶️ High-fidelity tracking started.")
    }

    /// Tears down GPS, accelerometer, and the buffer timer.
    func stopHighFidelityTracking() {
        locationManager.stopUpdatingLocation()
        motionManager.stopAccelerometerUpdates()
        bufferTimer?.invalidate()
        bufferTimer = nil
        rollingBuffer.removeAll()
        currentSpeedMPH = 0
        isDriving = false
        isTestMode = false
        print("⏸️ High-fidelity tracking stopped.")
    }

    // MARK: - Rolling Buffer

    /// Called every second by `bufferTimer`. Appends a new point and evicts the
    /// oldest one once the buffer reaches `bufferCapacity`.
    private func commitBufferPoint() {
        let point = TelemetryPoint(
            timeOffset: "T-\(String(format: "%02d", max(0, bufferCapacity - 1 - rollingBuffer.count)))s",
            speed_mph: currentSpeedMPH,
            event: "normal"
        )
        rollingBuffer.append(point)
        if rollingBuffer.count > bufferCapacity {
            rollingBuffer.removeFirst()
        }
    }
    // 👉 FIX 2: The Objective-C target for the Timer
        @objc private func handleBufferTick() {
            commitBufferPoint()
        }

    // MARK: - Crash Sentinel

    /// Evaluates every accelerometer sample. Net G-force excludes the constant
    /// 1G of gravity acting on the device at rest.
    private func evaluateCrash(acceleration: CMAcceleration) {
        let rawG = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )
        let netG = abs(rawG - 1.0)

        if netG > 2.5 {
            snapshotImpactBuffer()
            // Monitoring intentionally continues — we must keep recording post-impact.
        }
    }

    /// Freezes the current rolling buffer, re-labels each point with countdown
    /// timestamps (T-14s … T-00s), updates `latestImpactData`, and logs JSON.
    private func snapshotImpactBuffer() {
        let snapshot = rollingBuffer
        let total = snapshot.count
        let formatted: [TelemetryPoint] = snapshot.enumerated().map { index, point in
            let countdown = (total - 1) - index
            return TelemetryPoint(
                timeOffset: "T-\(String(format: "%02d", countdown))s",
                speed_mph: point.speed_mph,
                event: index == total - 1 ? "IMPACT" : point.event
            )
        }

        latestImpactData = formatted

        if let jsonData = try? JSONEncoder().encode(formatted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("🚨 IMPACT DETECTED — Pre-impact buffer:\n\(jsonString)")
            AccidentStore.shared.pendingTelemetry = PendingTelemetry(data: jsonString, timestamp: Date())
        }
    }

    // MARK: - Force-Quit Guard

    @objc private func appWillTerminate() {
        scheduleReArmNotification()
    }

    private func scheduleReArmNotification() {
        let center = UNUserNotificationCenter.current()

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Accident Assistant is Disabled"
            content.body  = "⚠️ Accident Assistant is disabled. Tap here to re-arm automatic crash detection."
            content.sound = .default

            // Fire 3 seconds after termination so the system has time to deliver it.
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
            let request = UNNotificationRequest(
                identifier: "rearm-telemetry",
                content: content,
                trigger: trigger
            )

            // 👉 FIX 3: Call UNUserNotificationCenter.current() directly instead of capturing 'center'
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    print("🔔 Re-arm notification failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension TelemetryManager: CLLocationManagerDelegate {

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last, location.speedAccuracy >= 0 else { return }
        let mph = max(0, Int(location.speed * 2.23694))   // m/s → mph
        Task { @MainActor in self.currentSpeedMPH = mph }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        print("📍 TelemetryManager location error: \(error.localizedDescription)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        print("📍 Location auth changed: \(status.rawValue)")
        if status == .authorizedAlways {
            Task { @MainActor in manager.startUpdatingLocation() }
        }
    }
}

//
//  LocationService.swift
//  SiteNote
//
//  一次性位置服务：请求 "使用期间" 权限、单次定位、反向地理编码。
//  不做后台追踪——只在用户打开新增弹窗时取一次位置。
//

import Foundation
import CoreLocation

/// 一次性位置服务。按需调用 `getCurrentLocation()` 获取坐标 + 可读地址。
///
/// 设计要点：
/// - 只请求 `WhenInUse` 权限，App 退到后台后不再定位。
/// - 精度 `kCLLocationAccuracyHundredMeters`，足够分辨"哪个工地"级别。
/// - 反向地理编码失败不影响坐标（地址字段可为 `nil`）。
@MainActor
final class LocationService: NSObject {

    /// 一次性位置结果。
    struct Location: Equatable {
        let latitude: Double
        let longitude: Double
        /// 反向地理编码得到的人类可读地址。查失败或无网为 `nil`。
        let address: String?
    }

    /// 本服务可能抛出的错误。
    enum LocationError: LocalizedError {
        case notAuthorized
        case unavailable

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "定位权限未授予"
            case .unavailable: return "位置不可用"
            }
        }
    }

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// 获取当前位置（含坐标和可读地址）。
    ///
    /// 若权限未决定，会先弹系统对话框并等待用户选择。已拒绝则立即抛 `notAuthorized`。
    /// 成功后自动把结果缓存到 UserDefaults 供 `lastSuccessfulLocation()` 使用。
    /// - Returns: 当前位置。`address` 字段可能为 `nil`（反查失败不影响坐标）。
    /// - Throws: `LocationError.notAuthorized` 或 `LocationError.unavailable`。
    func getCurrentLocation() async throws -> Location {
        // v1.6 (en-v1):截图模式 直接抛 — 不去碰 CLLocationManager。
        if MockDataSeeder.isActive { throw LocationError.notAuthorized }
        let status = await resolveAuthorization()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw LocationError.notAuthorized
        }

        let clLocation: CLLocation = try await withCheckedThrowingContinuation { cont in
            self.locationContinuation = cont
            manager.requestLocation()
        }

        let address = try? await reverseGeocode(clLocation)

        let result = Location(
            latitude: clLocation.coordinate.latitude,
            longitude: clLocation.coordinate.longitude,
            address: address
        )
        Self.storeLastLocation(result)
        return result
    }

    /// 读取最近一次成功获取的位置（跨启动持久化）。
    /// 用于当前获取失败时作为回退（室内/地下 GPS 信号差的常见场景）。
    static func lastSuccessfulLocation() -> Location? {
        let defaults = UserDefaults.standard
        guard let lat = defaults.object(forKey: "lastLocation.latitude") as? Double,
              let lng = defaults.object(forKey: "lastLocation.longitude") as? Double else {
            return nil
        }
        let address = defaults.string(forKey: "lastLocation.address")
        return Location(latitude: lat, longitude: lng, address: address)
    }

    /// 把一次成功的位置写到 UserDefaults 供下次做回退使用。
    private static func storeLastLocation(_ location: Location) {
        let defaults = UserDefaults.standard
        defaults.set(location.latitude, forKey: "lastLocation.latitude")
        defaults.set(location.longitude, forKey: "lastLocation.longitude")
        if let address = location.address {
            defaults.set(address, forKey: "lastLocation.address")
        } else {
            defaults.removeObject(forKey: "lastLocation.address")
        }
    }

    /// 若权限未决定则发起请求并等待用户选择；否则直接返回当前状态。
    /// v1.6 (en-v1):截图模式 永远返回 denied,杜绝 location dialog 污染截图。
    private func resolveAuthorization() async -> CLAuthorizationStatus {
        if MockDataSeeder.isActive { return .denied }
        let current = manager.authorizationStatus
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { cont in
            self.authContinuation = cont
            manager.requestWhenInUseAuthorization()
        }
    }

    /// 反向地理编码：返回 "Suburb, State" 简名格式（工地场景只关心 "哪个区"）。
    /// 例如 "Sydney, NSW"。无法拼出时返回 nil。
    private func reverseGeocode(_ location: CLLocation) async throws -> String? {
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let mark = placemarks.first else { return nil }

        let suburb = mark.locality ?? mark.subLocality
        let state = mark.administrativeArea

        if let suburb, let state {
            return "\(suburb), \(state)"
        }
        if let suburb { return suburb }
        if let state { return state }
        return nil
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            if let cont = locationContinuation {
                locationContinuation = nil
                cont.resume(returning: location)
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            if let cont = locationContinuation {
                locationContinuation = nil
                cont.resume(throwing: LocationError.unavailable)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if let cont = authContinuation {
                authContinuation = nil
                cont.resume(returning: status)
            }
        }
    }
}

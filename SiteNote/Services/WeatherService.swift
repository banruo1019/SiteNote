//
//  WeatherService.swift
//  SiteNote
//
//  调 Open-Meteo 免费天气 API 拉当前气温和天气状况。
//  网络失败时调用方应静默跳过（本服务直接抛错，不做降级）。
//

import Foundation

/// 天气查询服务。使用 Open-Meteo 免费 API（无需 Key、HTTPS、无配额）。
@MainActor
final class WeatherService {

    /// 查询结果。
    struct Weather: Equatable {
        /// 气温（摄氏度）。
        let temperature: Double
        /// WMO 天气编码（0=晴、61=雨 等）。
        let code: Int
        /// 面向用户的一行摘要，例如 "22°C 小雨"。
        let summary: String
    }

    enum WeatherError: Error {
        case networkFailed
        case decodeFailed
    }

    /// 查询指定坐标的当前天气。
    /// - Parameters:
    ///   - latitude: 纬度
    ///   - longitude: 经度
    /// - Returns: Weather。网络失败或解析失败时抛错。
    func fetch(latitude: Double, longitude: Double) async throws -> Weather {
        let urlString = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(latitude)"
            + "&longitude=\(longitude)"
            + "&current=temperature_2m,weather_code"
        guard let url = URL(string: urlString) else {
            throw WeatherError.networkFailed
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WeatherError.networkFailed
        }

        let payload: OpenMeteoResponse
        do {
            payload = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        } catch {
            throw WeatherError.decodeFailed
        }

        let temp = payload.current.temperature
        let code = payload.current.weatherCode
        let summary = "\(Int(temp.rounded()))°C \(Self.description(code: code))"

        return Weather(temperature: temp, code: code, summary: summary)
    }

    /// 把 WMO 天气编码映射到中文描述。涵盖建筑工地最关心的雨/雪/雷/雾。
    static func description(code: Int) -> String {
        switch code {
        case 0: return "晴"
        case 1: return "晴间多云"
        case 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51, 53, 55: return "毛毛雨"
        case 56, 57: return "冻毛毛雨"
        case 61, 63, 65: return "雨"
        case 66, 67: return "冻雨"
        case 71, 73, 75: return "雪"
        case 77: return "米雪"
        case 80, 81, 82: return "阵雨"
        case 85, 86: return "阵雪"
        case 95: return "雷暴"
        case 96, 99: return "雷暴冰雹"
        default: return "未知天气"
        }
    }

    private struct OpenMeteoResponse: Decodable {
        let current: Current
        struct Current: Decodable {
            let temperature: Double
            let weatherCode: Int
            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case weatherCode = "weather_code"
            }
        }
    }
}

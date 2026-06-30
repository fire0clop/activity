import Foundation

/// Конфигурация окружения. Базовый URL бэкенда (см. backend/ROADMAP §4).
enum AppConfig {
    #if targetEnvironment(simulator)
    // Симулятор всегда достаёт Mac через localhost — не зависит от смены Wi-Fi/IP.
    static let host = "localhost:8080"
    #else
    // Реальный телефон: LAN-IP Mac'а в той же Wi-Fi. Обновляется командой ./setip.sh
    static let host = "192.168.50.63:8080" // device-host
    #endif

    static let baseURL = URL(string: "http://\(host)/api/v1")!
    static let wsBaseURL = URL(string: "ws://\(host)/api/v1")!
}

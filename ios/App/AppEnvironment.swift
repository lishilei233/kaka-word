import Foundation

/// 集中管理开发、测试和生产环境之间会变化的配置，避免在页面或网络代码中散落环境判断。
struct AppEnvironment {
    let apiBaseURL: URL

    static let current = AppEnvironment(
        // 真机无法通过 localhost 访问 Mac；提交 TestFlight 前应替换为生产 HTTPS 地址。
        apiBaseURL: URL(string: "https://api.kakaword.com")!
    )
}

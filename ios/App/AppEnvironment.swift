import Foundation

/// 集中管理开发、测试和生产环境之间会变化的配置，避免在页面或网络代码中散落环境判断。
struct AppEnvironment {
    let apiBaseURL: URL

    static let current = AppEnvironment(
        // Release/TestFlight/App Store 必须使用审核员可访问的生产 HTTPS 服务。
        apiBaseURL: URL(string: "https://api.kakaword.com")!
    )
}

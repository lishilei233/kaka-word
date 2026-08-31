import Foundation

/// 集中管理开发、测试和生产环境之间会变化的配置，避免在页面或网络代码中散落环境判断。
struct AppEnvironment {
    let apiBaseURL: URL

    static let current: AppEnvironment = {
        let configured = Bundle.main.object(forInfoDictionaryKey: "PictureWordAPIBaseURL") as? String
        guard let value = configured?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              let url = URL(string: value),
              url.host != nil else {
            fatalError("PictureWordAPIBaseURL is missing or invalid")
        }
#if !DEBUG
        guard url.scheme == "https" else {
            fatalError("Release builds require an HTTPS PictureWordAPIBaseURL")
        }
#endif
        return AppEnvironment(apiBaseURL: url)
    }()
}

import Foundation

enum LearningMode: String, Codable, CaseIterable, Identifiable {
    case selfExplore
    case parentChild

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selfExplore: return "自己探索"
        case .parentChild: return "陪孩子玩"
        }
    }

    var subtitle: String {
        switch self {
        case .selfExplore: return "把日常照片做成英语手账"
        case .parentChild: return "和 3–8 岁孩子一起玩寻宝"
        }
    }

    var icon: String {
        switch self {
        case .selfExplore: return "sparkles"
        case .parentChild: return "figure.2.and.child.holdinghands"
        }
    }
}

struct DailyMission: Identifiable, Hashable {
    let id: String
    let title: String
    let prompt: String
    let parentTip: String
    let symbol: String
    let stickerTitle: String
    let targetCount: Int
}

struct MissionProgress: Codable, Hashable {
    let dayKey: String
    var missionID: String
    var recognizedWords: [String]
    var completedAt: Date?
    var stickerID: String?
}

struct StickerRecord: Codable, Identifiable, Hashable {
    let id: String
    let earnedAt: Date
    let missionID: String
    let title: String
    let symbol: String
}

struct MissionUpdate: Equatable {
    let count: Int
    let target: Int
    let newlyAdded: [String]
    let completedNow: Bool
    let sticker: StickerRecord?
}

enum DailyMissionCatalog {
    static let missions: [DailyMission] = [
        .init(id: "kitchen", title: "厨房小侦探", prompt: "去厨房找 3 样东西", parentTip: "让孩子先用手指出来，再一起听英文。", symbol: "fork.knife", stickerTitle: "厨房侦探", targetCount: 3),
        .init(id: "breakfast", title: "早餐桌寻宝", prompt: "找找早餐桌上的 3 样东西", parentTip: "不必摆拍，吃早餐时顺手完成就好。", symbol: "cup.and.saucer.fill", stickerTitle: "早餐达人", targetCount: 3),
        .init(id: "bedroom", title: "卧室探险", prompt: "在卧室发现 3 个单词", parentTip: "从孩子最熟悉的玩具和家具开始。", symbol: "bed.double.fill", stickerTitle: "卧室探险家", targetCount: 3),
        .init(id: "living-room", title: "客厅观察员", prompt: "在客厅找到 3 样东西", parentTip: "鼓励孩子自己决定镜头要对准哪里。", symbol: "sofa.fill", stickerTitle: "客厅观察员", targetCount: 3),
        .init(id: "bathroom", title: "洗漱时间", prompt: "在洗漱区找 3 样东西", parentTip: "洗手、刷牙时自然地重复一遍单词。", symbol: "shower.fill", stickerTitle: "清洁小能手", targetCount: 3),
        .init(id: "clothes", title: "今天穿什么", prompt: "拍下 3 件衣物或配饰", parentTip: "让孩子选出最喜欢的一件并听发音。", symbol: "tshirt.fill", stickerTitle: "穿搭小明星", targetCount: 3),
        .init(id: "toys", title: "玩具总动员", prompt: "从玩具里发现 3 个单词", parentTip: "每拍到一个，就让玩具和孩子打个招呼。", symbol: "teddybear.fill", stickerTitle: "玩具好朋友", targetCount: 3),
        .init(id: "books", title: "阅读角寻宝", prompt: "在阅读角找 3 样东西", parentTip: "完成后选一本书一起翻一页。", symbol: "books.vertical.fill", stickerTitle: "阅读小达人", targetCount: 3),
        .init(id: "red", title: "寻找红色", prompt: "找到 3 样红色附近的东西", parentTip: "先说颜色，再把镜头对准具体物品。", symbol: "paintpalette.fill", stickerTitle: "红色发现家", targetCount: 3),
        .init(id: "green", title: "寻找绿色", prompt: "找到 3 样绿色附近的东西", parentTip: "可以从植物、蔬菜或玩具开始。", symbol: "leaf.fill", stickerTitle: "绿色发现家", targetCount: 3),
        .init(id: "round", title: "圆圆的世界", prompt: "找 3 样圆形附近的东西", parentTip: "让孩子先比一个圆，再去寻找。", symbol: "circle.hexagongrid.fill", stickerTitle: "形状观察员", targetCount: 3),
        .init(id: "soft", title: "软乎乎寻宝", prompt: "找到 3 样摸起来柔软的东西", parentTip: "拍照前先摸一摸，说说是什么感觉。", symbol: "cloud.fill", stickerTitle: "触感小专家", targetCount: 3),
        .init(id: "fruit", title: "水果派对", prompt: "从水果附近发现 3 个单词", parentTip: "闻一闻、摸一摸，再一起听单词。", symbol: "carrot.fill", stickerTitle: "水果派对", targetCount: 3),
        .init(id: "snack", title: "点心时间", prompt: "在点心时间发现 3 个单词", parentTip: "把英语变成轻松的小仪式，不要求背诵。", symbol: "birthday.cake.fill", stickerTitle: "点心观察家", targetCount: 3),
        .init(id: "desk", title: "书桌整理员", prompt: "在书桌找到 3 样东西", parentTip: "认识一个单词，就顺手整理一样物品。", symbol: "pencil.and.ruler.fill", stickerTitle: "书桌整理员", targetCount: 3),
        .init(id: "bag", title: "包包里有什么", prompt: "从包里发现 3 个单词", parentTip: "只拍普通物品，避开姓名和证件信息。", symbol: "backpack.fill", stickerTitle: "随身小管家", targetCount: 3),
        .init(id: "window", title: "窗边观察", prompt: "在窗边发现 3 个单词", parentTip: "看看室内和窗外有什么不同。", symbol: "sun.max.fill", stickerTitle: "窗边观察员", targetCount: 3),
        .init(id: "balcony", title: "阳台漫游", prompt: "在阳台或门口找 3 样东西", parentTip: "注意安全，由家长拿稳手机。", symbol: "house.and.flag.fill", stickerTitle: "阳台漫游者", targetCount: 3),
        .init(id: "park", title: "公园探索", prompt: "在公园发现 3 个单词", parentTip: "边散步边找，不需要一次完成。", symbol: "tree.fill", stickerTitle: "公园探索家", targetCount: 3),
        .init(id: "street", title: "散步观察员", prompt: "散步时拍下 3 样常见东西", parentTip: "停稳后再拍照，注意车辆和路况。", symbol: "figure.walk", stickerTitle: "散步观察员", targetCount: 3),
        .init(id: "weather", title: "天气记录", prompt: "从今天的天气里发现 3 个单词", parentTip: "说说今天冷不冷、亮不亮、有没有风。", symbol: "cloud.sun.fill", stickerTitle: "天气记录员", targetCount: 3),
        .init(id: "plants", title: "植物朋友", prompt: "在植物附近发现 3 个单词", parentTip: "观察叶子和花，但不要随意采摘。", symbol: "camera.macro", stickerTitle: "植物好朋友", targetCount: 3),
        .init(id: "transport", title: "出发吧", prompt: "出门时发现 3 个交通单词", parentTip: "只在安全位置拍摄，不追赶车辆。", symbol: "bus.fill", stickerTitle: "交通观察员", targetCount: 3),
        .init(id: "shopping", title: "采购小助手", prompt: "购物时找到 3 样东西", parentTip: "让孩子帮忙寻找清单里的普通物品。", symbol: "basket.fill", stickerTitle: "采购小助手", targetCount: 3),
        .init(id: "picnic", title: "户外点心", prompt: "在户外休息时发现 3 个单词", parentTip: "可以分几张照片完成，不用一次拍全。", symbol: "takeoutbag.and.cup.and.straw.fill", stickerTitle: "户外点心家", targetCount: 3),
        .init(id: "morning", title: "早安寻宝", prompt: "起床后找到 3 样东西", parentTip: "用三个单词开启轻松的一天。", symbol: "sunrise.fill", stickerTitle: "早安小太阳", targetCount: 3),
        .init(id: "evening", title: "晚安回顾", prompt: "睡前回顾今天的 3 样东西", parentTip: "听完发音就结束，不做记忆检查。", symbol: "moon.stars.fill", stickerTitle: "晚安收藏家", targetCount: 3),
        .init(id: "favorites", title: "我的最爱", prompt: "拍下今天最喜欢的 3 样东西", parentTip: "让孩子说说为什么喜欢，答案没有对错。", symbol: "heart.fill", stickerTitle: "今日最爱", targetCount: 3),
    ]
}

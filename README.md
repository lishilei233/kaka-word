# Picture Word

拍照识别物体并把英文单词标记到照片上的 iOS 学习应用。产品提供两种本地玩法：

- **自己探索**：把日常照片做成英语手账。
- **陪孩子玩**：通过每日寻宝任务累计单词并收集贴纸。

识别成功后，App 会把压缩照片、缩略图和识别结果保存在设备本地，并在首页展示全部历史记录。历史记录不设数量上限，不上传或同步到云端；用户可以删除单条记录或清空全部记录。

识别完成后可生成 3:4 学习分享卡。分享前使用 iOS Vision 在设备本机检测人脸并默认模糊；导出的 JPEG 不保留原照片的地点和拍摄时间元数据。

## 项目结构

- `ios/` — SwiftUI iOS App，当前阶段只做 iOS
- `server/` — Node.js + Hono API

## 本地运行后端

```bash
cd server
npm install
cp .env.example .env
npm run dev
```

默认使用 `VISION_PROVIDER=qwen` 和 `qwen3.7-plus`。请在 `server/.env` 中填写新的 `QWEN_API_KEY`。如需不消耗模型额度地联调界面，可临时设置 `VISION_PROVIDER=mock`，返回固定的 `mug / book / plant`。

## 运行 iOS

打开 `ios/PictureWord.xcodeproj`，选择 iPhone Simulator 后运行。

模拟器默认请求 `http://127.0.0.1:8787`。真机调试时，把 `ios/Network.swift` 中的地址改成运行后端电脑的局域网 IP，并确保手机和电脑在同一网络。

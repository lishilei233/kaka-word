import SwiftUI
import UIKit

/// One recognition flow that renders partial labels directly in the card detail layout.
struct RecognitionFlowView: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var journeyStore: LearningJourneyStore
    @AppStorage(AppSettings.Key.maxObjects) private var maxObjects = AppSettings.defaultMaxObjects
    @AppStorage(AppSettings.Key.captionStyle) private var captionStyleRawValue = AppSettings.defaultCaptionStyle
    @AppStorage(AppSettings.Key.learningMode) private var modeRawValue = AppSettings.defaultLearningMode
    @StateObject private var model = AnalysisViewModel()
    @State private var completedResult: AnalyzeResult?
    @State private var showCancelConfirmation = false
    @State private var showShareCard = false
    @State private var didStart = false
    @State private var didSaveResult = false
    @State private var emptyResultMessage: String?
    @State private var saveErrorMessage: String?
    @State private var missionUpdate: MissionUpdate?
    @State private var savedRecordID: UUID?

    var body: some View {
        ZStack {
            NotebookBackground()
            PhotoWordCardDetailView(
                image: image,
                result: visibleResult,
                missionUpdate: missionUpdate,
                revealsAnnotations: true,
                status: cardStatus,
                onClose: close,
                onShare: {
                    guard completedResult != nil else { return }
                    showShareCard = true
                },
                onRetry: retry,
                onResultChange: updateResult
            )
        }
        .onAppear {
            guard !didStart else { return }
            didStart = true
            model.start(
                image: image,
                maxObjects: AppSettings.normalizedMaxObjects(maxObjects),
                captionStyle: captionStyle
            )
        }
        .onChange(of: model.phase) { _, newPhase in
            guard case .success(let result) = newPhase,
                  !showCancelConfirmation else { return }
            accept(result)
        }
        .onChange(of: showCancelConfirmation) { _, isPresented in
            guard !isPresented, case .success(let result) = model.phase else { return }
            accept(result)
        }
        .sheet(isPresented: $showShareCard) {
            if let completedResult {
                ShareCardView(image: image, result: completedResult)
            }
        }
        .alert("取消这次识别？", isPresented: $showCancelConfirmation) {
            Button("继续等待", role: .cancel) {
                if case .success(let result) = model.phase {
                    accept(result)
                }
            }
            Button("取消识别", role: .destructive) {
                model.cancel()
                dismiss()
            }
        } message: {
            Text("取消后不会保存本次照片和识别结果。")
        }
        .alert("无法保存历史记录", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .pictureWordBackSwipe(action: close)
    }

    private var visibleResult: AnalyzeResult {
        completedResult ?? AnalyzeResult(
            imageWidth: max(Int(image.size.width.rounded()), 1),
            imageHeight: max(Int(image.size.height.rounded()), 1),
            objects: model.objects,
            caption: nil,
            captionStyle: nil
        )
    }

    private var cardStatus: PhotoWordCardStatus {
        if let emptyResultMessage {
            return .failed(emptyResultMessage)
        }
        if let completedResult, !completedResult.objects.isEmpty {
            return .complete
        }
        switch model.phase {
        case .preparing:
            return .preparing
        case .uploading(let progress):
            return .uploading(progress)
        case .analyzing, .success:
            return .recognizing
        case .failed(let message):
            return .failed(message)
        case .cancelled:
            return .cancelled
        }
    }

    private var failureMessage: String? {
        guard case .failed(let message) = model.phase else { return nil }
        return message
    }

    private func close() {
        if model.phase.isActive || (completedResult == nil && failureMessage == nil && emptyResultMessage == nil) {
            showCancelConfirmation = true
        } else {
            dismiss()
        }
    }

    private func retry() {
        emptyResultMessage = nil
        completedResult = nil
        didSaveResult = false
        missionUpdate = nil
        savedRecordID = nil
        showShareCard = false
        model.retry(
            image: image,
            maxObjects: AppSettings.normalizedMaxObjects(maxObjects),
            captionStyle: captionStyle
        )
    }

    private func accept(_ result: AnalyzeResult) {
        guard completedResult == nil else { return }
        guard !result.objects.isEmpty else {
            emptyResultMessage = "没有找到适合学习的物体，请换个角度或选择另一张照片。"
            return
        }

        if !didSaveResult {
            didSaveResult = true
            let mode = LearningMode(rawValue: modeRawValue) ?? .selfExplore
            let update = mode == .parentChild ? journeyStore.record(objects: result.objects) : nil
            missionUpdate = update
            do {
                let record = try historyStore.save(
                    image: image,
                    result: result,
                    mode: mode,
                    missionID: mode == .parentChild ? journeyStore.currentMission.id : nil,
                    earnedStickerID: update?.sticker?.id
                )
                savedRecordID = record.id
            } catch {
                saveErrorMessage = error.localizedDescription
            }
        }

        completedResult = result
    }

    private var captionStyle: CaptionStyle {
        CaptionStyle(rawValue: captionStyleRawValue) ?? .serious
    }

    private func updateResult(_ updated: AnalyzeResult) -> String? {
        if let savedRecordID {
            do {
                try historyStore.updateResult(id: savedRecordID, result: updated)
            } catch {
                return error.localizedDescription
            }
        }
        completedResult = updated
        return nil
    }
}

import SwiftUI
import UIKit

struct SharedImageFile: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct SystemShareView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

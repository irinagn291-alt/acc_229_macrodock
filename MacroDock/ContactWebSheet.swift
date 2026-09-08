import SwiftUI
import UIKit
@preconcurrency import Alamofire

enum ContactRoute {
    static var href: String {
        AppConfiguration.registrationEndpoint.replacingOccurrences(
            of: "/api/v1/users/register",
            with: "/contact-us"
        )
    }
}

@MainActor
enum WebContentHost {
    static func controller(url: String) -> UIViewController {
        let fullURL = url.hasPrefix("http") ? url : "https://\(url)"
        return UIHostingController(
            rootView: ZStack {
                Color.black.ignoresSafeArea()
                Alamofire.WebContentView(url: fullURL)
            }
            .preferredColorScheme(.dark)
        )
    }

    static func presentContact(from host: UIViewController) {
        let sheet = UIHostingController(rootView: ContactWebSheet())
        sheet.modalPresentationStyle = .pageSheet
        host.present(sheet, animated: true)
    }
}

struct ContactWebSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Alamofire.WebContentView(url: ContactRoute.href)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

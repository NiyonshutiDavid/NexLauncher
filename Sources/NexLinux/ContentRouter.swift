import Foundation
import Adwaita
import NexApp
import NexCore

/// Shows the page the model is on (the Linux counterpart of the Mac app's `page` switch).
struct ContentRouter: View {
    let model: AppModel

    var view: Body {
        if case .collection(let id) = model.page, let node = model.node(id: id) {
            CollectionPage(model: model, node: node)
        } else if case .project(let id) = model.page, let project = model.project(id: id) {
            ProjectPage(model: model, project: project)
        } else if case .tasks = model.page {
            TasksPage(model: model)
        } else if case .ai = model.page {
            AIPage(model: model)
        } else if case .settings = model.page {
            SettingsPage(model: model)
        } else {
            HomePage(model: model)
        }
    }
}

/// A page whose Linux version is still being built.
struct ComingSoonPage: View {
    let model: AppModel
    let title: String
    var view: Body {
        StatusPage(title, icon: .default(icon: .applicationXExecutable), description: "Coming to Linux in the next update.") {}
            .topToolbar { BreadcrumbHeader(model: model) }
    }
}

/// The header for inner pages: Back plus the clickable breadcrumb, as on the Mac.
struct BreadcrumbHeader: View {
    let model: AppModel
    var view: Body {
        HeaderBar {
            Button(icon: .default(icon: .goPrevious)) { model.goBack() }
                .tooltip("Back")
        } end: {}
        .headerBarTitle {
            HStack(spacing: 4) {
                ForEach(crumbs) { crumb in
                    HStack(spacing: 4) {
                        if crumb.index > 0 { Text("›").style("dim-label") }
                        if let page = crumb.crumb.page {
                            Button(crumb.crumb.title) { model.page = page }.flat()
                        } else {
                            Text(crumb.crumb.title).style("heading")
                        }
                    }
                }
            }
        }
    }

    private struct IndexedCrumb: Identifiable { let index: Int; let crumb: Crumb; var id: Int { index } }

    private var crumbs: [IndexedCrumb] {
        var trail = model.breadcrumbs(for: model.page)
        if trail.isEmpty {
            let title: String
            switch model.page {
            case .tasks: title = "Tasks"
            case .ai: title = "AI Assistant"
            case .settings: title = "Settings"
            default: title = "Projects"
            }
            trail = [Crumb(title: "Projects", page: .home), Crumb(title: title, page: nil)]
        }
        return trail.enumerated().map { IndexedCrumb(index: $0.offset, crumb: $0.element) }
    }
}

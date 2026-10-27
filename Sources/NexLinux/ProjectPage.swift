import Foundation
import Adwaita
import NexApp
import NexCore

/// A project's page (filled in by the next task).
struct ProjectPage: View {
    let model: AppModel
    let project: Project
    var view: Body {
        StatusPage(project.name, icon: .default(icon: .folder), description: ProjectSubtitle.text(for: project)) {}
            .topToolbar { BreadcrumbHeader(model: model) }
    }
}

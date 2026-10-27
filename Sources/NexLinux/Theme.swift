import NexCore

/// Nexventures Ember, the same accent as the Mac app (ThemePalette), for libadwaita 1.5 and 1.6+.
enum Theme {
    static let css = """
    @define-color accent_bg_color #cf3f0e;
    @define-color accent_fg_color #ffffff;
    @define-color accent_color #a8320b;
    :root { --accent-bg-color: #cf3f0e; --accent-fg-color: #ffffff; --accent-color: #a8320b; }
    """
}

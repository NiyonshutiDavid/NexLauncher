// The few VTE calls NexLauncher uses, declared with opaque pointers so this module doesn't pull in GTK's headers
// (Adwaita for Swift's CAdw module already does; two copies of GtkWidget would clash). ABI per vte-2.91-gtk4.
#ifndef NEX_CVTE_SHIM_H
#define NEX_CVTE_SHIM_H

void *vte_terminal_new(void);
void vte_terminal_feed_child(void *terminal, const char *text, long length);
void vte_terminal_spawn_async(void *terminal, int pty_flags, const char *working_directory,
                              char **argv, char **envv, int spawn_flags,
                              void *child_setup, void *child_setup_data, void *child_setup_data_destroy,
                              int timeout, void *cancellable, void *callback, void *user_data);
void *g_object_ref_sink(void *object);
void g_object_unref(void *object);

#endif

#ifndef CSPICE_SHIM_H
#define CSPICE_SHIM_H

// GLib / GObject
#include <glib.h>
#include <glib-object.h>
#include <gio/gio.h>

// SPICE client
#define __SPICE_CLIENT_H_INSIDE__
#include <spice-client.h>
#include <channel-display.h>
#include <channel-inputs.h>

// Helper inline functions for GObject macros that don't work in Swift

static inline GObject *cspice_to_gobject(gpointer obj) {
    return (GObject *)obj;
}

static inline SpiceSession *cspice_to_session(gpointer obj) {
    return (SpiceSession *)obj;
}

static inline SpiceChannel *cspice_to_channel(gpointer obj) {
    return (SpiceChannel *)obj;
}

static inline SpiceInputsChannel *cspice_to_inputs_channel(gpointer obj) {
    return (SpiceInputsChannel *)obj;
}

static inline SpiceDisplayChannel *cspice_to_display_channel(gpointer obj) {
    return (SpiceDisplayChannel *)obj;
}

static inline gboolean cspice_is_display_channel(gpointer obj) {
    return G_TYPE_CHECK_INSTANCE_TYPE(obj, spice_display_channel_get_type());
}

static inline gboolean cspice_is_inputs_channel(gpointer obj) {
    return G_TYPE_CHECK_INSTANCE_TYPE(obj, spice_inputs_channel_get_type());
}

/// Get the channel-type property from a SpiceChannel
static inline gint cspice_channel_get_channel_type(SpiceChannel *channel) {
    gint type = -1;
    g_object_get(G_OBJECT(channel), "channel-type", &type, NULL);
    return type;
}

/// Set a string property on a GObject using g_object_set
static inline void cspice_set_string_property(gpointer obj, const char *name, const char *value) {
    g_object_set(G_OBJECT(obj), name, value, NULL);
}

/// Connect a signal using g_signal_connect_data (avoids G_CALLBACK macro)
static inline gulong cspice_signal_connect(gpointer instance, const gchar *signal_name,
                                            GCallback handler, gpointer data) {
    return g_signal_connect_data(instance, signal_name, handler, data, NULL, 0);
}

#endif /* CSPICE_SHIM_H */

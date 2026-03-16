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
#include <usb-device-manager.h>

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

// MARK: - USB Device Manager helpers
// SpiceUsbDevice is an opaque struct that Swift cannot import directly,
// so all helpers use gpointer (void*) for device parameters.

/// Get the USB device manager for a session (returns NULL on error)
static inline gpointer cspice_usb_device_manager_get(SpiceSession *session) {
    return (gpointer)spice_usb_device_manager_get(session, NULL);
}

/// Access element at index in a GPtrArray
static inline gpointer cspice_g_ptr_array_index(GPtrArray *array, guint index) {
    return g_ptr_array_index(array, index);
}

/// Get the description of a USB device (caller must g_free the result)
static inline gchar *cspice_usb_device_get_description(gpointer device) {
    return spice_usb_device_get_description((SpiceUsbDevice *)device, "%s %s");
}

/// Check if a device can be redirected
static inline gboolean cspice_usb_device_manager_can_redirect(gpointer manager,
                                                               gpointer device) {
    return spice_usb_device_manager_can_redirect_device(
        (SpiceUsbDeviceManager *)manager, (SpiceUsbDevice *)device, NULL);
}

/// Check if a device is currently connected (redirected)
static inline gboolean cspice_usb_device_manager_is_connected(gpointer manager,
                                                                gpointer device) {
    return spice_usb_device_manager_is_device_connected(
        (SpiceUsbDeviceManager *)manager, (SpiceUsbDevice *)device);
}

/// Get the list of USB devices
static inline GPtrArray *cspice_usb_device_manager_get_devices(gpointer manager) {
    return spice_usb_device_manager_get_devices((SpiceUsbDeviceManager *)manager);
}

/// Connect a USB device asynchronously
static inline void cspice_usb_device_manager_connect_device_async(gpointer manager,
                                                                    gpointer device,
                                                                    GCancellable *cancellable,
                                                                    GAsyncReadyCallback callback,
                                                                    gpointer user_data) {
    spice_usb_device_manager_connect_device_async(
        (SpiceUsbDeviceManager *)manager, (SpiceUsbDevice *)device,
        cancellable, callback, user_data);
}

/// Finish a connect-device async operation
static inline gboolean cspice_usb_device_manager_connect_device_finish(gpointer manager,
                                                                        GAsyncResult *res,
                                                                        GError **err) {
    return spice_usb_device_manager_connect_device_finish(
        (SpiceUsbDeviceManager *)manager, res, err);
}

/// Disconnect a USB device asynchronously
static inline void cspice_usb_device_manager_disconnect_device_async(gpointer manager,
                                                                      gpointer device,
                                                                      GCancellable *cancellable,
                                                                      GAsyncReadyCallback callback,
                                                                      gpointer user_data) {
    spice_usb_device_manager_disconnect_device_async(
        (SpiceUsbDeviceManager *)manager, (SpiceUsbDevice *)device,
        cancellable, callback, user_data);
}

/// Finish a disconnect-device async operation
static inline gboolean cspice_usb_device_manager_disconnect_device_finish(gpointer manager,
                                                                           GAsyncResult *res,
                                                                           GError **err) {
    return spice_usb_device_manager_disconnect_device_finish(
        (SpiceUsbDeviceManager *)manager, res, err);
}

/// Copy (ref) a SpiceUsbDevice boxed type
static inline gpointer cspice_usb_device_copy(gpointer device) {
    return g_boxed_copy(spice_usb_device_get_type(), device);
}

/// Free (unref) a SpiceUsbDevice boxed type
static inline void cspice_usb_device_free(gpointer device) {
    g_boxed_free(spice_usb_device_get_type(), device);
}

/// Create a shared CD device from a local file (ISO/IMG)
static inline gboolean cspice_usb_create_shared_cd(gpointer manager, const char *filename) {
    GError *error = NULL;
    gboolean ok = spice_usb_device_manager_create_shared_cd_device(
        SPICE_USB_DEVICE_MANAGER(manager), (gchar *)filename, &error);
    if (error) g_error_free(error);
    return ok;
}

/// Check if a device is a shared CD
static inline gboolean cspice_usb_is_shared_cd(gpointer manager, gpointer device) {
    return spice_usb_device_manager_is_device_shared_cd(
        SPICE_USB_DEVICE_MANAGER(manager), (SpiceUsbDevice *)device);
}

#endif /* CSPICE_SHIM_H */

#include "linux_bluetooth_plugin.h"

#include <bluetooth/bluetooth.h>
#include <bluetooth/rfcomm.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>
#include <cstdint>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr int kRfcommChannel = 1;

struct BluetoothPlugin {
  FlMethodChannel* method_channel;
  FlEventChannel* event_channel;
  GMutex mutex;
  int socket_fd = -1;
  uint64_t generation = 0;
  bool is_listening = false;
};

struct ConnectRequest {
  BluetoothPlugin* plugin;
  FlMethodCall* method_call;
  std::string address;
  int socket_fd = -1;
};

struct PendingEvent {
  BluetoothPlugin* plugin;
  int socket_fd;
  uint64_t generation;
  std::vector<uint8_t> bytes;
  bool disconnected;
};

bool ParseAddress(const std::string& value, bdaddr_t* address) {
  if (value.size() != 17) {
    return false;
  }

  for (size_t i = 0; i < 6; ++i) {
    const size_t offset = i * 3;
    if (i > 0 && value[offset - 1] != ':') {
      return false;
    }
    const int high = g_ascii_xdigit_value(value[offset]);
    const int low = g_ascii_xdigit_value(value[offset + 1]);
    if (high < 0 || low < 0) {
      return false;
    }
    address->b[5 - i] = static_cast<uint8_t>((high << 4) | low);
  }
  return true;
}

void SendEvent(BluetoothPlugin* plugin, FlValue* event) {
  if (!plugin->is_listening) {
    return;
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_event_channel_send(plugin->event_channel, event, nullptr, &error)) {
    g_warning("Failed to send Bluetooth event: %s", error->message);
  }
}

gboolean HandlePendingEvent(gpointer user_data) {
  std::unique_ptr<PendingEvent> pending(
      static_cast<PendingEvent*>(user_data));
  BluetoothPlugin* plugin = pending->plugin;

  g_mutex_lock(&plugin->mutex);
  if (plugin->socket_fd != pending->socket_fd ||
      plugin->generation != pending->generation) {
    g_mutex_unlock(&plugin->mutex);
    return G_SOURCE_REMOVE;
  }

  if (pending->disconnected) {
    close(plugin->socket_fd);
    plugin->socket_fd = -1;
    ++plugin->generation;
    g_mutex_unlock(&plugin->mutex);

    g_autoptr(FlValue) event = fl_value_new_map();
    fl_value_set_string_take(event, "type", fl_value_new_string("disconnected"));
    SendEvent(plugin, event);
    return G_SOURCE_REMOVE;
  }
  g_mutex_unlock(&plugin->mutex);

  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_string_take(event, "type", fl_value_new_string("data"));
  fl_value_set_string_take(
      event, "bytes",
      fl_value_new_uint8_list(pending->bytes.data(), pending->bytes.size()));
  SendEvent(plugin, event);
  return G_SOURCE_REMOVE;
}

void ReadSocket(BluetoothPlugin* plugin, int socket_fd, uint64_t generation) {
  uint8_t buffer[256];
  while (true) {
    const ssize_t count = recv(socket_fd, buffer, sizeof(buffer), 0);
    if (count > 0) {
      auto* pending = new PendingEvent{plugin, socket_fd, generation,
                                       std::vector<uint8_t>(buffer,
                                                            buffer + count),
                                       false};
      g_idle_add(HandlePendingEvent, pending);
      continue;
    }
    if (count < 0 && errno == EINTR) {
      continue;
    }

    auto* pending = new PendingEvent{plugin, socket_fd, generation, {}, true};
    g_idle_add(HandlePendingEvent, pending);
    return;
  }
}

void ConnectWorker(GTask* task,
                   gpointer,
                   gpointer task_data,
                   GCancellable*) {
  auto* request = static_cast<ConnectRequest*>(task_data);
  bdaddr_t bluetooth_address{};
  if (!ParseAddress(request->address, &bluetooth_address)) {
    g_task_return_new_error(task, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                            "Ungültige Bluetooth-MAC-Adresse.");
    return;
  }

  const int socket_fd = socket(AF_BLUETOOTH, SOCK_STREAM | SOCK_CLOEXEC,
                               BTPROTO_RFCOMM);
  if (socket_fd < 0) {
    g_task_return_new_error(task, G_IO_ERROR, g_io_error_from_errno(errno),
                            "Bluetooth-Socket konnte nicht geöffnet werden: %s",
                            g_strerror(errno));
    return;
  }

  sockaddr_rc remote_address{};
  remote_address.rc_family = AF_BLUETOOTH;
  remote_address.rc_channel = kRfcommChannel;
  bacpy(&remote_address.rc_bdaddr, &bluetooth_address);
  if (connect(socket_fd, reinterpret_cast<sockaddr*>(&remote_address),
              sizeof(remote_address)) < 0) {
    const int error_code = errno;
    close(socket_fd);
    g_task_return_new_error(
        task, G_IO_ERROR, g_io_error_from_errno(error_code),
        "RFCOMM-Verbindung fehlgeschlagen: %s. Prüfe, ob Bluetooth aktiviert "
        "und das Gerät gekoppelt ist.",
        g_strerror(error_code));
    return;
  }

  request->socket_fd = socket_fd;
  g_task_return_boolean(task, TRUE);
}

void ConnectCompleted(GObject*, GAsyncResult* result, gpointer) {
  GTask* task = G_TASK(result);
  auto* request =
      static_cast<ConnectRequest*>(g_task_get_task_data(task));
  BluetoothPlugin* plugin = request->plugin;
  g_autoptr(GError) error = nullptr;

  if (!g_task_propagate_boolean(task, &error)) {
    fl_method_call_respond_error(request->method_call, "bluetooth_connect",
                                 error->message, nullptr, nullptr);
    return;
  }

  g_mutex_lock(&plugin->mutex);
  if (plugin->socket_fd >= 0) {
    g_mutex_unlock(&plugin->mutex);
    close(request->socket_fd);
    request->socket_fd = -1;
    fl_method_call_respond_error(
        request->method_call, "bluetooth_connect",
        "Es besteht bereits eine Bluetooth-Verbindung.", nullptr, nullptr);
    return;
  }
  plugin->socket_fd = request->socket_fd;
  request->socket_fd = -1;
  const int socket_fd = plugin->socket_fd;
  const uint64_t generation = ++plugin->generation;
  g_mutex_unlock(&plugin->mutex);

  std::thread(ReadSocket, plugin, socket_fd, generation).detach();
  fl_method_call_respond_success(request->method_call, nullptr, nullptr);
}

void DestroyConnectRequest(gpointer user_data) {
  auto* request = static_cast<ConnectRequest*>(user_data);
  if (request->socket_fd >= 0) {
    close(request->socket_fd);
  }
  g_object_unref(request->method_call);
  delete request;
}

void MethodCallHandler(FlMethodChannel*,
                       FlMethodCall* method_call,
                       gpointer user_data) {
  auto* plugin = static_cast<BluetoothPlugin*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* arguments = fl_method_call_get_args(method_call);

  if (g_strcmp0(method, "connect") == 0) {
    FlValue* address = fl_value_lookup_string(arguments, "address");
    if (address == nullptr || fl_value_get_type(address) != FL_VALUE_TYPE_STRING) {
      fl_method_call_respond_error(method_call, "invalid_argument",
                                   "Bluetooth-MAC-Adresse fehlt.", nullptr,
                                   nullptr);
      return;
    }

    g_mutex_lock(&plugin->mutex);
    const bool already_connected = plugin->socket_fd >= 0;
    g_mutex_unlock(&plugin->mutex);
    if (already_connected) {
      fl_method_call_respond_error(
          method_call, "bluetooth_connect",
          "Es besteht bereits eine Bluetooth-Verbindung.", nullptr, nullptr);
      return;
    }

    auto* request = new ConnectRequest{
        plugin, FL_METHOD_CALL(g_object_ref(method_call)),
        fl_value_get_string(address), -1};
    GTask* task = g_task_new(nullptr, nullptr, ConnectCompleted, nullptr);
    g_task_set_task_data(task, request, DestroyConnectRequest);
    g_task_run_in_thread(task, ConnectWorker);
    g_object_unref(task);
    return;
  }

  if (g_strcmp0(method, "write") == 0) {
    FlValue* bytes = fl_value_lookup_string(arguments, "bytes");
    if (bytes == nullptr || fl_value_get_type(bytes) != FL_VALUE_TYPE_UINT8_LIST) {
      fl_method_call_respond_error(method_call, "invalid_argument",
                                   "Bluetooth-Daten fehlen.", nullptr, nullptr);
      return;
    }

    g_mutex_lock(&plugin->mutex);
    const int socket_fd = plugin->socket_fd;
    if (socket_fd < 0) {
      g_mutex_unlock(&plugin->mutex);
      fl_method_call_respond_error(method_call, "bluetooth_disconnected",
                                   "Keine Verbindung zum HC-06.", nullptr,
                                   nullptr);
      return;
    }

    const uint8_t* data = fl_value_get_uint8_list(bytes);
    size_t remaining = fl_value_get_length(bytes);
    while (remaining > 0) {
      const ssize_t count = send(socket_fd, data, remaining, MSG_NOSIGNAL);
      if (count < 0 && errno == EINTR) {
        continue;
      }
      if (count <= 0) {
        const int error_code = count == 0 ? EPIPE : errno;
        g_mutex_unlock(&plugin->mutex);
        const std::string message =
            std::string("Senden über Bluetooth fehlgeschlagen: ") +
            g_strerror(error_code);
        fl_method_call_respond_error(
            method_call, "bluetooth_write", message.c_str(), nullptr, nullptr);
        return;
      }
      data += count;
      remaining -= static_cast<size_t>(count);
    }
    g_mutex_unlock(&plugin->mutex);
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }

  if (g_strcmp0(method, "disconnect") == 0) {
    g_mutex_lock(&plugin->mutex);
    const int socket_fd = plugin->socket_fd;
    plugin->socket_fd = -1;
    ++plugin->generation;
    if (socket_fd >= 0) {
      shutdown(socket_fd, SHUT_RDWR);
      close(socket_fd);
    }
    g_mutex_unlock(&plugin->mutex);
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }

  fl_method_call_respond_not_implemented(method_call, nullptr);
}

FlMethodErrorResponse* ListenHandler(FlEventChannel*,
                                     FlValue*,
                                     gpointer user_data) {
  auto* plugin = static_cast<BluetoothPlugin*>(user_data);
  plugin->is_listening = true;
  return nullptr;
}

FlMethodErrorResponse* CancelHandler(FlEventChannel*,
                                     FlValue*,
                                     gpointer user_data) {
  auto* plugin = static_cast<BluetoothPlugin*>(user_data);
  plugin->is_listening = false;
  return nullptr;
}

}  // namespace

void linux_bluetooth_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  auto* plugin = new BluetoothPlugin{};
  g_mutex_init(&plugin->mutex);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);
  plugin->method_channel = fl_method_channel_new(
      messenger, "garten/bluetooth", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(plugin->method_channel,
                                            MethodCallHandler, plugin, nullptr);
  plugin->event_channel = fl_event_channel_new(
      messenger, "garten/bluetooth/events", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(plugin->event_channel, ListenHandler,
                                       CancelHandler, plugin, nullptr);
}

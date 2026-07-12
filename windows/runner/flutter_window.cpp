#include "flutter_window.h"

#include <cstdint>
#include <optional>
#include <string>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kWindowStyleChannel[] = "wds/window_style";

const flutter::EncodableValue* FindArgument(const flutter::EncodableMap& map,
                                            const char* key) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  return iterator == map.end() ? nullptr : &iterator->second;
}

std::optional<std::string> StringArgument(const flutter::EncodableMap& map,
                                          const char* key) {
  const flutter::EncodableValue* value = FindArgument(map, key);
  if (value == nullptr || !std::holds_alternative<std::string>(*value)) {
    return std::nullopt;
  }
  return std::get<std::string>(*value);
}

std::optional<int64_t> IntegerArgument(const flutter::EncodableMap& map,
                                       const char* key) {
  const flutter::EncodableValue* value = FindArgument(map, key);
  return value == nullptr ? std::nullopt : value->TryGetLongValue();
}

std::optional<Win32Window::VisualStyle> ParseVisualStyle(
    const std::string& style) {
  if (style == "win11") {
    return Win32Window::VisualStyle::kWindows11;
  }
  if (style == "win10") {
    return Win32Window::VisualStyle::kWindows10;
  }
  if (style == "win7") {
    return Win32Window::VisualStyle::kWindows7;
  }
  return std::nullopt;
}

COLORREF ColorFromArgb(int64_t value) {
  const uint32_t argb = static_cast<uint32_t>(value);
  const BYTE red = static_cast<BYTE>((argb >> 16) & 0xFF);
  const BYTE green = static_cast<BYTE>((argb >> 8) & 0xFF);
  const BYTE blue = static_cast<BYTE>(argb & 0xFF);
  return RGB(red, green, blue);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  window_style_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowStyleChannel,
          &flutter::StandardMethodCodec::GetInstance());
  window_style_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<
                 flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "update") {
          result->NotImplemented();
          return;
        }

        const flutter::EncodableValue* arguments = call.arguments();
        if (arguments == nullptr ||
            !std::holds_alternative<flutter::EncodableMap>(*arguments)) {
          result->Error("invalid_arguments",
                        "Window style update requires a map.");
          return;
        }

        const auto& map = std::get<flutter::EncodableMap>(*arguments);
        const std::optional<std::string> style_name =
            StringArgument(map, "style");
        const std::optional<std::string> brightness =
            StringArgument(map, "brightness");
        const std::optional<int64_t> accent = IntegerArgument(map, "accent");
        const std::optional<int64_t> surface =
            IntegerArgument(map, "surface");
        const std::optional<VisualStyle> style =
            style_name.has_value() ? ParseVisualStyle(*style_name)
                                   : std::nullopt;

        if (!style.has_value() || !brightness.has_value() ||
            (*brightness != "light" && *brightness != "dark") ||
            !accent.has_value() || !surface.has_value()) {
          result->Error(
              "invalid_arguments",
              "Expected resolved style, brightness, accent, and surface values.");
          return;
        }

        SetWindowStyle(*style, *brightness == "dark", ColorFromArgb(*accent),
                       ColorFromArgb(*surface));
        result->Success();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (window_style_channel_) {
    window_style_channel_->SetMethodCallHandler(nullptr);
    window_style_channel_.reset();
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

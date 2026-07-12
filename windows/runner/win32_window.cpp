#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include <algorithm>
#include <cstdint>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr DWORD kDwmWindowCornerPreference = 33;
constexpr DWORD kDwmBorderColor = 34;
constexpr DWORD kDwmCaptionColor = 35;
constexpr DWORD kDwmTextColor = 36;
constexpr DWORD kDwmSystemBackdropType = 38;
constexpr DWORD kDwmMicaEffect = 1029;
constexpr DWORD kDwmColorDefault = 0xFFFFFFFF;
constexpr DWORD kDwmUseImmersiveDarkModeLegacy = 19;

constexpr int kDwmCornerDefault = 0;
constexpr int kDwmCornerDoNotRound = 1;
constexpr int kDwmCornerRound = 2;
constexpr int kDwmCornerRoundSmall = 3;

constexpr int kDwmBackdropNone = 1;
constexpr int kDwmBackdropMainWindow = 2;

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);
using RtlGetVersion = LONG(WINAPI*)(OSVERSIONINFOW* version_info);
using SetWindowCompositionAttribute = BOOL(WINAPI*)(HWND window,
                                                    void* attribute_data);

enum class AccentState {
  kDisabled = 0,
  kEnableGradient = 1,
};

struct AccentPolicy {
  AccentState state;
  DWORD flags;
  DWORD color;
  DWORD animation_id;
};

struct WindowCompositionAttributeData {
  int attribute;
  void* data;
  SIZE_T data_size;
};

constexpr int kWindowCompositionAccentPolicy = 19;

struct WindowsVersion {
  DWORD major = 0;
  DWORD build = 0;
};

WindowsVersion GetWindowsVersion() {
  const HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
  if (ntdll == nullptr) {
    return {};
  }

  const auto rtl_get_version = reinterpret_cast<RtlGetVersion>(
      GetProcAddress(ntdll, "RtlGetVersion"));
  if (rtl_get_version == nullptr) {
    return {};
  }

  OSVERSIONINFOW version_info{};
  version_info.dwOSVersionInfoSize = sizeof(version_info);
  if (rtl_get_version(&version_info) != 0) {
    return {};
  }
  return {version_info.dwMajorVersion, version_info.dwBuildNumber};
}

Win32Window::VisualStyle DetectHostVisualStyle() {
  const WindowsVersion version = GetWindowsVersion();
  if (version.major >= 10 && version.build >= 22000) {
    return Win32Window::VisualStyle::kWindows11;
  }
  // The supported native host starts at Windows 10 1809 (build 17763).
  // Windows 7 is an appearance option only and is never host-selected.
  return Win32Window::VisualStyle::kWindows10;
}

bool IsHighContrastEnabled() {
  HIGHCONTRASTW high_contrast{};
  high_contrast.cbSize = sizeof(high_contrast);
  if (!SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(high_contrast),
                             &high_contrast, 0)) {
    return false;
  }
  return (high_contrast.dwFlags & HCF_HIGHCONTRASTON) != 0;
}

bool IsSystemDarkMode() {
  DWORD light_mode = 1;
  DWORD light_mode_size = sizeof(light_mode);
  const LSTATUS result = RegGetValueW(
      HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
      kGetPreferredBrightnessRegValue, RRF_RT_REG_DWORD, nullptr, &light_mode,
      &light_mode_size);
  return result == ERROR_SUCCESS && light_mode == 0;
}

COLORREF GetSystemAccentColor() {
  DWORD colorization_color = 0;
  BOOL opaque_blend = FALSE;
  if (SUCCEEDED(
          DwmGetColorizationColor(&colorization_color, &opaque_blend))) {
    const BYTE red = static_cast<BYTE>((colorization_color >> 16) & 0xFF);
    const BYTE green = static_cast<BYTE>((colorization_color >> 8) & 0xFF);
    const BYTE blue = static_cast<BYTE>(colorization_color & 0xFF);
    return RGB(red, green, blue);
  }
  return RGB(0, 113, 197);
}

COLORREF BlendColor(COLORREF foreground, COLORREF background, BYTE amount) {
  const auto blend_channel = [amount](BYTE foreground_channel,
                                      BYTE background_channel) {
    const int weighted_foreground = foreground_channel * (255 - amount);
    const int weighted_background = background_channel * amount;
    return static_cast<BYTE>(
        (weighted_foreground + weighted_background) / 255);
  };
  return RGB(blend_channel(GetRValue(foreground), GetRValue(background)),
             blend_channel(GetGValue(foreground), GetGValue(background)),
             blend_channel(GetBValue(foreground), GetBValue(background)));
}

COLORREF ContrastingTextColor(COLORREF background) {
  const int luminance = 299 * GetRValue(background) +
                        587 * GetGValue(background) +
                        114 * GetBValue(background);
  return luminance >= 150000 ? RGB(0, 0, 0) : RGB(255, 255, 255);
}

DWORD AccentGradientColor(COLORREF color) {
  return 0xFF000000 | (static_cast<DWORD>(GetBValue(color)) << 16) |
         (static_cast<DWORD>(GetGValue(color)) << 8) |
         static_cast<DWORD>(GetRValue(color));
}

bool SetCompositionAccent(HWND window, bool enabled, COLORREF color) {
  const HMODULE user32_module = GetModuleHandleW(L"user32.dll");
  if (user32_module == nullptr) {
    return false;
  }
  const auto set_window_composition_attribute =
      reinterpret_cast<SetWindowCompositionAttribute>(
          GetProcAddress(user32_module, "SetWindowCompositionAttribute"));
  if (set_window_composition_attribute == nullptr) {
    return false;
  }

  AccentPolicy policy{};
  policy.state = enabled ? AccentState::kEnableGradient
                         : AccentState::kDisabled;
  policy.color = AccentGradientColor(color);
  WindowCompositionAttributeData data{};
  data.attribute = kWindowCompositionAccentPolicy;
  data.data = &policy;
  data.data_size = sizeof(policy);
  return set_window_composition_attribute(window, &data) != FALSE;
}

template <typename T>
bool SetDwmAttribute(HWND window, DWORD attribute, const T& value) {
  const HRESULT result =
      DwmSetWindowAttribute(window, attribute, &value, sizeof(value));
  return SUCCEEDED(result);
}

bool SetBlurBehind(HWND window, bool enabled) {
  BOOL composition_enabled = FALSE;
  if (FAILED(DwmIsCompositionEnabled(&composition_enabled)) ||
      !composition_enabled) {
    return false;
  }

  DWM_BLURBEHIND blur_behind{};
  blur_behind.dwFlags = DWM_BB_ENABLE;
  blur_behind.fEnable = enabled ? TRUE : FALSE;
  return SUCCEEDED(DwmEnableBlurBehindWindow(window, &blur_behind));
}

bool SetSolidCaption(HWND window,
                     const WindowsVersion& version,
                     COLORREF caption_color,
                     COLORREF border_color) {
  const COLORREF text_color = ContrastingTextColor(caption_color);
  bool caption_applied = false;
  if (version.major >= 10 && version.build >= 22000) {
    const bool caption_result =
        SetDwmAttribute(window, kDwmCaptionColor, caption_color);
    const bool text_result =
        SetDwmAttribute(window, kDwmTextColor, text_color);
    const bool border_result =
        SetDwmAttribute(window, kDwmBorderColor, border_color);
    caption_applied = caption_result && text_result && border_result;
  }
  if (!caption_applied) {
    caption_applied = SetCompositionAccent(window, true, caption_color);
  }
  return caption_applied;
}

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

bool GetWorkAreaForRect(const RECT& bounds, RECT* work_area) {
  const HMONITOR monitor =
      MonitorFromRect(&bounds, MONITOR_DEFAULTTONEAREST);
  if (monitor == nullptr) {
    return false;
  }

  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfoW(monitor, &monitor_info)) {
    return false;
  }

  *work_area = monitor_info.rcWork;
  return true;
}

RECT ConstrainWindowBoundsToWorkArea(const RECT& bounds) {
  RECT work_area{};
  if (!GetWorkAreaForRect(bounds, &work_area)) {
    return bounds;
  }

  const LONG work_width = work_area.right - work_area.left;
  const LONG work_height = work_area.bottom - work_area.top;
  if (work_width <= 0 || work_height <= 0) {
    return bounds;
  }

  const LONG requested_width =
      std::max<LONG>(0, bounds.right - bounds.left);
  const LONG requested_height =
      std::max<LONG>(0, bounds.bottom - bounds.top);
  const LONG width = std::min(requested_width, work_width);
  const LONG height = std::min(requested_height, work_height);
  const LONG left = std::clamp(bounds.left, work_area.left,
                               work_area.right - width);
  const LONG top = std::clamp(bounds.top, work_area.top,
                              work_area.bottom - height);
  return {left, top, left + width, top + height};
}

void ConstrainWindowPositionToWorkArea(HWND window, WINDOWPOS* window_pos) {
  if (window_pos == nullptr ||
      (window_pos->flags & (SWP_NOMOVE | SWP_NOSIZE)) ==
          (SWP_NOMOVE | SWP_NOSIZE)) {
    return;
  }

  RECT current_bounds{};
  if (!GetWindowRect(window, &current_bounds)) {
    return;
  }

  const bool can_move = (window_pos->flags & SWP_NOMOVE) == 0;
  const bool can_resize = (window_pos->flags & SWP_NOSIZE) == 0;
  const LONG width = can_resize
                         ? std::max<LONG>(0, window_pos->cx)
                         : current_bounds.right - current_bounds.left;
  const LONG height = can_resize
                          ? std::max<LONG>(0, window_pos->cy)
                          : current_bounds.bottom - current_bounds.top;
  RECT requested_bounds = {
      can_move ? window_pos->x : current_bounds.left,
      can_move ? window_pos->y : current_bounds.top,
      0,
      0,
  };
  requested_bounds.right = requested_bounds.left + width;
  requested_bounds.bottom = requested_bounds.top + height;

  const RECT constrained_bounds =
      ConstrainWindowBoundsToWorkArea(requested_bounds);
  if (can_move) {
    window_pos->x = constrained_bounds.left;
    window_pos->y = constrained_bounds.top;
  }

  if (can_resize) {
    if (can_move) {
      window_pos->cx = constrained_bounds.right - constrained_bounds.left;
      window_pos->cy = constrained_bounds.bottom - constrained_bounds.top;
      return;
    }

    // A right or bottom edge resize keeps the top-left corner fixed, so
    // reduce the requested size instead of changing a position the OS ignores.
    RECT work_area{};
    if (GetWorkAreaForRect(requested_bounds, &work_area)) {
      window_pos->cx = std::min(
          width, std::max<LONG>(0, work_area.right - current_bounds.left));
      window_pos->cy = std::min(
          height, std::max<LONG>(0, work_area.bottom - current_bounds.top));
    }
  }
}

void SetWorkAreaMaxTrackSize(HWND window, MINMAXINFO* min_max_info) {
  if (min_max_info == nullptr) {
    return;
  }

  const HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  if (monitor == nullptr) {
    return;
  }

  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfoW(monitor, &monitor_info)) {
    return;
  }

  const RECT& monitor_bounds = monitor_info.rcMonitor;
  const RECT& work_area = monitor_info.rcWork;
  const LONG work_width = work_area.right - work_area.left;
  const LONG work_height = work_area.bottom - work_area.top;
  if (work_width <= 0 || work_height <= 0) {
    return;
  }

  min_max_info->ptMaxPosition.x = work_area.left - monitor_bounds.left;
  min_max_info->ptMaxPosition.y = work_area.top - monitor_bounds.top;
  min_max_info->ptMaxSize.x = work_width;
  min_max_info->ptMaxSize.y = work_height;
  min_max_info->ptMaxTrackSize.x = work_width;
  min_max_info->ptMaxTrackSize.y = work_height;
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;
  RECT requested_bounds = {
      Scale(origin.x, scale_factor),
      Scale(origin.y, scale_factor),
      0,
      0,
  };
  requested_bounds.right =
      requested_bounds.left + Scale(size.width, scale_factor);
  requested_bounds.bottom =
      requested_bounds.top + Scale(size.height, scale_factor);
  const RECT initial_bounds =
      ConstrainWindowBoundsToWorkArea(requested_bounds);

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      initial_bounds.left, initial_bounds.top,
      initial_bounds.right - initial_bounds.left,
      initial_bounds.bottom - initial_bounds.top,
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  dark_mode_ = IsSystemDarkMode();
  accent_color_ = GetSystemAccentColor();
  visual_style_ = DetectHostVisualStyle();
  ApplyWindowStyle(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      if (newRectSize == nullptr) {
        break;
      }
      const RECT constrained_bounds =
          ConstrainWindowBoundsToWorkArea(*newRectSize);
      LONG newWidth = constrained_bounds.right - constrained_bounds.left;
      LONG newHeight = constrained_bounds.bottom - constrained_bounds.top;

      SetWindowPos(hwnd, nullptr, constrained_bounds.left,
                   constrained_bounds.top, newWidth, newHeight,
                   SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_GETMINMAXINFO:
      SetWorkAreaMaxTrackSize(hwnd,
                              reinterpret_cast<MINMAXINFO*>(lparam));
      return 0;

    case WM_WINDOWPOSCHANGING:
      ConstrainWindowPositionToWorkArea(hwnd,
                                        reinterpret_cast<WINDOWPOS*>(lparam));
      return 0;

    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      ApplyWindowStyle(hwnd);
      return 0;

    case WM_DWMCOMPOSITIONCHANGED:
    case WM_SETTINGCHANGE:
    case WM_THEMECHANGED:
      ApplyWindowStyle(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

void Win32Window::SetWindowStyle(VisualStyle style,
                                 bool dark_mode,
                                 COLORREF accent_color,
                                 COLORREF surface_color) {
  visual_style_ = style;
  dark_mode_ = dark_mode;
  accent_color_ = accent_color;
  surface_color_ = surface_color;
  if (window_handle_ != nullptr) {
    ApplyWindowStyle(window_handle_);
  }
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::ApplyWindowStyle(HWND const window) {
  const bool high_contrast = IsHighContrastEnabled();
  const WindowsVersion version = GetWindowsVersion();
  const bool supports_modern_frame =
      version.major >= 10 && version.build >= 22000;
  const BOOL enable_dark_mode = dark_mode_ && !high_contrast ? TRUE : FALSE;
  if (!SetDwmAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                       enable_dark_mode)) {
    SetDwmAttribute(window, kDwmUseImmersiveDarkModeLegacy, enable_dark_mode);
  }

  const int no_backdrop = kDwmBackdropNone;
  const BOOL disable_mica = FALSE;
  if (supports_modern_frame) {
    SetDwmAttribute(window, kDwmSystemBackdropType, no_backdrop);
    SetDwmAttribute(window, kDwmMicaEffect, disable_mica);
  }
  SetBlurBehind(window, false);
  SetCompositionAccent(window, false, accent_color_);

  if (high_contrast) {
    const int default_corner = kDwmCornerDefault;
    if (supports_modern_frame) {
      SetDwmAttribute(window, kDwmWindowCornerPreference, default_corner);
      SetDwmAttribute(window, kDwmBorderColor, kDwmColorDefault);
      SetDwmAttribute(window, kDwmCaptionColor, kDwmColorDefault);
      SetDwmAttribute(window, kDwmTextColor, kDwmColorDefault);
    }
  } else if (visual_style_ == VisualStyle::kWindows11) {
    const int rounded_corner = kDwmCornerRound;
    const int main_window_backdrop = kDwmBackdropMainWindow;
    const BOOL enable_mica = TRUE;
    bool backdrop_applied = false;
    if (supports_modern_frame) {
      SetDwmAttribute(window, kDwmWindowCornerPreference, rounded_corner);
      if (version.build >= 22621) {
        backdrop_applied = SetDwmAttribute(
            window, kDwmSystemBackdropType, main_window_backdrop);
      }
      if (!backdrop_applied) {
        backdrop_applied =
            SetDwmAttribute(window, kDwmMicaEffect, enable_mica);
      }
    }
    if (backdrop_applied) {
      SetDwmAttribute(window, kDwmBorderColor, kDwmColorDefault);
      SetDwmAttribute(window, kDwmCaptionColor, kDwmColorDefault);
      SetDwmAttribute(window, kDwmTextColor, kDwmColorDefault);
    } else {
      SetSolidCaption(window, version, surface_color_, surface_color_);
    }
  } else if (visual_style_ == VisualStyle::kWindows10) {
    const int square_corner = kDwmCornerDoNotRound;
    if (supports_modern_frame) {
      SetDwmAttribute(window, kDwmWindowCornerPreference, square_corner);
    }
    SetSolidCaption(window, version, accent_color_, accent_color_);
  } else {
    const int small_corner = kDwmCornerRoundSmall;
    if (supports_modern_frame) {
      SetDwmAttribute(window, kDwmWindowCornerPreference, small_corner);
    }
    const bool blur_applied = SetBlurBehind(window, true);
    const COLORREF aero_caption = blur_applied
                                      ? BlendColor(accent_color_,
                                                   surface_color_, 176)
                                      : surface_color_;
    SetSolidCaption(window, version, aero_caption, accent_color_);
  }

  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOACTIVATE);
  RedrawWindow(window, nullptr, nullptr,
               RDW_INVALIDATE | RDW_FRAME | RDW_UPDATENOW);
}

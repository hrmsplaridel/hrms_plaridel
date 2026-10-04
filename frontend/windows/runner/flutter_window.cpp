#include "flutter_window.h"

#include <optional>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT_PTR kActivationTimer = 0x48524D53;
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             HANDLE activation_event, bool start_hidden)
    : project_(project), activation_event_(activation_event),
      start_hidden_(start_hidden) {}

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter::MethodChannel<flutter::EncodableValue> lifecycle_channel(
      flutter_controller_->engine()->messenger(), "hrms/desktop_lifecycle",
      &flutter::StandardMethodCodec::GetInstance());
  lifecycle_channel.SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "ready") {
          desktop_ready_ = true;
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  if (!SetTimer(GetHandle(), kActivationTimer, 200, nullptr)) return false;

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  KillTimer(GetHandle(), kActivationTimer);
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Wait for Dart's tray setup and initial hide before honoring a relaunch.
  if (message == WM_TIMER && wparam == kActivationTimer) {
    if (desktop_ready_ &&
        WaitForSingleObject(activation_event_, 0) == WAIT_OBJECT_0) {
      start_hidden_ = false;
      ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
      SetForegroundWindow(hwnd);
      SetFocus(flutter_controller_->view()->GetNativeWindow());
    }
    return 0;
  }
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

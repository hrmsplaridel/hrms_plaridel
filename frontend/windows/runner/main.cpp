#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

namespace {
// Session-local objects keep separate Windows logins independent.
class DesktopInstance {
 public:
  DesktopInstance() {
    mutex_ = CreateMutexW(nullptr, FALSE, L"Local\\PlaridelHRMS.Instance");
    activation_ = CreateEventW(nullptr, FALSE, FALSE,
                               L"Local\\PlaridelHRMS.Activate");
    if (mutex_ && activation_) {
      const DWORD result = WaitForSingleObject(mutex_, 0);
      owns_instance_ = result == WAIT_OBJECT_0 || result == WAIT_ABANDONED;
      valid_ = owns_instance_ || result == WAIT_TIMEOUT;
    }
  }

  ~DesktopInstance() {
    if (owns_instance_) ReleaseMutex(mutex_);
    if (activation_) CloseHandle(activation_);
    if (mutex_) CloseHandle(mutex_);
  }

  bool valid() const { return valid_; }
  bool owns_instance() const { return owns_instance_; }
  HANDLE activation() const { return activation_; }

 private:
  HANDLE mutex_ = nullptr;
  HANDLE activation_ = nullptr;
  bool owns_instance_ = false;
  bool valid_ = false;
};
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  const bool start_hidden =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--hidden") != command_line_arguments.end();
  DesktopInstance desktop_instance;
  if (!desktop_instance.valid()) {
    MessageBoxW(nullptr, L"HRMS could not initialize its desktop instance.",
                L"HRMS", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }
  if (!desktop_instance.owns_instance()) {
    if (!start_hidden) {
      AllowSetForegroundWindow(ASFW_ANY);
      SetEvent(desktop_instance.activation());
    }
    return EXIT_SUCCESS;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, desktop_instance.activation(), start_hidden);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"HRMS", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

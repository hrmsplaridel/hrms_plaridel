# Windows installer

From the repository root, download the official Microsoft Visual C++ x64
Redistributable on the build PC (repeat to refresh it before releases):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File frontend/windows/installer/download-prerequisites.ps1
```

The script verifies Microsoft's Authenticode signature before saving the package.
The downloaded binary and installer output are excluded from Git.

Build the Flutter application from `frontend`, supplying the backend address
reachable by the client (for example, the server's Tailscale address):

```powershell
flutter pub get
flutter build windows --release --dart-define=API_BASE_URL=http://YOUR_SERVER_TAILSCALE_IP:3000
```

Open `hrms_plaridel.iss` in Inno Setup 6 and compile. The output is
`output/HRMS-Plaridel-Setup-1.0.0.exe` (the version comes from `MyAppVersion`).
If the release build is already current, only download the prerequisite and
recompile the installer.

The runtime is bundled, so clients need no internet connection to install it.
Setup checks both registry views for the x64 runtime and skips installation if
the installed version is at least the bundled version. Otherwise it runs the
Microsoft installer with progress displayed and requests administrator approval.
This is required even for a per-user HRMS install because the runtime is machine-wide.
Cancellation or failure blocks HRMS installation with an error that can be retried.
A required runtime restart is surfaced at the end, and HRMS launch is suppressed
until after the restart. Uninstalling HRMS leaves the shared runtime installed.

Before distribution, test on Windows without the x64 runtime, with an older
runtime, and with the same or a newer runtime. Also check cancellation of the
administrator prompt and a runtime install that requests a restart. Verify that
HRMS opens and connects to the intended backend after installation.

Microsoft runtime documentation: https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist

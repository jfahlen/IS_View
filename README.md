# IS_View — iPhone client for IS_server
SwiftUI, iOS. Sends GPS to the Mac over Tailscale, shows the RGB window, the spectrum at your
location (blue) and at wherever you tap/drag (red).

Open `IS_View.xcodeproj` in Xcode, pick your signing Team and your iPhone, and Run.
In the app's gear menu set the server URL (`http://<mac tailscale ip>:8765`).
To test without moving: Debug > Simulate Location in Xcode (e.g. lat 34.16, lon −118.13 for the AV5 test scene).

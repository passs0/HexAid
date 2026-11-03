import Cocoa
import SwiftUI
import UniformTypeIdentifiers

struct ComponentStatus {
    var crossoverExists: Bool = false
    var versionString: String = "Not found"
    var hasGStreamer: Bool = false
    var gstreamerVersion: String = "Stock (Limited)"
    var hasRpath: Bool = false
    var hasD3DMetal: Bool = false
    var d3dMetalVersion: String = "Missing"
    var hasDXMT: Bool = false
    var bottleCount: Int = 0

    var isReady: Bool {
        crossoverExists && hasGStreamer && hasRpath && hasD3DMetal && hasDXMT
    }
}

@MainActor
final class HexAidViewModel: ObservableObject {
    @Published var status = ComponentStatus()
    @Published var isBusy = false
    @Published var updateGStreamer = true
    @Published var updateDXMT = true
    @Published var updateDXVK = true
    @Published var enableAVXAndMSync = true
    @Published var logs: [String] = []

    let cxAppPath = "/Applications/CrossOver.app"
    let bottlesPath = ("~/Library/Application Support/CrossOver/Bottles" as NSString).expandingTildeInPath

    init() {}

    func appendLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)")
    }

    func refreshStatus() {
        let cxPath = cxAppPath
        let btlPath = bottlesPath
        Task.detached {
            let next = Self.inspectStatus(cxAppPath: cxPath, bottlesPath: btlPath)
            await MainActor.run {
                self.status = next
            }
        }
    }

    nonisolated static func inspectStatus(cxAppPath: String, bottlesPath: String) -> ComponentStatus {
        let fm = FileManager.default
        var next = ComponentStatus()
        next.crossoverExists = fm.fileExists(atPath: cxAppPath)

        if let items = try? fm.contentsOfDirectory(atPath: bottlesPath) {
            next.bottleCount = items.filter { item in
                fm.fileExists(atPath: "\(bottlesPath)/\(item)/cxbottle.conf")
            }.count
        }

        if next.crossoverExists {
            let plistPath = "\(cxAppPath)/Contents/Info.plist"
            if let dict = NSDictionary(contentsOfFile: plistPath) {
                let shortVer = dict["CFBundleShortVersionString"] as? String ?? "?"
                let buildVer = dict["CFBundleVersion"] as? String ?? "?"
                next.versionString = "\(shortVer) (\(buildVer))"
            }

            let libavPath = "\(cxAppPath)/Contents/SharedSupport/CrossOver/lib64/gstreamer-1.0/libgstlibav.dylib"
            next.hasGStreamer = fm.fileExists(atPath: libavPath)
            if next.hasGStreamer {
                let gstPlist = "\(cxAppPath)/Contents/SharedSupport/CrossOver/lib64/GStreamer.framework/Versions/Current/Resources/Info.plist"
                if let gstDict = NSDictionary(contentsOfFile: gstPlist),
                   let gstVer = gstDict["CFBundleShortVersionString"] as? String {
                    next.gstreamerVersion = "v\(gstVer) (Full + FFmpeg)"
                } else {
                    next.gstreamerVersion = "Full (GStreamer.framework)"
                }
            }

            let d3dMetalBin = "\(cxAppPath)/Contents/SharedSupport/CrossOver/lib64/apple_gptk/external/D3DMetal.framework/D3DMetal"
            next.hasD3DMetal = fm.fileExists(atPath: d3dMetalBin)
            if next.hasD3DMetal {
                let d3dPlist = "\(cxAppPath)/Contents/SharedSupport/CrossOver/lib64/apple_gptk/external/D3DMetal.framework/Resources/Info.plist"
                if let d3dDict = NSDictionary(contentsOfFile: d3dPlist),
                   let ver = d3dDict["CFBundleShortVersionString"] as? String {
                    next.d3dMetalVersion = "v\(ver)"
                } else {
                    next.d3dMetalVersion = "Installed"
                }
            }

            let dxmtPath = "\(cxAppPath)/Contents/SharedSupport/CrossOver/lib/dxmt/x86_64-windows/d3d11.dll"
            next.hasDXMT = fm.fileExists(atPath: dxmtPath)

            let wineGstPath = "\(cxAppPath)/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/winegstreamer.so"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: wineGstPath)),
               let needle = "GStreamer.framework/Versions/Current/lib".data(using: .utf8) {
                next.hasRpath = data.range(of: needle) != nil
            }
        }

        return next
    }

    func runPatch() {
        guard !isBusy else { return }
        isBusy = true
        logs.removeAll()
        appendLog("Starting HexAid patch on \(cxAppPath)...")

        let doGst = updateGStreamer
        let doDxmt = updateDXMT
        let doDxvk = updateDXVK
        let doPerf = enableAVXAndMSync
        let cxPath = cxAppPath
        let btlPath = bottlesPath

        Task.detached {
            let script = """
            set -e
            setopt NULL_GLOB
            CX_APP="\(cxPath)"
            LIB64="$CX_APP/Contents/SharedSupport/CrossOver/lib64"
            WINE_UNIX="$CX_APP/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix"
            DXMT_DIR="$CX_APP/Contents/SharedSupport/CrossOver/lib/dxmt"
            DXVK_DIR="$CX_APP/Contents/SharedSupport/CrossOver/lib/dxvk"
            BOTTLES_DIR="\(btlPath)"

            if pgrep -x "CrossOver" >/dev/null 2>&1 || pgrep -x "wineloader" >/dev/null 2>&1 || pgrep -x "wineserver" >/dev/null 2>&1; then
                echo "Closing running CrossOver / Wine processes..."
                killall CrossOver wineloader wineserver 2>/dev/null || true
                sleep 1
            fi

            if [ "\(doGst ? "1" : "0")" = "1" ]; then
                echo "Resolving latest GStreamer build from Sikarugir-App/gstreamer..."
                GST_TAG=$(curl -fsSL "https://api.github.com/repos/Sikarugir-App/gstreamer/releases/latest" 2>/dev/null | grep -m1 '"tag_name":' | sed -E 's/.*"([^"]+)".*/\\1/' || true)
                if [ -z "$GST_TAG" ]; then
                    GST_TAG="1.28.1"
                fi
                GST_URL="https://github.com/Sikarugir-App/gstreamer/releases/download/${GST_TAG}/gstreamer-1.0-${GST_TAG}-x86_64.tar.xz"
                echo "Downloading & extracting GStreamer ${GST_TAG} (with FFmpeg/libav)..."
                rm -rf "$LIB64/GStreamer.framework"
                curl -fL "$GST_URL" | tar -xJ -C "$LIB64/"

                echo "Cleaning conflicting stock GStreamer/GLib libraries & linking plugins..."
                cd "$LIB64"
                rm -f libgst*.dylib libglib-2.0*.dylib libgobject-2.0*.dylib libgio-2.0*.dylib libgmodule-2.0*.dylib libgthread-2.0*.dylib libpcre2*.dylib libintl*.dylib libffi*.dylib
                rm -rf gstreamer-1.0
                ln -s "GStreamer.framework/Versions/Current/lib/gstreamer-1.0" gstreamer-1.0

                echo "Linking winegstreamer.so to GStreamer.framework..."
                if ! otool -l "$WINE_UNIX/winegstreamer.so" | grep -q "GStreamer.framework/Versions/Current/lib"; then
                    install_name_tool -add_rpath "@loader_path/../../../lib64/GStreamer.framework/Versions/Current/lib" "$WINE_UNIX/winegstreamer.so"
                else
                    echo "winegstreamer.so rpath already configured."
                fi
            fi

            if [ "\(doDxmt ? "1" : "0")" = "1" ]; then
                echo "Resolving latest DXMT release from 3Shain/dxmt..."
                DXMT_URL=$(curl -fsSL "https://api.github.com/repos/3Shain/dxmt/releases/latest" 2>/dev/null | grep -oE 'https://github.com/3Shain/dxmt/releases/download/[^"]+builtin\\.tar\\.gz' | head -n1 || true)
                if [ -z "$DXMT_URL" ]; then
                    DXMT_URL="https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz"
                fi
                echo "Downloading & extracting DXMT ($DXMT_URL)..."
                mkdir -p "$DXMT_DIR"
                curl -fL "$DXMT_URL" | tar -xz -C "$DXMT_DIR/"
            fi

            if [ "\(doDxvk ? "1" : "0")" = "1" ]; then
                echo "Checking latest macOS DXVK release from Gcenx/DXVK-macOS..."
                DXVK_URL=$(curl -fsSL "https://api.github.com/repos/Gcenx/DXVK-macOS/releases/latest" 2>/dev/null | grep -oE 'https://github.com/Gcenx/DXVK-macOS/releases/download/[^"]+\\.tar\\.gz' | head -n1 || true)
                if [ -n "$DXVK_URL" ]; then
                    echo "Downloading & updating DXVK ($DXVK_URL)..."
                    TMP_DXVK=$(mktemp -d /tmp/hexaid_dxvk.XXXXXX)
                    if curl -fL "$DXVK_URL" | tar -xz -C "$TMP_DXVK" 2>/dev/null; then
                        mkdir -p "$DXVK_DIR/x86_64-windows" "$DXVK_DIR/i386-windows"
                        find "$TMP_DXVK" -path "*/x64/*.dll" -exec cp -f {} "$DXVK_DIR/x86_64-windows/" \\; 2>/dev/null || true
                        find "$TMP_DXVK" -path "*/x32/*.dll" -exec cp -f {} "$DXVK_DIR/i386-windows/" \\; 2>/dev/null || true
                        echo "DXVK updated."
                    fi
                    rm -rf "$TMP_DXVK"
                fi
            fi

            if [ "\(doPerf ? "1" : "0")" = "1" ] && [ -d "$BOTTLES_DIR" ]; then
                echo "Ensuring WINEMSYNC=1 and ROSETTA_ADVERTISE_AVX=1 on existing bottles..."
                for CONF in "$BOTTLES_DIR"/*/cxbottle.conf; do
                    [ -f "$CONF" ] || continue
                    if ! grep -q '"WINEMSYNC"' "$CONF"; then
                        printf '\\n"WINEMSYNC" = "1"\\n' >> "$CONF"
                    fi
                    if ! grep -q '"ROSETTA_ADVERTISE_AVX"' "$CONF"; then
                        printf '"ROSETTA_ADVERTISE_AVX" = "1"\\n' >> "$CONF"
                    fi
                done
            fi

            echo "Clearing quarantine, re-signing CrossOver.app & resetting caches..."
            xattr -cr "$CX_APP"
            codesign --force --deep --sign - "$CX_APP"
            rm -f "$HOME/Library/Application Support/CrossOver/gstreamer-1.0-registry.x86_64.bin"

            echo "✅ HexAid patch complete! All existing and new bottles are now upgraded."
            """

            await self.executeShellScript(script)
        }
    }

    func importD3DMetalFromFolderOrVolume() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Select Mounted Apple GPTK Volume or redist Folder"
        panel.message = "Choose a mounted Apple Game Porting Toolkit (Evaluation Environment) volume or folder containing D3DMetal.framework"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        let selectedPath = selectedURL.path
        let cxPath = cxAppPath

        isBusy = true
        logs.removeAll()
        appendLog("Searching for D3DMetal.framework in \(selectedPath)...")

        Task.detached {
            let script = """
            set -e
            SRC_ROOT="\(selectedPath)"
            CX_APP="\(cxPath)"
            GPTK_DEST="$CX_APP/Contents/SharedSupport/CrossOver/lib64/apple_gptk/external"

            D3DM_FW=$(find "$SRC_ROOT" -maxdepth 5 -name "D3DMetal.framework" -type d | head -n1 || true)
            if [ -z "$D3DM_FW" ]; then
                echo "❌ Could not find D3DMetal.framework inside $SRC_ROOT"
                exit 1
            fi
            SRC_EXT=$(dirname "$D3DM_FW")
            echo "Found D3DMetal at: $D3DM_FW"
            mkdir -p "$GPTK_DEST"
            rm -rf "$GPTK_DEST/D3DMetal.framework"
            cp -a "$D3DM_FW" "$GPTK_DEST/"
            if [ -f "$SRC_EXT/libd3dshared.dylib" ]; then
                cp -a "$SRC_EXT/libd3dshared.dylib" "$GPTK_DEST/"
            fi
            echo "Re-signing CrossOver.app..."
            xattr -cr "$CX_APP"
            codesign --force --deep --sign - "$CX_APP"
            echo "✅ D3DMetal.framework updated successfully!"
            """
            await self.executeShellScript(script)
        }
    }

    func clearShaderCaches() {
        guard !isBusy else { return }
        isBusy = true
        logs.removeAll()
        appendLog("Clearing D3DMetal, DXMT & GStreamer caches...")

        Task.detached {
            let script = """
            rm -f "$HOME/Library/Application Support/CrossOver/gstreamer-1.0-registry.x86_64.bin"
            find /var/folders -name "*d3dm*" -exec rm -rf {} + 2>/dev/null || true
            echo "✅ Cleared GStreamer plugin registry & D3DMetal shader caches."
            """
            await self.executeShellScript(script)
        }
    }

    func executeShellScript(_ script: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            Task { @MainActor in
                for line in lines {
                    self.appendLog(line)
                }
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
            handle.readabilityHandler = nil
            let code = process.terminationStatus
            await MainActor.run {
                self.isBusy = false
                self.refreshStatus()
                if code != 0 {
                    self.appendLog("❌ Error: Process exited with status \(code)")
                }
            }
        } catch {
            handle.readabilityHandler = nil
            await MainActor.run {
                self.isBusy = false
                self.appendLog("❌ Error: \(error.localizedDescription)")
            }
        }
    }
}

struct StatusRow: View {
    let title: String
    let subtitle: String
    let badgeText: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(ok ? .green : .orange)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(badgeText)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background((ok ? Color.green : Color.orange).opacity(0.15))
                .foregroundColor(ok ? .green : .orange)
                .cornerRadius(6)
        }
        .padding(.vertical, 3)
    }
}

struct ContentView: View {
    @StateObject private var vm = HexAidViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("HexAid")
                            .font(.system(size: 20, weight: .bold))
                        Text("CrossOver Patcher")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(5)
                    }
                    Text("/Applications/CrossOver.app • v\(vm.status.versionString) • \(vm.status.bottleCount) Bottle(s) Protected")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    vm.refreshStatus()
                }
                .disabled(vm.isBusy)
            }

            Divider()

            VStack(spacing: 4) {
                StatusRow(
                    title: "GStreamer + FFmpeg (libgstlibav.dylib)",
                    subtitle: "Fixes WMV / Media Foundation cutscenes (Resident Evil, Silent Hill, UE4/5)",
                    badgeText: vm.status.gstreamerVersion,
                    ok: vm.status.hasGStreamer
                )
                StatusRow(
                    title: "winegstreamer.so Library Link (LC_RPATH)",
                    subtitle: "In-place Mach-O rpath wiring to GStreamer.framework",
                    badgeText: vm.status.hasRpath ? "Linked" : "Unpatched",
                    ok: vm.status.hasRpath
                )
                StatusRow(
                    title: "Apple D3DMetal (Game Porting Toolkit)",
                    subtitle: "DirectX 12 to Metal translation layer in lib64/apple_gptk",
                    badgeText: vm.status.d3dMetalVersion,
                    ok: vm.status.hasD3DMetal
                )
                StatusRow(
                    title: "DXMT (DirectX 10/11 to Metal)",
                    subtitle: "High-performance Metal backend for DirectX 11 games in lib/dxmt",
                    badgeText: vm.status.hasDXMT ? "Installed" : "Missing",
                    ok: vm.status.hasDXMT
                )
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 6) {
                Text("Patch Options (Applies to All Existing & Future Bottles):")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.secondary)
                HStack(spacing: 16) {
                    Toggle("Full GStreamer + FFmpeg", isOn: $vm.updateGStreamer)
                    Toggle("Latest DXMT", isOn: $vm.updateDXMT)
                    Toggle("Latest DXVK", isOn: $vm.updateDXVK)
                    Toggle("Enable MSync + AVX", isOn: $vm.enableAVXAndMSync)
                }
                .font(.system(size: 12))
                .disabled(vm.isBusy)
            }

            HStack(spacing: 10) {
                Button(action: { vm.runPatch() }) {
                    HStack {
                        if vm.isBusy {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                        } else {
                            Image(systemName: "bandage.fill")
                        }
                        Text(vm.isBusy ? "Patching CrossOver..." : (vm.status.isReady ? "Re-Apply Patch to CrossOver.app" : "Patch CrossOver.app Now"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .disabled(vm.isBusy || !vm.status.crossoverExists)

                Button("Import GPTK D3DMetal...") {
                    vm.importD3DMetalFromFolderOrVolume()
                }
                .help("Upgrade D3DMetal.framework from a mounted Apple Game Porting Toolkit .dmg")
                .disabled(vm.isBusy || !vm.status.crossoverExists)

                Button("Clear Caches") {
                    vm.clearShaderCaches()
                }
                .help("Reset GStreamer registry & D3DMetal shader caches")
                .disabled(vm.isBusy)
            }

            if !vm.logs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activity Log:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(vm.logs.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 120)
                    .background(Color.black.opacity(0.85))
                    .foregroundColor(.green)
                    .cornerRadius(6)
                }
            }
        }
        .padding(18)
        .frame(width: 580)
        .onAppear {
            vm.refreshStatus()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 470),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "HexAid — CrossOver Patcher"
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

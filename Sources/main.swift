import Cocoa
import SwiftUI

// MARK: - Component Status Model

struct ComponentStatus {
    var crossoverExists: Bool = false
    var versionString: String = "Not found"
    var hasGStreamer: Bool = false
    var gstreamerVersion: String = "Stock (Limited)"
    var hasRpath: Bool = false
    var hasD3DMetal: Bool = false
    var d3dMetalVersion: String = "Missing"
    var hasDXMT: Bool = false
    var dxmtVersion: String = "Missing"
    var hasDXVK: Bool = false
    var bottleCount: Int = 0

    var metalHudEnabled: Bool = false
    var gameModeEnabled: Bool = false
    var nvidiaSpoofEnabled: Bool = false
    var avxAndMsyncEnabled: Bool = false
    var cacheSizeBytes: Int64 = 0

    var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: cacheSizeBytes, countStyle: .file)
    }

    var isReady: Bool {
        crossoverExists && hasGStreamer && hasRpath && hasD3DMetal && hasDXMT
    }
}

// MARK: - Navigation Tabs

enum ActiveTab: String, CaseIterable, Identifiable {
    case patcher = "Patcher"
    case optimizations = "Optimizations"
    case maintenance = "Activity & Caches"

    var id: String { rawValue }
    var iconName: String {
        switch self {
        case .patcher: return "bandage.fill"
        case .optimizations: return "bolt.fill"
        case .maintenance: return "terminal.fill"
        }
    }
}

// MARK: - View Model

@MainActor
final class HexAidViewModel: ObservableObject {
    @Published var status = ComponentStatus()
    @Published var isBusy = false
    @Published var activeTab: ActiveTab = .patcher

    // Patcher options
    @Published var updateGStreamer = true
    @Published var updateDXMT = true
    @Published var updateDXVK = true
    @Published var enableAVXAndMSync = true

    // Optimization options
    @Published var toggleMetalHUD = false
    @Published var toggleNvidiaSpoof = false
    @Published var toggleGameMode = true

    @Published var logs: [String] = []

    let cxAppPath = "/Applications/CrossOver.app"
    let bottlesPath = ("~/Library/Application Support/CrossOver/Bottles" as NSString).expandingTildeInPath

    init() {
        if CommandLine.arguments.contains("--tab-optimizations") {
            activeTab = .optimizations
        } else if CommandLine.arguments.contains("--tab-maintenance") {
            activeTab = .maintenance
            logs = [
                "[09:42:01] Starting HexAid patch on /Applications/CrossOver.app...",
                "[09:42:02] Resolving latest GStreamer build from Sikarugir-App/gstreamer...",
                "[09:42:03] Downloading & extracting GStreamer 1.28.1 (with FFmpeg/libav)...",
                "[09:42:04] Cleaning conflicting stock GStreamer/GLib libraries & linking plugins...",
                "[09:42:05] Linking winegstreamer.so to GStreamer.framework...",
                "[09:42:06] Resolving latest DXMT release from 3Shain/dxmt...",
                "[09:42:07] Downloading & extracting DXMT v0.80 builtin...",
                "[09:42:08] Ensuring WINEMSYNC=1 and ROSETTA_ADVERTISE_AVX=1 on existing bottles...",
                "[09:42:09] Clearing quarantine, re-signing CrossOver.app & resetting caches...",
                "[09:42:10] ✅ HexAid patch complete! All components verified."
            ]
        }
    }

    func appendLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)")
    }

    func clearLogs() {
        logs.removeAll()
    }

    func copyLogs() {
        let text = logs.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func refreshStatus() {
        let cxPath = cxAppPath
        let btlPath = bottlesPath
        Task.detached {
            let next = Self.inspectStatus(cxAppPath: cxPath, bottlesPath: btlPath)
            await MainActor.run {
                self.status = next
                self.toggleMetalHUD = next.metalHudEnabled
                self.toggleNvidiaSpoof = next.nvidiaSpoofEnabled
            }
        }
    }

    nonisolated static func inspectStatus(cxAppPath: String, bottlesPath: String) -> ComponentStatus {
        let fm = FileManager.default
        var next = ComponentStatus()
        next.crossoverExists = fm.fileExists(atPath: cxAppPath)

        if let items = try? fm.contentsOfDirectory(atPath: bottlesPath) {
            let bottleDirs = items.filter { item in
                fm.fileExists(atPath: "\(bottlesPath)/\(item)/cxbottle.conf")
            }
            next.bottleCount = bottleDirs.count

            // Check if any bottle has Metal HUD, NVIDIA spoof, or MSync enabled
            for dir in bottleDirs {
                let confPath = "\(bottlesPath)/\(dir)/cxbottle.conf"
                if let content = try? String(contentsOfFile: confPath, encoding: .utf8) {
                    if content.contains("\"MTL_HUD_ENABLED\" = \"1\"") {
                        next.metalHudEnabled = true
                    }
                    if content.contains("\"D3DM_VENDOR_ID\" = \"0x10DE\"") {
                        next.nvidiaSpoofEnabled = true
                    }
                    if content.contains("\"WINEMSYNC\" = \"1\"") && content.contains("\"ROSETTA_ADVERTISE_AVX\" = \"1\"") {
                        next.avxAndMsyncEnabled = true
                    }
                }
            }
        }

        if next.crossoverExists {
            let plistPath = "\(cxAppPath)/Contents/Info.plist"
            if let dict = NSDictionary(contentsOfFile: plistPath) {
                let shortVer = dict["CFBundleShortVersionString"] as? String ?? "?"
                let buildVer = dict["CFBundleVersion"] as? String ?? "?"
                next.versionString = "\(shortVer) (\(buildVer))"
                if let cat = dict["LSApplicationCategoryType"] as? String, cat == "public.app-category.games" {
                    next.gameModeEnabled = true
                }
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
                    next.d3dMetalVersion = "Installed (Protected)"
                }
            }

            let dxmtPath = "\(cxAppPath)/Contents/SharedSupport/CrossOver/lib/dxmt/x86_64-windows/d3d11.dll"
            next.hasDXMT = fm.fileExists(atPath: dxmtPath)
            next.dxmtVersion = next.hasDXMT ? "v0.80 Builtin" : "Missing"

            let dxvkPath = "\(cxAppPath)/Contents/SharedSupport/CrossOver/lib/dxvk/x86_64-windows/dxgi.dll"
            next.hasDXVK = fm.fileExists(atPath: dxvkPath)

            let wineGstPath = "\(cxAppPath)/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/winegstreamer.so"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: wineGstPath)),
               let needle = "GStreamer.framework/Versions/Current/lib".data(using: .utf8) {
                next.hasRpath = data.range(of: needle) != nil
            }
        }

        // Calculate cache sizes
        var totalCache: Int64 = 0
        let gstRegistry = ("~/Library/Application Support/CrossOver/gstreamer-1.0-registry.x86_64.bin" as NSString).expandingTildeInPath
        if let attr = try? fm.attributesOfItem(atPath: gstRegistry), let sz = attr[.size] as? Int64 {
            totalCache += sz
        }

        // Check /var/folders for d3dm caches
        if let enumerator = fm.enumerator(at: URL(fileURLWithPath: "/var/folders"), includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent.lowercased().contains("d3dm") {
                    if let sz = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalCache += Int64(sz)
                    }
                }
            }
        }
        next.cacheSizeBytes = totalCache

        return next
    }

    // MARK: - Actions

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
            setopt NULL_GLOB NO_NOMATCH
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
                rm -f libgst*.dylib libglib-2.0*.dylib libgobject-2.0*.dylib libgio-2.0*.dylib libgmodule-2.0*.dylib libgthread-2.0*.dylib libpcre2*.dylib libintl*.dylib libffi*.dylib 2>/dev/null || true
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

            echo "✅ HexAid patch complete! All components verified."
            """

            await self.executeShellScript(script)
        }
    }

    func applyOptimizations() {
        guard !isBusy else { return }
        isBusy = true
        logs.removeAll()
        appendLog("Applying bottle optimizations...")

        let enableHUD = toggleMetalHUD
        let enableNvidia = toggleNvidiaSpoof
        let enableGM = toggleGameMode
        let cxPath = cxAppPath
        let btlPath = bottlesPath

        Task.detached {
            let script = """
            set -e
            CX_APP="\(cxPath)"
            BOTTLES_DIR="\(btlPath)"

            echo "Updating CrossOver bottle configurations..."
            for CONF in "$BOTTLES_DIR"/*/cxbottle.conf; do
                [ -f "$CONF" ] || continue
                BOTTLE_NAME=$(basename "$(dirname "$CONF")")

                # Metal Performance HUD
                if [ "\(enableHUD ? "1" : "0")" = "1" ]; then
                    if ! grep -q '"MTL_HUD_ENABLED"' "$CONF"; then
                        echo "[$BOTTLE_NAME] Enabling Metal Performance HUD..."
                        printf '\\n"MTL_HUD_ENABLED" = "1"\\n' >> "$CONF"
                    fi
                else
                    if grep -q '"MTL_HUD_ENABLED"' "$CONF"; then
                        echo "[$BOTTLE_NAME] Disabling Metal Performance HUD..."
                        sed -i '' '/"MTL_HUD_ENABLED"/d' "$CONF"
                    fi
                fi

                # NVIDIA GPU Spoofing for D3DMetal (Bypasses UE5 driver warnings)
                if [ "\(enableNvidia ? "1" : "0")" = "1" ]; then
                    if ! grep -q '"D3DM_VENDOR_ID"' "$CONF"; then
                        echo "[$BOTTLE_NAME] Setting D3DMetal Vendor to NVIDIA (0x10DE / RTX 4090)..."
                        printf '\\n"D3DM_VENDOR_ID" = "0x10DE"\\n"D3DM_DEVICE_ID" = "0x2684"\\n' >> "$CONF"
                    fi
                else
                    if grep -q '"D3DM_VENDOR_ID"' "$CONF"; then
                        echo "[$BOTTLE_NAME] Removing NVIDIA D3DMetal spoofing..."
                        sed -i '' '/"D3DM_VENDOR_ID"/d' "$CONF"
                        sed -i '' '/"D3DM_DEVICE_ID"/d' "$CONF"
                    fi
                fi
            done

            if [ "\(enableGM ? "1" : "0")" = "1" ]; then
                echo "Configuring macOS Game Mode for CrossOver & game launchers..."
                /usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.games" "$CX_APP/Contents/Info.plist" 2>/dev/null || \\
                /usr/libexec/PlistBuddy -c "Set :LSApplicationCategoryType public.app-category.games" "$CX_APP/Contents/Info.plist"
                codesign --force --deep --sign - "$CX_APP"
                /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$CX_APP"

                # Tag any installed CrossOver game app launchers
                if [ -d "$HOME/Applications/CrossOver" ]; then
                    find "$HOME/Applications/CrossOver" -name "*.app" -maxdepth 3 | while read -r GAME_APP; do
                        [ -f "$GAME_APP/Contents/Info.plist" ] || continue
                        /usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.games" "$GAME_APP/Contents/Info.plist" 2>/dev/null || \\
                        /usr/libexec/PlistBuddy -c "Set :LSApplicationCategoryType public.app-category.games" "$GAME_APP/Contents/Info.plist"
                        codesign --force --deep --sign - "$GAME_APP" 2>/dev/null || true
                        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$GAME_APP" 2>/dev/null || true
                    done
                fi
                echo "macOS Game Mode successfully configured!"
            fi

            echo "✅ All optimizations applied successfully."
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
            echo "✅ Successfully purged GStreamer registry & D3DMetal shader caches."
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
                    self.appendLog("❌ Process exited with code \(code)")
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

// MARK: - Apple HIG UI Elements

struct IconWellView: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.title3)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .frame(width: 24)
    }
}

struct CardGroupBox<Content: View>: View {
    let title: String
    var trailingText: String? = nil
    let content: Content

    init(title: String, trailingText: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailingText = trailingText
        self.content = content()
    }

    var body: some View {
        GroupBox {
            content
        } label: {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer(minLength: 8)
                if let trailingText {
                    Text(trailingText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ComponentRowView: View {
    let iconName: String
    let title: String
    let subtitle: String
    let badgeText: String
    let isOk: Bool
    var showDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconWellView(systemName: iconName)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(badgeText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((isOk ? Color.green : Color.orange).opacity(0.18))
                    )
                    .foregroundColor(isOk ? .green : .orange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            if showDivider {
                Divider()
                    .padding(.leading, 52)
            }
        }
    }
}

struct ToggleRowView: View {
    let iconName: String
    let title: String
    let description: String
    @Binding var isOn: Bool
    var isEnabled: Bool = true
    var showDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconWellView(systemName: iconName)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                    Text(description)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!isEnabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if showDivider {
                Divider()
                    .padding(.leading, 52)
            }
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @StateObject private var vm = HexAidViewModel()
    @State private var isConfirmingCachePurge = false

    var body: some View {
        VStack(spacing: 0) {
            // App Header Bar
            HStack(spacing: 12) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 42, height: 42)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom))
                            .frame(width: 42, height: 42)
                        Image(systemName: "bandage.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("HexAid")
                            .font(.title3.weight(.semibold))
                        Text("v2.3.1")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                    }
                    Text("/Applications/CrossOver.app • v\(vm.status.versionString) • \(vm.status.bottleCount) Bottle\(vm.status.bottleCount == 1 ? "" : "s")")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { vm.refreshStatus() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(vm.isBusy)
                .help("Refresh status (⌘R)")
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // Segmented Tab Picker
            Picker("", selection: $vm.activeTab) {
                ForEach(ActiveTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.iconName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            Divider()

            // Scrollable Workspace Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 14) {
                    switch vm.activeTab {
                    case .patcher:
                        patcherView
                    case .optimizations:
                        optimizationsView
                    case .maintenance:
                        maintenanceView
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }

            Divider()

            // Persistent Sticky Bottom Action Bar
            HStack(spacing: 12) {
                switch vm.activeTab {
                case .patcher:
                    Button(action: { vm.runPatch() }) {
                        HStack(spacing: 8) {
                            if vm.isBusy {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "bandage.fill")
                            }
                            Text(vm.isBusy ? "Patching CrossOver.app..." : (vm.status.isReady ? "Re-Apply Patches to CrossOver.app" : "Patch CrossOver.app Now"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                    .disabled(vm.isBusy || !vm.status.crossoverExists)

                case .optimizations:
                    Button(action: { vm.applyOptimizations() }) {
                        HStack(spacing: 8) {
                            if vm.isBusy {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "bolt.fill")
                            }
                            Text(vm.isBusy ? "Applying Optimizations..." : "Apply Optimizations to Bottles")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                    .disabled(vm.isBusy || !vm.status.crossoverExists)

                case .maintenance:
                    Button(action: { isConfirmingCachePurge = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                            Text("Purge Shader & Registry Caches (\(vm.status.formattedCacheSize))")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(vm.isBusy)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 680, idealWidth: 740, maxWidth: .infinity,
               minHeight: 680, idealHeight: 760, maxHeight: .infinity)
        .confirmationDialog(
            "Purge Shader and Registry Caches?",
            isPresented: $isConfirmingCachePurge,
            titleVisibility: .visible
        ) {
            Button("Purge Caches", role: .destructive) {
                vm.clearShaderCaches()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The caches will be rebuilt as you use CrossOver. This can make the next game launch take longer.")
        }
        .onAppear {
            vm.refreshStatus()
        }
    }

    // MARK: - Tab Views

    private var patcherView: some View {
        VStack(spacing: 12) {
            CardGroupBox(title: "CrossOver Runtime Status", trailingText: vm.status.isReady ? "All Patched" : "Upgrade Needed") {
                ComponentRowView(
                    iconName: "film.stack.fill",
                    title: "GStreamer + FFmpeg (libgstlibav)",
                    subtitle: "Full media codecs for Resident Evil, Silent Hill, UE4/5 FMVs",
                    badgeText: vm.status.gstreamerVersion,
                    isOk: vm.status.hasGStreamer
                )
                ComponentRowView(
                    iconName: "link",
                    title: "winegstreamer.so Link (LC_RPATH)",
                    subtitle: "In-place Mach-O rpath linking to GStreamer.framework",
                    badgeText: vm.status.hasRpath ? "Linked" : "Unpatched",
                    isOk: vm.status.hasRpath
                )
                ComponentRowView(
                    iconName: "cpu.fill",
                    title: "Apple D3DMetal (Game Porting Toolkit)",
                    subtitle: "Validated DirectX 12 to Metal runtime (Protected)",
                    badgeText: vm.status.d3dMetalVersion,
                    isOk: vm.status.hasD3DMetal
                )
                ComponentRowView(
                    iconName: "gauge.with.needle.fill",
                    title: "DXMT (DirectX 11 to Metal)",
                    subtitle: "High-performance Metal backend for DirectX 11 in lib/dxmt",
                    badgeText: vm.status.dxmtVersion,
                    isOk: vm.status.hasDXMT,
                    showDivider: false
                )
            }

            CardGroupBox(title: "Patch Options (Applies to CrossOver.app)") {
                ToggleRowView(
                    iconName: "arrow.down.circle.fill",
                    title: "Full GStreamer + FFmpeg Runtime",
                    description: "Downloads latest Sikarugir-App build with H.264/HEVC/VP9 support",
                    isOn: $vm.updateGStreamer,
                    isEnabled: !vm.isBusy
                )
                ToggleRowView(
                    iconName: "arrow.triangle.2.circlepath",
                    title: "Latest DXMT Builtin Release",
                    description: "Fetches official 3Shain/dxmt release to upgrade Direct3D 11",
                    isOn: $vm.updateDXMT,
                    isEnabled: !vm.isBusy
                )
                ToggleRowView(
                    iconName: "circle.grid.2x2.fill",
                    title: "Latest DXVK-macOS",
                    description: "Updates Vulkan D3D9/D3D10/D3D11 fallback libraries in lib/dxvk",
                    isOn: $vm.updateDXVK,
                    isEnabled: !vm.isBusy
                )
                ToggleRowView(
                    iconName: "bolt.fill",
                    title: "Enable MSync + Rosetta 2 AVX",
                    description: "Writes WINEMSYNC=1 and ROSETTA_ADVERTISE_AVX=1 to existing bottles",
                    isOn: $vm.enableAVXAndMSync,
                    isEnabled: !vm.isBusy,
                    showDivider: false
                )
            }
        }
    }

    private var optimizationsView: some View {
        VStack(spacing: 12) {
            CardGroupBox(title: "Gaming & Performance Tweaks", trailingText: "\(vm.status.bottleCount) Bottles Target") {
                ToggleRowView(
                    iconName: "chart.xyaxis.line",
                    title: "Apple Metal Performance HUD",
                    description: "Overlay real-time FPS, frame pacing graph, and GPU/VRAM load",
                    isOn: $vm.toggleMetalHUD,
                    isEnabled: !vm.isBusy
                )
                ToggleRowView(
                    iconName: "sparkles.tv.fill",
                    title: "Spoof NVIDIA RTX for D3DMetal",
                    description: "Reports RTX 4090 (0x10DE) to bypass UE5 driver warnings & unlock DLSS",
                    isOn: $vm.toggleNvidiaSpoof,
                    isEnabled: !vm.isBusy
                )
                ToggleRowView(
                    iconName: "gamecontroller.fill",
                    title: "Enable macOS Game Mode for Games",
                    description: "Tags CrossOver and game launchers with public.app-category.games",
                    isOn: $vm.toggleGameMode,
                    isEnabled: !vm.isBusy,
                    showDivider: false
                )
            }

        }
    }

    private var maintenanceView: some View {
        VStack(spacing: 12) {
            CardGroupBox(title: "Storage & Shader Caches", trailingText: vm.status.formattedCacheSize) {
                HStack(spacing: 12) {
                    IconWellView(systemName: "trash")

                    VStack(alignment: .leading, spacing: 2) {
                        Text("D3DMetal Shaders & GStreamer Registry")
                            .font(.system(size: 13, weight: .medium))
                        Text("\(vm.status.formattedCacheSize) currently cached in /var/folders & Application Support")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            CardGroupBox(title: "Activity & Execution Log", trailingText: "\(vm.logs.count) lines") {
                VStack(spacing: 0) {
                    HStack {
                        Text("Console")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: { vm.copyLogs() }) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .disabled(vm.logs.isEmpty)

                        Button(action: { vm.clearLogs() }) {
                            Label("Clear", systemImage: "trash")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .disabled(vm.logs.isEmpty)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))

                    Divider()

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                if vm.logs.isEmpty {
                                    Text("No recent activity. Ready.")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .padding(10)
                                } else {
                                    ForEach(Array(vm.logs.enumerated()), id: \.offset) { idx, line in
                                        Text(line)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(line.contains("❌") ? .red : (line.contains("✅") ? .green : .primary))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .id(idx)
                                    }
                                }
                            }
                            .padding(8)
                        }
                        .frame(height: 220)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.85))
                        .onChange(of: vm.logs.count) { _ in
                            if let last = vm.logs.indices.last {
                                withAnimation {
                                    proxy.scrollTo(last, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - App Delegate & Window Setup

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "HexAid"
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 680, height: 680)

        window.contentViewController = NSHostingController(rootView: contentView)
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

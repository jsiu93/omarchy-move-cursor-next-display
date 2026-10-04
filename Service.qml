/**
 * Omarchy service entry point. Reads the optional keymap, checks for key
 * conflicts, and keeps the runtime Hyprland bindings registered across config
 * reloads. Cursor movement itself lives in hypr/bind.lua.
 */
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Item {
    id: root
    property var manifest: null
    readonly property string sourceDir: manifest && manifest.__sourceDir
        ? manifest.__sourceDir
        : Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.jsiu93.move-cursor-display"
    readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/move-cursor-display.json"
    readonly property string owner: Date.now().toString() + ":" + Math.random().toString()
    readonly property string prefix: "Move cursor: "
    readonly property var actions: ["next", "prev", "next_center", "prev_center"]
    property var desired: ({ next: "ALT + grave", prev: null, next_center: null, prev_center: null })
    property int revision: 0
    property int runningRevision: 0
    property bool busy: false
    property bool pending: false
    property bool stopping: false
    property string phase: ""
    property string lastWarning: ""

    // ---- Input validation and Lua transport ---------------------------------
    function luaString(value: string): string {
        // Lua decimal escapes have three digits, preventing adjacent-digit ambiguity.
        return '"' + value.replace(/[\\"\x00-\x1f\x7f]/g, function(c) {
            return "\\" + ("000" + c.charCodeAt(0)).slice(-3)
        }) + '"'
    }

    function warn(message: string): void {
        if (message === root.lastWarning) return
        root.lastWarning = message
        console.warn(root.prefix + message)
        Quickshell.execDetached(["hyprctl", "notify", "0", "5000", "0", root.prefix + message])
    }

    function keyInfo(value: string): var {
        const parts = value.trim().split(/\s*\+\s*/)
        const key = parts.pop()
        // Named XKB keysyms keep collision checks consistent with binds -j.
        if (!key || !/^[A-Za-z0-9_]+$/.test(key)) throw new Error("Use an XKB keysym, such as grave or F8")
        const modifiers = { SHIFT: 1, CTRL: 4, CONTROL: 4, ALT: 8, MOD1: 8,
            MOD2: 16, MOD3: 32, SUPER: 64, WIN: 64, LOGO: 64, MOD4: 64, MOD5: 128 }
        let mask = 0
        for (let i = 0; i < parts.length; i++) {
            const name = parts[i].toUpperCase()
            const bit = Object.prototype.hasOwnProperty.call(modifiers, name) ? modifiers[name] : 0
            if (!bit) throw new Error("Unknown modifier: " + parts[i])
            mask |= bit
        }
        const canonical = []
        const names = [[1, "SHIFT"], [4, "CTRL"], [8, "ALT"], [16, "MOD2"],
            [32, "MOD3"], [64, "SUPER"], [128, "MOD5"]]
        for (let i = 0; i < names.length; i++)
            if (mask & names[i][0]) canonical.push(names[i][1])
        canonical.push(key)
        return { key: key.toLowerCase(), mask: mask, value: canonical.join(" + ") }
    }

    function acceptConfig(text: string): void {
        try {
            const config = JSON.parse(text)
            if (!config || typeof config !== "object" || Array.isArray(config))
                throw new Error("Expected a JSON object")
            const keys = { next: "ALT + grave", prev: null, next_center: null, prev_center: null }
            for (let i = 0; i < root.actions.length; i++) {
                const action = root.actions[i]
                if (Object.prototype.hasOwnProperty.call(config, action)) {
                    const value = config[action]
                    if (value !== null && typeof value !== "string")
                        throw new Error(action + " must be a key string or null")
                    keys[action] = value === null ? null : root.keyInfo(value).value
                }
            }
            root.desired = keys
            root.lastWarning = ""
            root.requestApply()
        } catch (error) {
            root.warn("Fix " + root.configPath + ". Keeping current keys. " + error)
        }
    }

    // ---- Serialized reconciliation ------------------------------------------
    function requestApply(): void {
        root.revision++
        root.pending = true
        debounce.restart()
    }

    function pump(): void {
        if (root.stopping || root.busy || !root.pending) return
        root.pending = false
        root.busy = true
        root.runningRevision = root.revision
        root.phase = "query"
        runner.command = ["hyprctl", "binds", "-j"]
        runner.running = true
    }

    function applyBindings(text: string): void {
        const bindings = JSON.parse(text)
        if (!Array.isArray(bindings)) throw new Error("Invalid binding response")
        const entries = []
        const used = {}
        const skipped = []
        for (let i = 0; i < root.actions.length; i++) {
            const action = root.actions[i]
            const value = root.desired[action]
            if (value === null) continue
            const key = root.keyInfo(value)
            const identity = key.mask + ":" + key.key
            let conflict = !!used[identity]
            for (let j = 0; j < bindings.length; j++) {
                const binding = bindings[j]
                if (String(binding.description || "").indexOf(root.prefix) === 0) continue
                // Binds in any submap count as occupied.
                if (Number(binding.modmask) === key.mask
                    && (String(binding.key).toLowerCase() === key.key || binding.catch_all))
                    conflict = true
            }
            if (conflict) { skipped.push(action + " (" + value + ")"); continue }
            used[identity] = true
            entries.push(action + "=" + root.luaString(value))
        }
        if (skipped.length) root.warn("Keys already in use: " + skipped.join(", ") + ". Choose other keys in " + root.configPath)
        const token = root.luaString(root.owner)
        const script = "local m=__move_cursor_display; if not m or m.owner~=" + token
            + " then m=dofile(" + root.luaString(root.sourceDir + "/hypr/bind.lua") + ") end; "
            + "m.owner=" + token + "; m.apply({" + entries.join(",") + "})"
        root.phase = "apply"
        runner.command = ["hyprctl", "eval", script]
        runner.running = true
    }

    function finished(code: int, text: string): void {
        if (root.stopping) return
        if (code !== 0 || (root.phase === "apply" && text.trim() !== "ok")) {
            root.warn("Binding update failed: " + text.trim())
        } else if (root.phase === "query" && root.runningRevision === root.revision) {
            try { root.applyBindings(text); return }
            catch (error) { root.warn("Binding check failed: " + error) }
        }
        root.busy = false
        root.pump()
    }

    Timer {
        id: debounce
        interval: 100
        onTriggered: root.pump()
    }
    Process {
        id: runner
        stdout: StdioCollector { id: output; waitForEnd: true }
        stderr: StdioCollector { id: errors; waitForEnd: true }
        onExited: function(exitCode) {
            const result = output.text + errors.text
            Qt.callLater(function() { root.finished(exitCode, result) })
        }
    }
    FileView {
        id: configFile
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.acceptConfig(text())
        onLoadFailed: function(error) {
            if (error === FileViewError.FileNotFound) root.acceptConfig("{}")
            else root.warn("Could not read " + root.configPath + ". Keeping current keys.")
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "configreloaded") {
                // Replay the last valid keymap even while an edit contains invalid JSON.
                root.requestApply()
                configFile.reload()
            }
        }
    }
    Component.onCompleted: Qt.callLater(function() { configFile.path = root.configPath })
    Component.onDestruction: {
        root.stopping = true
        Quickshell.execDetached(["hyprctl", "eval", "if __move_cursor_display and __move_cursor_display.owner=="
            + root.luaString(root.owner) + " then __move_cursor_display.clear() end"])
    }
}

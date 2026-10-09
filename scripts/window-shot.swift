import AppKit

let owner = CommandLine.arguments[1]
let output = CommandLine.arguments[2]
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
guard let window = windows.first(where: { ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0 }),
      let number = window[kCGWindowNumber as String] as? Int else {
    print("no window")
    exit(1)
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
task.arguments = ["-l", String(number), "-o", "-x", output]
try task.run()
task.waitUntilExit()
print("saved")

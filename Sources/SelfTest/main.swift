import Foundation
import UsageCore

// 极简断言 harness：无 XCTest 依赖，任一失败则退出码 1。
var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ✓ \(msg)") }
    else { print("  ✗ \(msg)"); failures += 1 }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ msg: String) {
    if a == b { print("  ✓ \(msg)") }
    else { print("  ✗ \(msg) — got \(a), want \(b)"); failures += 1 }
}

print("阈值")
eq(UsageParsing.level(for: 0),    .normal,   "0 → normal")
eq(UsageParsing.level(for: 62),   .normal,   "62 → normal")
eq(UsageParsing.level(for: 74.9), .normal,   "74.9 → normal")
eq(UsageParsing.level(for: 75),   .warning,  "75 → warning")
eq(UsageParsing.level(for: 89),   .warning,  "89 → warning")
eq(UsageParsing.level(for: 90),   .critical, "90 → critical")
eq(UsageParsing.level(for: 100),  .critical, "100 → critical")

print("倒计时")
let now = Date(timeIntervalSince1970: 1_000_000)
func at(_ s: TimeInterval) -> Date { now.addingTimeInterval(s) }
eq(UsageParsing.countdown(to: at(2*3600 + 14*60), now: now), "2h 14m", "2h14m")
eq(UsageParsing.countdown(to: at(6*3600 + 54*60), now: now), "6h 54m", "6h54m")
eq(UsageParsing.countdown(to: at(45*60), now: now),          "45m",    "45m")
eq(UsageParsing.countdown(to: at(2*86400 + 3*3600), now: now), "2d 3h", "2d3h")
eq(UsageParsing.countdown(to: at(-10), now: now),            "现在",   "过期→现在")

print("解析：真实 limits 数组结构 + ISO 日期 + Fable 标签")
let json1 = Data("""
{ "five_hour": {"utilization":65.0,"resets_at":"2026-07-23T09:30:00.404913+00:00"},
  "seven_day": {"utilization":19.0,"resets_at":"2026-07-30T00:00:00.4+00:00"},
  "seven_day_opus": null,
  "limits":[
    {"kind":"session","group":"session","percent":65,"severity":"normal","resets_at":"2026-07-23T09:30:00.404913+00:00","scope":null},
    {"kind":"weekly_all","group":"weekly","percent":19,"severity":"normal","resets_at":"2026-07-30T00:00:00.4+00:00","scope":null},
    {"kind":"weekly_scoped","group":"weekly","percent":3,"severity":"normal","resets_at":"2026-07-30T00:00:00.4+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null}}
  ] }
""".utf8)
let s1 = UsageParsing.parse(json1, now: now)
eq(s1.session?.utilization, 65, "session 65")
eq(s1.weekly?.utilization, 19, "weekly 19")
eq(s1.weeklyThird?.utilization, 3, "third 3")
eq(s1.thirdLabel, "Fable", "third 标签 Fable")
check(s1.hasAny, "hasAny")
// ISO 日期解析：2026-07-23T09:30:00Z
let iso = UsageParsing.parseDate("2026-07-23T09:30:00.404913+00:00")
eq(iso.map { Int($0.timeIntervalSince1970) }, 1784799000, "ISO→epoch")

print("解析：回退到顶层窗口（无 limits）")
let json2 = Data("""
{ "five_hour": {"utilization":30,"resets_at":1008040},
  "seven_day": {"utilization":40,"resets_at":1024840},
  "seven_day_opus": {"utilization":50,"resets_at":1024840} }
""".utf8)
let s2 = UsageParsing.parse(json2)
eq(s2.session?.utilization, 30, "回退 session 30")
eq(s2.weekly?.utilization, 40, "回退 weekly 40")
eq(s2.weeklyThird?.utilization, 50, "回退 third 50")

print("解析：字符串数字 + rate_limits 容器")
let s3 = UsageParsing.parse(Data("""
{ "rate_limits": { "five_hour": {"used_percentage":"55.5","reset":1008040} } }
""".utf8))
eq(s3.session?.utilization, 55.5, "字符串 55.5")

print("解析：坏数据不崩")
check(!UsageParsing.parse(Data("not json".utf8)).hasAny, "非 JSON")
check(!UsageParsing.parse(Data("[1,2,3]".utf8)).hasAny, "数组")
check(!UsageParsing.parse(Data("{}".utf8)).hasAny,      "空对象")

print("")
if failures == 0 { print("全部通过 ✅"); exit(0) }
else { print("\(failures) 项失败 ❌"); exit(1) }

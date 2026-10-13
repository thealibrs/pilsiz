// Vestel SmartCenter sanal kumanda tuş kodları.
// Kaynak: topluluk tersine mühendislik çalışmaları (shkspr.mobi, pyvesteltv, ha-vestel-toshiba-tv).
enum RemoteKey: Int, CaseIterable, Sendable {
    case num0 = 1000, num1, num2, num3, num4, num5, num6, num7, num8, num9
    case back = 1010
    case power = 1012
    case mute = 1013
    case volumeUp = 1016
    case volumeDown = 1017
    case info = 1018
    case down = 1019
    case up = 1020
    case left = 1021
    case right = 1022
    case stop = 1024
    case play = 1025
    case rewind = 1027
    case forward = 1028
    case subtitle = 1031
    case channelUp = 1032
    case channelDown = 1033
    case exit = 1037
    case home = 1046
    case epg = 1047
    case menu = 1048
    case pause = 1049
    case yellow = 1050
    case blue = 1052
    case ok = 1053
    case green = 1054
    case red = 1055
    case source = 1056

    static func digit(_ n: Int) -> RemoteKey { RemoteKey(rawValue: 1000 + n)! }
}

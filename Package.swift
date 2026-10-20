// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EdgeLink",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "EdgeLinkCore", targets: ["EdgeLinkCore"]),
        .executable(name: "bthid", targets: ["bthid"]),
        .executable(name: "edgelink-hid", targets: ["edgelink-hid"]),
        .executable(name: "EdgeLink", targets: ["EdgeLink"]),
    ],
    targets: [
        // 블루투스 HID: SDP 등록, L2CAP 채널, 리포트 전송. 앱과 bthid가 같이 쓴다.
        .target(
            name: "EdgeLinkCore",
            linkerSettings: [.linkedFramework("IOBluetooth")]
        ),
        // 1단계 연결 검증용 명령줄 도구
        .executableTarget(
            name: "bthid",
            dependencies: ["EdgeLinkCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("ApplicationServices"),
                // 명령줄 도구도 블루투스 권한 문구가 있어야 TCC가 막지 않는다
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/bthid/Info.plist",
                ]),
            ]
        ),
        // 블루투스 도우미. 앱이 따로 띄워 블루투스 HID를 맡긴다 (번들의 Contents/MacOS/edgelink-hid)
        .executableTarget(
            name: "edgelink-hid",
            dependencies: ["EdgeLinkCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                // 블루투스 권한 문구 (앱이 띄우면 권한은 앱 것을 따르지만, 혼자 띄워도 막히지 않게)
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/edgelink-hid/Info.plist",
                ]),
            ]
        ),
        // 메뉴바 앱. 번들(.app)은 scripts/build-app.sh로 만든다.
        .executableTarget(
            name: "EdgeLink",
            dependencies: ["EdgeLinkCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "EdgeLinkCoreTests",
            dependencies: ["EdgeLinkCore"]
        ),
    ]
)

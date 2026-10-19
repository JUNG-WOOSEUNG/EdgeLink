// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EdgeLink",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "EdgeLinkCore", targets: ["EdgeLinkCore"]),
        .executable(name: "bthid", targets: ["bthid"]),
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
        .testTarget(
            name: "EdgeLinkCoreTests",
            dependencies: ["EdgeLinkCore"]
        ),
    ]
)

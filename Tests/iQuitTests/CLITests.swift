import Foundation
import Testing
@testable import iQuit

@Suite("CLI parsing")
struct CLITests {
    @Test("flags map to commands")
    func parseFlags() {
        #expect(CLI.parse(["iQuit", "--quit-all"]) == .quitAll)
        #expect(CLI.parse(["iQuit", "quit-all"]) == .quitAll)
        #expect(CLI.parse(["iQuit", "--force-quit-all"]) == .forceQuitAll)
        #expect(CLI.parse(["iQuit", "--list"]) == .list)
        #expect(CLI.parse(["iQuit", "--status"]) == .status)
        #expect(CLI.parse(["iQuit", "--help"]) == .help)
        #expect(CLI.parse(["iQuit", "-h"]) == .help)
    }

    @Test("quit requires a name")
    func parseQuit() {
        #expect(CLI.parse(["iQuit", "--quit", "TextEdit"]) == .quit("TextEdit"))
        #expect(CLI.parse(["iQuit", "--quit"]) == .help)
        #expect(CLI.parse(["iQuit", "--quit", ""]) == .help)
    }

    @Test("no arguments or unknown positional means GUI launch")
    func parseNone() {
        #expect(CLI.parse(["iQuit"]) == nil)
        #expect(CLI.parse(["iQuit", "something"]) == nil)
        #expect(CLI.parse(["iQuit", "--bogus"]) == .help)
    }

    @Test("encode/decode round-trips", arguments: [
        CLICommand.quitAll, .forceQuitAll, .quit("Text Edit"), .quit("a:b"), .list, .status, .help
    ])
    func roundTrip(command: CLICommand) {
        #expect(CLICommand.decode(command.encoded) == command)
    }

    @Test("decode rejects garbage")
    func decodeGarbage() {
        #expect(CLICommand.decode("") == nil)
        #expect(CLICommand.decode("nope") == nil)
    }
}

@Suite("URL scheme")
struct URLCommandTests {
    @Test("hosts map to commands")
    func hosts() {
        #expect(URLCommand.parse(URL(string: "iquit://quit-all")!) == .quitAll)
        #expect(URLCommand.parse(URL(string: "iquit://force-quit-all")!) == .forceQuitAll)
        #expect(URLCommand.parse(URL(string: "iquit://list")!) == .list)
        #expect(URLCommand.parse(URL(string: "iquit://status")!) == .status)
        #expect(URLCommand.parse(URL(string: "IQUIT://Quit-All")!) == .quitAll)
    }

    @Test("quit takes a name query")
    func quitName() {
        #expect(URLCommand.parse(URL(string: "iquit://quit?name=TextEdit")!) == .quit("TextEdit"))
        #expect(URLCommand.parse(URL(string: "iquit://quit?name=Text%20Edit")!) == .quit("Text Edit"))
        #expect(URLCommand.parse(URL(string: "iquit://quit")!) == nil)
        #expect(URLCommand.parse(URL(string: "iquit://quit?name=")!) == nil)
    }

    @Test("other schemes are ignored")
    func otherScheme() {
        #expect(URLCommand.parse(URL(string: "https://quit-all")!) == nil)
        #expect(URLCommand.parse(URL(string: "iquit://unknown")!) == nil)
    }
}

@Suite("IPC framing")
struct IPCTests {
    @Test("reply encodes nonce and text")
    func encodeDecode() {
        let raw = IPC.encodeReply(nonce: "abc", text: "quit\t3")
        #expect(IPC.decodeReply(raw, nonce: "abc") == "quit\t3")
        #expect(IPC.decodeReply(raw, nonce: "xyz") == nil)
    }

    @Test("text may contain the separator")
    func separatorInText() {
        let raw = IPC.encodeReply(nonce: "n", text: "a|b|c")
        #expect(IPC.decodeReply(raw, nonce: "n") == "a|b|c")
    }
}

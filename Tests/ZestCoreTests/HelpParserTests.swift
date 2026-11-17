import Testing
@testable import ZestCore

@Suite struct HelpParserTests {
    func names(_ result: HelpParser.Result) -> [String] {
        result.subcommands.compactMap { $0.name.all.first }
    }

    @Test func cobraWithColons() {
        let help = """
        Work seamlessly with GitHub from the command line.

        CORE COMMANDS
          auth:          Authenticate gh and git with GitHub
          pr:            Manage pull requests

        HELP TOPICS
          environment:   Environment variables that can be used with gh
          exit-codes:    Exit codes used by gh

        FLAGS
          --help      Show help for command
          --version   Show gh version
        """
        let result = HelpParser.parse(help)
        #expect(names(result) == ["auth", "pr"])
        #expect(result.subcommands.first?.description == "Authenticate gh and git with GitHub")
        #expect(result.options.count == 2)
    }

    @Test func dockerPlugins() {
        let help = """
        Management Commands:
          builder     Manage builds
          compose*    Docker Compose
          scout*      Docker Scout
        """
        #expect(names(HelpParser.parse(help)) == ["builder", "compose", "scout"])
    }

    @Test func npmCommandParagraph() {
        let help = """
        All commands:

            access, adduser, audit, bugs, cache, ci, completion,
            config, dedupe

        Specify configs in the ini-formatted file:
        """
        #expect(names(HelpParser.parse(help)) == ["access", "adduser", "audit", "bugs", "cache", "ci", "completion", "config", "dedupe"])
    }

    @Test func keepsColonsInsideNames() {
        let help = """
        Commands:
          apps:list [platform]    List FirebaseApps within a Firebase project.
          deploy                  Deploy code and assets to your Firebase project
        """
        #expect(names(HelpParser.parse(help)) == ["apps:list", "deploy"])
    }
}

@Suite struct SpecYAMLTests {
    @Test func quotesWordsYAMLReadsAsBooleans() throws {
        var spec = Spec(name: Names(["make"]))
        spec.options = [Option(name: Names(["-j"]), description: "Jobs")]
        spec.options?[0].args = OneOrMany([Arg(name: "n")])
        let yaml = try SpecStore.encodeYAML(spec)
        #expect(yaml.contains("name: 'n'"))
    }
}

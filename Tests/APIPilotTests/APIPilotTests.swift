import Foundation
import Testing
@testable import APIPilot

@Suite struct ParsingTests {
    let sample = try! SpecParser.parse(data: Data(SampleSpec.yaml.utf8))

    @Test func readsSampleSpec() {
        #expect(sample.title == "JSONPlaceholder")
        #expect(sample.format == "OpenAPI 3.1.0")
        #expect(sample.operations.count == 10)
        #expect(sample.servers.first?.url == "https://jsonplaceholder.typicode.com")
        #expect(sample.groupedOperations.map(\.tag) == ["Posts", "Comments", "Users", "Todos"])
    }

    @Test func mergesPathLevelParameters() throws {
        let operation = try #require(sample.operation(id: "GET /posts/{id}"))
        #expect(operation.parameters.map(\.name) == ["id"])
        #expect(operation.parameters.first?.required == true)
    }

    @Test func mergesAllOf() throws {
        let raw = try #require(sample.schema(named: "Post"))
        let schema = Schema(raw, document: sample.document)
        #expect(schema.properties.map(\.name) == ["title", "body", "userId", "id"])
        #expect(schema.required == ["title", "body", "userId", "id"])
    }

    @Test func buildsDraftFromOperation() throws {
        let operation = try #require(sample.operation(id: "POST /posts"))
        let draft = DraftFactory.make(from: operation, spec: sample)
        #expect(draft.url == "{{baseUrl}}/posts")
        #expect(draft.bodyMode == .json)
        let body = try JSONParser.parse(draft.body)
        #expect(body["title"]?.string == "Hello from API Pilot")
        #expect(body["id"] == nil)
        #expect(draft.assertions.map(\.source) == [.status, .schema])
        #expect(draft.assertions.first?.expected == "201")
    }

    @Test func readsSwagger2() throws {
        let json = """
        {"swagger":"2.0","info":{"title":"Pets","version":"1"},"host":"pets.example.com","basePath":"/v1","schemes":["https"],
         "securityDefinitions":{"key":{"type":"apiKey","in":"header","name":"X-Key"}},"security":[{"key":[]}],
         "paths":{"/pets/{id}":{"get":{"parameters":[{"name":"id","in":"path","required":true,"type":"integer"}],
           "responses":{"200":{"description":"ok","schema":{"$ref":"#/definitions/Pet"}}}}},
          "/pets":{"post":{"parameters":[{"name":"body","in":"body","schema":{"$ref":"#/definitions/Pet"}}],"responses":{"201":{"description":"made"}}}}},
         "definitions":{"Pet":{"type":"object","required":["name"],"properties":{"name":{"type":"string"}}}}}
        """
        let spec = try SpecParser.parse(data: Data(json.utf8))
        #expect(spec.servers.first?.url == "https://pets.example.com/v1")
        #expect(spec.schemaNames == ["Pet"])
        let get = try #require(spec.operation(id: "GET /pets/{id}"))
        #expect(get.parameters.first?.schema?["type"]?.string == "integer")
        #expect(get.security == ["key"])
        let post = try #require(spec.operation(id: "POST /pets"))
        #expect(post.requestBody?.preferred?.schema != nil)
        let draft = DraftFactory.make(from: get, spec: spec)
        #expect(draft.auth.mode == .apiKey)
        #expect(draft.auth.keyName == "X-Key")
    }

    @Test func rejectsNonSpec() {
        #expect(throws: (any Error).self) { try SpecParser.parse(data: Data("name: hello".utf8)) }
    }
}

@Suite struct JSONTests {
    @Test func keepsKeyOrderAndNumbers() throws {
        let value = try JSONParser.parse(#"{"z":1,"a":[true,null,"é\n"],"big":12345678901234567890}"#)
        #expect(value.keys == ["z", "a", "big"])
        #expect(value["big"]?.plainText == "12345678901234567890")
        #expect(value["a"]?[2]?.string == "é\n")
        #expect(value.serialized(pretty: false) == #"{"z":1,"a":[true,null,"é\n"],"big":12345678901234567890}"#)
    }

    @Test func reportsErrors() {
        #expect(throws: JSONParseError.self) { try JSONParser.parse("{\"a\":}") }
        #expect(throws: JSONParseError.self) { try JSONParser.parse("[1,2") }
    }

    @Test func evaluatesPaths() throws {
        let value = try JSONParser.parse(#"{"data":{"items":[{"id":7},{"id":9}]},"weird key":1}"#)
        #expect(JSONPath.evaluate("$.data.items[1].id", in: value)?.plainText == "9")
        #expect(JSONPath.evaluate("data.items[-1].id", in: value)?.plainText == "9")
        #expect(JSONPath.evaluate("$.data.items.length", in: value)?.plainText == "2")
        #expect(JSONPath.evaluate("$.data.items[*].id", in: value) == .array([.number("7"), .number("9")]))
        #expect(JSONPath.evaluate("$['weird key']", in: value)?.plainText == "1")
        #expect(JSONPath.evaluate("$.missing", in: value) == nil)
    }
}

@Suite struct ValidationTests {
    let spec = try! SpecParser.parse(data: Data(SampleSpec.yaml.utf8))

    private func user() -> Schema {
        Schema(spec.schema(named: "User")!, document: spec.document)
    }

    @Test func acceptsValidBody() throws {
        let body = try JSONParser.parse(#"{"id":1,"name":"A","username":"a","email":"a@b.co","address":{"city":"X"}}"#)
        #expect(SchemaValidator.validate(body, against: user()).isEmpty)
    }

    @Test func reportsProblemsWithPaths() throws {
        let body = try JSONParser.parse(#"{"id":"1","name":"A","email":"nope","address":{"city":3}}"#)
        let issues = SchemaValidator.validate(body, against: user())
        let paths = Set(issues.map(\.path))
        #expect(paths.contains("$"))
        #expect(paths.contains("$.id"))
        #expect(paths.contains("$.email"))
        #expect(paths.contains("$.address.city"))
        #expect(issues.contains { $0.message.contains("username") })
    }

    @Test func checksArraysAndIntegers() throws {
        let schema = Schema(try JSONParser.parse(#"{"type":"array","maxItems":2,"items":{"type":"integer","minimum":1}}"#), document: spec.document)
        #expect(SchemaValidator.validate(try JSONParser.parse("[1, 2]"), against: schema).isEmpty)
        #expect(SchemaValidator.validate(try JSONParser.parse("[1, 2.5, 0]"), against: schema).count == 3)
    }
}

@Suite struct RequestTests {
    @Test func interpolatesVariables() {
        var unresolved = Set<String>()
        let text = Interpolator.apply("{{ host }}/{{path}}/{{missing}}", variables: ["host": "https://x.io", "path": "{{inner}}", "inner": "v1"], unresolved: &unresolved)
        #expect(text == "https://x.io/v1/{{missing}}")
        #expect(unresolved == ["missing"])
    }

    @Test func buildsFullRequest() throws {
        var draft = RequestDraft()
        draft.method = "post"
        draft.url = "{{baseUrl}}/users/{id}/posts"
        draft.pathParams = [KeyValue(key: "id", value: "a b")]
        draft.query = [KeyValue(key: "q", value: "x&y"), KeyValue(key: "off", value: "1", enabled: false)]
        draft.headers = [KeyValue(key: "X-Trace", value: "{{$uuid}}")]
        draft.bodyMode = .json
        draft.body = #"{"name":"{{name}}"}"#
        draft.auth.mode = .bearer
        draft.auth.token = "{{token}}"
        let request = try RequestBuilder.build(draft, variables: ["baseUrl": "https://api.test", "name": "Ada", "token": "t0k"])
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://api.test/users/a%20b/posts?q=x%26y")
        #expect(request.header("Authorization") == "Bearer t0k")
        #expect(request.header("Content-Type") == "application/json")
        #expect(request.header("X-Trace")?.count == 36)
        #expect(request.bodyText == #"{"name":"Ada"}"#)
    }

    @Test func failsWithoutBaseURL() {
        var draft = RequestDraft()
        draft.url = "{{baseUrl}}/x"
        #expect(throws: RequestError.self) { try RequestBuilder.build(draft, variables: [:]) }
    }

    @Test func encodesFormAndAPIKey() throws {
        var draft = RequestDraft()
        draft.url = "https://api.test/login"
        draft.bodyMode = .form
        draft.form = [KeyValue(key: "user", value: "a b"), KeyValue(key: "pass", value: "p&q")]
        draft.auth.mode = .apiKey
        draft.auth.keyName = "key"
        draft.auth.keyValue = "123"
        draft.auth.keyLocation = "query"
        let request = try RequestBuilder.build(draft, variables: [:])
        #expect(request.bodyText == "user=a+b&pass=p%26q")
        #expect(request.url.query == "key=123")
    }

    @Test func generatesCurl() throws {
        var draft = RequestDraft()
        draft.method = "PUT"
        draft.url = "https://api.test/it's"
        draft.bodyMode = .text
        draft.body = "hi"
        let request = try RequestBuilder.build(draft, variables: [:])
        let curl = CodeGenerator.code(for: request, language: .curl)
        #expect(curl.hasPrefix("curl -X PUT 'https://api.test/it'\\''s'"))
        #expect(curl.contains("--data-raw 'hi'"))
    }

    @Test func savedDraftsRoundTrip() throws {
        var draft = RequestDraft()
        draft.name = "Create"
        draft.query = [KeyValue(key: "a", value: "1"), KeyValue()]
        draft.assertions = [Assertion(source: .status, expected: "201")]
        let data = try WorkspaceFiles.encoder.encode(draft.cleaned)
        let decoded = try WorkspaceFiles.decoder.decode(RequestDraft.self, from: data)
        #expect(try WorkspaceFiles.encoder.encode(decoded) == data)
        #expect(decoded.query.count == 1)
        let partial = try WorkspaceFiles.decoder.decode(RequestDraft.self, from: Data(#"{"url":"https://x.io"}"#.utf8))
        #expect(partial.method == "GET")
        #expect(partial.url == "https://x.io")
    }
}

@Suite struct AssertionTests {
    let result = HTTPResult(status: 201, headers: [("Content-Type", "application/json")],
                            body: Data(#"{"id":101,"title":"t"}"#.utf8), duration: 0.12, url: nil, date: Date())

    @Test func evaluatesAssertions() {
        let assertions = [
            Assertion(source: .status, expected: "201"),
            Assertion(source: .jsonPath, target: "$.id", comparison: .greaterThan, expected: "100"),
            Assertion(source: .header, target: "content-type", comparison: .contains, expected: "json"),
            Assertion(source: .responseTime, comparison: .lessThan, expected: "50")
        ]
        let results = AssertionEngine.evaluate(assertions, result: result, operation: nil, spec: nil)
        #expect(results.map(\.passed) == [true, true, true, false])
    }

    @Test func capturesValues() {
        let values = AssertionEngine.captures([Capture(variable: "postId", path: "$.id")], result: result)
        #expect(values == ["postId": "101"])
    }

    @Test func checksContract() throws {
        let spec = try SpecParser.parse(data: Data(SampleSpec.yaml.utf8))
        let operation = spec.operation(id: "POST /posts")
        let check = AssertionEngine.schemaIssues(result: result, operation: operation, spec: spec)
        #expect(check.checked)
        #expect(check.issues.map(\.message).sorted() == ["missing required property \"body\"", "missing required property \"userId\""])
    }
}

@Suite struct MockTests {
    @Test func parsesHTTPRequest() throws {
        let raw = "POST /posts?x=1 HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\n\r\nabcd"
        let request = try #require(MockHTTPRequest(Data(raw.utf8)))
        #expect(request.method == "POST")
        #expect(request.path == "/posts")
        #expect(String(decoding: request.body, as: UTF8.self) == "abcd")
        #expect(MockHTTPRequest(Data("GET / HTTP/1.1\r\nContent-Length: 9\r\n\r\nabc".utf8)) == nil)
    }

    @Test func servesExamples() async throws {
        let spec = try SpecParser.parse(data: Data(SampleSpec.yaml.utf8))
        let server = MockServer(spec: spec)
        let port = UInt16.random(in: 20000...40000)
        try server.start(port: port)
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(200))

        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/posts/5")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let body = try JSONParser.parse(data)
        #expect(body["title"]?.string == "Hello from API Pilot")
        #expect(body["id"]?.plainText == "1")

        var post = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/posts")!)
        post.httpMethod = "POST"
        post.httpBody = Data(#"{"title":1}"#.utf8)
        let (errorData, errorResponse) = try await URLSession.shared.data(for: post)
        #expect((errorResponse as? HTTPURLResponse)?.statusCode == 422)
        #expect(try JSONParser.parse(errorData)["issues"]?.array?.count == 3)

        let (_, missing) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/nothing")!)
        #expect((missing as? HTTPURLResponse)?.statusCode == 404)
    }
}

@Suite struct DocsTests {
    @Test func exportsHTML() throws {
        let spec = try SpecParser.parse(data: Data(SampleSpec.yaml.utf8))
        let html = DocsExporter.html(for: spec)
        #expect(html.contains("<title>JSONPlaceholder API reference</title>"))
        #expect(html.contains("id=\"createpost\""))
        #expect(html.contains("Hello from API Pilot"))
    }
}

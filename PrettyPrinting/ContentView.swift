import SwiftUI

indirect enum Doc<Ann> {
    case empty
    case text(String, Ann? = nil)
    case sequence(Doc, Doc)
    case newline
    case indent(Doc)
    case hang(Doc)
    case choice(Doc, Doc) // left is widest doc
}

struct PrettyState<Ann> {
    var columnWidth: Int
    var stack: [(indentation: Int, Doc<Ann>)]
    var tabWidth = 4
    var currentColumn = 0

    init(columnwidth: Int, doc: Doc<Ann>) {
        self.columnWidth = columnwidth
        self.stack = [(0, doc)]
    }

    mutating func render() -> [(String, Ann?)] {
        guard let (indentation, el) = stack.popLast() else { return [] }
        switch el {
        case .empty:
            return render()
        case .text(let string, let ann):
            currentColumn += string.count
            return [(string, ann)] + render()
        case .sequence(let doc, let doc2):
            stack.append((indentation, doc2))
            stack.append((indentation, doc))
            return render()
        case .newline:
            currentColumn = indentation
            return [("\n" + String(repeating: " ", count: indentation), nil)] + render()
        case .indent(let doc):
            stack.append((indentation + tabWidth, doc))
            return render()
        case .hang(let doc):
            stack.append((currentColumn, doc))
            return render()
        case .choice(let doc, let doc2):
            let copy = self
            stack.append((indentation, doc))
            let attempt = render()
            let plain = attempt.map { $0.0 }.joined()
            if plain.fits(width: columnWidth-copy.currentColumn) {
                return attempt
            } else {
                self = copy
                stack.append((indentation, doc2))
                return render()
            }
        }
    }
}

extension String {
    func fits(width: Int) -> Bool {
        prefix { !$0.isNewline }.count <= width
    }
}

extension Doc {
    func flatten() -> Doc {
        switch self {
        case .empty:
            .empty
        case .text:
            self
        case .sequence(let doc, let doc2):
            .sequence(doc.flatten(), doc2.flatten())
        case .newline:
            .text(" ")
        case .indent(let doc):
            .indent(doc.flatten())
        case .hang(let doc):
            .hang(doc.flatten())
        case .choice(let doc, _):
            doc
        }
    }

    func group() -> Doc {
        .choice(flatten(), self)
    }
}


extension Doc {
    func pretty(columns: Int) -> [(String, Ann?)] {
        var state = PrettyState(columnwidth: columns, doc: self)
        return state.render()
    }

    static func +(lhs: Doc, rhs: Doc) -> Doc {
        .sequence(lhs, rhs)
    }
}

func joined<A>(_ elements: [Doc<A>], separator: Doc<A>) -> Doc<A> {
    guard let f = elements.first else { return .empty }
    return elements.dropFirst().reduce(f) { $0 + separator + $1 }
}

extension Doc: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        assert(!value.contains("\n"))
        self = .text(value)
    }
}

enum SyntaxKind {
    case keyword
    case type

    var color: Color {
        switch self {
        case .keyword:
            return .purple
        case .type:
            return .teal
        }
    }
}

func parameters(_ params: [Doc<SyntaxKind>]) -> Doc<SyntaxKind> {
    let j = joined(params, separator: "," + .newline).group()
    return .choice(.hang(j), .indent(.newline + j) + .newline)
}

let arguments = parameters([
    .text("proposal: ") + type("ProposedViewSize"),
    .text("subviews: ") + type("Subviews"),
    .text("cache: ") + keyword("inout") + type(" ()")
])

func keyword(_ string: String) -> Doc<SyntaxKind> {
    .text(string, .keyword)
}

func type(_ string: String) -> Doc<SyntaxKind> {
    .text(string, .type)
}

let doc: Doc = keyword("func") + .text(" hello(") + arguments + .text(") {") + .indent(.newline + .text("print(\"Hello\")")) + .newline + .text("}")

func renderPlainText<A>(_ doc: [(String, A?)]) -> String {
    doc.map { $0.0 }.joined()
}

func renderText(_ doc: [(String, SyntaxKind?)]) -> Text {
    doc.reduce(Text("")) { t, piece in
        t + Text(piece.0).foregroundStyle(piece.1?.color ?? .primary)
    }
}

struct ContentView: View {
    @State var width = 20.0
    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                Text(String(repeating: ".", count: Int(width)))
                renderText(doc.pretty(columns: Int(width)))
                    .fixedSize()
            }
            Spacer()
            Slider(value: $width, in: 0...120)
        }
        .monospaced()
        .padding()
    }
}

#Preview {
    ContentView()
}

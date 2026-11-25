// Box-only test entry: runs the Swift core on Linux against core/tests/cases.json.
import Foundation
let args = CommandLine.arguments
Res.root = URL(fileURLWithPath: args[1])          // folder containing data/ and dict/
exit(Int32(runSelfTest(args[2])))

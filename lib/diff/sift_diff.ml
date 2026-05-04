module Line = Line
module Hunk = Hunk
module File = File

type t = Diff.t

module Error = Error

let empty = Diff.empty
let make = Diff.make
let files = Diff.files
let file_count = Diff.file_count
let is_empty = Diff.is_empty
let equal = Diff.equal
let compare = Diff.compare
let pp = Diff.pp

module Parser = Parser
module Compute = Compute

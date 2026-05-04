type t =
  | Ocaml_block
  | C_block
  | C_line
  | Shell_line
  | Lisp_line
  | Sql_line
  | Xml_block

let equal a b =
  match (a, b) with
  | Ocaml_block, Ocaml_block
  | C_block, C_block
  | C_line, C_line
  | Shell_line, Shell_line
  | Lisp_line, Lisp_line
  | Sql_line, Sql_line
  | Xml_block, Xml_block ->
      true
  | _ -> false

let rank = function
  | Ocaml_block -> 0
  | C_block -> 1
  | C_line -> 2
  | Shell_line -> 3
  | Lisp_line -> 4
  | Sql_line -> 5
  | Xml_block -> 6

let compare a b = Int.compare (rank a) (rank b)

let to_string = function
  | Ocaml_block -> "ocaml-block"
  | C_block -> "c-block"
  | C_line -> "c-line"
  | Shell_line -> "shell-line"
  | Lisp_line -> "lisp-line"
  | Sql_line -> "sql-line"
  | Xml_block -> "xml-block"

let pp ppf t = Format.pp_print_string ppf (to_string t)

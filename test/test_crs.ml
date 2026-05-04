open Windtrap
module C = Sift_crs

let pp_to_string pp x = Format.asprintf "%a" pp x

let handle s =
  match C.Handle.of_string s with
  | Ok h -> h
  | Error e -> failf "expected valid handle %S, got %a" s C.Error.pp e

let comment ?status ?priority ?recipient ~reporter body =
  let reporter = handle reporter in
  let recipient = Option.map handle recipient in
  let header = C.Header.make ?status ?priority ~reporter ?recipient () in
  C.Comment.make ~header ~body

let span ?(start_offset = 0) ?(stop_offset = 1) ?(start_line = 1)
    ?(start_col = 0) ?(stop_line = 1) ?(stop_col = 1) () =
  C.Span.v ~start_offset ~stop_offset ~start_line ~start_col ~stop_line
    ~stop_col ()

let expect_some ~msg = function
  | Some x -> x
  | None -> failf "%s: expected Some _" msg

let expect_none ~msg = function
  | None -> ()
  | Some _ -> failf "%s: expected None" msg

let expect_ok ~msg = function
  | Ok x -> x
  | Error e -> failf "%s: expected Ok _, got %a" msg C.Error.pp e

let expect_error ~msg = function
  | Error e -> e
  | Ok _ -> failf "%s: expected Error _" msg

let expect_invalid_arg ~msg f =
  let raised =
    try
      f ();
      false
    with Invalid_argument _ -> true
  in
  is_true ~msg raised

let expect_one ~msg = function
  | [ x ] -> x
  | xs -> failf "%s: expected one item, got %d" msg (List.length xs)

let expect_valid ~msg item =
  match C.Item.comment item with
  | Ok c -> c
  | Error e -> failf "%s: expected valid item, got %a" msg C.Error.pp e

let expect_invalid ~msg item =
  is_false ~msg:(msg ^ " is_valid") (C.Item.is_valid item);
  ignore
    (expect_error ~msg:(msg ^ " comment") (C.Item.comment item) : C.Error.t)

let expect_handle_error ~input =
  let e =
    expect_error ~msg:("invalid handle " ^ input) (C.Handle.of_string input)
  in
  match C.Error.kind e with
  | C.Error.Invalid_handle got ->
      equal ~msg:"invalid handle payload" string input got
  | C.Error.Invalid_status _ | C.Error.Invalid_priority _
  | C.Error.Invalid_header _ | C.Error.Invalid_span _ | C.Error.Invalid_anchor _
  | C.Error.Stale_item ->
      failf "expected Invalid_handle for %S, got %a" input C.Error.pp e

let assert_comment_fields ?status ?priority ?recipient ~reporter ~body ~msg c =
  let status = Option.value status ~default:C.Status.CR in
  let priority = Option.value priority ~default:C.Priority.Now in
  is_true ~msg:(msg ^ " status") (C.Status.equal status (C.Comment.status c));
  is_true ~msg:(msg ^ " priority")
    (C.Priority.equal priority (C.Comment.priority c));
  is_true ~msg:(msg ^ " reporter")
    (C.Handle.equal (handle reporter) (C.Comment.reporter c));
  (match (recipient, C.Comment.recipient c) with
  | None, None -> ()
  | Some expected, Some actual ->
      is_true ~msg:(msg ^ " recipient")
        (C.Handle.equal (handle expected) actual)
  | None, Some actual ->
      failf "%s recipient: expected none, got %s" msg
        (C.Handle.to_string actual)
  | Some expected, None ->
      failf "%s recipient: expected %s, got none" msg expected);
  equal ~msg:(msg ^ " body") string body (C.Comment.body c)

let assert_item ?status ?priority ?recipient ~syntax ~raw ~reporter ~body ~msg
    item =
  is_true ~msg:(msg ^ " syntax") (C.Syntax.equal syntax (C.Item.syntax item));
  equal ~msg:(msg ^ " raw") string raw (C.Item.raw item);
  let c = expect_valid ~msg item in
  assert_comment_fields ?status ?priority ?recipient ~reporter ~body ~msg c

let make_item ?status ?priority ?recipient ~reporter ~body ~raw () =
  C.Item.make ~path:"sample.ml" ~syntax:C.Syntax.Ocaml_block ~span:(span ())
    ~raw
    (Ok (comment ?status ?priority ?recipient ~reporter body))

let apply_ok ~msg edit ~source = expect_ok ~msg (C.Edit.apply edit ~source)

let handle_tests =
  [
    test "accepts bot handles with brackets" (fun () ->
        let h = handle "dependabot[bot]" in
        equal ~msg:"to_string" string "dependabot[bot]" (C.Handle.to_string h);
        equal ~msg:"pp" string "dependabot[bot]" (pp_to_string C.Handle.pp h));
    test "rejects invalid handles" (fun () ->
        List.iter
          (fun input -> expect_handle_error ~input)
          [ ""; "two words"; "alice@example"; "team/name"; "ümlaut" ];
        expect_invalid_arg ~msg:"Handle.v rejects invalid input" (fun () ->
            ignore (C.Handle.v "two words" : C.Handle.t)));
  ]

let formatting_tests =
  [
    test "formats and parses statuses and priorities" (fun () ->
        equal ~msg:"CR to_string" string "CR" (C.Status.to_string C.Status.CR);
        equal ~msg:"XCR to_string" string "XCR"
          (C.Status.to_string C.Status.XCR);
        is_true ~msg:"of_string CR"
          (C.Status.equal C.Status.CR
             (expect_some ~msg:"status CR" (C.Status.of_string "CR")));
        expect_none ~msg:"lowercase status" (C.Status.of_string "cr");
        equal ~msg:"now suffix" string "" (C.Priority.suffix C.Priority.Now);
        equal ~msg:"soon suffix" string "soon"
          (C.Priority.suffix C.Priority.Soon);
        equal ~msg:"someday suffix" string "someday"
          (C.Priority.suffix C.Priority.Someday);
        is_true ~msg:"of_suffix soon"
          (C.Priority.equal C.Priority.Soon
             (expect_some ~msg:"priority soon" (C.Priority.of_suffix "soon")));
        expect_none ~msg:"empty priority suffix" (C.Priority.of_suffix ""));
    test "formats headers and comments" (fun () ->
        let reporter = handle "alice" in
        let h = C.Header.make ~reporter () in
        is_true ~msg:"default status"
          (C.Status.equal C.Status.CR (C.Header.status h));
        is_true ~msg:"default priority"
          (C.Priority.equal C.Priority.Now (C.Header.priority h));
        equal ~msg:"default header pp" string "CR alice"
          (pp_to_string C.Header.pp h);
        let h =
          C.Header.make ~status:C.Status.XCR ~priority:C.Priority.Someday
            ~reporter ~recipient:(handle "bob") ()
        in
        equal ~msg:"explicit header pp" string "XCR-someday alice for bob"
          (pp_to_string C.Header.pp h);
        let c = C.Comment.make ~header:h ~body:"fixed by dependency bump" in
        equal ~msg:"comment status accessor" string "XCR"
          (C.Status.to_string (C.Comment.status c));
        equal ~msg:"comment priority accessor" string "someday"
          (C.Priority.to_string (C.Comment.priority c));
        equal ~msg:"comment pp_header" string "XCR-someday alice for bob:"
          (pp_to_string C.Comment.pp_header c);
        equal ~msg:"comment pp" string
          "XCR-someday alice for bob: fixed by dependency bump"
          (pp_to_string C.Comment.pp c));
    test "parses headers and comments" (fun () ->
        let h =
          expect_ok ~msg:"header"
            (C.Parser.header "CR-soon alice for dependabot[bot]")
        in
        is_true ~msg:"parsed header priority"
          (C.Priority.equal C.Priority.Soon (C.Header.priority h));
        is_true ~msg:"parsed header reporter"
          (C.Handle.equal (handle "alice") (C.Header.reporter h));
        (match C.Header.recipient h with
        | Some recipient ->
            equal ~msg:"parsed header recipient" string "dependabot[bot]"
              (C.Handle.to_string recipient)
        | None -> fail "expected parsed recipient");
        let c =
          expect_ok ~msg:"comment"
            (C.Parser.comment
               "XCR-someday dependabot[bot] for reviewer: bumped package")
        in
        assert_comment_fields ~status:C.Status.XCR ~priority:C.Priority.Someday
          ~recipient:"reviewer" ~reporter:"dependabot[bot]"
          ~body:"bumped package" ~msg:"parsed comment" c);
  ]

let span_tests =
  [
    test "validates spans and exposes positions" (fun () ->
        let s =
          expect_some ~msg:"valid span"
            (C.Span.make ~start_offset:3 ~stop_offset:9 ~start_line:2
               ~start_col:4 ~stop_line:2 ~stop_col:10 ())
        in
        equal ~msg:"start_offset" int 3 (C.Span.start_offset s);
        equal ~msg:"stop_offset" int 9 (C.Span.stop_offset s);
        equal ~msg:"start_line" int 2 (C.Span.start_line s);
        equal ~msg:"start_col" int 4 (C.Span.start_col s);
        equal ~msg:"stop_line" int 2 (C.Span.stop_line s);
        equal ~msg:"stop_col" int 10 (C.Span.stop_col s);
        ignore
          (expect_some ~msg:"zero-width span"
             (C.Span.make ~start_offset:5 ~stop_offset:5 ~start_line:3
                ~start_col:7 ~stop_line:3 ~stop_col:7 ())
            : C.Span.t));
    test "rejects invalid spans" (fun () ->
        expect_none ~msg:"negative start offset"
          (C.Span.make ~start_offset:(-1) ~stop_offset:1 ~start_line:1
             ~start_col:0 ~stop_line:1 ~stop_col:1 ());
        expect_none ~msg:"line zero"
          (C.Span.make ~start_offset:0 ~stop_offset:1 ~start_line:0 ~start_col:0
             ~stop_line:1 ~stop_col:1 ());
        expect_none ~msg:"negative column"
          (C.Span.make ~start_offset:0 ~stop_offset:1 ~start_line:1
             ~start_col:(-1) ~stop_line:1 ~stop_col:1 ());
        expect_none ~msg:"stop before start offset"
          (C.Span.make ~start_offset:2 ~stop_offset:1 ~start_line:1 ~start_col:2
             ~stop_line:1 ~stop_col:1 ());
        expect_invalid_arg ~msg:"Span.v rejects invalid input" (fun () ->
            ignore
              (C.Span.v ~start_offset:2 ~stop_offset:1 ~start_line:1
                 ~start_col:2 ~stop_line:1 ~stop_col:1 ()
                : C.Span.t)));
  ]

let parser_tests =
  [
    test "parses OCaml block comments" (fun () ->
        let raw = "(* CR alice: ocaml block *)" in
        let source = "let x = 1\n" ^ raw ^ "\nlet y = 2\n" in
        let item =
          expect_one ~msg:"ocaml block"
            (C.Parser.source ~path:"sample.ml" source)
        in
        assert_item ~syntax:C.Syntax.Ocaml_block ~raw ~reporter:"alice"
          ~body:"ocaml block" ~msg:"ocaml block" item;
        equal ~msg:"item path" string "sample.ml" (C.Item.path item);
        let item_span = C.Item.span item in
        equal ~msg:"span start line" int 2 (C.Span.start_line item_span);
        equal ~msg:"span start col" int 0 (C.Span.start_col item_span);
        equal ~msg:"span stop line" int 2 (C.Span.stop_line item_span);
        equal ~msg:"span stop col" int (String.length raw)
          (C.Span.stop_col item_span));
    test "parses nested OCaml comments" (fun () ->
        let raw = "(* CR alice: outer (* nested *) body *)" in
        let item =
          expect_one ~msg:"nested ocaml" (C.Parser.source ~path:"x.ml" raw)
        in
        assert_item ~syntax:C.Syntax.Ocaml_block ~raw ~reporter:"alice"
          ~body:"outer (* nested *) body" ~msg:"nested ocaml" item);
    test "ignores CR-like comments inside string literals" (fun () ->
        let raw = "(* CR bob: real comment *)" in
        let source =
          "let block = \"(* CR alice: fixture *)\"\n"
          ^ "let line = \"// CR alice: fixture\"\n" ^ raw ^ "\n"
        in
        let item =
          expect_one ~msg:"real comment only"
            (C.Parser.source ~path:"sample.ml" source)
        in
        assert_item ~syntax:C.Syntax.Ocaml_block ~raw ~reporter:"bob"
          ~body:"real comment" ~msg:"real comment" item);
    test "parses C block and XML block comments" (fun () ->
        let c_raw = "/* CR bob: c block */" in
        let xml_raw = "<!-- XCR-soon carol for dan: xml block -->" in
        let items =
          C.Parser.source ~path:"sample"
            (c_raw ^ "\nlet z = 0\n" ^ xml_raw ^ "\n")
        in
        match items with
        | [ c_item; xml_item ] ->
            assert_item ~syntax:C.Syntax.C_block ~raw:c_raw ~reporter:"bob"
              ~body:"c block" ~msg:"c block" c_item;
            assert_item ~status:C.Status.XCR ~priority:C.Priority.Soon
              ~recipient:"dan" ~syntax:C.Syntax.Xml_block ~raw:xml_raw
              ~reporter:"carol" ~body:"xml block" ~msg:"xml block" xml_item
        | _ -> failf "expected two block items, got %d" (List.length items));
    test "parses common line comments" (fun () ->
        let raws =
          [
            ("// CR alice: slash", C.Syntax.C_line, "alice", "slash");
            ("# CR bob: hash", C.Syntax.Shell_line, "bob", "hash");
            ("; CR carol: semi", C.Syntax.Lisp_line, "carol", "semi");
            ("-- CR dan: sql", C.Syntax.Sql_line, "dan", "sql");
          ]
        in
        let source =
          String.concat "\n" (List.map (fun (raw, _, _, _) -> raw) raws) ^ "\n"
        in
        let items = C.Parser.source ~path:"comments" source in
        equal ~msg:"line comment item count" int (List.length raws)
          (List.length items);
        List.iter2
          (fun (raw, syntax, reporter, body) item ->
            assert_item ~syntax ~raw ~reporter ~body ~msg:raw item)
          raws items);
    test "preserves malformed CR-like comments as invalid items" (fun () ->
        let raws =
          [
            "(* CR @bad: malformed reporter *)";
            "// CR-sooner alice: malformed priority";
            "# XCR alice for @bad: malformed recipient";
          ]
        in
        let source = String.concat "\n" raws ^ "\n" in
        let items = C.Parser.source ~path:"bad" source in
        equal ~msg:"invalid item count" int (List.length raws)
          (List.length items);
        List.iter2
          (fun raw item ->
            equal ~msg:"invalid raw preserved" string raw (C.Item.raw item);
            expect_invalid ~msg:raw item)
          raws items);
    test "splits adjacent line CRs before malformed CR-like comments" (fun () ->
        let source = "// CR alice: ok\n// CR @bad: bad\n" in
        match C.Parser.source ~path:"adjacent.c" source with
        | [ first; second ] ->
            assert_item ~syntax:C.Syntax.C_line ~raw:"// CR alice: ok"
              ~reporter:"alice" ~body:"ok" ~msg:"first adjacent CR" first;
            equal ~msg:"second adjacent raw" string "// CR @bad: bad"
              (C.Item.raw second);
            expect_invalid ~msg:"second adjacent CR" second
        | items ->
            failf "expected two adjacent line items, got %d" (List.length items));
    test "splits adjacent hash CR line comments" (fun () ->
        let source = "# CR alice: first\n# CR bob: second\n" in
        match C.Parser.source ~path:"adjacent.sh" source with
        | [ first; second ] ->
            assert_item ~syntax:C.Syntax.Shell_line ~raw:"# CR alice: first"
              ~reporter:"alice" ~body:"first" ~msg:"first hash CR" first;
            assert_item ~syntax:C.Syntax.Shell_line ~raw:"# CR bob: second"
              ~reporter:"bob" ~body:"second" ~msg:"second hash CR" second
        | items ->
            failf "expected two adjacent hash items, got %d" (List.length items));
    test "keeps ordinary same-syntax continuation lines in line CR bodies"
      (fun () ->
        let source =
          "// CR alice: first line\n// ordinary continuation\n// another line\n"
        in
        let item =
          expect_one ~msg:"line continuation"
            (C.Parser.source ~path:"continuation.c" source)
        in
        assert_item ~syntax:C.Syntax.C_line
          ~raw:
            "// CR alice: first line\n// ordinary continuation\n// another line"
          ~reporter:"alice"
          ~body:"first line\nordinary continuation\nanother line"
          ~msg:"line continuation" item);
  ]

let filter_tests =
  [
    test "matches invalid, status, priority, reporter, and recipient filters"
      (fun () ->
        let cr =
          make_item ~reporter:"alice" ~body:"now" ~raw:"(* CR alice: now *)" ()
        in
        let soon =
          make_item ~priority:C.Priority.Soon ~recipient:"bob" ~reporter:"alice"
            ~body:"soon" ~raw:"(* CR-soon alice for bob: soon *)" ()
        in
        let xcr =
          make_item ~status:C.Status.XCR ~reporter:"carol" ~body:"done"
            ~raw:"(* XCR carol: done *)" ()
        in
        let invalid =
          C.Item.make ~path:"sample.ml" ~syntax:C.Syntax.Ocaml_block
            ~span:(span ()) ~raw:"(* CR @bad: broken *)"
            (Error (C.Error.make (C.Error.Invalid_handle "@bad")))
        in
        is_true ~msg:"All matches valid" (C.Filter.matches C.Filter.All cr);
        is_true ~msg:"All matches invalid"
          (C.Filter.matches C.Filter.All invalid);
        is_true ~msg:"Invalid matches invalid"
          (C.Filter.matches C.Filter.Invalid invalid);
        is_false ~msg:"Invalid skips valid"
          (C.Filter.matches C.Filter.Invalid cr);
        is_true ~msg:"Status CR matches CR"
          (C.Filter.matches (C.Filter.Status C.Status.CR) cr);
        is_false ~msg:"Status CR skips XCR"
          (C.Filter.matches (C.Filter.Status C.Status.CR) xcr);
        is_true ~msg:"Priority Soon matches soon"
          (C.Filter.matches (C.Filter.Priority C.Priority.Soon) soon);
        is_false ~msg:"Priority Soon skips now"
          (C.Filter.matches (C.Filter.Priority C.Priority.Soon) cr);
        is_true ~msg:"Reporter alice matches"
          (C.Filter.matches (C.Filter.Reporter (handle "alice")) soon);
        is_false ~msg:"Reporter alice skips carol"
          (C.Filter.matches (C.Filter.Reporter (handle "alice")) xcr);
        is_true ~msg:"Recipient bob matches"
          (C.Filter.matches (C.Filter.Recipient (Some (handle "bob"))) soon);
        is_false ~msg:"Recipient bob skips unassigned"
          (C.Filter.matches (C.Filter.Recipient (Some (handle "bob"))) cr);
        is_true ~msg:"Recipient none matches unassigned"
          (C.Filter.matches (C.Filter.Recipient None) cr);
        is_false ~msg:"Recipient none skips assigned"
          (C.Filter.matches (C.Filter.Recipient None) soon));
  ]

let edit_tests =
  [
    test "attaches and applies OCaml block comments" (fun () ->
        let source = "let x = 1\nlet y = 2\n" in
        let c = comment ~reporter:"alice" "review x" in
        let edit =
          expect_ok ~msg:"attach ocaml"
            (C.Edit.attach ~source ~syntax:C.Syntax.Ocaml_block
               ~anchor:(C.Edit.Before_line 2) c)
        in
        equal ~msg:"attach range is empty" int (C.Edit.start_offset edit)
          (C.Edit.stop_offset edit);
        let expected = "let x = 1\n(* CR alice: review x *)\nlet y = 2\n" in
        equal ~msg:"attach ocaml result" string expected
          (apply_ok ~msg:"apply attach ocaml" edit ~source));
    test "attaches and applies line comments" (fun () ->
        let source = "alpha\nbeta\n" in
        let c = comment ~reporter:"alice" "shell review" in
        let edit =
          expect_ok ~msg:"attach shell"
            (C.Edit.attach ~source ~syntax:C.Syntax.Shell_line
               ~anchor:(C.Edit.After_line 1) c)
        in
        let expected = "alpha\n# CR alice: shell review\nbeta\n" in
        equal ~msg:"attach shell result" string expected
          (apply_ok ~msg:"apply attach shell" edit ~source));
    test "replaces OCaml block comments while preserving syntax" (fun () ->
        let source = "(* CR alice: old *)\n" in
        let item =
          expect_one ~msg:"replace parse" (C.Parser.source ~path:"x.ml" source)
        in
        let replacement =
          comment ~status:C.Status.XCR ~priority:C.Priority.Soon
            ~recipient:"carol" ~reporter:"bob" "new"
        in
        let edit =
          expect_ok ~msg:"replace ocaml" (C.Edit.replace item replacement)
        in
        equal ~msg:"replace ocaml replacement" string
          "(* XCR-soon bob for carol: new *)" (C.Edit.replacement edit);
        equal ~msg:"replace ocaml result" string
          "(* XCR-soon bob for carol: new *)\n"
          (apply_ok ~msg:"apply replace ocaml" edit ~source));
    test "replaces line comments while preserving syntax" (fun () ->
        let source = "# CR alice: old\nvalue\n" in
        let item =
          expect_one ~msg:"replace line parse"
            (C.Parser.source ~path:"script.sh" source)
        in
        let replacement =
          comment ~status:C.Status.XCR ~priority:C.Priority.Soon
            ~recipient:"carol" ~reporter:"bob" "new"
        in
        let edit =
          expect_ok ~msg:"replace shell" (C.Edit.replace item replacement)
        in
        equal ~msg:"replace shell replacement" string
          "# XCR-soon bob for carol: new" (C.Edit.replacement edit);
        equal ~msg:"replace shell result" string
          "# XCR-soon bob for carol: new\nvalue\n"
          (apply_ok ~msg:"apply replace shell" edit ~source));
    test "converts unresolved CRs to addressed XCR comments" (fun () ->
        let source = "(* CR-soon alice for bob: please rename *)\n" in
        let item =
          expect_one ~msg:"resolve parse" (C.Parser.source ~path:"x.ml" source)
        in
        let original = expect_valid ~msg:"resolve original" item in
        let resolved =
          comment ~status:C.Status.XCR
            ~priority:(C.Comment.priority original)
            ~recipient:"alice" ~reporter:"carol" (C.Comment.body original)
        in
        let edit =
          expect_ok ~msg:"resolve replace" (C.Edit.replace item resolved)
        in
        equal ~msg:"resolve replacement" string
          "(* XCR-soon carol for alice: please rename *)"
          (C.Edit.replacement edit);
        equal ~msg:"resolve result" string
          "(* XCR-soon carol for alice: please rename *)\n"
          (apply_ok ~msg:"apply resolve" edit ~source));
    test "removes and applies edits" (fun () ->
        let source = "(* CR alice: old *)\n" in
        let item =
          expect_one ~msg:"remove parse" (C.Parser.source ~path:"x.ml" source)
        in
        let edit = C.Edit.remove item in
        equal ~msg:"remove replacement" string "" (C.Edit.replacement edit);
        equal ~msg:"remove result" string "\n"
          (apply_ok ~msg:"apply remove" edit ~source));
    test "rejects replace on invalid items and apply on stale ranges" (fun () ->
        let invalid =
          C.Item.make ~path:"sample.ml" ~syntax:C.Syntax.Ocaml_block
            ~span:(span ~start_offset:20 ~stop_offset:30 ~stop_col:30 ())
            ~raw:"(* CR @bad: broken *)"
            (Error (C.Error.make (C.Error.Invalid_handle "@bad")))
        in
        let replacement = comment ~reporter:"alice" "new" in
        let e =
          expect_error ~msg:"replace invalid"
            (C.Edit.replace invalid replacement)
        in
        is_true ~msg:"replace invalid error kind"
          (C.Error.kind e = C.Error.Stale_item);
        let edit = C.Edit.remove invalid in
        ignore
          (expect_error ~msg:"apply stale range"
             (C.Edit.apply edit ~source:"short")
            : C.Error.t));
  ]

let () =
  run "sift.crs"
    [
      group "handles" handle_tests;
      group "formatting" formatting_tests;
      group "spans" span_tests;
      group "parser" parser_tests;
      group "filters" filter_tests;
      group "edits" edit_tests;
    ]

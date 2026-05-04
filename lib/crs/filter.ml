type t =
  | All
  | Invalid
  | Status of Status.t
  | Priority of Priority.t
  | Reporter of Handle.t
  | Recipient of Handle.t option

let matches t item =
  match (t, Item.comment item) with
  | All, _ -> true
  | Invalid, Error _ -> true
  | Invalid, Ok _ -> false
  | Status status, Ok comment -> Status.equal status (Comment.status comment)
  | Status _, Error _ -> false
  | Priority priority, Ok comment ->
      Priority.equal priority (Comment.priority comment)
  | Priority _, Error _ -> false
  | Reporter reporter, Ok comment ->
      Handle.equal reporter (Comment.reporter comment)
  | Reporter _, Error _ -> false
  | Recipient recipient, Ok comment -> (
      match (recipient, Comment.recipient comment) with
      | None, None -> true
      | Some a, Some b -> Handle.equal a b
      | _ -> false)
  | Recipient _, Error _ -> false

let equal_option equal a b =
  match (a, b) with
  | None, None -> true
  | Some a, Some b -> equal a b
  | _ -> false

let compare_option compare a b =
  match (a, b) with
  | None, None -> 0
  | None, Some _ -> -1
  | Some _, None -> 1
  | Some a, Some b -> compare a b

let equal a b =
  match (a, b) with
  | All, All | Invalid, Invalid -> true
  | Status a, Status b -> Status.equal a b
  | Priority a, Priority b -> Priority.equal a b
  | Reporter a, Reporter b -> Handle.equal a b
  | Recipient a, Recipient b -> equal_option Handle.equal a b
  | _ -> false

let rank = function
  | All -> 0
  | Invalid -> 1
  | Status _ -> 2
  | Priority _ -> 3
  | Reporter _ -> 4
  | Recipient _ -> 5

let compare a b =
  let c = Int.compare (rank a) (rank b) in
  if c <> 0 then c
  else
    match (a, b) with
    | All, All | Invalid, Invalid -> 0
    | Status a, Status b -> Status.compare a b
    | Priority a, Priority b -> Priority.compare a b
    | Reporter a, Reporter b -> Handle.compare a b
    | Recipient a, Recipient b -> compare_option Handle.compare a b
    | _ -> 0

let to_string = function
  | All -> "all"
  | Invalid -> "invalid"
  | Status status -> "status:" ^ Status.to_string status
  | Priority priority -> "priority:" ^ Priority.to_string priority
  | Reporter reporter -> "reporter:" ^ Handle.to_string reporter
  | Recipient None -> "recipient:none"
  | Recipient (Some recipient) -> "recipient:" ^ Handle.to_string recipient

let pp ppf t = Format.pp_print_string ppf (to_string t)

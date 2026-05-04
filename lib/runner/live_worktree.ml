type mode = Off | Worktree
type request = int
type load = { input : Sift_git.input; fingerprint : Sift_git.Fingerprint.t }
type pending = { fingerprint : Sift_git.Fingerprint.t; first_seen_at : float }

type t = {
  mode : mode;
  review : Sift_review.t;
  last_loaded : Sift_git.Fingerprint.t option;
  pending : pending option;
  poll_in_flight : request option;
  reload_in_flight : (request * Sift_git.Fingerprint.t) option;
  source_mutation_in_flight : request option;
  next_request : request;
  debounce : float;
}

type event =
  | Tick of float
  | Fingerprint_loaded of
      float * request * (Sift_git.Fingerprint.t, string) result
  | Worktree_loaded of request * (load, string) result
  | Review_changed of Sift_review.t

type action =
  | Load_fingerprint of request
  | Load_worktree of request * Sift_git.Fingerprint.t
  | Replace_review of Sift_review.t
  | Report_error of string

let check_debounce debounce =
  if debounce < 0. then
    invalid_arg "Live_worktree: debounce must be non-negative"

let make ?(debounce = 0.75) mode ~review ~fingerprint () =
  check_debounce debounce;
  {
    mode;
    review;
    last_loaded = fingerprint;
    pending = None;
    poll_in_flight = None;
    reload_in_flight = None;
    source_mutation_in_flight = None;
    next_request = 0;
    debounce;
  }

let mode t = t.mode
let review t = t.review

let next_request t =
  let request = t.next_request in
  (request, { t with next_request = request + 1 })

let refresh_review t input =
  Sift_review.refresh t.review ~feature:input.Sift_git.feature
    ~cr_items:input.cr_items

let request_equal = Int.equal

let same_poll_request t request =
  match t.poll_in_flight with
  | Some in_flight -> request_equal request in_flight
  | None -> false

let reload_request_fingerprint t request =
  match t.reload_in_flight with
  | Some (in_flight, fingerprint) when request_equal request in_flight ->
      Some fingerprint
  | Some _ | None -> None

let same_source_mutation_request t request =
  match t.source_mutation_in_flight with
  | Some in_flight -> request_equal request in_flight
  | None -> false

let clear_in_flight t =
  {
    t with
    pending = None;
    poll_in_flight = None;
    reload_in_flight = None;
    source_mutation_in_flight = None;
  }

let tick now t =
  match t.mode with
  | Off -> (t, [])
  | Worktree -> (
      match
        (t.source_mutation_in_flight, t.poll_in_flight, t.reload_in_flight)
      with
      | Some _, _, _ | _, Some _, _ | _, _, Some _ -> (t, [])
      | None, None, None -> (
          match t.pending with
          | Some pending when now -. pending.first_seen_at >= t.debounce ->
              let request, t = next_request t in
              ( {
                  t with
                  pending = None;
                  reload_in_flight = Some (request, pending.fingerprint);
                },
                [ Load_worktree (request, pending.fingerprint) ] )
          | Some _ | None ->
              let request, t = next_request t in
              ( { t with poll_in_flight = Some request },
                [ Load_fingerprint request ] )))

let fingerprint_loaded now t request result =
  if not (same_poll_request t request) then (t, [])
  else
    let t = { t with poll_in_flight = None } in
    match result with
    | Error message -> (t, [ Report_error message ])
    | Ok fingerprint -> (
        match t.mode with
        | Off -> ({ t with pending = None }, [])
        | Worktree -> (
            match t.last_loaded with
            | Some last_loaded
              when Sift_git.Fingerprint.equal last_loaded fingerprint ->
                ({ t with pending = None }, [])
            | Some _ | None -> (
                match t.pending with
                | Some pending
                  when Sift_git.Fingerprint.equal pending.fingerprint
                         fingerprint ->
                    (t, [])
                | Some _ | None ->
                    ( {
                        t with
                        pending = Some { fingerprint; first_seen_at = now };
                      },
                      [] ))))

let worktree_loaded t request result =
  match reload_request_fingerprint t request with
  | None -> (t, [])
  | Some expected_fingerprint -> (
      let t = { t with reload_in_flight = None } in
      match result with
      | Error message -> (t, [ Report_error message ])
      | Ok { input; fingerprint } ->
          if not (Sift_git.Fingerprint.equal expected_fingerprint fingerprint)
          then (t, [])
          else
            let review = refresh_review t input in
            ( {
                t with
                review;
                mode = Worktree;
                last_loaded = Some fingerprint;
                pending = None;
              },
              [ Replace_review review ] ))

let step event t =
  match event with
  | Tick now -> tick now t
  | Fingerprint_loaded (now, request, result) ->
      fingerprint_loaded now t request result
  | Worktree_loaded (request, result) -> worktree_loaded t request result
  | Review_changed review -> ({ t with review }, [])

let source_mutation_fingerprint_error =
  "cannot write source CRs because the worktree changed; wait for Sift to \
   refresh and try again"

let source_mutation_started ?fingerprint t =
  let fingerprint_matches =
    match t.mode with
    | Off -> Ok ()
    | Worktree -> (
        match (t.last_loaded, fingerprint) with
        | Some last_loaded, Some fingerprint
          when Sift_git.Fingerprint.equal last_loaded fingerprint ->
            Ok ()
        | Some _, Some _ -> Error source_mutation_fingerprint_error
        | Some _, None ->
            Error "cannot verify worktree freshness before writing source CRs"
        | None, _ ->
            Error "cannot write source CRs before the worktree review reloads")
  in
  match fingerprint_matches with
  | Error message -> Error message
  | Ok () ->
      let request, t = next_request t in
      Ok
        ( { (clear_in_flight t) with source_mutation_in_flight = Some request },
          request )

let source_mutation_aborted t request =
  if same_source_mutation_request t request then (clear_in_flight t, true)
  else (t, false)

let source_mutation_loaded t request result =
  if not (same_source_mutation_request t request) then (t, Ok None)
  else
    let t = clear_in_flight t in
    match result with
    | Error message ->
        ({ t with mode = Worktree; last_loaded = None }, Error message)
    | Ok { input; fingerprint } ->
        let review = refresh_review t input in
        ( {
            t with
            review;
            mode = Worktree;
            last_loaded = Some fingerprint;
            pending = None;
          },
          Ok (Some review) )

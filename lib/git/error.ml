type command = { cwd : string; argv : string list }
type status = Exited of int | Signaled of int | Stopped of int

type t =
  | Invalid_repository of string
  | No_worktree of string
  | Git_not_found of string
  | Git_failed of command * status * string
  | Io of string
  | Diff of Sift_diff.Error.t

let equal_command a b =
  String.equal a.cwd b.cwd && List.equal String.equal a.argv b.argv

let compare_command a b =
  match String.compare a.cwd b.cwd with
  | 0 -> List.compare String.compare a.argv b.argv
  | n -> n

let equal_status a b =
  match (a, b) with
  | Exited a, Exited b -> Int.equal a b
  | Signaled a, Signaled b -> Int.equal a b
  | Stopped a, Stopped b -> Int.equal a b
  | (Exited _ | Signaled _ | Stopped _), _ -> false

let rank_status = function Exited _ -> 0 | Signaled _ -> 1 | Stopped _ -> 2

let compare_status a b =
  match Int.compare (rank_status a) (rank_status b) with
  | 0 -> (
      match (a, b) with
      | Exited a, Exited b -> Int.compare a b
      | Signaled a, Signaled b -> Int.compare a b
      | Stopped a, Stopped b -> Int.compare a b
      | (Exited _ | Signaled _ | Stopped _), _ -> 0)
  | n -> n

let rank = function
  | Invalid_repository _ -> 0
  | No_worktree _ -> 1
  | Git_not_found _ -> 2
  | Git_failed _ -> 3
  | Io _ -> 4
  | Diff _ -> 5

let equal a b =
  match (a, b) with
  | Invalid_repository a, Invalid_repository b -> String.equal a b
  | No_worktree a, No_worktree b -> String.equal a b
  | Git_not_found a, Git_not_found b -> String.equal a b
  | Git_failed (ca, sa, ea), Git_failed (cb, sb, eb) ->
      equal_command ca cb && equal_status sa sb && String.equal ea eb
  | Io a, Io b -> String.equal a b
  | Diff a, Diff b -> Sift_diff.Error.equal a b
  | ( ( Invalid_repository _ | No_worktree _ | Git_not_found _ | Git_failed _
      | Io _ | Diff _ ),
      _ ) ->
      false

let compare a b =
  match Int.compare (rank a) (rank b) with
  | 0 -> (
      match (a, b) with
      | Invalid_repository a, Invalid_repository b -> String.compare a b
      | No_worktree a, No_worktree b -> String.compare a b
      | Git_not_found a, Git_not_found b -> String.compare a b
      | Git_failed (ca, sa, ea), Git_failed (cb, sb, eb) -> (
          match compare_command ca cb with
          | 0 -> (
              match compare_status sa sb with
              | 0 -> String.compare ea eb
              | n -> n)
          | n -> n)
      | Io a, Io b -> String.compare a b
      | Diff a, Diff b -> Sift_diff.Error.compare a b
      | ( ( Invalid_repository _ | No_worktree _ | Git_not_found _
          | Git_failed _ | Io _ | Diff _ ),
          _ ) ->
          0)
  | n -> n

let pp_command ppf command =
  Format.fprintf ppf "%s: %s" command.cwd (String.concat " " command.argv)

let pp_status ppf = function
  | Exited code -> Format.fprintf ppf "exited %d" code
  | Signaled signal -> Format.fprintf ppf "signaled %d" signal
  | Stopped signal -> Format.fprintf ppf "stopped %d" signal

let pp ppf = function
  | Invalid_repository path ->
      Format.fprintf ppf "invalid git repository: %s" path
  | No_worktree path ->
      Format.fprintf ppf "git repository has no worktree: %s" path
  | Git_not_found git -> Format.fprintf ppf "git executable not found: %s" git
  | Git_failed (command, status, stderr) ->
      Format.fprintf ppf "git failed (%a, %a): %s" pp_command command pp_status
        status stderr
  | Io message -> Format.fprintf ppf "git io error: %s" message
  | Diff error -> Format.fprintf ppf "diff error: %a" Sift_diff.Error.pp error

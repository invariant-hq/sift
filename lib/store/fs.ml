type path = string
type bytes = string
type 'a codec = { encode : 'a -> bytes; decode : bytes -> ('a, Error.t) result }

type io = {
  read : path -> (bytes, Error.t) result;
  write : path -> bytes -> (unit, Error.t) result;
  mkdir_p : path -> (unit, Error.t) result;
}

let is_safe_char = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' -> true
  | _ -> false

let hex = "0123456789abcdef"

let add_escaped buf c =
  let code = Char.code c in
  Buffer.add_char buf '%';
  Buffer.add_char buf hex.[code lsr 4];
  Buffer.add_char buf hex.[code land 0x0f]

let encode_filename s =
  let buf = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      if is_safe_char c then Buffer.add_char buf c else add_escaped buf c)
    s;
  Buffer.contents buf

let file ~dir key =
  Filename.concat dir (encode_filename (Key.to_string key) ^ ".sift")

let load io codec path =
  match io.read path with
  | Error error -> Error error
  | Ok bytes -> codec.decode bytes

let save io codec path v =
  let bytes = codec.encode v in
  match io.mkdir_p (Filename.dirname path) with
  | Error error -> Error error
  | Ok () -> io.write path bytes

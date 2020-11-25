(* Copyright (c) Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 *)

open Bos
open Rresult
open Astring

let rec iter fn l =
  match l with hd :: tl -> fn hd >>= fun () -> iter fn tl | [] -> Ok ()

let stream cmd =
  let bin, args =
    Cmd.to_list cmd |> function
    | hd :: tl -> (hd, Array.of_list (hd :: tl))
    | _ -> failwith "invalid command"
  in
  let open Unix in
  Logs.debug (fun l ->
      l "Exec: %s" (String.concat ~sep:" " (Array.to_list args)));
  let _ = create_process bin args stdin stdout stderr in
  match wait () with
  | _, WEXITED 0 -> Ok ()
  | _, WEXITED e -> Error (`Msg (Fmt.strf "Exited with code %d" e))
  | _, _ -> Error (`Msg "Process terminated abruptly")

let run_and_log_s cmd =
  OS.File.tmp "opam-tools-run-%s.stderr" >>= fun tmp_file ->
  let err = OS.Cmd.err_file tmp_file in
  let res = OS.Cmd.(run_out ~err cmd |> out_string) in
  match res with
  | Ok (stdout, (_, `Exited 0)) -> Ok stdout
  | Ok (stdout, _) ->
      OS.File.read tmp_file >>= fun stderr ->
      Logs.err (fun l ->
          l "%a failed. Output was:@.%a%a"
            Fmt.(styled `Cyan Cmd.pp)
            cmd
            Fmt.(styled `Red text)
            stderr Fmt.text (String.trim stdout));
      Error (`Msg "Command execution failed")
  | Error (`Msg m) -> Error (`Msg m)

let run_and_log cmd = run_and_log_s cmd >>= fun _ -> Ok ()

let run_and_log_l cmd =
  run_and_log_s cmd >>= fun out ->
  R.ok (String.cuts ~sep:"\n" out |> List.map String.trim)

let map fn l =
  List.map fn l
  |> List.fold_left
       (fun acc b ->
         match (acc, b) with
         | Ok acc, Ok v -> Ok (v :: acc)
         | Ok _acc, Error v -> Error v
         | (Error _ as e), _ -> e)
       (Ok [])
  |> function
  | Ok v -> Ok (List.rev v)
  | e -> e

let opam_version () =
  match run_and_log_s Cmd.(v "opam" % "--version") with
  | Ok v -> Ok v
  | Error (`Msg _) -> Error (`Msg "opam not installed on system")

let ocaml_version ?ocamlc () =
  let oc =
    match ocamlc with None -> Cmd.v "ocamlc" | Some x -> Cmd.(v @@ p x)
  in
  match run_and_log_s Cmd.(oc % "-version") with
  | Ok s -> (
      match Ocaml_version.of_string s with
      | Ok v -> Ok v
      | Error (`Msg _) ->
          Error (`Msg "unable to parse OCaml string from ocamlc"))
  | Error (`Msg _) -> Error (`Msg "unable to find an installed ocamlc")

let run_opam args = run_and_log Cmd.(v "opam" %% args % "--color=never")

let run_opam_s args = run_and_log_s Cmd.(v "opam" %% args % "--color=never")

let run_opam_l args = run_and_log_l Cmd.(v "opam" %% args % "--color=never")

let install_ocaml_to ~prefix ~src () =
  OS.Dir.with_current src
    (fun () ->
      run_and_log Cmd.(v "./configure" % "--prefix" % p prefix) >>= fun () ->
      run_and_log Cmd.(v "make" % "-j" % "world.opt") >>= fun () ->
      run_and_log Cmd.(v "make" % "install"))
    ()
  >>= fun x -> x

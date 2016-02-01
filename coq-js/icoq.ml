(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2015     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(* Coq Interface to be used by JavaScript Ocaml code. Parts based in
   the coq source code.

   By Emilio J. Gallego Arias, Mines ParisTech, Paris.
*)

open Errors
open Feedback
open Names
open Pcoq
open Pp
open Util

(* Init options for coq *)
type init_opts = {

  (* callback to load cma files *)
  ml_load    : string -> unit;

  (* callback to handle async feedback *)
  fb_handler : feedback -> unit;

}

(* Enable dynamic compilation for now *)
let dyn_comp = true

(*************************************************************************)
(* Timeout support                                                       *)
(*************************************************************************)

type timeout = { timeout : 'a. int -> (unit -> 'a) -> exn -> 'a }

let mk_jscoq_timeout timeout exn =
  let timeout_ms  = float_of_int (timeout * 1000) in
  (* A faster implementation?? initial_ms = Js.Unsafe.global##_Date##now() *)
  let date_now    = jsnew Js.date_now ()          in
  let initial_ms  = ref date_now##getTime()       in
  Printf.eprintf "Initializing Timeout at second: %f\n%!" !initial_ms;
  fun () ->
    let date_now   = jsnew Js.date_now () in
    let current_ms = date_now##getTime()  in
    Printf.eprintf "Checking timeout: %f vs %f\n%!" current_ms !initial_ms;
    if current_ms -. !initial_ms > timeout_ms then raise exn

let js_coq_timeout : Control.timeout =
  { Control.timeout = fun timeout cmd ex ->
        (* Set the control variables to check-for timeouts *)
        Control.timeout_check     := true;
        Control.timeout_check_fun := mk_jscoq_timeout timeout ex;
        let res = cmd () in
        Control.timeout_check := false;
        res
  }

(*************************************************************************)
(* Main API                                                              *)
(*************************************************************************)

(* The order of some of the steps is not 100% guaranteed to be correct
   for now... *)
let init opts =

  (* We may hook library loading to avoid dynamic bytecode-to-js
   * compilation.
   *)
  let open Mltop in
  let jstop : Mltop.toplevel = {
    load_obj = opts.ml_load;
    (* We ignore all the other operations for now *)
    use_file = (fun s  -> Printf.eprintf "[jstop] use_file \"%s\" called\n%!" s);
    add_dir  = (fun s  -> Printf.eprintf "[jstop] add_dir \"%s\" called\n%!" s);
    ml_loop  = (fun () -> Printf.eprintf "[jstop] ml_loop not supported\n%!");
  } in

  if not dyn_comp then Mltop.set_top jstop;

  (* Internal Coq initialization *)
  Lib.init();

  (* Local libraries:
   *
   * XXX: Check what is going on here...
   *)
  (* let coq_default_path = DirPath.make []           in *)
  (* Loadpath.add_load_path "." coq_default_path            ~implicit:true; *)
  Loadpath.add_load_path "." Nameops.default_root_prefix ~implicit:false;

  (* We need to declare a toplevel module name.
   *
   * Not sure if this restriction can be removed
   *)
  let jsname = DirPath.make [Id.of_string "JsTop"] in
  Declaremods.start_library jsname;

  (* Initialize the STM. *)
  Stm.init();

  (* Initialize logging. *)
  (* This is for Coq trunk *)
  (* Pp.log_via_feedback (fun msg -> Richpp.repr (Richpp.richpp_of_pp msg)); *)
  Pp.log_via_feedback ();
  Pp.set_feeder opts.fb_handler;

  (* Misc tweaks *)
  (* Vernacentries.enable_goal_printing := false; *)
  Vernacentries.qed_display_script   := false;

  (* Set timeout handling *)
  Control.set_timeout js_coq_timeout;

  (* Return the initial state of the STM *)
  Stm.get_current_state ()

let version =
  Coq_config.version, Coq_config.date, Coq_config.compile_date, Coq_config.caml_version

(* Add a load path *)
let add_load_path pkg pkg_path has_ml =
  let coq_path = DirPath.make @@ List.rev @@ List.map Id.of_string pkg in
  Loadpath.add_load_path ("./" ^ pkg_path) coq_path ~implicit:false;
  if has_ml then Mltop.add_ml_dir pkg_path

let add_to_doc sid eid s = fst @@ Stm.add ~ontop:sid false eid s

let edit_doc   sid       = let _ = Stm.edit_at sid in ()

let commit_doc = Stm.observe

let query st cmd = Stm.query st cmd

(* XXX: We want to implement our custom proof printer (from
 * printing/printer.ml
 *

 * At a minimum, we want to output a the list of hypothesis and the
 * goal separatedly. See pr_context_of.
 *)
let string_of_goals () =
  let pp_goals =
    try Printer.pr_open_subgoals ()
    with Proof_global.NoCurrentProof -> str ""
  in
  string_of_ppcmds pp_goals

(*
let print_toplevel_error (e, info) =
  Errors.iprint (e, info)

let pr_open_cur_subgoals () =
  try Printer.pr_open_subgoals ()
  with Proof_global.NoCurrentProof -> str ""

let e_dinfo eid cmd s (s' : Stateid.t) (t : [ `NewTip | `Unfocus of Stateid.t ]) : unit =
  let open Printf in
  eprintf "edinfo %d for %s with sid: [%s/%s]\n%!" eid cmd (Stateid.to_string s) (Stateid.to_string s');
  match t with
  | `NewTip      -> eprintf "  Got NewTip\n%!"
  | `Unfocus sid -> eprintf "  Got Unfocus %s\n%!" (Stateid.to_string sid)
  ;
  ()

let execute eid s =
try
    flush stdout;
    flush stderr;
    flush_all ();
    (* Printf.eprintf "execute end\n%!"; *)
  with
  | any ->
     let any = Errors.push any in
     Format.set_formatter_out_channel stdout;
     let msg = print_toplevel_error any ++ fnl () in
     pp_with ~pp_tag:Ppstyle.pp_tag !Pp_control.std_ft msg;
     pp_flush ();
     false
*)

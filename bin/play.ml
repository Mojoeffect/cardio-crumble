open Runtime_events
open Cmdliner

let starting_time = ref None

let adjust_time ts =
  (* The ints64 representing the duration of a runtime phase are in units of nanoseconds, whereas the ints32 representing the timestamps of midi notes are in units of miliseconds.
     So this function indirectly  multiplies the timestamp by a a factor 1000 (intentionally). *)
  let int64_to_32 i = Int32.of_int @@ Int64.to_int @@ i in
  Option.map
    (fun st ->
      Int64.sub (Timestamp.to_int64 ts) (Timestamp.to_int64 st) |> int64_to_32)
    !starting_time

let runtime_counter device tones _domain_id ts counter _value =
  match counter with
  | EV_C_MINOR_PROMOTED ->
      starting_time := Some ts;
      Midi.(
        write_output device
          [ message_on ~note:tones.base_note ~timestamp:0l () ])
      (* Unix.sleep 5;
         Midi.(write_output [ message_off ~note:base_note () ]) *)
  | _ -> ()

let runtime_begin device tones _domain_id ts = function
  | EV_MAJOR -> (
      match adjust_time ts with
      | None -> ()
      | Some ts ->
          Midi.(
            write_output device
              [
                message_on ~note:tones.third ~timestamp:ts
                  (* ~volume:'\070' *) ();
              ]);
          Printf.printf "%f: start of EV_MAJOR. ts: %ld\n%!" (Sys.time ()) ts
          (* outest *))
  | EV_MAJOR_SWEEP -> ()
  (*   print_endline "start of EV_MAJOR_SWEEP" inside EV_MAjOR *)
  | EV_MAJOR_MARK_ROOTS ->
      ()
      (*
      print_endline "start of EV_MAJOR_MARK_ROOTS" (* inside EV_MAJOR *)*)
  | EV_MAJOR_MARK -> (
      match adjust_time ts with
      | None -> ()
      | Some ts ->
          Midi.(
            write_output device
              [
                message_on ~note:tones.fourth ~timestamp:ts
                  (*~volume:'\060'*) ();
              ]);
          Printf.printf "%f: start of EV_MAJOR_MARK. ts: %ld\n%!" (Sys.time ())
            ts
          (* inside EV_MAJOR *))
  | EV_MINOR -> (
      match adjust_time ts with
      | None -> ()
      | Some ts ->
          Midi.(
            write_output device
              [ message_on ~note:tones.first ~timestamp:ts () ]);
          Printf.printf "%f: start of EV_MINOR. ts: %ld\n%!" (Sys.time ()) ts
          (* outest *))
  | EV_MINOR_LOCAL_ROOTS -> (
      match adjust_time ts with
      | None -> ()
      | Some ts ->
          Midi.(
            write_output device
              [
                message_on ~note:tones.second ~timestamp:ts
                  (*~volume:'\070'*) ();
              ]);
          Printf.printf "%f: start of EV_MINOR_LOCAL_ROOTS ts: %ld\n%!"
            (Sys.time ()) ts
          (* inside EV_MINOR *))
  | _ -> ()

let runtime_end _device _domain_id _ts = function
  | EV_MAJOR ->
      (* Midi.(write_output  [ message_off ~note:third_overtone ~volume:'\070' () ]); *)
      Printf.printf "%f: end of EV_MAJOR\n" (Sys.time ())
  | EV_MAJOR_SWEEP -> () (* Printf.printf "end of EV_MAJOR_SWEEP\n" *)
  | EV_MAJOR_MARK_ROOTS -> ()
  (* Printf.printf "end of EV_MAJOR_MARK_ROOTS\n" *)
  | EV_MAJOR_MARK ->
      (* Midi.(
         write_output [ message_off ~note:fourth_overtone ~volume:'\060' () ]); *)
      Printf.printf "%f: end of EV_MAJOR_MARK\n" (Sys.time ())
  | EV_MINOR ->
      (* Midi.(write_output [ message_off ~note:first_overtone () ]); *)
      Printf.printf "%f: end of EV_MINOR\n" (Sys.time ())
  | EV_MINOR_LOCAL_ROOTS ->
      (* Midi.(
         write_output [ message_off ~note:second_overtone ~volume:'\070' () ]); *)
      Printf.printf "%f: end of EV_MINOR_LOCAL_ROOTS\n" (Sys.time ())
  | _ -> ()

let handle_control_c device =
  let handle =
    Sys.Signal_handle
      (fun _ ->
        match Midi.shutdown device with
        | Ok _ -> ()
        | Error msg ->
            let s = Midi.error_to_string msg in
            Printf.eprintf "(ctrl-c handler) Error during device shutdown: %s" s;
            exit 1)
  in
  Sys.(signal sigint handle)

let tracing device child_alive path_pid tones =
  let c = create_cursor path_pid in
  let runtime_begin = runtime_begin device tones in
  let runtime_counter = runtime_counter device tones in
  let runtime_end = runtime_end device in
  let cbs = Callbacks.create ~runtime_begin ~runtime_end ~runtime_counter () in
  while child_alive () do
    ignore (read_poll c cbs None);
    Unix.sleepf 0.1
  done

let play device_id argv =
  let prog, args =
    match argv with
    | prog :: args -> (prog, Array.of_list args)
    | _ -> failwith "No program given"
  in
  let device = Midi.create_device device_id in
  let _ = handle_control_c device in
  (* Extract the user supplied program and arguments. *)
  let proc =
    Unix.create_process_env prog args
      [| "OCAML_RUNTIME_EVENTS_START=1" |]
      Unix.stdin Unix.stdout Unix.stderr
  in
  Unix.sleepf 0.1;
  tracing device (Util.child_alive proc) (Some (".", proc)) (Midi.major 48);
  print_endline "got to the end";
  match Midi.shutdown device with
  | Ok () -> 0
  | Error msg ->
      let s = Midi.error_to_string msg in
      Printf.eprintf "Error during device shutdown: %s" s;
      1

let argv = Arg.(non_empty & pos_all string [] & info [] ~docv:"ARGV")

let device_id =
  Arg.(value & opt int 0 & info [ "d"; "device_id" ] ~docv:"DEVICE_ID")

let play_t = Term.(const play $ device_id $ argv)
let cmd = Cmd.v (Cmd.info "play") play_t

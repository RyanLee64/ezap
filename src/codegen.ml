(* Code generation: translate takes a semantically checked AST and
produces LLVM IR

LLVM tutorial: Make sure to read the OCaml version of the tutorial

http://llvm.org/docs/tutorial/index.html

Detailed documentation on the OCaml LLVM library:

http://llvm.moe/
http://llvm.moe/ocaml/

*)

module L = Llvm
module A = Ast
open Sast 

module StringMap = Map.Make(String)


(* translate : Sast.program -> Llvm.module *)
let translate (globals, functions) =
  let context    = L.global_context () in
  
  (* Create the LLVM compilation module into which
     we will generate code *)
  let the_module = L.create_module context "ezap" in

  let sock_t = L.named_struct_type context "sock_struct" in 
  let sock_t_ptr = L.pointer_type sock_t in 

  (* Get types from the context *)
  let i32_t      = L.i32_type    context
  and i8_t       = L.i8_type     context
  and i1_t       = L.i1_type     context
  and float_t    = L.double_type context
  and str_t      = L.pointer_type (L.i8_type context)
  and void_t     = L.void_type   context in

  (* Return the LLVM type for a ezap type *)
  let ltype_of_typ = function
      A.Int   -> i32_t
    | A.Bool  -> i1_t
    | A.Float -> float_t
    | A.Void  -> void_t
    | A.String -> str_t
    | A.Char   -> i8_t
    | A.Socket -> sock_t_ptr
  in

  (*fill out the body of our socket struct type*)
  ignore(L.struct_set_body sock_t [|i8_t; i32_t; i32_t|] false);


  (* Create a map of global variables after creating each *)
  let global_vars : L.llvalue StringMap.t =
    let global_var m (t, n) = 
      let init = match t with
          A.Float -> L.const_float (ltype_of_typ t) 0.0
        | _ -> L.const_int (ltype_of_typ t) 0
      in StringMap.add n (L.define_global n init the_module) m in
    List.fold_left global_var StringMap.empty globals in

  (* External function declarations  *)
  let printf_t : L.lltype = 
      L.var_arg_function_type i32_t [| L.pointer_type i8_t |] in
  let printf_func : L.llvalue = 
      L.declare_function "printf" printf_t the_module in

  let printbig_t : L.lltype =
      L.function_type i32_t [| i32_t |] in
  let printbig_func : L.llvalue =
      L.declare_function "printbig" printbig_t the_module in

  let createstr_t: L.lltype =
      L.function_type str_t [| str_t |] in
  let createstr_func: L.llvalue  =
      L.declare_function "createstr" createstr_t the_module in

  let add_strs_t: L.lltype = 
    L.function_type str_t [|str_t; str_t|] in 
  let add_strs_func: L.llvalue = 
    L.declare_function "concatstrs" add_strs_t the_module in 
  
  let char_at_t: L.lltype = 
    L.function_type i8_t [|str_t; i32_t|] in 
  let char_at_func: L.llvalue = 
    L.declare_function "charatstr" char_at_t the_module in 
  
  let check_str_eq_t: L.lltype = 
    L.function_type i1_t [|str_t; str_t|] in 
  let check_str_func: L.llvalue = 
    L.declare_function "checkstreq" check_str_eq_t the_module in

  let create_t: L.lltype = 
    L.function_type void_t [|sock_t_ptr|] in 
  let create_func: L.llvalue = 
    L.declare_function "ez_create" create_t the_module in

  let connect_t: L.lltype = 
    L.function_type void_t [|sock_t_ptr; str_t; i32_t|] in 
  let connect_func: L.llvalue = 
    L.declare_function "ez_connect" connect_t the_module in

  let close_t: L.lltype = 
    L.function_type void_t [|sock_t_ptr|] in 
  let close_func: L.llvalue = 
    L.declare_function "ez_close" close_t the_module in
  
  let send_t: L.lltype = 
    L.function_type void_t [|sock_t_ptr; str_t|] in 
  let send_func: L.llvalue = 
    L.declare_function "ez_send" send_t the_module in

  let recv_t: L.lltype = 
    L.function_type str_t [|sock_t_ptr|] in 
  let recv_func: L.llvalue = 
    L.declare_function "ez_recv" recv_t the_module in 
  
  let write_t: L.lltype = 
    L.function_type void_t [|str_t|] in 
  let write_func: L.llvalue = 
    L.declare_function "writestr" write_t the_module in 
  
  let read_t: L.lltype = 
    L.function_type str_t [| |] in 
  let read_func: L.llvalue = 
    L.declare_function "readstr" read_t the_module in 
  
  

  (* Define each function (arguments and return type) so we can 
     call it even before we've created its body *)
  let function_decls : (L.llvalue * sfunc_decl) StringMap.t =
    let function_decl m fdecl =
      let name = fdecl.sfname
      and formal_types = 
	Array.of_list (List.map (fun (t,_) -> ltype_of_typ t) fdecl.sformals)
      in let ftype = L.function_type (ltype_of_typ fdecl.styp) formal_types in
      StringMap.add name (L.define_function name ftype the_module, fdecl) m in
    List.fold_left function_decl StringMap.empty functions in
  
  (* Fill in the body of the given function *)
  let build_function_body fdecl =
    let (the_function, _) = StringMap.find fdecl.sfname function_decls in
    let builder = L.builder_at_end context (L.entry_block the_function) in

    let int_format_str = L.build_global_stringptr "%d\n" "fmt" builder
    and float_format_str = L.build_global_stringptr "%g\n" "fmt" builder 
    and str_format_str = L.build_global_stringptr   "%s\n" "fmt" builder 
    and char_format_str = L.build_global_stringptr  "%c\n"  "fmt" builder in

    (* Construct the function's "locals": formal arguments and locally
       declared variables.  Allocate each on the stack, initialize their
       value, if appropriate, and remember their values in the "locals" map *)
    let local_vars =
      let add_formal m (t, n) p = 
        L.set_value_name n p;
	let local = L.build_alloca (ltype_of_typ t) n builder in
        ignore (L.build_store p local builder);        
	StringMap.add n local m 

      (* Allocate space for any locally declared variables and add the
       * resulting registers to our map *)
      and add_local m (t, n) =
	let local_var = L.build_alloca (ltype_of_typ t) n builder
	in StringMap.add n local_var m 
      in

      let formals = List.fold_left2 add_formal StringMap.empty fdecl.sformals
          (Array.to_list (L.params the_function)) in
      List.fold_left add_local formals fdecl.slocals 
    in

    (* Return the value for a variable or formal argument.
       Check local names first, then global names *)
    let lookup n = try StringMap.find n local_vars
                   with Not_found -> StringMap.find n global_vars
    in

    (* Construct code for an expression; return its value *)
    let rec expr builder ((_, e) : sexpr) = match e with
	SLiteral i  -> L.const_int i32_t i
      | SBoolLit b  -> L.const_int i1_t (if b then 1 else 0)
      | SFliteral l -> L.const_float_of_string float_t l
      | SStrLiteral s -> 
        let temp = L.build_global_stringptr s "temp_assign_ptr" builder in 
        L.build_call createstr_func [| temp |] "strlit" builder
      | SNoexpr     -> L.const_int i32_t 0
      | SCharLiteral c -> L.const_int i8_t (int_of_char c) 
      | SSock(e1, e2) -> let sock = L.build_alloca sock_t "socket" builder in 
          let e1' = expr builder e1 in
          let e2' = expr builder e2 in 
          (*get pointer to first/second/third element of socket struct 
          a.k.a. connection type/port #/socket file descriptor (null intitially)*)
          let connection_typ_ptr = L.build_gep sock [|L.const_int i32_t 0; L.const_int i32_t 0|] "conn_ptr" builder in
          let port_number_ptr = L.build_gep sock [|L.const_int i32_t 0; L.const_int i32_t 1|] "port_ptr" builder in
          let file_descriptor_ptr = L.build_gep sock [|L.const_int i32_t 0; L.const_int i32_t 2|] "file_descrip" builder in
          (*store our calculated values in the allocd struct via the ptrs*)
          ignore(L.build_store e1' connection_typ_ptr builder);
          ignore(L.build_store e2' port_number_ptr builder);
          ignore(L.build_store (L.const_int i32_t 0) file_descriptor_ptr builder);
          ignore(L.build_call create_func[|sock|] "" builder); 
          sock
          (*return the filled out struct*) 
      | SId s       -> L.build_load (lookup s) s builder
      | SAssign (s, e) -> let e' = expr builder e in
                          ignore(L.build_store e' (lookup s) builder); e'
      | SPAssign (s, e) -> 
        (* leverage concat logic for SPAssign*)
        let old_str = L.build_load (lookup s) s builder in 
        let e' = expr builder e in 
        let new_str  = L.build_call add_strs_func[|old_str; e'|] "strcat" builder in 
        ignore(L.build_free old_str builder);
        L.build_store new_str (lookup s) builder
        
      | SBinop ((A.Float,_ ) as e1, op, e2) ->
    
	  let e1' = expr builder e1
	  and e2' = expr builder e2 in
	  (match op with 
	    A.Add     -> L.build_fadd
	  | A.Sub     -> L.build_fsub
	  | A.Mult    -> L.build_fmul
	  | A.Div     -> L.build_fdiv 
	  | A.Equal   -> L.build_fcmp L.Fcmp.Oeq
	  | A.Neq     -> L.build_fcmp L.Fcmp.One
	  | A.Less    -> L.build_fcmp L.Fcmp.Olt
	  | A.Leq     -> L.build_fcmp L.Fcmp.Ole
	  | A.Greater -> L.build_fcmp L.Fcmp.Ogt
	  | A.Geq     -> L.build_fcmp L.Fcmp.Oge
	  | A.And | A.Or | A.Charat->
	      raise (Failure "internal error: semant should have rejected and/or on float")
	  ) e1' e2' "tmp" builder
      | SBinop ((A.String,_) as e1, op, e2) ->
    let e1' = expr builder e1
    and e2' = expr builder e2 in
    (match op with
      A.Add     -> L.build_call add_strs_func[|e1'; e2'|] "strcat" builder 
     | A.Charat -> L.build_call char_at_func[|e1'; e2'|] "charat" builder
     | A.Equal  -> L.build_call check_str_func[|e1'; e2'|] "equality" builder

    | _ -> 	raise (Failure "unsupported string operation")
    ) 
      | SBinop (e1, op, e2) ->
	  let e1' = expr builder e1
	  and e2' = expr builder e2 in
	  (match op with
	    A.Add     -> L.build_add
	  | A.Sub     -> L.build_sub
	  | A.Mult    -> L.build_mul
          | A.Div     -> L.build_sdiv
	  | A.And     -> L.build_and
	  | A.Or      -> L.build_or
	  | A.Equal   -> L.build_icmp L.Icmp.Eq
	  | A.Neq     -> L.build_icmp L.Icmp.Ne
	  | A.Less    -> L.build_icmp L.Icmp.Slt
	  | A.Leq     -> L.build_icmp L.Icmp.Sle
	  | A.Greater -> L.build_icmp L.Icmp.Sgt
	  | A.Geq     -> L.build_icmp L.Icmp.Sge
    | _ -> 	raise (Failure "unsupported int operation semant should have rejected")
	  ) e1' e2' "tmp" builder 
      | SUnop(op, ((t, _) as e)) ->
          let e' = expr builder e in
	  (match op with
	    A.Neg when t = A.Float -> L.build_fneg 
	  | A.Neg                  -> L.build_neg
          | A.Not                  -> L.build_not) e' "tmp" builder
      | SCall ("print", [e]) | SCall ("printb", [e]) ->
	  L.build_call printf_func [| int_format_str ; (expr builder e) |]
	    "printf" builder
      | SCall ("printbig", [e]) ->
	  L.build_call printbig_func [| (expr builder e) |] "printbig" builder
      | SCall ("printf", [e]) -> 
	  L.build_call printf_func [| float_format_str ; (expr builder e) |]
	    "printf" builder
      | SCall ("prints", [e]) ->
    L.build_call printf_func [| str_format_str ; (expr builder e) |]
      "printf" builder 
      | SCall ("printc", [e]) -> 
    L.build_call printf_func [| char_format_str; (expr builder e) |]
      "printf"  builder
      | SCall ("connect", lst) ->
    L.build_call connect_func [|(expr builder (List.nth lst 0));
    (expr builder (List.nth lst 1));(expr builder (List.nth lst 2)) |]
      "" builder
      | SCall ("send", lst) ->
    L.build_call send_func [|(expr builder (List.nth lst 0));
    (expr builder (List.nth lst 1))|]
        "" builder
      | SCall ("recv", [e]) ->
    L.build_call recv_func [|(expr builder e)|]
        "recvd_data" builder
      | SCall ("write", [e]) -> 
    L.build_call write_func [|expr builder e|] "" builder
      | SCall ("read", _ ) -> 
    L.build_call read_func [| |] "readstr" builder
      | SCall (f, args) ->
         let (fdef, fdecl) = StringMap.find f function_decls in
	 let llargs = List.rev (List.map (expr builder) (List.rev args)) in
	 let result = (match fdecl.styp with 
                        A.Void -> ""
                      | _ -> f ^ "_result") in
         L.build_call fdef (Array.of_list llargs) result builder
    in
    
    (* LLVM insists each basic block end with exactly one "terminator" 
       instruction that transfers control.  This function runs "instr builder"
       if the current block does not already have a terminator.  Used,
       e.g., to handle the "fall off the end of the function" case. *)
       (*NOTE: stmt add_terminal different that function add_terminal*)
    let add_terminal builder instr =
      match L.block_terminator (L.insertion_block builder) with
	Some _ -> ()
      | None -> ignore (instr builder) in
	
    (* Build the code for the given statement; return the builder for
       the statement's successor (i.e., the next instruction will be built
       after the one generated by this call) *)

    let rec stmt builder = function
	SBlock sl -> List.fold_left stmt builder sl
      | SExpr e -> ignore(expr builder e); builder 
      | SReturn e -> ignore(match fdecl.styp with
                              (* Special "return nothing" instr *)
                              A.Void -> L.build_ret_void builder 
                              (* Build return statement *)
                            | _ -> L.build_ret (expr builder e) builder );
                     builder
      | SIf (predicate, then_stmt, else_stmt) ->
         let bool_val = expr builder predicate in
	 let merge_bb = L.append_block context "merge" the_function in
         let build_br_merge = L.build_br merge_bb in (* partial function *)

	 let then_bb = L.append_block context "then" the_function in
	 add_terminal (stmt (L.builder_at_end context then_bb) then_stmt)
	   build_br_merge;

	 let else_bb = L.append_block context "else" the_function in
	 add_terminal (stmt (L.builder_at_end context else_bb) else_stmt)
	   build_br_merge;

	 ignore(L.build_cond_br bool_val then_bb else_bb builder);
	 L.builder_at_end context merge_bb
      | SContext(((typ, v)), resource,  body) ->
        (match v with 
        SId s ->  
          (*bb for cleaning up resources*)
          let cleanup_bb = L.append_block context "clean" the_function in 

          (*bb for exucuting the statements in the body of the with statement*)
          let body_bb = L.append_block context "body" the_function in 


          let evaluated_resource = expr builder resource in 
          (*so while the value s maps to might change this pointer will not as we control it*)
          let pointer = L.build_alloca (ltype_of_typ typ) "contextptr" builder in
          (*store the evaluated resource in our pointer for later and in our symbol tabl*)
          ignore(L.build_store evaluated_resource pointer builder);
          ignore(L.build_store evaluated_resource (lookup s) builder);
          ignore( L.build_br body_bb builder);
          
          (*cleanup routine*)
          let cleanup_builder = L.builder_at_end context cleanup_bb in 

          let lookup = L.build_load pointer "cleanup_load" cleanup_builder in 
          (*here is where we will add conditional behavior for sockets
          vs strings currently only configured for strings*)

          (*we have to free strings*)
          ignore(
            if typ = String then L.build_free lookup cleanup_builder
            else L.build_call close_func [|lookup|] "" cleanup_builder);
          
          (*body routine*)
          let body_builder = L.builder_at_end context body_bb in 
          ignore(add_terminal (stmt body_builder body) (L.build_br cleanup_bb)); 
  
          (*return the cleanup builder to continue building the module*)
          cleanup_builder

        |__-> raise(Failure "semant should have caught that this is not assignable"))
        

      | SWhile (predicate, body) ->
	  let pred_bb = L.append_block context "while" the_function in
	  ignore(L.build_br pred_bb builder);

	  let body_bb = L.append_block context "while_body" the_function in
	  add_terminal (stmt (L.builder_at_end context body_bb) body)
	    (L.build_br pred_bb);

	  let pred_builder = L.builder_at_end context pred_bb in
	  let bool_val = expr pred_builder predicate in

	  let merge_bb = L.append_block context "merge" the_function in
	  ignore(L.build_cond_br bool_val body_bb merge_bb pred_builder);
	  L.builder_at_end context merge_bb

      (* Implement for loops as while loops *)
      | SFor (e1, e2, e3, body) -> stmt builder
	    ( SBlock [SExpr e1 ; SWhile (e2, SBlock [body ; SExpr e3]) ] )
    in

    (* Build the code for each statement in the function *)
    let builder = stmt builder (SBlock fdecl.sbody) in

    (* Add a return if the last block falls off the end *)
    add_terminal builder (match fdecl.styp with
        A.Void -> L.build_ret_void
      | A.Float -> L.build_ret (L.const_float float_t 0.0)
      | t -> L.build_ret (L.const_int (ltype_of_typ t) 0))
  in

  List.iter build_function_body functions;
  the_module

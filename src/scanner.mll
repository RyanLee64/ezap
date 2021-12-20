(* Scanner for ezAP language*)

{open Parser}

let digit = ['0' - '9']
let digits = digit+
let whitespace_chars = [' ' '\t']
let newline = '\r' | '\n' | "\r\n"
let whitespace = whitespace_chars | newline
rule token = parse 
    whitespace {token lexbuf} (*eat whitespace*)
(*comments*)
|   "//"       {s_comment lexbuf}
|   "/*"       {mult_comment lexbuf}
|   "new"      {NEW}
|   '"'        {read_string (Buffer.create 17)}    
|   "Socket"   {SOCKET}
|   "String"   {STRING}


(*MICRO C TEMPLATE *)
| '('      { LPAREN }
| ')'      { RPAREN }
| '{'      { LBRACE }
| '}'      { RBRACE }
| ';'      { SEMI }
| ','      { COMMA }
| '+'      { PLUS }
| '-'      { MINUS }
| '*'      { TIMES }
| '/'      { DIVIDE }
| '='      { ASSIGN }
| "=="     { EQ }
| "!="     { NEQ }
| '<'      { LT }
| "<="     { LEQ }
| ">"      { GT }
| ">="     { GEQ }
| "&&"     { AND }
| "||"     { OR }
| "!"      { NOT }
| "if"     { IF }
| "else"   { ELSE }
| "for"    { FOR }
| "while"  { WHILE }
| "return" { RETURN }
| "int"    { INT }
| "bool"   { BOOL }
| "float"  { FLOAT }
| "void"   { VOID }
| "true"   { BLIT(true)  }
| "false"  { BLIT(false) }

| digits as lxm { LITERAL(int_of_string lxm) }
| digits '.'  digit* ( ['e' 'E'] ['+' '-']? digits )? as lxm { FLIT(lxm) }
| ['a'-'z' 'A'-'Z']['a'-'z' 'A'-'Z' '0'-'9' '_']*     as lxm { ID(lxm) }
| eof { EOF }
| _ as char { raise (Failure("illegal character " ^ Char.escaped char)) }



and s_comment = parse
    "\n"    {token lexbuf}
|   _       {scomment lexbuf}

and mult_comment = parse
  "*/" { token lexbuf }
| _    { multcomment lexbuf }

and read_str buf =
  parse
  | '"'       { STRLIT (Buffer.contents buf) }
  | '\\' '/'  { Buffer.add_char buf '/'; read_string buf lexbuf }
  | '\\' '\\' { Buffer.add_char buf '\\'; read_string buf lexbuf }
  | '\\' 'b'  { Buffer.add_char buf '\b'; read_string buf lexbuf }
  | '\\' 'f'  { Buffer.add_char buf '\012'; read_string buf lexbuf }
  | '\\' 'n'  { Buffer.add_char buf '\n'; read_string buf lexbuf }
  | '\\' 'r'  { Buffer.add_char buf '\r'; read_string buf lexbuf }
  | '\\' 't'  { Buffer.add_char buf '\t'; read_string buf lexbuf }
  | [^ '"' '\\']+
    { Buffer.add_string buf (Lexing.lexeme lexbuf);
      read_string buf lexbuf
    }
  | _ { raise (SyntaxError ("Illegal string character: " ^ Lexing.lexeme lexbuf)) }
  | eof { raise (SyntaxError ("String is not terminated")) }

  (*
12/19 STATUS
1. Lexing strings, comments both single/mutli
2. Added in new, String, Socket keywordss
3. Need to determine what if anything to do special with
functions like connect/the rest of the socket ops
4. Need to check over proposal and look for additional 
differences that need to be lexed accordingly 
  *)
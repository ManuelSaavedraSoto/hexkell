# Language Design Document

## Language Features

* Lazy evaluation
* First-class functions
* Pattern Matching
* Wrapping of static GDScript functions in closures

## Concrete Syntax EBNF

```ebnf
(* Concrete Syntax *)
(* Top Level *)
program = { definition } , ( "do" | "$" ) , [ expr ] ;

definition = equation , { equation } ;

equation = identifier , { pattern } , ( ( "=" , expr ) | guard ) ;

guard = "|" , expr , "=" , expr , { "|" , expr , "=" , expr } ;

(* Types *)
type = functional_type | primary_type ;

functional_type = primary_type , "->" , type ;

primary_type = type_identifier	(* TBD *)
			 | type_variable    (* TBD *)
			 | "(" , type , ")"
			 | "[" , type , "]" ;

(* Expressions *)
expr = if_expr
	 | let_expr
	 | let_func
	 | case_expr
	 | lambda
	 | logic_expr ;

logic_expr = and_expr , { "||" , and_expr } ;

and_expr = comparison , { "&&" , comparison } ;

comparison = cons_expr , {  ( "==" | "!=" | "<" | "<=" | ">" | ">=" ) , cons_expr } ;

cons_expr = term , [ ":" , cons_expr ] ;

term = factor , { ( "+" | "-" | "++" ) , factor } ;

factor = composition , { ( "*" | "/" | "%" ) , composition } ;

composition = application , [ "." , composition ] ;

application = primary_expr , { primary_expr } ;

primary_expr = literal
			 | identifier
			 | negation
			 | prefix_op
			 | section
			 | list
			 | tuple
			 | "(" , expr , ")" ;

literal = integer | boolean ;

integer = digit , { digit } ;

boolean = "true" | "false" ;

identifier = ( letter | "_" ) , { letter | digit | "_" } ;

negation = "-" , primary_expr
		 | "!" , primary_expr ;

prefix_op = "(" , ( binary_op | "!" ) , ")" ;

section = "(" , binary_op , primary_expr , ")"
		| "(" , primary_expr , binary_op , ")" ;

binary_op = "+" | "-" | "*" | "/" | "%" | "<" | ">" | "." | ":" 
		  | "<=" | ">=" | "==" | "!=" | "&&" | "||" | "++" ;

tuple = "(" , expr , "," , expr , { "," , expr } , ")" ;

list = "[]"
	 | "[" , expr , list_tail , "]" ;

list_tail = { "," , expr }							(* list *)
		  | "|" , generator , { "," , generator }	(* comprehension *)
		  | ".." , [ expr ] ; 						(* range *)

if_expr = "if" , expr , "then" , expr , "else" , expr ;

let_expr = "let" , [ "rec" ] , pattern , "=" , expr , "in" , expr ;

case_expr = "match" , expr , "with" ,
			[ "|" ] , case_branch , { "|" , case_branch } ;

case_branch = pattern , "=" , expr ;

lambda = "\\" , pattern , { pattern } , "->" , expr ;

pattern = simple_pattern , [ ":" , pattern ] ;

simple_pattern = identifier
			   | literal
			   | "(" , pattern , { "," , pattern } , ")"
			   | "[" , pattern , { "," , pattern } , "]"
			   | "[]"
			   | "_" ;

(* Syntactic Sugar *)
let_func = "let" , [ "rec" ] , identifier , pattern , { pattern } , "=" expr ;

generator = pattern , "<-" , expr
		  | expr
		  | "let" , identifier , "=" , expr ;

(* Lexical Elements *)
digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
letter = ? alphabetic characters ? ;

(*	Notes:
	Equations for the same definition must have the same identifier,
	otherwise they are considered different definitions.

	Unless specified, whitespace characters are ignored when parsing. 
	In case of (-) operations, `f -n` is treated as `f (-n)`, while
	`x-n`, `x- n` and `x - n` are treated as the infix minus operation.

	Prefix operations are meant to be used for lambda definitions, i.e.
	`foldr (+) 0 [1..10]`, and same goes for partial applications of
	binary operators, i.e. `map (+1) [1..10]`. Parser for the language
	is expected to implement look-ahead.

	Singleton lists `[expr]` are produced by empty `{ "," , expr }`
	matches.
*)
```

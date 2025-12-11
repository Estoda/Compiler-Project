%{
#include <stdio.h>
#include <string.h>

int yylex(void);
void yyerror(char *);

extern int yylineno;
extern FILE* yyin;
extern FILE* yyout;
FILE* yyError = NULL;

int sym[256]; /* enough for many vars (IDs assigned by scanner) */
%}

%union {
    int ival;
    float fval;
    char* sval;
}

/* tokens */
%token<ival> INTEGER
%token<ival> VARIABLE
%token PRINT
%token IF
%token ELSE
%token INT
%token END
%token<sval> OP

/* nonterm types */
%type<ival> expr condition

/* precedence & dangling-else */
%nonassoc LOWER_ELSE
%right '='
%left '+' '-'
%left '*' '/'

%%

program:
      stmts
    ;

/* zero or more statements */
stmts:
      /* empty */
    | stmts stmt
    ;

stmt:
      declaration
    | assignment
    | printStatement
    | IfStatement
    | expr ';'       { fprintf(yyout, "%d\n", $1); }
    ;

/* declaration and assignment use literal '=' and ';' */
declaration:
      INT VARIABLE '=' expr ';'
      {
          sym[$2] = $4;
          fprintf(yyout, "Declared var[%d] = %d\n", $2, $4);
      }
    ;

assignment:
      VARIABLE '=' expr ';'
      {
          sym[$1] = $3;
          fprintf(yyout, "Assigned var[%d] = %d\n", $1, $3);
      }
    ;

printStatement:
      PRINT '(' expr ')' ';'
      {
          fprintf(yyout, "Print: %d\n", $3);
      }
    ;

/* If without else uses LOWER_ELSE to avoid dangling-else */
IfStatement:
      IF '(' condition ')' ':' block %prec LOWER_ELSE END
      {
          if ($3) fprintf(yyout, "If (true) -> then-block executed\n");
          else     fprintf(yyout, "If (false) -> then-block (evaluated false)\n");
      }
    | IF '(' condition ')' ':' block ELSE ':' block END
      {
          if ($3) fprintf(yyout, "If (true) -> then-block executed (with else)\n");
          else     fprintf(yyout, "If (false) -> else-block executed\n");
      }
    ;

/* block is a sequence of statements (no special newline token) */
block:
      stmts
    ;

/* condition returns 0 or 1 */
condition:
      expr OP expr
      {
          char *op = $2;
          if (strcmp(op, "==") == 0)      $$ = ($1 == $3);
          else if (strcmp(op, "!=") == 0) $$ = ($1 != $3);
          else if (strcmp(op, "<=") == 0) $$ = ($1 <= $3);
          else if (strcmp(op, ">=") == 0) $$ = ($1 >= $3);
          else if (strcmp(op, "<") == 0)  $$ = ($1 <  $3);
          else if (strcmp(op, ">") == 0)  $$ = ($1 >  $3);
          else {
              yyerror("Unknown operator in condition");
              $$ = 0;
          }
      }
    ;

/* arithmetic expressions */
expr:
      INTEGER               { $$ = $1; }
    | VARIABLE              { $$ = sym[$1]; }
    | expr '+' expr        { $$ = $1 + $3; }
    | expr '-' expr        { $$ = $1 - $3; }
    | expr '*' expr        { $$ = $1 * $3; }
    | expr '/' expr        { $$ = $1 / $3; }
    | '(' expr ')'         { $$ = $2; }
    ;

%%

void yyerror(char *s) {
    if (!yyError) yyError = stderr;
    fprintf(yyError, "Error: %s at line %d\n", s, yylineno);
}

int main(void) {
    yyin = fopen("in.txt", "r");
    yyout = fopen("out.txt", "w");
    yyError = fopen("outError.txt", "w");
    if (!yyin) { perror("open in.txt"); return 1; }
    if (!yyout) { perror("open out.txt"); return 1; }

    yyparse();

    fclose(yyin);
    fclose(yyout);
    if (yyError && yyError != stderr) fclose(yyError);
    return 0;
}
